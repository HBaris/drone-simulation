--!strict
-- FPVOverlay.luau
-- First-Person View (FPV) Drone OSD (On-Screen Display) with artificial horizon, crosshair, and telemetry.

local FPVOverlay = {}

export type FPVReferences = {
	ScreenGui: ScreenGui,
	HorizonLine: Frame,
	Crosshair: Frame,
	SpeedText: TextLabel,
	AltText: TextLabel,
	HeadingText: TextLabel,
	BatteryText: TextLabel,
	FlightModeText: TextLabel,
	ControlsHelp: Frame,
	ToggleVisibility: (visible: boolean) -> (),
	Update: (speedMps: number, altMeters: number, yawDeg: number, pitchDeg: number, rollDeg: number) -> (),
}

function FPVOverlay.create(playerGui: Instance): FPVReferences
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DroneFPVGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "FPVRoot"
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	-- Center Crosshair
	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.Size = UDim2.new(0, 40, 0, 40)
	crosshair.Position = UDim2.new(0.5, -20, 0.5, -20)
	crosshair.BackgroundTransparency = 1
	crosshair.Parent = root

	local hLine = Instance.new("Frame")
	hLine.Size = UDim2.new(1, 0, 0, 2)
	hLine.Position = UDim2.new(0, 0, 0.5, -1)
	hLine.BackgroundColor3 = Color3.fromRGB(0, 255, 180)
	hLine.BorderSizePixel = 0
	hLine.Parent = crosshair

	local vLine = Instance.new("Frame")
	vLine.Size = UDim2.new(0, 2, 1, 0)
	vLine.Position = UDim2.new(0.5, -1, 0, 0)
	vLine.BackgroundColor3 = Color3.fromRGB(0, 255, 180)
	vLine.BorderSizePixel = 0
	vLine.Parent = crosshair

	-- Artificial Horizon Ladder Line
	local horizon = Instance.new("Frame")
	horizon.Name = "ArtificialHorizon"
	horizon.Size = UDim2.new(0, 160, 0, 2)
	horizon.Position = UDim2.new(0.5, -80, 0.5, 0)
	horizon.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
	horizon.BackgroundTransparency = 0.3
	horizon.BorderSizePixel = 0
	horizon.Parent = root

	-- Left Telemetry Box (SPEED)
	local speedBox = Instance.new("Frame")
	speedBox.Size = UDim2.new(0, 140, 0, 50)
	speedBox.Position = UDim2.new(0.2, -70, 0.5, -25)
	speedBox.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	speedBox.BackgroundTransparency = 0.5
	speedBox.BorderSizePixel = 0
	speedBox.Parent = root
	Instance.new("UICorner", speedBox).CornerRadius = UDim.new(0, 6)

	local speedLabel = Instance.new("TextLabel")
	speedLabel.Size = UDim2.new(1, 0, 0, 16)
	speedLabel.Text = "HIZ (SPD)"
	speedLabel.TextColor3 = Color3.fromRGB(160, 180, 200)
	speedLabel.Font = Enum.Font.Gotham
	speedLabel.TextSize = 11
	speedLabel.BackgroundTransparency = 1
	speedLabel.Parent = speedBox

	local speedText = Instance.new("TextLabel")
	speedText.Size = UDim2.new(1, 0, 0, 30)
	speedText.Position = UDim2.new(0, 0, 0, 16)
	speedText.Text = "0.0 m/s"
	speedText.TextColor3 = Color3.fromRGB(0, 255, 180)
	speedText.Font = Enum.Font.GothamBold
	speedText.TextSize = 18
	speedText.BackgroundTransparency = 1
	speedText.Parent = speedBox

	-- Right Telemetry Box (ALTITUDE)
	local altBox = Instance.new("Frame")
	altBox.Size = UDim2.new(0, 140, 0, 50)
	altBox.Position = UDim2.new(0.8, -70, 0.5, -25)
	altBox.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	altBox.BackgroundTransparency = 0.5
	altBox.BorderSizePixel = 0
	altBox.Parent = root
	Instance.new("UICorner", altBox).CornerRadius = UDim.new(0, 6)

	local altLabel = Instance.new("TextLabel")
	altLabel.Size = UDim2.new(1, 0, 0, 16)
	altLabel.Text = "İRTİFA (ALT)"
	altLabel.TextColor3 = Color3.fromRGB(160, 180, 200)
	altLabel.Font = Enum.Font.Gotham
	altLabel.TextSize = 11
	altLabel.BackgroundTransparency = 1
	altLabel.Parent = altBox

	local altText = Instance.new("TextLabel")
	altText.Size = UDim2.new(1, 0, 0, 30)
	altText.Position = UDim2.new(0, 0, 0, 16)
	altText.Text = "0.0 m"
	altText.TextColor3 = Color3.fromRGB(0, 255, 180)
	altText.Font = Enum.Font.GothamBold
	altText.TextSize = 18
	altText.BackgroundTransparency = 1
	altText.Parent = altBox

	-- Top Center Heading / Compass
	local headingText = Instance.new("TextLabel")
	headingText.Size = UDim2.new(0, 200, 0, 30)
	headingText.Position = UDim2.new(0.5, -100, 0, 25)
	headingText.Text = "PUSULA: 000° N"
	headingText.TextColor3 = Color3.fromRGB(240, 240, 255)
	headingText.Font = Enum.Font.GothamBold
	headingText.TextSize = 14
	headingText.BackgroundTransparency = 1
	headingText.Parent = root

	-- Flight Mode Badge
	local flightModeText = Instance.new("TextLabel")
	flightModeText.Size = UDim2.new(0, 240, 0, 26)
	flightModeText.Position = UDim2.new(0.5, -120, 0, 55)
	flightModeText.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	flightModeText.BackgroundTransparency = 0.3
	flightModeText.Text = "🕹️ MANUEL FPV UÇUŞ MODU"
	flightModeText.TextColor3 = Color3.fromRGB(0, 220, 255)
	flightModeText.Font = Enum.Font.GothamBold
	flightModeText.TextSize = 12
	flightModeText.Parent = root
	Instance.new("UICorner", flightModeText).CornerRadius = UDim.new(0, 6)

	-- Bottom Battery / Voltage indicator
	local batteryText = Instance.new("TextLabel")
	batteryText.Size = UDim2.new(0, 180, 0, 25)
	batteryText.Position = UDim2.new(0.5, -90, 1, -45)
	batteryText.Text = "🔋 4S LIPO: 15.8V | 98%"
	batteryText.TextColor3 = Color3.fromRGB(0, 255, 120)
	batteryText.Font = Enum.Font.GothamMedium
	batteryText.TextSize = 13
	batteryText.BackgroundTransparency = 1
	batteryText.Parent = root

	-- Keyboard Controls Cheat-Sheet (Top-Left)
	local controlsHelp = Instance.new("Frame")
	controlsHelp.Size = UDim2.new(0, 240, 0, 205)
	controlsHelp.Position = UDim2.new(0, 20, 0, 20)
	controlsHelp.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	controlsHelp.BackgroundTransparency = 0.3
	controlsHelp.BorderSizePixel = 0
	controlsHelp.Parent = root
	Instance.new("UICorner", controlsHelp).CornerRadius = UDim.new(0, 8)

	local helpTitle = Instance.new("TextLabel")
	helpTitle.Size = UDim2.new(1, -16, 0, 24)
	helpTitle.Position = UDim2.new(0, 8, 0, 4)
	helpTitle.Text = "🎮 DRONE PİLOT KONTROLLERİ"
	helpTitle.TextColor3 = Color3.fromRGB(0, 255, 180)
	helpTitle.Font = Enum.Font.GothamBold
	helpTitle.TextSize = 12
	helpTitle.TextXAlignment = Enum.TextXAlignment.Left
	helpTitle.BackgroundTransparency = 1
	helpTitle.Parent = controlsHelp

	local helpDesc = Instance.new("TextLabel")
	helpDesc.Size = UDim2.new(1, -16, 0, 170)
	helpDesc.Position = UDim2.new(0, 8, 0, 26)
	helpDesc.Text = "• W / S : İleri / Geri (Pitch)\n• A / D : Sola / Sağa Yatış (Roll)\n• Space / Shift : Gaz Yüksel / Alçal\n• Q / E : Dönüş (Yaw)\n• C : Kamera Değiştir (FPV / 3rd)\n• M : Rota Editörü / Manuel Mod\n• R : Uçuş Kaydı Başlat / Bitir\n• P : Kaydı Tekrar Oynat\n• H : Eve Dön (RTL)  • L : İniş\n• K : Motor-1 arızası  • B : Batarya testi\n• X : Kazadan sonra sıfırla"
	helpDesc.TextColor3 = Color3.fromRGB(200, 210, 225)
	helpDesc.Font = Enum.Font.Gotham
	helpDesc.TextSize = 11
	helpDesc.TextXAlignment = Enum.TextXAlignment.Left
	helpDesc.TextYAlignment = Enum.TextYAlignment.Top
	helpDesc.BackgroundTransparency = 1
	helpDesc.Parent = controlsHelp

	local function toggleVisibility(visible: boolean)
		root.Visible = visible
	end

	local function update(speedMps: number, altMeters: number, yawDeg: number, pitchDeg: number, rollDeg: number)
		speedText.Text = string.format("%.1f m/s\n(%.0f km/h)", speedMps, speedMps * 3.6)
		altText.Text = string.format("%.1f m", altMeters)

		local cardinal = "N"
		if yawDeg >= 22.5 and yawDeg < 67.5 then cardinal = "NE"
		elseif yawDeg >= 67.5 and yawDeg < 112.5 then cardinal = "E"
		elseif yawDeg >= 112.5 and yawDeg < 157.5 then cardinal = "SE"
		elseif yawDeg >= 157.5 and yawDeg < 202.5 then cardinal = "S"
		elseif yawDeg >= 202.5 and yawDeg < 247.5 then cardinal = "SW"
		elseif yawDeg >= 247.5 and yawDeg < 292.5 then cardinal = "W"
		elseif yawDeg >= 292.5 and yawDeg < 337.5 then cardinal = "NW"
		end
		headingText.Text = string.format("PUSULA: %03d° %s", math.floor(yawDeg), cardinal)

		-- Artificial horizon pitch and roll
		horizon.Rotation = -rollDeg
		horizon.Position = UDim2.new(0.5, -80, 0.5, math.clamp(pitchDeg * 2, -100, 100))
	end

	return {
		ScreenGui = screenGui,
		HorizonLine = horizon,
		Crosshair = crosshair,
		SpeedText = speedText,
		AltText = altText,
		HeadingText = headingText,
		BatteryText = batteryText,
		FlightModeText = flightModeText,
		ControlsHelp = controlsHelp,
		ToggleVisibility = toggleVisibility,
		Update = update,
	}
end

return table.freeze(FPVOverlay)
