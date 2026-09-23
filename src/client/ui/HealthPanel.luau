--!strict
-- HealthPanel.luau
-- Per-motor and battery health panel. Reads a DroneHealthModel.Telemetry table, so the same
-- panel can show the real drone once its MAVLink telemetry arrives through the bridge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneHealthModel = require(ReplicatedStorage:WaitForChild("DroneHealthModel"))
local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local HealthPanel = {}

export type Panel = {
	Frame: Frame,
	Update: (telemetry: DroneHealthModel.Telemetry, mode: string, status: string, event: string, homeDistM: number) -> (),
}

local GOOD = Color3.fromRGB(0, 230, 140)
local WARN = Color3.fromRGB(255, 190, 40)
local BAD = Color3.fromRGB(255, 70, 70)
local DIM = Color3.fromRGB(150, 160, 175)

local function label(parent: Instance, y: number, height: number, size: number, bold: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -16, 0, height)
	l.Position = UDim2.new(0, 8, 0, y)
	l.BackgroundTransparency = 1
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = Color3.fromRGB(210, 220, 235)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = ""
	l.Parent = parent
	return l
end

local function levelColor(value: number, warnAt: number, badAt: number): Color3
	if value >= badAt then
		return BAD
	elseif value >= warnAt then
		return WARN
	end
	return GOOD
end

function HealthPanel.create(screenGui: ScreenGui): Panel
	local frame = Instance.new("Frame")
	frame.Name = "DroneHealthPanel"
	frame.Size = UDim2.new(0, 280, 0, 262)
	frame.Position = UDim2.new(1, -300, 0, 140)
	frame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local title = label(frame, 4, 20, 12, true)
	title.Text = "🩺 DRONE SAĞLIĞI  ·  kaynak: SİMÜLASYON"
	title.TextColor3 = Color3.fromRGB(0, 255, 180)

	local modeText = label(frame, 24, 18, 12, true)
	local statusText = label(frame, 42, 16, 11, false)

	local motorRows = {}
	for i, geom in ipairs(DroneHealthModel.MOTORS) do
		local y = 62 + (i - 1) * 34
		local name = label(frame, y, 14, 11, true)
		name.Text = geom.Name .. (if geom.Yaw > 0 then "  (CCW)" else "  (CW)")

		local barBack = Instance.new("Frame")
		barBack.Size = UDim2.new(0, 90, 0, 8)
		barBack.Position = UDim2.new(1, -98, 0, y + 3)
		barBack.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
		barBack.BorderSizePixel = 0
		barBack.Parent = frame

		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 0, 1, 0)
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = GOOD
		bar.Parent = barBack

		local detail = label(frame, y + 15, 14, 11, false)
		detail.TextColor3 = DIM
		motorRows[i] = { Bar = bar, Detail = detail }
	end

	local batteryText = label(frame, 200, 16, 12, true)
	local batteryDetail = label(frame, 216, 14, 11, false)
	batteryDetail.TextColor3 = DIM
	local eventText = label(frame, 232, 28, 11, true)

	local function update(t: DroneHealthModel.Telemetry, mode: string, status: string, event: string, homeDistM: number)
		modeText.Text = string.format("MOD: %s  ·  %s  ·  eve %.0f m", mode, if t.Armed then "ARMED" else "DISARMED", homeDistM)
		modeText.TextColor3 = if mode == "CRASHED" then BAD elseif mode == "MANUAL" then GOOD else WARN
		statusText.Text = status

		for i, m in ipairs(t.Motors) do
			local row = motorRows[i]
			row.Bar.Size = UDim2.new(m.Output, 0, 1, 0)
			row.Bar.BackgroundColor3 = if m.Failed then BAD elseif m.Saturated then BAD else levelColor(m.Output, 0.7, 0.9)
			if m.Failed then
				row.Detail.Text = "ARIZA — motor durdu"
				row.Detail.TextColor3 = BAD
			else
				row.Detail.Text = string.format("%3.0f%%  %5.0f rpm  %4.1f A  %2.0f°C%s",
					m.Output * 100, m.Rpm, m.CurrentA, m.TempC, if m.Saturated then "  DOYGUN!" else "")
				row.Detail.TextColor3 = if m.TempC > 80 then BAD else DIM
			end
		end

		batteryText.Text = string.format("🔋 %.2f V  ·  %.1f A  ·  %%%.0f", t.VoltageV, t.CurrentA, t.RemainingPct)
		batteryText.TextColor3 = if t.VoltageV <= DroneConfig.FAILSAFE.BATT_CRT_VOLT then BAD
			elseif t.VoltageV <= DroneConfig.FAILSAFE.BATT_LOW_VOLT then WARN
			else GOOD
		batteryDetail.Text = string.format("hücre %.2f V  ·  harcanan %.0f mAh  ·  itki/ağırlık %.2f", t.CellV, t.UsedMah, t.ThrustToWeight)
		eventText.Text = if event ~= "" then "⚠ " .. event else ""
		eventText.TextColor3 = WARN
	end

	return { Frame = frame, Update = update }
end

return HealthPanel
