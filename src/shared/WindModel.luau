--!strict
-- WindModel.luau
-- Turns the 10 m wind report published by WeatherService (ReplicatedStorage.Weather attributes)
-- into the wind vector the drone feels at its altitude: log wind profile over the city plus
-- turbulence (gusts) from coherent noise. Returns meters/second, Roblox axes (X east, Z south).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(script.Parent.DroneConfig)

local W = DroneConfig.WEATHER

local WindModel = {}

export type Report = {
	SpeedMs: number, -- mean 10 m wind
	FromDeg: number, -- meteorological direction the wind blows FROM; < 0 = variable
	GustMs: number, -- 0 when not reported
	Source: string,
}

local function weatherFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("Weather")
end

function WindModel.report(): Report
	local f = weatherFolder()
	if not f then
		return { SpeedMs = W.MANUAL.SPEED_MS, FromDeg = W.MANUAL.FROM_DEG, GustMs = W.MANUAL.GUST_MS, Source = "MANUEL" }
	end
	return {
		SpeedMs = (f:GetAttribute("SpeedMs") :: number?) or 0,
		FromDeg = (f:GetAttribute("FromDeg") :: number?) or 0,
		GustMs = (f:GetAttribute("GustMs") :: number?) or 0,
		Source = (f:GetAttribute("Source") :: string?) or "?",
	}
end

-- Mean wind speed at `heightM` above ground over the city, from a 10 m report over open terrain.
function WindModel.profileFactor(heightM: number): number
	local h = math.max(heightM, 2 * W.SITE_Z0_M)
	local toBlend = math.log(W.BLEND_HEIGHT_M / W.SOURCE_Z0_M) / math.log(10 / W.SOURCE_Z0_M)
	local fromBlend = math.log(h / W.SITE_Z0_M) / math.log(W.BLEND_HEIGHT_M / W.SITE_Z0_M)
	return toBlend * math.min(fromBlend, 1.2)
end

-- Unit vector the air moves toward, for a meteorological "from" direction (0 = from north).
local function towardVector(fromDeg: number): Vector3
	local toward = math.rad(fromDeg + 180)
	return Vector3.new(math.sin(toward), 0, -math.cos(toward)) -- east = sin, north = cos (-Z)
end

-- Smooth pseudo-random signal with roughly unit standard deviation (two octaves of Perlin noise).
local function turbulence(t: number, seed: number): number
	return (math.noise(t, seed, 0.5) * 2.2 + math.noise(t * 2.7, seed + 17.3, 0.5) * 1.1)
end

-- Wind the drone feels at time `t` (s) and height above ground `aglM`.
function WindModel.at(t: number, aglM: number, report: Report?): Vector3
	local r = report or WindModel.report()
	local mean = r.SpeedMs * WindModel.profileFactor(aglM)
	if mean < 0.05 and r.GustMs <= 0 then
		return Vector3.zero
	end

	-- Variable direction (METAR "VRB"): wander slowly around the compass
	local fromDeg = if r.FromDeg >= 0 then r.FromDeg else (math.noise(t / 60, 3.1) * 360 + 180)
	local along = towardVector(fromDeg)
	local across = Vector3.new(-along.Z, 0, along.X)

	-- Gust report -> turbulence sigma (peak gust ~ mean + 2.5 sigma); otherwise a city default
	local sigma = if r.GustMs > r.SpeedMs then (r.GustMs - r.SpeedMs) / 2.5 else W.TURBULENCE_INTENSITY * r.SpeedMs
	sigma *= WindModel.profileFactor(aglM)
	local timescale = math.clamp(W.EDDY_LENGTH_M / math.max(mean, 1), 1, 10)
	local tt = t / timescale

	return along * (mean + sigma * turbulence(tt, 1.7))
		+ across * (0.75 * sigma * turbulence(tt, 9.2))
		+ Vector3.new(0, 0.5 * sigma * turbulence(tt, 23.5), 0)
end

return WindModel
