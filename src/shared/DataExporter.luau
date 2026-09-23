--!strict
-- DataExporter.luau
-- Serializes simulation trajectories to JSON / CSV formats for physical drone firmware loading.

local HttpService = game:GetService("HttpService")
local DroneConfig = require(script.Parent.DroneConfig)
local FlightMath = require(script.Parent.FlightMath)

local DataExporter = {}

export type DroneTrajectoryPoint = {
	t: number,       -- Time offset in seconds
	x: number,       -- East coordinate in meters
	y: number,       -- North coordinate in meters
	z: number,       -- Altitude in meters (Up)
	yaw: number,     -- Heading in degrees
	r: number,       -- LED Red (0-255)
	g: number,       -- LED Green (0-255)
	b: number,       -- LED Blue (0-255)
}

export type DroneMissionPlan = {
	drone_id: number,
	export_timestamp: number,
	sample_rate_hz: number,
	total_duration_sec: number,
	points: { DroneTrajectoryPoint },
}

-- Convert Waypoints list of Roblox coordinates to time-sampled physical metric mission
function DataExporter.generateMissionFromPath(
	droneId: number,
	waypoints: { FlightMath.Waypoint },
	sampleRateHz: number?,
	originRef: Vector3?
): DroneMissionPlan
	local hz = sampleRateHz or 10 -- 10Hz standard telemetry rate
	local dt = 1 / hz
	local positions: { Vector3 } = {}

	for _, wp in ipairs(waypoints) do
		table.insert(positions, wp.Position)
	end

	local segLengths, totalLen = FlightMath.calculatePathLengths(positions)
	local avgSpeed = DroneConfig.FLIGHT.MAX_HORIZONTAL_SPEED
	local totalDuration = if totalLen > 0 then (totalLen / avgSpeed) else 5.0
	local totalSamples = math.ceil(totalDuration * hz)

	local missionPoints: { DroneTrajectoryPoint } = {}

	for s = 0, totalSamples do
		local t = s * dt
		local dist = (t / totalDuration) * totalLen
		local robloxPos, forwardVec = FlightMath.sampleSplineAtDistance(positions, segLengths, totalLen, dist)

		-- Convert to meters ENU (East, North, Up)
		local metricPos = FlightMath.studsToMetersENU(robloxPos, originRef)

		-- Calculate yaw angle from forward vector
		local yawDeg = math.deg(math.atan2(-forwardVec.X, -forwardVec.Z))
		if yawDeg < 0 then
			yawDeg += 360
		end

		table.insert(missionPoints, {
			t = math.round(t * 100) / 100,
			x = math.round(metricPos.X * 100) / 100,
			y = math.round(metricPos.Y * 100) / 100,
			z = math.round(metricPos.Z * 100) / 100,
			yaw = math.round(yawDeg * 10) / 10,
			r = 0,
			g = 255,
			b = 120,
		})
	end

	return {
		drone_id = droneId,
		export_timestamp = os.time(),
		sample_rate_hz = hz,
		total_duration_sec = math.round(totalDuration * 100) / 100,
		points = missionPoints,
	}
end

-- Export single drone mission to JSON
function DataExporter.exportToJSON(mission: DroneMissionPlan): string
	return HttpService:JSONEncode(mission)
end

-- Export single drone mission to CSV (t, x_m, y_m, z_m, yaw_deg, r, g, b)
function DataExporter.exportToCSV(mission: DroneMissionPlan): string
	local lines = {
		"# Drone Light Show Trajectory Export",
		string.format("# Drone ID: %d | Total Duration: %.2fs | Rate: %d Hz", mission.drone_id, mission.total_duration_sec, mission.sample_rate_hz),
		"time_sec,x_east_m,y_north_m,z_up_m,yaw_deg,led_r,led_g,led_b"
	}

	for _, pt in ipairs(mission.points) do
		table.insert(lines, string.format(
			"%.2f,%.3f,%.3f,%.3f,%.1f,%d,%d,%d",
			pt.t, pt.x, pt.y, pt.z, pt.yaw, pt.r, pt.g, pt.b
		))
	end

	return table.concat(lines, "\n")
end

-- Export entire swarm (all 800 drones) into one consolidated JSON dictionary
function DataExporter.exportSwarmToJSON(swarmMissions: { [number]: DroneMissionPlan }): string
	local swarmPackage = {
		project = "Drone Light Show Simulation",
		created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		drone_count = 0,
		drones = swarmMissions,
	}

	for _ in pairs(swarmMissions) do
		swarmPackage.drone_count += 1
	end

	return HttpService:JSONEncode(swarmPackage)
end

-- Parse and Import mission from JSON
function DataExporter.importFromJSON(jsonString: string): DroneMissionPlan?
	local success, result = pcall(function()
		return HttpService:JSONDecode(jsonString)
	end)

	if success and type(result) == "table" and result.points then
		return result :: DroneMissionPlan
	end

	warn("[DataExporter] Failed to parse JSON mission:", result)
	return nil
end

return table.freeze(DataExporter)
