--!strict
-- DroneHUD.client.luau
-- Live Telemetry HUD displaying active drone count, primary altitude, speed, and real-time FPS.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "DroneHUD"
hudGui.ResetOnSpawn = false
hudGui.Parent = playerGui

local hudFrame = Instance.new("Frame")
hudFrame.Name = "HUDFrame"
hudFrame.Size = UDim2.new(0, 240, 0, 110)
hudFrame.Position = UDim2.new(1, -260, 0, 20)
hudFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
hudFrame.BackgroundTransparency = 0.2
hudFrame.BorderSizePixel = 0
hudFrame.Parent = hudGui

local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 8)
hudCorner.Parent = hudFrame

local hudStroke = Instance.new("UIStroke")
hudStroke.Color = Color3.fromRGB(45, 55, 75)
hudStroke.Thickness = 1
hudStroke.Parent = hudFrame

local function createTelemetryRow(name: string, labelText: string, posY: number): (TextLabel, TextLabel)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.5, -10, 0, 20)
	label.Position = UDim2.new(0, 10, 0, posY)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(150, 160, 175)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = hudFrame

	local val = Instance.new("TextLabel")
	val.Name = name .. "Val"
	val.Size = UDim2.new(0.5, -10, 0, 20)
	val.Position = UDim2.new(0.5, 0, 0, posY)
	val.BackgroundTransparency = 1
	val.Text = "--"
	val.Font = Enum.Font.GothamBold
	val.TextSize = 12
	val.TextColor3 = Color3.fromRGB(0, 255, 180)
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = hudFrame

	return label, val
end

local _, countVal = createTelemetryRow("Count", "Drone Sayısı:", 10)
local _, fpsVal = createTelemetryRow("FPS", "FPS:", 32)
local _, altVal = createTelemetryRow("Alt", "İrtifa (Y):", 54)
local _, speedVal = createTelemetryRow("Speed", "Hız:", 76)

-- Performance & Telemetry Update Loop
local frameCount = 0
local lastFpsTime = os.clock()
local currentFps = 60
local lastPos = Vector3.zero
local currentSpeed = 0

RunService.RenderStepped:Connect(function(dt: number)
	frameCount += 1
	local now = os.clock()
	if now - lastFpsTime >= 0.5 then
		currentFps = math.round(frameCount / (now - lastFpsTime))
		frameCount = 0
		lastFpsTime = now
	end

	-- Count active drones
	local swarmFolder = Workspace:FindFirstChild("DroneSwarm")
	local droneCount = if swarmFolder then #swarmFolder:GetChildren() else 0
	countVal.Text = tostring(droneCount)

	-- Update FPS badge color based on performance
	fpsVal.Text = string.format("%d FPS", currentFps)
	if currentFps >= 50 then
		fpsVal.TextColor3 = Color3.fromRGB(0, 255, 150)
	elseif currentFps >= 30 then
		fpsVal.TextColor3 = Color3.fromRGB(255, 200, 50)
	else
		fpsVal.TextColor3 = Color3.fromRGB(255, 80, 80)
	end

	-- Primary Drone 1 Telemetry
	local primaryDrone = swarmFolder and swarmFolder:FindFirstChild("Drone_001") :: Model?
	if primaryDrone and primaryDrone.PrimaryPart then
		local pos = primaryDrone.PrimaryPart.Position
		local altMeters = pos.Y / DroneConfig.STUDS_PER_METER
		altVal.Text = string.format("%.1f m (%.0f st)", altMeters, pos.Y)

		if dt > 0 then
			local dist = (pos - lastPos).Magnitude
			currentSpeed = dist / dt
			local speedMps = currentSpeed / DroneConfig.STUDS_PER_METER
			speedVal.Text = string.format("%.1f m/s", speedMps)
		end
		lastPos = pos
	else
		altVal.Text = "0.0 m"
		speedVal.Text = "0.0 m/s"
	end
end)

print("[DroneHUD] Telemetry and Performance HUD loaded.")
