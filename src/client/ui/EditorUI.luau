--!strict
-- EditorUI.luau
-- Manages the 2D ScreenGui panels, buttons, tabs, and export modals for the Drone Studio.

local EditorUI = {}

export type UIReferences = {
	ScreenGui: ScreenGui,
	MainPanel: Frame,
	WaypointFrame: Frame,
	SwarmFrame: Frame,
	BtnTabWaypoints: TextButton,
	BtnTabSwarm: TextButton,
	BtnStart: TextButton,
	BtnStop: TextButton,
	BtnClear: TextButton,
	BtnExportJSON: TextButton,
	BtnExportCSV: TextButton,
	BtnFormHeart: TextButton,
	BtnFormSphere: TextButton,
	BtnFormHelix: TextButton,
	BtnFormCircle: TextButton,
	BtnFormGrid: TextButton,
	DroneCountLabel: TextLabel,
	CountButtons: { [number]: TextButton },
}

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

function EditorUI.create(playerGui: Instance): UIReferences
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DroneSimulationUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

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

	-- Tabs
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

	-- Waypoint Frame
	local waypointFrame = Instance.new("Frame")
	waypointFrame.Size = UDim2.new(1, -20, 0, 380)
	waypointFrame.Position = UDim2.new(0, 10, 0, 85)
	waypointFrame.BackgroundTransparency = 1
	waypointFrame.Parent = mainPanel

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, 0, 0, 40)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = "• Tıklayarak haritaya Waypoint ekleyin\n• Dronlar noktaları pürüzsüz takip eder"
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextSize = 12
	infoLabel.TextColor3 = Color3.fromRGB(180, 190, 200)
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.Parent = waypointFrame

	local btnStart = createActionButton("▶ UÇUŞU BAŞLAT", 50, Color3.fromRGB(0, 160, 90), waypointFrame)
	local btnStop = createActionButton("⏹ DURDUR & İNİŞ YAP", 93, Color3.fromRGB(200, 60, 60), waypointFrame)
	local btnClear = createActionButton("🗑 ROTAYI TEMİZLE", 136, Color3.fromRGB(70, 75, 85), waypointFrame)
	local btnExportJSON = createActionButton("📤 JSON DIŞA AKTAR (PX4/ESP32)", 179, Color3.fromRGB(45, 110, 200), waypointFrame)
	local btnExportCSV = createActionButton("📊 CSV DIŞA AKTAR", 222, Color3.fromRGB(90, 60, 150), waypointFrame)

	-- Swarm Frame
	local swarmFrame = Instance.new("Frame")
	swarmFrame.Size = UDim2.new(1, -20, 0, 380)
	swarmFrame.Position = UDim2.new(0, 10, 0, 85)
	swarmFrame.BackgroundTransparency = 1
	swarmFrame.Visible = false
	swarmFrame.Parent = mainPanel

	local droneCountLabel = Instance.new("TextLabel")
	droneCountLabel.Size = UDim2.new(1, 0, 0, 20)
	droneCountLabel.Position = UDim2.new(0, 0, 0, 10)
	droneCountLabel.BackgroundTransparency = 1
	droneCountLabel.Text = "Aktif Drone Sayısı: 50"
	droneCountLabel.Font = Enum.Font.GothamBold
	droneCountLabel.TextSize = 13
	droneCountLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
	droneCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	droneCountLabel.Parent = swarmFrame

	local btnFormHeart = createActionButton("❤ KALP FORMASYONU", 40, Color3.fromRGB(220, 40, 80), swarmFrame)
	local btnFormSphere = createActionButton("🌐 3D KÜRE (GLOBE) ŞOVU", 83, Color3.fromRGB(40, 160, 220), swarmFrame)
	local btnFormHelix = createActionButton("🧬 DNA / HELIX SPİRALİ", 126, Color3.fromRGB(150, 40, 220), swarmFrame)
	local btnFormCircle = createActionButton("⭕ ÇEMBER / HALKA", 169, Color3.fromRGB(220, 160, 40), swarmFrame)
	local btnFormGrid = createActionButton("▦ MATRİS IZGARA", 212, Color3.fromRGB(60, 180, 120), swarmFrame)

	-- Count Selector
	local countsContainer = Instance.new("Frame")
	countsContainer.Size = UDim2.new(1, 0, 0, 30)
	countsContainer.Position = UDim2.new(0, 0, 0, 260)
	countsContainer.BackgroundTransparency = 1
	countsContainer.Parent = swarmFrame

	local countButtons: { [number]: TextButton } = {}
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

		countButtons[cnt] = b
	end

	return {
		ScreenGui = screenGui,
		MainPanel = mainPanel,
		WaypointFrame = waypointFrame,
		SwarmFrame = swarmFrame,
		BtnTabWaypoints = btnTabWaypoints,
		BtnTabSwarm = btnTabSwarm,
		BtnStart = btnStart,
		BtnStop = btnStop,
		BtnClear = btnClear,
		BtnExportJSON = btnExportJSON,
		BtnExportCSV = btnExportCSV,
		BtnFormHeart = btnFormHeart,
		BtnFormSphere = btnFormSphere,
		BtnFormHelix = btnFormHelix,
		BtnFormCircle = btnFormCircle,
		BtnFormGrid = btnFormGrid,
		DroneCountLabel = droneCountLabel,
		CountButtons = countButtons,
	}
end

-- Displays the Export Output Modal
function EditorUI.showExportModal(parentGui: Instance, textData: string, formatName: string)
	local modal = Instance.new("Frame")
	modal.Size = UDim2.new(0, 500, 0, 350)
	modal.Position = UDim2.new(0.5, -250, 0.5, -175)
	modal.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	modal.BorderSizePixel = 0
	modal.Parent = parentGui

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

return table.freeze(EditorUI)
