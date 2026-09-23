--!strict
-- DroneHealthModel.luau
-- Quad-X motor mixer, motor (RPM / current / temperature) and LiPo battery model.
-- The telemetry fields mirror what a Pixhawk reports over MAVLink (SERVO_OUTPUT_RAW,
-- ESC_TELEMETRY_1_TO_4, BATTERY_STATUS) so the same health panel can later show the real drone.

local DroneConfig = require(script.Parent.DroneConfig)

local AF = DroneConfig.AIRFRAME
local GRAVITY = 9.81

local DroneHealthModel = {}

-- ArduPilot Quad-X: angle from the nose (deg, clockwise) and propeller spin direction.
-- roll factor = cos(angle + 90), pitch factor = cos(angle), yaw: CCW = +1, CW = -1.
DroneHealthModel.MOTORS = table.freeze({
	{ Name = "M1 ÖN-SAĞ", Angle = 45, Yaw = 1 },
	{ Name = "M2 ARKA-SOL", Angle = -135, Yaw = 1 },
	{ Name = "M3 ÖN-SOL", Angle = -45, Yaw = -1 },
	{ Name = "M4 ARKA-SAĞ", Angle = 135, Yaw = -1 },
})

export type MotorState = {
	Output: number,   -- 0..1 command (SERVO_OUTPUT_RAW)
	Rpm: number,      -- ESC telemetry
	CurrentA: number,
	TempC: number,
	Failed: boolean,
	Saturated: boolean,
}

export type Telemetry = {
	Motors: { MotorState },
	Armed: boolean,
	VoltageV: number,
	CellV: number,
	CurrentA: number,
	UsedMah: number,
	RemainingPct: number,
	ThrustToWeight: number, -- instantaneous total thrust / weight (1.0 = hover)
}

function DroneHealthModel.new(): Telemetry
	local motors = {}
	for i = 1, #DroneHealthModel.MOTORS do
		motors[i] = { Output = 0, Rpm = 0, CurrentA = 0, TempC = AF.AMBIENT_TEMP_C, Failed = false, Saturated = false }
	end
	return {
		Motors = motors,
		Armed = false,
		VoltageV = AF.BATTERY_CELLS * 4.2,
		CellV = 4.2,
		CurrentA = 0,
		UsedMah = 0,
		RemainingPct = 100,
		ThrustToWeight = 0,
	}
end

-- Resting LiPo cell voltage by state of charge (0..1)
local OCV_CURVE = { { 0, 3.30 }, { 0.10, 3.60 }, { 0.25, 3.72 }, { 0.50, 3.82 }, { 0.75, 3.97 }, { 0.90, 4.10 }, { 1, 4.20 } }

local function cellOpenCircuit(soc: number): number
	soc = math.clamp(soc, 0, 1)
	for i = 2, #OCV_CURVE do
		local a, b = OCV_CURVE[i - 1], OCV_CURVE[i]
		if soc <= b[1] then
			return a[2] + (b[2] - a[2]) * (soc - a[1]) / (b[1] - a[1])
		end
	end
	return 4.2
end

-- accelMs2: world acceleration of the drone (m/s², Y up).
-- angAccel: body angular acceleration (rad/s²) around roll, pitch, yaw axes.
function DroneHealthModel.step(t: Telemetry, dt: number, accelMs2: Vector3, angAccel: Vector3, armed: boolean)
	t.Armed = armed

	-- Total thrust must cancel gravity and produce the acceleration (thrust acts along body-up).
	local totalThrust = if armed then AF.MASS_KG * (accelMs2 + Vector3.new(0, GRAVITY, 0)).Magnitude else 0
	t.ThrustToWeight = totalThrust / (AF.MASS_KG * GRAVITY)

	-- Differential thrust (N per unit mixer factor) needed for the angular accelerations
	local lever = AF.ARM_LENGTH_M * 0.707 * 4
	local rollN = angAccel.X * AF.INERTIA_KGM2 / lever
	local pitchN = angAccel.Y * AF.INERTIA_KGM2 / lever
	local yawN = angAccel.Z * AF.INERTIA_KGM2 / (lever * 0.25) -- yaw comes from weak prop drag torque

	local working = 0
	for _, m in ipairs(t.Motors) do
		if not m.Failed then
			working += 1
		end
	end
	local base = if working > 0 then totalThrust / working else 0

	local totalCurrent = AF.AVIONICS_CURRENT_A
	for i, m in ipairs(t.Motors) do
		local geom = DroneHealthModel.MOTORS[i]
		local rad = math.rad(geom.Angle)
		local thrust = base + rollN * math.cos(rad + math.pi / 2) + pitchN * math.cos(rad) + yawN * geom.Yaw
		local out = if armed and not m.Failed then thrust / AF.MAX_THRUST_PER_MOTOR_N else 0
		m.Saturated = out >= 1
		out = if armed and not m.Failed then math.clamp(out, AF.MOT_SPIN_ARM, 1) else 0
		m.Output = out
		m.Rpm = AF.MAX_MOTOR_RPM * math.sqrt(out) -- thrust grows with RPM²
		m.CurrentA = AF.MAX_MOTOR_CURRENT_A * out ^ 1.5
		totalCurrent += m.CurrentA

		-- First-order motor heating toward a load-dependent temperature
		local targetTemp = AF.AMBIENT_TEMP_C + 70 * out * out
		m.TempC += (targetTemp - m.TempC) * math.min(1, dt / 40)
	end

	t.CurrentA = totalCurrent
	t.UsedMah += totalCurrent * dt / 3.6
	local soc = 1 - t.UsedMah / AF.BATTERY_CAPACITY_MAH
	t.RemainingPct = math.max(0, soc * 100)
	t.VoltageV = AF.BATTERY_CELLS * cellOpenCircuit(soc) - totalCurrent * AF.BATTERY_RESISTANCE_OHM
	t.CellV = t.VoltageV / AF.BATTERY_CELLS
end

return DroneHealthModel
