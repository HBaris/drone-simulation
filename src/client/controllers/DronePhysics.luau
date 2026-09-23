--!strict
-- DronePhysics.luau
-- Kinematic multirotor model shared by every flight mode.
-- Conventions: studs, Y up; Yaw in degrees counter-clockwise (forward = (-sin, 0, -cos));
-- Pitch > 0 = nose down (accelerating forward); Roll > 0 = right side down.

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
}

export type StickInput = { Forward: number, Right: number, Up: number, Yaw: number } -- each -1..1

function DronePhysics.new(position: Vector3, yaw: number): State
	return { Position = position, Velocity = Vector3.zero, Yaw = yaw, Pitch = 0, Roll = 0 }
end

function DronePhysics.forward(yawDeg: number): Vector3
	local r = math.rad(yawDeg)
	return Vector3.new(-math.sin(r), 0, -math.cos(r))
end

function DronePhysics.right(yawDeg: number): Vector3
	local r = math.rad(yawDeg)
	return Vector3.new(math.cos(r), 0, -math.sin(r))
end

-- Horizontal acceleration the rotors must produce against air drag (m/s²), along the velocity.
local function dragCompensation(velocity: Vector3): Vector3
	local hv = Vector3.new(velocity.X, 0, velocity.Z) / S
	return hv * hv.Magnitude * DroneConfig.AIRFRAME.DRAG_COEFF
end

-- Total acceleration the thrust vector has to provide (m/s², excluding gravity).
function DronePhysics.thrustAccel(velocity: Vector3, kinematicAccelStuds: Vector3): Vector3
	return kinematicAccelStuds / S + dragCompensation(velocity)
end

local function smoothAttitude(s: State, dt: number, targetPitch: number, targetRoll: number)
	local k = math.min(1, AUTO_LEVEL_SPEED * dt)
	s.Pitch += (targetPitch - s.Pitch) * k
	s.Roll += (targetRoll - s.Roll) * k
end

function DronePhysics.stepManual(s: State, dt: number, stick: StickInput)
	smoothAttitude(s, dt, stick.Forward * TILT_LIMIT, stick.Right * TILT_LIMIT)
	s.Yaw = (s.Yaw - stick.Yaw * YAW_SPEED * dt) % 360

	local targetH = DronePhysics.forward(s.Yaw) * (s.Pitch / TILT_LIMIT) * MAX_SPEED
		+ DronePhysics.right(s.Yaw) * (s.Roll / TILT_LIMIT) * MAX_SPEED
	local v = s.Velocity
	local vy = v.Y + (stick.Up * CLIMB_RATE - v.Y) * 0.15
	s.Velocity = Vector3.new(v.X + (targetH.X - v.X) * 0.1, vy, v.Z + (targetH.Z - v.Z) * 0.1)
	s.Position += s.Velocity * dt
end

-- Autonomous modes: follow the autopilot's desired velocity with ArduPilot's acceleration limits
-- (WPNAV_ACCEL along the path, 2x sideways like WPNAV_ACCEL_C), face the direction of travel and
-- lean exactly as much as the acceleration + drag requires.
local function clampLength(v: Vector3, maxLen: number): Vector3
	return if v.Magnitude > maxLen then v.Unit * maxLen else v
end

function DronePhysics.stepGuided(s: State, dt: number, desiredVelocity: Vector3)
	local dv = desiredVelocity - s.Velocity
	local along = if desiredVelocity.Magnitude > 1e-3 then desiredVelocity.Unit else Vector3.zero
	local dvAlong = along * dv:Dot(along)
	dv = clampLength(dvAlong, AP.WPNAV_ACCEL * S * dt) + clampLength(dv - dvAlong, 2 * AP.WPNAV_ACCEL * S * dt)
	s.Velocity += dv
	s.Position += s.Velocity * dt

	local hv = Vector3.new(s.Velocity.X, 0, s.Velocity.Z)
	if hv.Magnitude > 1.0 * S then
		local targetYaw = math.deg(math.atan2(-hv.X, -hv.Z))
		local diff = (targetYaw - s.Yaw + 180) % 360 - 180
		local maxStep = AP.YAW_RATE * dt
		s.Yaw = (s.Yaw + math.clamp(diff, -maxStep, maxStep)) % 360
	end

	local a = DronePhysics.thrustAccel(s.Velocity, if dt > 0 then dv / dt else Vector3.zero)
	local targetPitch = math.deg(math.atan(a:Dot(DronePhysics.forward(s.Yaw)) / GRAVITY))
	local targetRoll = math.deg(math.atan(a:Dot(DronePhysics.right(s.Yaw)) / GRAVITY))
	smoothAttitude(s, dt, math.clamp(targetPitch, -TILT_LIMIT, TILT_LIMIT), math.clamp(targetRoll, -TILT_LIMIT, TILT_LIMIT))
end

-- Lost a motor / crashed: free fall with the frame spinning and flipping.
function DronePhysics.stepCrash(s: State, dt: number)
	s.Velocity += Vector3.new(0, -GRAVITY * S * dt, 0)
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
