--!strict
-- FlightPackage.luau
-- Encodes simulator flights as "drone-sim-flight" JSON: meters East/North/Up relative to the
-- launch pad (DroneConfig.HOME). tools/sim2mission.py turns this into a Pixhawk mission
-- (.plan / .waypoints) anchored at the real drone's GPS home.

local DroneConfig = require(script.Parent.DroneConfig)
local FlightMath = require(script.Parent.FlightMath)

local FlightPackage = {}

export type RecordedSample = {
	t: number,        -- seconds since recording start
	Position: Vector3, -- Roblox studs
	Yaw: number,       -- simulator yaw in degrees (pilot controller convention)
	Pitch: number,
	Roll: number,
}

local function toENU(pos: Vector3): Vector3
	return FlightMath.studsToMetersENU(pos, DroneConfig.HOME.SIM_POSITION)
end

-- Pilot controller yaw turns counter-clockwise from North; compass heading turns clockwise.
function FlightPackage.headingFromSimYaw(simYawDeg: number): number
	return (-simYawDeg) % 360
end

-- Compass heading (0 = North, 90 = East) of a Roblox direction vector (-Z is North).
function FlightPackage.headingFromVector(dir: Vector3): number
	return math.deg(math.atan2(dir.X, -dir.Z)) % 360
end

local function header(source: string, extra: string): string
	-- Real-world sites know the launch pad's GPS, so the converter can place the mission there.
	local geo = DroneConfig.HOME.GEO
	local homeGeo = if geo then string.format('"home_geo":[%.7f,%.7f],', geo[1], geo[2]) else ""
	return string.format(
		'{"format":"drone-sim-flight","version":1,"source":"%s","frame":"ENU_m_relative_to_home",'
			.. '"site":"%s",%s"stud_per_meter":%s,"created_at":"%s",%s',
		source,
		DroneConfig.ACTIVE_SITE,
		homeGeo,
		tostring(DroneConfig.STUDS_PER_METER),
		DateTime.now():ToIsoDate(),
		extra
	)
end

-- Manual flight recording. Built by hand (not JSONEncode) to keep 10 Hz recordings compact
-- enough for the copy modal.
function FlightPackage.encodeRecording(samples: { RecordedSample }, sampleRateHz: number): string
	local rows = table.create(#samples)
	for i, s in ipairs(samples) do
		local enu = toENU(s.Position)
		rows[i] = string.format(
			"[%.2f,%.2f,%.2f,%.2f,%.0f]",
			s.t,
			enu.X,
			enu.Y,
			enu.Z,
			FlightPackage.headingFromSimYaw(s.Yaw)
		)
	end
	return header(
		"manual_recording",
		string.format('"sample_rate_hz":%d,"columns":["t","e","n","u","hdg"],"samples":[', sampleRateHz)
	) .. table.concat(rows, ",") .. "]}"
end

-- Waypoint route drawn in the editor. Real drones fly straight legs between waypoints, so the
-- waypoints themselves are exported, not the spline the simulator draws through them.
function FlightPackage.encodeRoute(waypoints: { FlightMath.Waypoint }): string
	local rows = table.create(#waypoints)
	for i, wp in ipairs(waypoints) do
		local enu = toENU(wp.Position)
		local speed = if wp.Speed then string.format(',"speed":%.2f', wp.Speed / DroneConfig.STUDS_PER_METER) else ""
		rows[i] = string.format('{"e":%.2f,"n":%.2f,"u":%.2f%s}', enu.X, enu.Y, enu.Z, speed)
	end
	return header("waypoint_route", '"waypoints":[') .. table.concat(rows, ",") .. "]}"
end

return table.freeze(FlightPackage)
