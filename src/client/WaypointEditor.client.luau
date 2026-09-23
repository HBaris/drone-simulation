--!strict
-- WaypointEditor.client.luau
-- Interactive 3D Waypoint & Swarm Choreography Editor for PC.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local FlightMath = require(ReplicatedStorage:WaitForChild("FlightMath"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

local Network = ReplicatedStorage:WaitForChild("DroneNetwork")
local StartFlightEvent = Network:WaitForChild("StartFlight") :: RemoteEvent
local StopFlightEvent = Network:WaitForChild("StopFlight") :: RemoteEvent
local SetFormationEvent = Network:WaitForChild("SetFormation") :: RemoteEvent
local ExportFunction = Network:WaitForChild("ExportMissionData") :: RemoteFunction

-- Waypoint Storage
local waypoints: { FlightMath.Waypoint } = {}
local waypointMarkers: { Instance } = {}
local pathBeams: { Instance } = {}

local editorMode = "WAYPOINTS" -- "WAYPOINTS" or "SWARM"
local defaultAltitude = DroneConfig.FLIGHT.TAKEOFF_ALTITUDE
local swarmDroneCount = 50

-- Create Editor GUI
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DroneSimulationUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Main Control Panel (Bottom-Left)
local mainPanel = Instance.new("Frame")
mainPanel.Name = "MainPanel"
mainPanel.Size = UDim2.new(0, 320, 0, 480)
mainPanel.Position = UDim2.new(0, 20, 1, -500)
mainPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
mainPanel.BackgroundTransparency = 0.1
mainPanel.BorderSizePixel = 0
mainPanel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainPanel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 255, 150)
stroke.Thickness = 1.5
stroke.Parent = mainPanel

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 35)
title.Position = UDim2.new(0, 10, 0, 10)
title.BackgroundTransparency = 1
title.Text = "⚡ DRONE SIMULATION STUDIO"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(0, 255, 150)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = mainPanel

-- Mode Toggle Tabs
local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(1, -20, 0, 32)
tabContainer.Position = UDim2.new(0, 10, 0, 45)
tabContainer.BackgroundTransparency = 1
tabContainer.Parent = mainPanel

local btnTabWaypoints = Instance.new("TextButton")
btnTabWaypoints.Size = UDim2.new(0.5, -4, 1, 0)
btnTabWaypoints.Position = UDim2.new(0, 0, 0, 0)
btnTabWaypoints.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
btnTabWaypoints.Text = "Rota Editörü"
btnTabWaypoints.Font = Enum.Font.GothamMedium
btnTabWaypoints.TextSize = 13
btnTabWaypoints.TextColor3 = Color3.new(1, 1, 1)
btnTabWaypoints.Parent = tabContainer

local btnTabSwarm = Instance.new("TextButton")
btnTabSwarm.Size = UDim2.new(0.5, -4, 1, 0)
btnTabSwarm.Position = UDim2.new(0.5, 4, 0, 0)
btnTabSwarm.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
btnTabSwarm.Text = "Sürü & Şov (800)"
btnTabSwarm.Font = Enum.Font.GothamMedium
btnTabSwarm.TextSize = 13
btnTabSwarm.TextColor3 = Color3.fromRGB(180, 180, 180)
btnTabSwarm.Parent = tabContainer

-- Container for Waypoint controls
local waypointFrame = Instance.new("Frame")
waypointFrame.Size = UDim2.new(1, -20, 0, 380)
waypointFrame.Position = UDim2.new(0, 10, 0, 85)
waypointFrame.BackgroundTransparency = 1
waypointFrame.Parent = mainPanel

-- Info Label
local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, 0, 0, 40)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "• Tıklayarak haritaya Waypoint ekleyin\n• Dronlar noktaları pürüzsüz takip eder"
infoLabel.Font = Enum.Font.Gotham
infoLabel.TextSize = 12
infoLabel.TextColor3 = Color3.fromRGB(180, 190, 200)
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Parent = waypointFrame

-- Altitude Controller
local altLabel = Instance.new("TextLabel")
altLabel.Size = UDim2.new(1, 0, 0, 20)
altLabel.Position = UDim2.new(0, 0, 0, 45)
altLabel.BackgroundTransparency = 1
altLabel.Text = "Hedef İrtifa: 15.0 studs (~4.3m)"
altLabel.Font = Enum.Font.Gotham
altLabel.TextSize = 13
altLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
altLabel.TextXAlignment = Enum.TextXAlignment.Left
altLabel.Parent = waypointFrame

local function createActionButton(text: string, posY: number, color: Color3, parent: Instance): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 36)
	btn.Position = UDim2.new(0, 0, 0, posY)
	btn.BackgroundColor3 = color
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Parent = parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn

	return btn
end

local btnStart = createActionButton("▶ UÇUŞU BAŞLAT", 75, Color3.fromRGB(0, 160, 90), waypointFrame)
local btnStop = createActionButton("⏹ DURDUR & İNİŞ YAP", 118, Color3.fromRGB(200, 60, 60), waypointFrame)
local btnClear = createActionButton("🗑 ROTAYI TEMİZLE", 161, Color3.fromRGB(70, 75, 85), waypointFrame)
local btnExportJSON = createActionButton("📤 JSON DIŞA AKTAR (PX4/ESP32)", 204, Color3.fromRGB(45, 110, 200), waypointFrame)
local btnExportCSV = createActionButton("📊 CSV DIŞA AKTAR", 247, Color3.fromRGB(90, 60, 150), waypointFrame)

-- Swarm Frame
local swarmFrame = Instance.new("Frame")
swarmFrame.Size = UDim2.new(1, -20, 0, 380)
swarmFrame.Position = UDim2.new(0, 10, 0, 85)
swarmFrame.BackgroundTransparency = 1
swarmFrame.Visible = false
swarmFrame.Parent = mainPanel

local swarmInfo = Instance.new("TextLabel")
swarmInfo.Size = UDim2.new(1, 0, 0, 35)
swarmInfo.BackgroundTransparency = 1
swarmInfo.Text = "800 Drona Kadar Işık Şovu Formasyonları\nBulkMoveTo ile 60 FPS Optimize"
swarmInfo.Font = Enum.Font.Gotham
swarmInfo.TextSize = 12
swarmInfo.TextColor3 = Color3.fromRGB(180, 190, 200)
swarmInfo.TextXAlignment = Enum.TextXAlignment.Left
swarmInfo.Parent = swarmFrame

local droneCountLabel = Instance.new("TextLabel")
droneCountLabel.Size = UDim2.new(1, 0, 0, 20)
droneCountLabel.Position = UDim2.new(0, 0, 0, 40)
droneCountLabel.BackgroundTransparency = 1
droneCountLabel.Text = "Aktif Drone Sayısı: 50"
droneCountLabel.Font = Enum.Font.GothamBold
droneCountLabel.TextSize = 13
droneCountLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
droneCountLabel.TextXAlignment = Enum.TextXAlignment.Left
droneCountLabel.Parent = swarmFrame

local btnFormHeart = createActionButton("❤ KALP FORMASYONU", 70, Color3.fromRGB(220, 40, 80), swarmFrame)
local btnFormSphere = createActionButton("🌐 3D KÜRE (GLOBE) ŞOVU", 113, Color3.fromRGB(40, 160, 220), swarmFrame)
local btnFormHelix = createActionButton("🧬 DNA / HELIX SPİRALİ", 156, Color3.fromRGB(150, 40, 220), swarmFrame)
local btnFormCircle = createActionButton("⭕ ÇEMBER / HALKA", 199, Color3.fromRGB(220, 160, 40), swarmFrame)
local btnFormGrid = createActionButton("▦ MATRİS IZGARA", 242, Color3.fromRGB(60, 180, 120), swarmFrame)

-- Quick Drone Count Buttons
local countsContainer = Instance.new("Frame")
countsContainer.Size = UDim2.new(1, 0, 0, 30)
countsContainer.Position = UDim2.new(0, 0, 0, 290)
countsContainer.BackgroundTransparency = 1
countsContainer.Parent = swarmFrame

local counts = { 10, 50, 100, 300, 800 }
for i, cnt in ipairs(counts) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.18, 0, 1, 0)
	b.Position = UDim2.new((i - 1) * 0.205, 0, 0, 0)
	b.BackgroundColor3 = Color3.fromRGB(50, 55, 65)
	b.Text = tostring(cnt)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = countsContainer

	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 4)
	bc.Parent = b

	b.MouseButton1Click:Connect(function()
		swarmDroneCount = cnt
		droneCountLabel.Text = "Aktif Drone Sayısı: " .. cnt
	end)
end

-- Tab Switching Logic
btnTabWaypoints.MouseButton1Click:Connect(function()
	editorMode = "WAYPOINTS"
	waypointFrame.Visible = true
	swarmFrame.Visible = false
	btnTabWaypoints.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
	btnTabWaypoints.TextColor3 = Color3.new(1, 1, 1)
	btnTabSwarm.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
	btnTabSwarm.TextColor3 = Color3.fromRGB(180, 180, 180)
end)

btnTabSwarm.MouseButton1Click:Connect(function()
	editorMode = "SWARM"
	waypointFrame.Visible = false
	swarmFrame.Visible = true
	btnTabSwarm.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
	btnTabSwarm.TextColor3 = Color3.new(1, 1, 1)
	btnTabWaypoints.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
	btnTabWaypoints.TextColor3 = Color3.fromRGB(180, 180, 180)
end)

-- Visual Waypoint Rendering
local function redrawTrajectory()
	-- Clean existing beams/attachments
	for _, inst in ipairs(pathBeams) do
		inst:Destroy()
	end
	table.clear(pathBeams)

	if #waypoints < 2 then
		return
	end

	for i = 1, #waypoints - 1 do
		local p1 = waypoints[i].Position
		local p2 = waypoints[i + 1].Position

		local part = Instance.new("Part")
		part.Name = "PathLine"
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(0, 255, 180)
		part.Transparency = 0.3

		local dist = (p2 - p1).Magnitude
		part.Size = Vector3.new(0.2, 0.2, dist)
		part.CFrame = CFrame.lookAt(p1 + (p2 - p1) * 0.5, p2)
		part.Parent = Workspace

		table.insert(pathBeams, part)
	end
end

local function addWaypointAt(targetPos: Vector3)
	local wpPos = Vector3.new(targetPos.X, targetPos.Y + defaultAltitude, targetPos.Z)
	local index = #waypoints + 1

	table.insert(waypoints, {
		Position = wpPos,
		Altitude = defaultAltitude,
	})

	-- Visual 3D Marker
	local marker = Instance.new("Part")
	marker.Name = "WP_Marker_" .. index
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.3, 1.5, 1.5)
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(0, 255, 150)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CFrame = CFrame.new(wpPos) * CFrame.Angles(0, 0, math.rad(90))

	-- Text billboard on top
	local bbg = Instance.new("BillboardGui")
	bbg.Size = UDim2.new(0, 40, 0, 40)
	bbg.StudsOffset = Vector3.new(0, 1.5, 0)
	bbg.AlwaysOnTop = true
	bbg.Parent = marker

	local num = Instance.new("TextLabel")
	num.Size = UDim2.new(1, 0, 1, 0)
	num.BackgroundTransparency = 1
	num.Text = tostring(index)
	num.Font = Enum.Font.GothamBold
	num.TextSize = 18
	num.TextColor3 = Color3.fromRGB(255, 255, 255)
	num.Parent = bbg

	marker.Parent = Workspace
	table.insert(waypointMarkers, marker)

	redrawTrajectory()
end

-- Mouse Click Event in Waypoint Mode
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or editorMode ~= "WAYPOINTS" then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local hit = mouse.Hit
		if hit then
			addWaypointAt(hit.Position)
		end
	end
end)

-- Button Actions
btnStart.MouseButton1Click:Connect(function()
	if #waypoints >= 2 then
		StartFlightEvent:FireServer(waypoints)
	end
end)

btnStop.MouseButton1Click:Connect(function()
	StopFlightEvent:FireServer()
end)

btnClear.MouseButton1Click:Connect(function()
	StopFlightEvent:FireServer()
	for _, m in ipairs(waypointMarkers) do
		m:Destroy()
	end
	table.clear(waypointMarkers)
	table.clear(waypoints)
	redrawTrajectory()
end)

-- Formation Button Handlers
btnFormHeart.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Heart", swarmDroneCount, 1.5)
end)

btnFormSphere.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Sphere", swarmDroneCount, 1.0)
end)

btnFormHelix.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Helix", swarmDroneCount, 1.0)
end)

btnFormCircle.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Circle", swarmDroneCount, 1.0)
end)

btnFormGrid.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Grid", swarmDroneCount, 1.0)
end)

-- Export Handling (Popup View with Copyable Text)
local function showExportModal(textData: string, formatName: string)
	local modal = Instance.new("Frame")
	modal.Size = UDim2.new(0, 500, 0, 350)
	modal.Position = UDim2.new(0.5, -250, 0.5, -175)
	modal.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	modal.BorderSizePixel = 0
	modal.Parent = screenGui

	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0, 10)
	mc.Parent = modal

	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(0, 200, 255)
	mStroke.Thickness = 2
	mStroke.Parent = modal

	local mTitle = Instance.new("TextLabel")
	mTitle.Size = UDim2.new(1, -60, 0, 35)
	mTitle.Position = UDim2.new(0, 15, 0, 10)
	mTitle.BackgroundTransparency = 1
	mTitle.Text = string.format("Çıktı (%s) - Gerçek Drona Aktar", formatName)
	mTitle.Font = Enum.Font.GothamBold
	mTitle.TextSize = 15
	mTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
	mTitle.TextXAlignment = Enum.TextXAlignment.Left
	mTitle.Parent = modal

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -40, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = modal

	local closeC = Instance.new("UICorner")
	closeC.CornerRadius = UDim.new(0, 6)
	closeC.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		modal:Destroy()
	end)

	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.new(1, -30, 1, -60)
	textBox.Position = UDim2.new(0, 15, 0, 50)
	textBox.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
	textBox.TextColor3 = Color3.fromRGB(200, 220, 240)
	textBox.Font = Enum.Font.Code
	textBox.TextSize = 11
	textBox.ClearTextOnFocus = false
	textBox.MultiLine = true
	textBox.TextEditable = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.Text = textData
	textBox.Parent = modal

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 6)
	tc.Parent = textBox
end

btnExportJSON.MouseButton1Click:Connect(function()
	local jsonString = ExportFunction:InvokeServer("JSON")
	showExportModal(jsonString, "JSON")
end)

btnExportCSV.MouseButton1Click:Connect(function()
	local csvString = ExportFunction:InvokeServer("CSV")
	showExportModal(csvString, "CSV")
end)

print("[WaypointEditor] Editor GUI and 3D Interaction Ready.")
