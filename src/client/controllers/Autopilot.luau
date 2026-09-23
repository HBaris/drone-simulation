--!strict
-- Autopilot.luau
-- Flight modes and guidance for the primary drone, modelled on ArduPilot Copter:
--   MANUAL (pilot, altitude-hold style) · AUTO (mission) · RTL · LAND · CRASHED
-- AUTO flies the same mission tools/sim2mission.py writes: TAKEOFF -> straight legs between
-- waypoints -> RTL. Shared singleton: the pilot controller runs it, the route editor commands it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local S = DroneConfig.STUDS_PER_METER
local AP = DroneConfig.AUTOPILOT
local FS = DroneConfig.FAILSAFE

export type Mode = "MANUAL" | "AUTO" | "RTL" | "LAND" | "CRASHED"

local Autopilot = {
	Mode = "MANUAL" :: Mode,
	Armed = false,
	Home = DroneConfig.HOME.SIM_POSITION, -- set where the drone arms, like a real flight controller
	Status = "", -- human-readable phase, e.g. "WP 2/5" or "RTL: eve dönüyor"
	LastEvent = "", -- last mode change reason / failsafe
	Mission = {} :: { Vector3 },
	MissionIndex = 0,
	Phase = "",
	PhaseTimer = 0,
	ClimbTargetY = 0,
	LegStart = Vector3.zero, -- start of the current straight leg (cross-track reference)
	FailsafeBatteryLow = false,
	FailsafeBatteryCritical = false,
}

function Autopilot.setMode(mode: Mode, reason: string?)
	if Autopilot.Mode == "CRASHED" and mode ~= "MANUAL" then
		return
	end
	Autopilot.Mode = mode
	Autopilot.Phase = ""
	Autopilot.PhaseTimer = 0
	Autopilot.ClimbTargetY = 0
	Autopilot.LastEvent = string.format("%s%s", mode, if reason then " — " .. reason else "")
	print("[Autopilot] Mode:", Autopilot.LastEvent)
end

function Autopilot.arm(pos: Vector3)
	if not Autopilot.Armed then
		Autopilot.Armed = true
		Autopilot.Home = pos
	end
end

function Autopilot.disarm()
	Autopilot.Armed = false
end

-- Waypoint positions in studs. Mirrors the exported mission: take off vertically, then fly
-- straight to each waypoint, then return to launch.
function Autopilot.startMission(points: { Vector3 })
	if #points == 0 or Autopilot.Mode == "CRASHED" then
		return
	end
	Autopilot.Mission = table.clone(points)
	Autopilot.MissionIndex = 0 -- 0 = takeoff leg
	Autopilot.setMode("AUTO", string.format("%d waypoint", #points))
end

function Autopilot.relAlt(pos: Vector3): number
	return (pos.Y - Autopilot.Home.Y) / S
end

-- Scale the whole vector (not just Y) to the climb/descent limits so the path stays straight.
local function limitVertical(v: Vector3): Vector3
	local up, dn = AP.WPNAV_SPEED_UP * S, AP.WPNAV_SPEED_DN * S
	if v.Y > up then
		return v * (up / v.Y)
	elseif v.Y < -dn then
		return v * (-dn / v.Y)
	end
	return v
end

-- Velocity (studs/s) that flies straight at `target`, respecting ArduPilot speed limits and
-- braking to `endSpeed` (m/s, 0 = stop on the target).
local function velocityToward(pos: Vector3, target: Vector3, endSpeed: number): Vector3
	local delta = target - pos
	local dist = delta.Magnitude
	if dist < 1e-3 then
		return Vector3.zero
	end
	local brake = math.sqrt((endSpeed * S) ^ 2 + 2 * AP.WPNAV_ACCEL * S * dist)
	local speed = math.min(AP.WPNAV_SPEED * S, brake)
	return limitVertical(delta.Unit * speed)
end

local function landVelocity(pos: Vector3, groundY: number?): Vector3
	-- Height from the ground raycast (like a rangefinder); without one, altitude above home
	-- (what ArduPilot uses from the barometer when no rangefinder is fitted).
	local heightAboveGround = if groundY then (pos.Y - groundY) / S else Autopilot.relAlt(pos)
	local speed = if heightAboveGround > AP.LAND_ALT_LOW then AP.LAND_SPEED_HIGH else AP.LAND_SPEED
	return Vector3.new(0, -speed * S, 0)
end

-- Pure-pursuit "carrot" on the straight leg: aim a few meters ahead of the closest point on
-- the line, so any drift (wind, a sharp corner) is steered back onto the leg.
local LOOKAHEAD_M = 6
local function carrotOnLeg(pos: Vector3, legStart: Vector3, wp: Vector3): Vector3
	local leg = wp - legStart
	local len = leg.Magnitude
	if len < 1e-3 then
		return wp
	end
	local along = math.clamp((pos - legStart):Dot(leg.Unit), 0, len)
	return legStart + leg.Unit * math.min(len, along + LOOKAHEAD_M * S)
end

local function stepAuto(pos: Vector3): Vector3
	local radius = AP.WPNAV_RADIUS * S
	if Autopilot.MissionIndex == 0 then
		local target = Vector3.new(pos.X, Autopilot.Home.Y + AP.TAKEOFF_ALT * S, pos.Z)
		Autopilot.Status = string.format("KALKIŞ → %.0f m", AP.TAKEOFF_ALT)
		-- Like NAV_TAKEOFF: done once at (or already above) the takeoff altitude
		if pos.Y >= target.Y - 0.5 * S then
			Autopilot.MissionIndex = 1
			Autopilot.LegStart = pos
		end
		return velocityToward(pos, target, 0)
	end

	local wp = Autopilot.Mission[Autopilot.MissionIndex]
	if not wp then
		Autopilot.setMode("RTL", "görev tamamlandı")
		return Vector3.zero
	end
	Autopilot.Status = string.format("WP %d/%d  %.0f m", Autopilot.MissionIndex, #Autopilot.Mission, (wp - pos).Magnitude / S)
	if (wp - pos).Magnitude < radius then
		Autopilot.MissionIndex += 1
		Autopilot.LegStart = wp
	end
	-- Slow down for the corner into the next leg (a 90° turn is taken at 1/4 cruise speed)
	local nextWp = Autopilot.Mission[Autopilot.MissionIndex + 1]
	local cornerSpeed = 0
	if nextWp and (wp - pos).Magnitude > 1e-3 and (nextWp - wp).Magnitude > 1e-3 then
		local cosTurn = (wp - pos).Unit:Dot((nextWp - wp).Unit)
		cornerSpeed = AP.WPNAV_SPEED * ((1 + cosTurn) / 2) ^ 2
	end
	-- Speed comes from the distance to the waypoint, direction from the carrot on the leg
	local toWp = velocityToward(pos, wp, cornerSpeed)
	local aim = carrotOnLeg(pos, Autopilot.LegStart, wp) - pos
	return if aim.Magnitude > 1e-3 then limitVertical(aim.Unit * toWp.Magnitude) else toWp
end

local function stepRTL(dt: number, pos: Vector3, groundY: number?): Vector3
	local home = Autopilot.Home
	local rtlY = math.max(pos.Y, home.Y + AP.RTL_ALT * S)
	local horizontal = Vector3.new(home.X - pos.X, 0, home.Z - pos.Z).Magnitude

	if Autopilot.Phase == "" then
		Autopilot.Phase = if horizontal < AP.WPNAV_RADIUS * S then "LOITER" else "CLIMB"
		Autopilot.PhaseTimer = 0
		Autopilot.Status = ""
	end
	-- Climb target is fixed when RTL starts so the return leg is level and straight.
	if Autopilot.Phase == "CLIMB" then
		if Autopilot.ClimbTargetY == 0 then
			Autopilot.ClimbTargetY = rtlY
		end
		Autopilot.Status = string.format("RTL: %.0f m'ye tırmanıyor", (Autopilot.ClimbTargetY - home.Y) / S)
		local target = Vector3.new(pos.X, Autopilot.ClimbTargetY, pos.Z)
		if math.abs(pos.Y - target.Y) < 0.5 * S then
			Autopilot.Phase = "RETURN"
		end
		return velocityToward(pos, target, 0)
	elseif Autopilot.Phase == "RETURN" then
		local target = Vector3.new(home.X, pos.Y, home.Z)
		Autopilot.Status = string.format("RTL: eve %.0f m", horizontal / S)
		if horizontal < 0.5 * S then
			Autopilot.Phase = "LOITER"
			Autopilot.PhaseTimer = 0
		end
		return velocityToward(pos, target, 0)
	elseif Autopilot.Phase == "LOITER" then
		Autopilot.PhaseTimer += dt
		Autopilot.Status = string.format("RTL: ev üstünde bekliyor %.0f sn", AP.RTL_LOIT_TIME - Autopilot.PhaseTimer)
		if Autopilot.PhaseTimer >= AP.RTL_LOIT_TIME then
			Autopilot.Phase = "DESCEND"
		end
		return velocityToward(pos, Vector3.new(home.X, pos.Y, home.Z), 0)
	end
	Autopilot.Status = string.format("RTL: iniş %.1f m", Autopilot.relAlt(pos))
	return landVelocity(pos, groundY)
end

-- Desired velocity (studs/s) for the autonomous modes; nil when the pilot is flying.
function Autopilot.guidance(dt: number, pos: Vector3, groundY: number?): Vector3?
	local mode = Autopilot.Mode
	if mode == "AUTO" then
		return stepAuto(pos)
	elseif mode == "RTL" then
		return stepRTL(dt, pos, groundY)
	elseif mode == "LAND" then
		Autopilot.Status = string.format("İNİŞ %.1f m", Autopilot.relAlt(pos))
		return landVelocity(pos, groundY)
	end
	Autopilot.Status = ""
	return nil
end

-- Failsafes checked every frame while armed (battery, geofence), like ArduPilot:
-- voltage must stay low for BATT_LOW_TIMER so a sag during a hard climb does not trigger it,
-- and a fence breach triggers RTL once, after which the pilot may take over.
local lowVoltTimer, critVoltTimer, fenceBreached = 0, 0, false

function Autopilot.checkFailsafes(dt: number, pos: Vector3, voltage: number)
	if not Autopilot.Armed or Autopilot.Mode == "CRASHED" then
		return
	end
	critVoltTimer = if voltage <= FS.BATT_CRT_VOLT then critVoltTimer + dt else 0
	lowVoltTimer = if voltage <= FS.BATT_LOW_VOLT then lowVoltTimer + dt else 0
	if critVoltTimer >= FS.BATT_LOW_TIMER and not Autopilot.FailsafeBatteryCritical then
		Autopilot.FailsafeBatteryCritical = true
		Autopilot.setMode("LAND", string.format("KRİTİK BATARYA %.1f V", voltage))
		return
	end
	if lowVoltTimer >= FS.BATT_LOW_TIMER and not Autopilot.FailsafeBatteryLow then
		Autopilot.FailsafeBatteryLow = true
		local reason = string.format("DÜŞÜK BATARYA %.1f V", voltage)
		if Autopilot.Mode == "RTL" then
			Autopilot.LastEvent = "RTL — " .. reason -- already returning; don't restart the RTL phases
		elseif Autopilot.Mode ~= "LAND" then
			Autopilot.setMode("RTL", reason)
		end
		return
	end

	local offset = pos - Autopilot.Home
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude / S
	local outside = distance > FS.FENCE_RADIUS or Autopilot.relAlt(pos) > FS.FENCE_ALT_MAX
	if outside and not fenceBreached and Autopilot.Mode ~= "LAND" then
		Autopilot.setMode("RTL", string.format("GEOFENCE İHLALİ (%.0f m, %.0f m irtifa)", distance, Autopilot.relAlt(pos)))
	end
	fenceBreached = outside
end

function Autopilot.resetFailsafes()
	lowVoltTimer, critVoltTimer, fenceBreached = 0, 0, false
	Autopilot.FailsafeBatteryLow = false
	Autopilot.FailsafeBatteryCritical = false
end

return Autopilot
