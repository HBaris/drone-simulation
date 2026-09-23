--!strict
-- BridgeClient.luau
-- Client half of the MAVLink bridge: packs the drone state for BridgeLink.server (ENU meters
-- relative to the launch pad, MAVLink sign conventions) and executes ground-station commands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local Autopilot = require(script.Parent:WaitForChild("Autopilot"))

local S = DroneConfig.STUDS_PER_METER
local PAD = DroneConfig.HOME.SIM_POSITION

local BridgeClient = {}

export type Context = {
	Drone: any, -- DronePhysics.State
	Telemetry: any, -- DroneHealthModel.Telemetry
	Wind: Vector3,
	OnGround: boolean,
	Crash: string,
	YawRate: number, -- deg/s, clockwise positive
}

-- Controller hooks for commands the autopilot alone cannot carry out
export type Hooks = {
	Arm: () -> boolean,
	Disarm: (force: boolean) -> (),
	Reset: () -> (),
	MotorTest: (motor: number, pct: number, seconds: number, delay: number) -> (),
}

function BridgeClient.enuToSim(e: number, n: number, u: number): Vector3
	return PAD + Vector3.new(e * S, u * S, -n * S)
end

local function simToEnu(v: Vector3): (number, number, number)
	return v.X / S, -v.Z / S, v.Y / S
end

local function round(x: number, digits: number): number
	local m = 10 ^ digits
	return math.round(x * m) / m
end

function BridgeClient.buildState(ctx: Context): { [string]: any }
	local d, t = ctx.Drone, ctx.Telemetry
	local e, n, u = simToEnu(d.Position - PAD)
	local ve, vn, vu = simToEnu(d.Velocity)
	local he, hn, hu = simToEnu(Autopilot.Home - PAD)
	local motors, rpm, temps, currents = {}, {}, {}, {}
	for i, m in ipairs(t.Motors) do
		motors[i], rpm[i], temps[i], currents[i] = round(m.Output, 3), math.round(m.Rpm), round(m.TempC, 1), round(m.CurrentA, 2)
	end
	return {
		mode = Autopilot.Mode,
		armed = Autopilot.Armed,
		status = Autopilot.Status,
		event = Autopilot.LastEvent,
		crash = ctx.Crash,
		on_ground = ctx.OnGround,
		mission_index = Autopilot.MissionIndex,
		e = round(e, 3), n = round(n, 3), u = round(u, 3),
		ve = round(ve, 3), vn = round(vn, 3), vu = round(vu, 3),
		home_e = round(he, 3), home_n = round(hn, 3), home_u = round(hu, 3),
		heading = round((-d.Yaw) % 360, 2),
		pitch = round(-d.Pitch, 2), -- MAVLink: nose up positive; sim: nose down positive
		roll = round(d.Roll, 2),
		yaw_rate = round(ctx.YawRate, 2),
		voltage = round(t.VoltageV, 3), cell_v = round(t.CellV, 3), current = round(t.CurrentA, 2),
		used_mah = round(t.UsedMah, 1), remaining = math.floor(t.RemainingPct),
		motors = motors, rpm = rpm, temps = temps, motor_currents = currents,
		wind = { round(ctx.Wind.X, 2), round(-ctx.Wind.Z, 2), round(ctx.Wind.Y, 2) },
		home_geo = DroneConfig.HOME.GEO,
	}
end

-- Executes one command from the bridge (see tools/dronebridge/mavsim.py for the producer).
function BridgeClient.execute(c: { [string]: any }, drone: any, hooks: Hooks)
	local kind = c.type
	if kind == "arm" then
		hooks.Arm()
	elseif kind == "disarm" then
		hooks.Disarm(c.force == true)
	elseif kind == "mode" then
		local mode = c.mode
		if mode == "HOLD" then
			Autopilot.setMode("GUIDED", c.reason or "konum tut")
		elseif mode == "MANUAL" or mode == "GUIDED" then
			-- ArduCopter lets you pick these on the ground (TEI flow: GUIDED -> ARM -> TAKEOFF)
			Autopilot.setMode(mode, c.reason or "yer istasyonu")
		elseif mode == "RTL" or mode == "LAND" then
			if Autopilot.Armed then -- only meaningful in the air
				Autopilot.setMode(mode, c.reason or "yer istasyonu")
			end
		end
	elseif kind == "takeoff" then
		if Autopilot.Armed then
			Autopilot.guidedTakeoff(drone.Position, c.alt)
		end
	elseif kind == "velocity" then
		Autopilot.guidedVelocityCommand(Vector3.new(c.ve * S, c.vu * S, -c.vn * S), c.yaw_rate or 0)
	elseif kind == "goto" then
		Autopilot.guidedGoto(BridgeClient.enuToSim(c.e, c.n, c.u))
	elseif kind == "mission" then
		local points, holds, speeds = {}, {}, {}
		for i, p in ipairs(c.points) do
			points[i] = BridgeClient.enuToSim(p.e, p.n, p.u)
			holds[i] = p.hold or 0
			speeds[i] = p.speed
		end
		if hooks.Arm() then
			Autopilot.startMission(points, { TakeoffAlt = c.takeoff_alt, Holds = holds, Speeds = speeds, End = c["end"] })
		end
	elseif kind == "motortest" then
		hooks.MotorTest(c.motor, c.pct, c.seconds, c.delay or 0)
	elseif kind == "param" then
		if c.name == "cruise_speed" then
			Autopilot.CruiseSpeed = math.clamp(c.value, 1, 20)
		elseif c.name == "rtl_alt" then
			Autopilot.RtlAlt = math.clamp(c.value, 2, 120)
		elseif c.name == "fence_radius" then
			Autopilot.FenceRadius = math.max(c.value, 10)
		end
	elseif kind == "reset" then
		hooks.Reset()
	end
end

return BridgeClient
