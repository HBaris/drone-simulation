--!strict
-- Autopilot.luau
-- Flight modes and guidance for the primary drone, modelled on ArduPilot Copter:
--   MANUAL (pilot, altitude-hold style) · GUIDED (hold / velocity / go-to / takeoff, driven by a
--   ground station) · AUTO (mission) · RTL · LAND · CRASHED
-- AUTO flies the same mission tools/sim2mission.py writes (TAKEOFF -> straight legs -> RTL) and the
-- missions a GCS uploads through the MAVLink bridge (holds, speed changes, RTL/LAND/hold at the end).
-- Shared singleton: the pilot controller runs it; the route editor and the bridge command it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local S = DroneConfig.STUDS_PER_METER
local AP = DroneConfig.AUTOPILOT
local FS = DroneConfig.FAILSAFE

export type Mode = "MANUAL" | "GUIDED" | "AUTO" | "RTL" | "LAND" | "CRASHED"
export type MissionEnd = "RTL" | "LAND" | "HOLD"
export type MissionOptions = {
	TakeoffAlt: number?, -- m above home
	Holds: { number }?, -- s to wait at each waypoint
	Speeds: { number? }?, -- m/s on the leg into each waypoint (nil = cruise speed)
	End: MissionEnd?,
}

local GUIDED_VELOCITY_TIMEOUT = 3 -- s, like ArduPilot: stop if the GCS stops sending velocity

local Autopilot = {
	Mode = "MANUAL" :: Mode,
	Armed = false,
	Home = DroneConfig.HOME.SIM_POSITION, -- set where the drone arms, like a real flight controller
	Status = "", -- human-readable phase, e.g. "WP 2/5" or "RTL: eve dönüyor"
	LastEvent = "", -- last mode change reason / failsafe
	Mission = {} :: { Vector3 },
	MissionOptions = {} :: MissionOptions,
	MissionIndex = 0,
	Phase = "",
	PhaseTimer = 0,
	ClimbTargetY = 0,
	LegStart = Vector3.zero, -- start of the current straight leg (cross-track reference)
	FailsafeBatteryLow = false,
	FailsafeBatteryCritical = false,
	-- Live parameters (a GCS can change them through the bridge)
	CruiseSpeed = AP.WPNAV_SPEED,
	RtlAlt = AP.RTL_ALT,
	FenceRadius = FS.FENCE_RADIUS,
	-- GUIDED state
	GuidedTarget = nil :: Vector3?,
	GuidedVelocity = nil :: Vector3?, -- studs/s
	GuidedYawRate = 0, -- deg/s, clockwise positive (MAVLink)
	GuidedVelocityAge = 0,
}

function Autopilot.setMode(mode: Mode, reason: string?)
	if Autopilot.Mode == "CRASHED" and mode ~= "MANUAL" then
		return
	end
	Autopilot.Mode = mode
	Autopilot.Phase = ""
	Autopilot.PhaseTimer = 0
	Autopilot.ClimbTargetY = 0
	if mode == "GUIDED" then
		Autopilot.GuidedTarget = nil -- hold wherever the drone is when guidance next runs
		Autopilot.GuidedVelocity = nil
	end
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

-- Waypoint positions in studs. Mirrors a real mission: take off vertically, fly straight legs,
-- then RTL (default), LAND at the last point, or HOLD there (ArduCopter's default at mission end).
function Autopilot.startMission(points: { Vector3 }, options: MissionOptions?)
	if #points == 0 or Autopilot.Mode == "CRASHED" then
		return
	end
	Autopilot.Mission = table.clone(points)
	Autopilot.MissionOptions = options or {}
	Autopilot.MissionIndex = 0 -- 0 = takeoff leg
	Autopilot.setMode("AUTO", string.format("%d waypoint", #points))
end

-- GUIDED commands from a ground station
function Autopilot.guidedTakeoff(pos: Vector3, altM: number)
	if Autopilot.Mode ~= "GUIDED" then
		Autopilot.setMode("GUIDED", "kalkış")
	end
	Autopilot.GuidedTarget = Vector3.new(pos.X, Autopilot.Home.Y + altM * S, pos.Z)
	Autopilot.GuidedVelocity = nil
end

function Autopilot.guidedGoto(target: Vector3)
	if Autopilot.Mode ~= "GUIDED" then
		Autopilot.setMode("GUIDED", "hedefe git")
	end
	Autopilot.GuidedTarget = target
	Autopilot.GuidedVelocity = nil
end

function Autopilot.guidedVelocityCommand(velocityStuds: Vector3, yawRateDeg: number)
	if Autopilot.Mode ~= "GUIDED" then
		return -- ArduPilot ignores velocity targets outside GUIDED
	end
	Autopilot.GuidedVelocity = velocityStuds
	Autopilot.GuidedYawRate = yawRateDeg
	Autopilot.GuidedVelocityAge = 0
end

-- Heading control in GUIDED (nil = face the direction of travel): the GCS's yaw rate while it sends
-- velocity, heading held while holding position (like ArduPilot), facing the target on a go-to.
function Autopilot.commandedYawRate(): number?
	if Autopilot.Mode ~= "GUIDED" then
		return nil
	end
	if Autopilot.GuidedVelocity then
		return Autopilot.GuidedYawRate
	end
	return if Autopilot.Status == "GUIDED: konum tutuyor" then 0 else nil
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
local function velocityToward(pos: Vector3, target: Vector3, endSpeed: number, cruise: number?): Vector3
	local delta = target - pos
	local dist = delta.Magnitude
	if dist < 1e-3 then
		return Vector3.zero
	end
	local brake = math.sqrt((endSpeed * S) ^ 2 + 2 * AP.WPNAV_ACCEL * S * dist)
	local speed = math.min((cruise or Autopilot.CruiseSpeed) * S, brake)
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

local function stepAuto(dt: number, pos: Vector3): Vector3
	local radius = AP.WPNAV_RADIUS * S
	local options = Autopilot.MissionOptions
	if Autopilot.MissionIndex == 0 then
		local takeoffAlt = options.TakeoffAlt or AP.TAKEOFF_ALT
		local target = Vector3.new(pos.X, Autopilot.Home.Y + takeoffAlt * S, pos.Z)
		Autopilot.Status = string.format("KALKIŞ → %.0f m", takeoffAlt)
		-- Like NAV_TAKEOFF: done once at (or already above) the takeoff altitude
		if pos.Y >= target.Y - 0.5 * S then
			Autopilot.MissionIndex = 1
			Autopilot.LegStart = pos
		end
		return velocityToward(pos, target, 0)
	end

	local mission = Autopilot.Mission
	local index = Autopilot.MissionIndex
	local wp = mission[index]
	if not wp then
		local finish = options.End or "RTL"
		if finish == "HOLD" then
			Autopilot.Status = "görev bitti — son noktada bekliyor"
			return velocityToward(pos, mission[#mission], 0)
		end
		Autopilot.setMode(finish, "görev tamamlandı")
		return Vector3.zero
	end

	-- Waypoint hold time (MISSION_ITEM param1)
	if Autopilot.Phase == "WPHOLD" then
		Autopilot.PhaseTimer += dt
		local hold = (options.Holds and options.Holds[index]) or 0
		Autopilot.Status = string.format("WP %d/%d  bekliyor %.0f sn", index, #mission, hold - Autopilot.PhaseTimer)
		if Autopilot.PhaseTimer >= hold then
			Autopilot.Phase = ""
			Autopilot.MissionIndex += 1
			Autopilot.LegStart = wp
		end
		return velocityToward(pos, wp, 0)
	end

	local hold = (options.Holds and options.Holds[index]) or 0
	local cruise = options.Speeds and options.Speeds[index]
	Autopilot.Status = string.format("WP %d/%d  %.0f m", index, #mission, (wp - pos).Magnitude / S)
	if (wp - pos).Magnitude < radius then
		if hold > 0 then
			Autopilot.Phase, Autopilot.PhaseTimer = "WPHOLD", 0
			return velocityToward(pos, wp, 0)
		end
		Autopilot.MissionIndex += 1
		Autopilot.LegStart = wp
	end
	-- Slow down for the corner into the next leg (a 90° turn is taken at 1/4 cruise speed);
	-- stop completely if the drone must hold at the waypoint
	local nextWp = mission[Autopilot.MissionIndex + 1]
	local cornerSpeed = 0
	if hold <= 0 and nextWp and (wp - pos).Magnitude > 1e-3 and (nextWp - wp).Magnitude > 1e-3 then
		local cosTurn = (wp - pos).Unit:Dot((nextWp - wp).Unit)
		cornerSpeed = (cruise or Autopilot.CruiseSpeed) * ((1 + cosTurn) / 2) ^ 2
	end
	-- Speed comes from the distance to the waypoint, direction from the carrot on the leg
	local toWp = velocityToward(pos, wp, cornerSpeed, cruise)
	local aim = carrotOnLeg(pos, Autopilot.LegStart, wp) - pos
	return if aim.Magnitude > 1e-3 then limitVertical(aim.Unit * toWp.Magnitude) else toWp
end

local function stepGuided(dt: number, pos: Vector3): Vector3
	if Autopilot.GuidedVelocity then
		Autopilot.GuidedVelocityAge += dt
		if Autopilot.GuidedVelocityAge <= GUIDED_VELOCITY_TIMEOUT then
			local v = Autopilot.GuidedVelocity :: Vector3
			Autopilot.Status = string.format("GUIDED: hız %.1f m/s", v.Magnitude / S)
			return limitVertical(v)
		end
		Autopilot.GuidedVelocity = nil -- command stream stopped: brake and hold here
		Autopilot.GuidedTarget = pos
	end
	local target = Autopilot.GuidedTarget or pos
	Autopilot.GuidedTarget = target
	local dist = (target - pos).Magnitude / S
	Autopilot.Status = if dist > 1 then string.format("GUIDED: hedefe %.0f m", dist) else "GUIDED: konum tutuyor"
	return velocityToward(pos, target, 0)
end

local function stepRTL(dt: number, pos: Vector3, groundY: number?): Vector3
	local home = Autopilot.Home
	local rtlY = math.max(pos.Y, home.Y + Autopilot.RtlAlt * S)
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
		return stepAuto(dt, pos)
	elseif mode == "GUIDED" then
		return stepGuided(dt, pos)
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
	local outside = distance > Autopilot.FenceRadius or Autopilot.relAlt(pos) > FS.FENCE_ALT_MAX
	if outside and not fenceBreached and Autopilot.Mode ~= "LAND" then
		Autopilot.setMode("RTL", string.format("GEOFENCE İHLALİ (%.0f m, %.0f m irtifa)", distance, Autopilot.relAlt(pos)))
	end
	fenceBreached = outside
end

-- ArduPilot fence avoidance (AVOID_ENABLE) in pilot modes: the drone slows down and stops FENCE_MARGIN
-- inside the altitude ceiling and the circle, instead of flying through and triggering RTL.
-- `velocity` in studs/s, `estPos` = what the flight controller believes. Returns the allowed velocity.
function Autopilot.fenceLimitVelocity(estPos: Vector3, velocity: Vector3): (Vector3, boolean)
	local limited = false
	local v = velocity
	local ceiling = FS.FENCE_ALT_MAX - FS.FENCE_MARGIN
	local alt = Autopilot.relAlt(estPos)
	if v.Y > 0 then
		local allowed = math.max(0, ceiling - alt) * S -- 1 m/s per meter left: smooth stop at the ceiling
		if v.Y > allowed then
			v = Vector3.new(v.X, allowed, v.Z)
			limited = alt > ceiling - 5
		end
	end
	local offset = Vector3.new(estPos.X - Autopilot.Home.X, 0, estPos.Z - Autopilot.Home.Z)
	local dist = offset.Magnitude / S
	local edge = Autopilot.FenceRadius - FS.FENCE_MARGIN
	if dist > 1 then
		local out = offset.Unit
		local outward = Vector3.new(v.X, 0, v.Z):Dot(out)
		local allowed = math.max(0, edge - dist) * S
		if outward > allowed then
			v -= out * (outward - allowed)
			limited = limited or dist > edge - 10
		end
	end
	if limited then
		Autopilot.Status = string.format("⚠ SANAL SINIR: tavan %.0f m · yarıçap %.0f m", FS.FENCE_ALT_MAX, Autopilot.FenceRadius)
	end
	return v, limited
end

function Autopilot.resetFailsafes()
	lowVoltTimer, critVoltTimer, fenceBreached = 0, 0, false
	Autopilot.FailsafeBatteryLow = false
	Autopilot.FailsafeBatteryCritical = false
end

return Autopilot
