--!strict
-- DronePilotController.client.luau
-- First-Person & Chase-Camera Manual Flight Controller for Quadcopter Drone in Istanbul.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local FPVOverlay = require(script.Parent.Parent:WaitForChild("ui"):WaitForChild("FPVOverlay"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- Initialize FPV OSD HUD
local osd = FPVOverlay.create(playerGui)

-- Flight State Variables
local isManualPilotActive = true
local cameraMode = "FPV" -- "FPV" or "CHASE"

local dronePosition = Vector3.new(-220, 4.0, 0) -- Starts at Helipad on European coast
local droneVelocity = Vector3.zero
local droneYaw = -90.0 -- Facing East towards Bosphorus Bridge and Asian side!
local dronePitch = 0.0
local droneRoll = 0.0

-- Flight Tuning Limits
local MAX_SPEED = DroneConfig.FLIGHT.MAX_HORIZONTAL_SPEED * 1.5 -- studs/sec (~10 m/s)
local CLIMB_RATE = DroneConfig.FLIGHT.MAX_CLIMB_SPEED
local YAW_SPEED = 100.0 -- deg/sec
local PITCH_LIMIT = 35.0 -- deg
local ROLL_LIMIT = 35.0 -- deg
local DRAG = 0.95
local AUTO_LEVEL_SPEED = 6.0

-- Sound Source
local motorSound = Instance.new("Sound")
motorSound.Name = "DroneMotorSound"
motorSound.SoundId = "rbxassetid://9114223170" -- Quadcopter electric motor loop
motorSound.Volume = 0.5
motorSound.Looped = true
motorSound.PlaybackSpeed = 1.0
motorSound.Parent = Workspace

-- Find or Wait for Primary Drone Model
local function getPrimaryDrone(): Model?
	local swarm = Workspace:WaitForChild("DroneSwarm", 5)
	if swarm then
		return swarm:FindFirstChild("Drone_001") :: Model?
	end
	return nil
end

-- Key State Tracking
local keysDown = {
	W = false, S = false, A = false, D = false,
	Space = false, LeftShift = false,
	Q = false, E = false,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	local code = input.KeyCode
	if code == Enum.KeyCode.W then keysDown.W = true
	elseif code == Enum.KeyCode.S then keysDown.S = true
	elseif code == Enum.KeyCode.A then keysDown.A = true
	elseif code == Enum.KeyCode.D then keysDown.D = true
	elseif code == Enum.KeyCode.Space then keysDown.Space = true
	elseif code == Enum.KeyCode.LeftShift then keysDown.LeftShift = true
	elseif code == Enum.KeyCode.Q then keysDown.Q = true
	elseif code == Enum.KeyCode.E then keysDown.E = true
	elseif code == Enum.KeyCode.C then
		-- Toggle Camera Mode
		cameraMode = if cameraMode == "FPV" then "CHASE" else "FPV"
	elseif code == Enum.KeyCode.M then
		-- Toggle Manual Pilot vs Editor
		isManualPilotActive = not isManualPilotActive
		osd.ToggleVisibility(isManualPilotActive)
		if not isManualPilotActive then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = player.Character and player.Character:FindFirstChild("Humanoid")
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local code = input.KeyCode
	if code == Enum.KeyCode.W then keysDown.W = false
	elseif code == Enum.KeyCode.S then keysDown.S = false
	elseif code == Enum.KeyCode.A then keysDown.A = false
	elseif code == Enum.KeyCode.D then keysDown.D = false
	elseif code == Enum.KeyCode.Space then keysDown.Space = false
	elseif code == Enum.KeyCode.LeftShift then keysDown.LeftShift = false
	elseif code == Enum.KeyCode.Q then keysDown.Q = false
	elseif code == Enum.KeyCode.E then keysDown.E = false
	end
end)

-- Main Manual Aerodynamics & Camera Loop
RunService.RenderStepped:Connect(function(dt: number)
	if not isManualPilotActive then
		return
	end

	local drone = getPrimaryDrone()
	if not drone or not drone.PrimaryPart then
		return
	end

	-- 1. Input Processing: Pitch & Roll
	local targetPitch = 0.0
	local targetRoll = 0.0

	if keysDown.W then targetPitch = PITCH_LIMIT end
	if keysDown.S then targetPitch = -PITCH_LIMIT end
	if keysDown.A then targetRoll = -ROLL_LIMIT end
	if keysDown.D then targetRoll = ROLL_LIMIT end

	-- Smooth angle transitions (Auto-leveling like Betaflight Angle Mode)
	dronePitch += (targetPitch - dronePitch) * math.min(1, AUTO_LEVEL_SPEED * dt)
	droneRoll += (targetRoll - droneRoll) * math.min(1, AUTO_LEVEL_SPEED * dt)

	-- 2. Yaw Rotation
	if keysDown.Q then droneYaw += YAW_SPEED * dt end
	if keysDown.E then droneYaw -= YAW_SPEED * dt end
	droneYaw = (droneYaw % 360)

	-- 3. Thrust & Flight Acceleration
	local forwardRad = math.rad(droneYaw)
	local forwardDir = Vector3.new(-math.sin(forwardRad), 0, -math.cos(forwardRad))
	local rightDir = Vector3.new(math.cos(forwardRad), 0, -math.sin(forwardRad))

	-- Tilting pitch drives forward/backward force
	local pitchThrust = (dronePitch / PITCH_LIMIT) * MAX_SPEED
	local rollThrust = (droneRoll / ROLL_LIMIT) * MAX_SPEED

	local targetVelH = (forwardDir * pitchThrust) + (rightDir * rollThrust)
	droneVelocity = Vector3.new(
		droneVelocity.X + (targetVelH.X - droneVelocity.X) * 0.1,
		droneVelocity.Y,
		droneVelocity.Z + (targetVelH.Z - droneVelocity.Z) * 0.1
	)

	-- Vertical Throttle (Space / Shift)
	local targetVy = 0.0
	if keysDown.Space then targetVy = CLIMB_RATE end
	if keysDown.LeftShift then targetVy = -CLIMB_RATE end
	droneVelocity = Vector3.new(droneVelocity.X, droneVelocity.Y + (targetVy - droneVelocity.Y) * 0.15, droneVelocity.Z)

	-- Apply velocity and enforce ground minimum
	dronePosition += droneVelocity * dt
	if dronePosition.Y < 2.0 then
		dronePosition = Vector3.new(dronePosition.X, 2.0, dronePosition.Z)
		droneVelocity = Vector3.new(droneVelocity.X, 0, droneVelocity.Z)
	end

	-- 4. Calculate Final Drone CFrame
	local baseCF = CFrame.new(dronePosition) * CFrame.Angles(0, math.rad(droneYaw), 0)
	local tiltCF = CFrame.Angles(math.rad(dronePitch), 0, -math.rad(droneRoll))
	local finalDroneCF = baseCF * tiltCF
	drone:PivotTo(finalDroneCF)

	-- 5. Camera Control
	camera.CameraType = Enum.CameraType.Scriptable
	if cameraMode == "FPV" then
		-- FPV Nose Camera looking forward
		local fpvOffset = finalDroneCF * CFrame.new(0, 0.2, -0.9)
		camera.CFrame = fpvOffset
	else
		-- Third-person chase camera behind and above
		local chasePos = dronePosition - (forwardDir * 12) + Vector3.new(0, 4.5, 0)
		camera.CFrame = CFrame.lookAt(chasePos, dronePosition + Vector3.new(0, 1, 0))
	end

	-- 6. Sound Pitch Update
	local speedMagnitude = droneVelocity.Magnitude
	if not motorSound.IsPlaying then motorSound:Play() end
	motorSound.PlaybackSpeed = 0.8 + (speedMagnitude / MAX_SPEED) * 0.6

	-- 7. Update FPV OSD Telemetry
	local speedMps = speedMagnitude / DroneConfig.STUDS_PER_METER
	local altMeters = dronePosition.Y / DroneConfig.STUDS_PER_METER
	osd.Update(speedMps, altMeters, droneYaw, dronePitch, droneRoll)
end)

print("[DronePilotController] Drone Pilot Controller ready for Istanbul flight!")
