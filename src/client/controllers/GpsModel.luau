--!strict
-- GpsModel.luau
-- Position estimate the flight controller believes (GPS + barometer through the EKF), which drifts
-- away from the true position. The autopilot navigates on this estimate, so the true drone wanders
-- by the error — hover drift, landing offset — exactly like a real Pixhawk with an M8N.
-- Error: first-order Gauss-Markov per axis (slow wander), scaled by HDOP; buildings blocking the sky
-- (FlightEnvironment.skyObstruction) cut satellites, raise HDOP and cause multipath jumps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local G = DroneConfig.GPS
local S = DroneConfig.STUDS_PER_METER

local GpsModel = {}
GpsModel.__index = GpsModel

export type Gps = typeof(setmetatable(
	{} :: {
		Error: Vector3, -- meters (east, up, south = Roblox axes)
		Glitch: Vector3, -- meters, decaying multipath jump
		Obstruction: number,
		Sats: number,
		Hdop: number,
		Rng: Random,
	},
	GpsModel
))

function GpsModel.new(seed: number?): Gps
	return setmetatable({
		Error = Vector3.zero,
		Glitch = Vector3.zero,
		Obstruction = 0,
		Sats = G.SATS_OPEN,
		Hdop = G.HDOP_OPEN,
		Rng = Random.new(seed or os.time()),
	}, GpsModel)
end

local function gaussian(rng: Random): number
	-- Box-Muller
	local u1 = math.max(rng:NextNumber(), 1e-9)
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * rng:NextNumber())
end

function GpsModel.setObstruction(self: Gps, fraction: number)
	self.Obstruction = fraction
	self.Sats = math.max(0, math.round(G.SATS_OPEN - (G.SATS_OPEN - 4) * fraction))
	self.Hdop = G.HDOP_OPEN * (1 + 3 * fraction * fraction)
end

-- Advance the error and return the estimated position (studs) for the true position.
function GpsModel.step(self: Gps, dt: number, truePos: Vector3): Vector3
	if not G.ENABLED then
		return truePos
	end
	local scale = self.Hdop / G.HDOP_OPEN
	local k = math.sqrt(2 * dt / G.TAU_S)
	local decay = dt / G.TAU_S
	local sh, sv = G.SIGMA_H_M * scale, G.SIGMA_V_M
	local e = self.Error
	self.Error = Vector3.new(
		e.X - e.X * decay + sh * k * gaussian(self.Rng),
		e.Y - e.Y * decay + sv * k * gaussian(self.Rng),
		e.Z - e.Z * decay + sh * k * gaussian(self.Rng)
	)

	-- Multipath: reflected signals near buildings make the fix jump; the EKF slowly rejects it
	self.Glitch *= math.exp(-dt / 4)
	local rate = G.GLITCH_RATE * math.max(0, self.Obstruction - 0.3) / 0.7
	if self.Rng:NextNumber() < rate * dt then
		local az = self.Rng:NextNumber() * 2 * math.pi
		local size = G.GLITCH_M[1] + (G.GLITCH_M[2] - G.GLITCH_M[1]) * self.Rng:NextNumber()
		self.Glitch += Vector3.new(math.cos(az) * size, 0, math.sin(az) * size)
	end
	return truePos + (self.Error + self.Glitch) * S
end

-- Horizontal error magnitude in meters (for the health panel / telemetry)
function GpsModel.horizontalError(self: Gps): number
	local total = self.Error + self.Glitch
	return Vector3.new(total.X, 0, total.Z).Magnitude
end

return GpsModel
