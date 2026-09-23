--!strict
-- DronePhysics.luau
-- Kinematic multirotor model shared by every flight mode.
-- Conventions: studs, Y up; Yaw in degrees counter-clockwise (forward = (-sin, 0, -cos));
-- Pitch > 0 = nose down (accelerating forward); Roll > 0 = right side down.
-- Wind (m/s, from WindModel) acts through air drag on the air-relative velocity. The flight
-- controller only knows a lagged wind estimate (like the EKF's), so gusts push the drone off its
-- path until the estimate catches up, and past the tilt limit the drone cannot hold against it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local S = DroneConfig.STUDS_PER_METER
local GRAVITY = 9.81
local AP = DroneConfig.AUTOPILOT

-- Manual (Angle + altitude hold, like ArduPilot AltHold)
local MAX_SPEED = DroneConfig.FLIGHT.MAX_HORIZONTAL_SPEED * 1.5 -- studs/s (~8.5 m/s)
local CLIMB_RATE = DroneConfig.FLIGHT.MAX_CLIMB_SPEED
local YAW_SPEED = 100.0
local TILT_LIMIT = 35.0
local AUTO_LEVEL_SPEED = 6.0

local DronePhysics = {}

export type State = {
	Position: Vector3,
	Velocity: Vector3,
	Yaw: number,
	Pitch: number,
	Roll: number,
	ThrustAccel: Vector3, -- m/s² the rotors produce this frame (excluding gravity) -> motor model
	WindEst: Vector3, -- m/s, the controller's estimate of the wind
	Saturated: boolean, -- needed more tilt than TILT_LIMIT (losing against the wind)
}

export type StickInput = { Forward: number, Right: number, Up: number, Yaw: number } -- each -1..1

function DronePhysics.new(position: Vector3, yaw: number): State
	return {
		Position = position, Velocity = Vector3.zero, Yaw = yaw, Pitch = 0, Roll = 0,
		ThrustAccel = Vector3.zero, WindEst = Vector3.zero, Saturated = false,
	}
end

function DronePhysics.forward(yawDeg: number): Vector3
	local r = math.rad(yawDeg)
	return Vector3.new(-math.sin(r), 0, -math.cos(r))
end

function DronePhysics.right(yawDeg: number): Vector3
	local r = math.rad(yawDeg)
	return Vector3.new(math.cos(r), 0, -math.sin(r))
end

local MAX_TILT_ACCEL = GRAVITY * math.tan(math.rad(TILT_LIMIT)) -- m/s² of horizontal thrust available
local WIND_ESTIMATE_TAU = 2.0 -- s, how fast the controller learns a change in wind

-- Horizontal acceleration the rotors must produce against air drag (m/s²) for a ground velocity
-- (studs/s) in a wind (m/s).
local function dragCompensation(velocity: Vector3, wind: Vector3): Vector3
	local air = Vector3.new(velocity.X / S - wind.X, 0, velocity.Z / S - wind.Z)
	return air * air.Magnitude * DroneConfig.AIRFRAME.DRAG_COEFF
end

local function horizontal(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function smoothAttitude(s: State, dt: number, targetPitch: number, targetRoll: number)
	local k = math.min(1, AUTO_LEVEL_SPEED * dt)
	s.Pitch += (targetPitch - s.Pitch) * k
	s.Roll += (targetRoll - s.Roll) * k
end

-- Manual (Angle + altitude hold): stick tilt sets the velocity relative to the AIR, so with the
-- sticks centred the drone drifts with the wind, exactly like ArduPilot AltHold / Stabilize.
function DronePhysics.stepManual(s: State, dt: number, stick: StickInput, wind: Vector3)
	smoothAttitude(s, dt, stick.Forward * TILT_LIMIT, stick.Right * TILT_LIMIT)
	s.Yaw = (s.Yaw - stick.Yaw * YAW_SPEED * dt) % 360

	local targetH = DronePhysics.forward(s.Yaw) * (s.Pitch / TILT_LIMIT) * MAX_SPEED
		+ DronePhysics.right(s.Yaw) * (s.Roll / TILT_LIMIT) * MAX_SPEED
		+ horizontal(wind) * S
	local v = s.Velocity
	local vy = v.Y + (stick.Up * CLIMB_RATE - v.Y) * 0.15 + wind.Y * S * dt
	local newVelocity = Vector3.new(v.X + (targetH.X - v.X) * 0.1, vy, v.Z + (targetH.Z - v.Z) * 0.1)
	local kinematic = if dt > 0 then (newVelocity - v) / dt else Vector3.zero
	s.Velocity = newVelocity
	s.Position += s.Velocity * dt
	s.WindEst = wind
	s.ThrustAccel = kinematic / S + dragCompensation(s.Velocity, wind)
	s.Saturated = false
end

-- Autonomous modes: follow the autopilot's desired velocity with ArduPilot's acceleration limits
-- (WPNAV_ACCEL along the path, 2x sideways like WPNAV_ACCEL_C), face the direction of travel and
-- lean exactly as much as the acceleration + drag requires.
local function clampLength(v: Vector3, maxLen: number): Vector3
	return if v.Magnitude > maxLen then v.Unit * maxLen else v
end

function DronePhysics.stepGuided(s: State, dt: number, desiredVelocity: Vector3, wind: Vector3)
	local dv = desiredVelocity - s.Velocity
	local along = if desiredVelocity.Magnitude > 1e-3 then desiredVelocity.Unit else Vector3.zero
	local dvAlong = along * dv:Dot(along)
	dv = clampLength(dvAlong, AP.WPNAV_ACCEL * S * dt) + clampLength(dv - dvAlong, 2 * AP.WPNAV_ACCEL * S * dt)
	local commanded = if dt > 0 then dv / dt / S else Vector3.zero -- m/s²

	-- The controller feeds forward drag from its (lagged) wind estimate; the real drag uses the real wind
	s.WindEst = s.WindEst:Lerp(wind, math.min(1, dt / WIND_ESTIMATE_TAU))
	local thrustH = horizontal(commanded) + dragCompensation(s.Velocity, s.WindEst)
	s.Saturated = thrustH.Magnitude > MAX_TILT_ACCEL
	thrustH = clampLength(thrustH, MAX_TILT_ACCEL)
	local actualH = thrustH - dragCompensation(s.Velocity, wind)
	local actualY = commanded.Y + (wind.Y - s.WindEst.Y) -- vertical gusts: 1/s coupling
	s.ThrustAccel = Vector3.new(thrustH.X, commanded.Y, thrustH.Z)
	s.Velocity += Vector3.new(actualH.X, actualY, actualH.Z) * S * dt
	s.Position += s.Velocity * dt

	local hv = Vector3.new(s.Velocity.X, 0, s.Velocity.Z)
	if hv.Magnitude > 1.0 * S then
		local targetYaw = math.deg(math.atan2(-hv.X, -hv.Z))
		local diff = (targetYaw - s.Yaw + 180) % 360 - 180
		local maxStep = AP.YAW_RATE * dt
		s.Yaw = (s.Yaw + math.clamp(diff, -maxStep, maxStep)) % 360
	end

	local a = thrustH
	local targetPitch = math.deg(math.atan(a:Dot(DronePhysics.forward(s.Yaw)) / GRAVITY))
	local targetRoll = math.deg(math.atan(a:Dot(DronePhysics.right(s.Yaw)) / GRAVITY))
	smoothAttitude(s, dt, math.clamp(targetPitch, -TILT_LIMIT, TILT_LIMIT), math.clamp(targetRoll, -TILT_LIMIT, TILT_LIMIT))
end

-- Lost a motor / crashed: free fall with the frame spinning and flipping.
function DronePhysics.stepCrash(s: State, dt: number, wind: Vector3)
	s.Velocity += Vector3.new(0, -GRAVITY * S * dt, 0) - dragCompensation(s.Velocity, wind) * S * dt
	s.ThrustAccel = Vector3.zero
	s.Velocity *= (1 - 0.3 * dt)
	s.Position += s.Velocity * dt
	s.Yaw = (s.Yaw + 540 * dt) % 360
	s.Roll = math.min(s.Roll + 90 * dt, 70)
end

function DronePhysics.cframe(s: State): CFrame
	-- Negative X rotation tips the nose (-Z) down for positive pitch.
	return CFrame.new(s.Position) * CFrame.Angles(0, math.rad(s.Yaw), 0) * CFrame.Angles(-math.rad(s.Pitch), 0, -math.rad(s.Roll))
end

return DronePhysics
