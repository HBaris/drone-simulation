--!strict
-- FlightMath.luau
-- Mathematical utilities for Drone trajectory calculation, Splines, Bank angles, and Geo-coordinates.

local DroneConfig = require(script.Parent.DroneConfig)

local FlightMath = {}

-- Catmull-Rom Spline Interpolation between 4 points
-- Passes directly through P1 (at t=0) and P2 (at t=1)
function FlightMath.catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t

	return 0.5 * (
		(2 * p1) +
		(-p0 + p2) * t +
		(2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
		(-p0 + 3 * p1 - 3 * p2 + p3) * t3
	)
end

-- Evaluates full path across multiple waypoints at normalized parameter 0 <= u <= 1
export type Waypoint = {
	Position: Vector3,
	Altitude: number, -- target height
	Yaw: number?,     -- target yaw in degrees (optional)
	WaitTime: number?,-- wait time in seconds (optional)
	Speed: number?,   -- segment target speed (optional)
	LedColor: Color3?,-- color for show (optional)
}

-- Computes total path length by sampling segments
function FlightMath.calculatePathLengths(points: { Vector3 }, samplesPerSegment: number?): ({ number }, number)
	local samples = samplesPerSegment or 10
	local segmentLengths: { number } = {}
	local totalLength = 0

	if #points < 2 then
		return segmentLengths, 0
	end

	for i = 1, #points - 1 do
		local p0 = points[math.max(1, i - 1)]
		local p1 = points[i]
		local p2 = points[i + 1]
		local p3 = points[math.min(#points, i + 2)]

		local segLen = 0
		local prevPos = p1
		for s = 1, samples do
			local t = s / samples
			local pos = FlightMath.catmullRom(p0, p1, p2, p3, t)
			segLen += (pos - prevPos).Magnitude
			prevPos = pos
		end
		table.insert(segmentLengths, segLen)
		totalLength += segLen
	end

	return segmentLengths, totalLength
end

-- Sample position and forward direction at arc-length distance `dist` along waypoints
function FlightMath.sampleSplineAtDistance(
	points: { Vector3 },
	segmentLengths: { number },
	totalLength: number,
	distance: number
): (Vector3, Vector3)
	if #points == 0 then
		return Vector3.zero, Vector3.new(0, 0, -1)
	elseif #points == 1 then
		return points[1], Vector3.new(0, 0, -1)
	end

	local targetDist = math.clamp(distance, 0, totalLength)
	local accumulated = 0
	local targetSegment = 1
	local localT = 0

	for i, len in ipairs(segmentLengths) do
		if accumulated + len >= targetDist or i == #segmentLengths then
			targetSegment = i
			local rem = targetDist - accumulated
			localT = if len > 0 then math.clamp(rem / len, 0, 1) else 0
			break
		end
		accumulated += len
	end

	local p0 = points[math.max(1, targetSegment - 1)]
	local p1 = points[targetSegment]
	local p2 = points[targetSegment + 1]
	local p3 = points[math.min(#points, targetSegment + 2)]

	local pos = FlightMath.catmullRom(p0, p1, p2, p3, localT)

	-- Compute tangent vector (forward look direction)
	local deltaT = 0.01
	local nextPos = FlightMath.catmullRom(p0, p1, p2, p3, math.min(1, localT + deltaT))
	local forward = (nextPos - pos)
	if forward.Magnitude > 0.001 then
		forward = forward.Unit
	else
		forward = Vector3.new(0, 0, -1)
	end

	return pos, forward
end

-- Calculates realistic quadcopter pitch and roll tilt based on velocity/acceleration
function FlightMath.computeDroneTilt(
	velocity: Vector3,
	acceleration: Vector3,
	baseCFrame: CFrame
): CFrame
	local maxTiltRad = math.rad(DroneConfig.FLIGHT.MAX_TILT_ANGLE)

	-- Transform acceleration into drone local coordinates
	local localAcc = baseCFrame:VectorToObjectSpace(acceleration)

	-- Pitch leans forward when accelerating forward (along -Z), leans back when braking
	local pitch = math.clamp(-localAcc.Z * 0.05, -maxTiltRad, maxTiltRad)
	-- Roll leans sideways when accelerating laterally (along +X)
	local roll = math.clamp(-localAcc.X * 0.05, -maxTiltRad, maxTiltRad)

	return CFrame.Angles(pitch, 0, roll)
end

-- Convert Roblox Vector3 (Studs, Y-up) to Real-World Drone Metric Coordinates (Meters, Z-up ENU)
function FlightMath.studsToMetersENU(pos: Vector3, origin: Vector3?): Vector3
	local ref = origin or Vector3.zero
	local rel = pos - ref
	local scale = 1 / DroneConfig.STUDS_PER_METER

	-- Roblox: X=East, Y=Altitude/Up, Z=South (-Z=North)
	local east = rel.X * scale
	local north = -rel.Z * scale
	local up = rel.Y * scale

	return Vector3.new(east, north, up)
end

-- Convert Real-World Metric (Meters ENU) to Roblox Vector3 (Studs, Y-up)
function FlightMath.metersENUToStuds(enu: Vector3, origin: Vector3?): Vector3
	local ref = origin or Vector3.zero
	local scale = DroneConfig.STUDS_PER_METER

	local x = enu.X * scale
	local y = enu.Z * scale
	local z = -enu.Y * scale

	return ref + Vector3.new(x, y, z)
end

return table.freeze(FlightMath)
