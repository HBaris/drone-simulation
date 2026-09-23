--!strict
-- WeatherService.server.luau
-- Publishes the current wind at the simulation site to ReplicatedStorage.Weather (attributes),
-- which WindModel turns into gusty wind at the drone's altitude. Sources, best first:
--   1. METAR — observed wind at the nearest airport (aviationweather.gov, LTBA ~3 km away)
--   2. MET Norway locationforecast — model forecast for the exact spot, current hour
--   3. Open-Meteo — model forecast (often rate-limited from shared IPs)
--   4. DroneConfig.WEATHER.MANUAL
-- Requires "Allow HTTP Requests" (Game Settings > Security); otherwise falls back to MANUAL.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))

local W = DroneConfig.WEATHER
local KNOT = 0.514444

type Reading = { SpeedMs: number, FromDeg: number, GustMs: number, TempC: number?, Source: string, Station: string, ObservedAt: string }

local weather = Instance.new("Configuration")
weather.Name = "Weather"
weather.Parent = ReplicatedStorage

local function get(url: string): any
	local response = HttpService:RequestAsync({ Url = url, Method = "GET" })
	if not response.Success then
		error(string.format("HTTP %d", response.StatusCode))
	end
	return HttpService:JSONDecode(response.Body)
end

local function distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number
	local r = 6371
	local dLat, dLon = math.rad(lat2 - lat1), math.rad(lon2 - lon1)
	local a = math.sin(dLat / 2) ^ 2 + math.cos(math.rad(lat1)) * math.cos(math.rad(lat2)) * math.sin(dLon / 2) ^ 2
	return 2 * r * math.asin(math.sqrt(a))
end

local function fromMetar(lat: number, lon: number): Reading
	local list = get("https://aviationweather.gov/api/data/metar?format=json&ids=" .. table.concat(W.METAR_STATIONS, ","))
	for _, id in ipairs(W.METAR_STATIONS) do
		for _, m in ipairs(list) do
			if m.icaoId == id and type(m.wspd) == "number" then
				local ageMin = (DateTime.now().UnixTimestamp - (m.obsTime or 0)) / 60
				if ageMin <= W.METAR_MAX_AGE_MIN then
					return {
						SpeedMs = m.wspd * KNOT,
						FromDeg = if type(m.wdir) == "number" then m.wdir else -1, -- "VRB" = variable
						GustMs = if type(m.wgst) == "number" then m.wgst * KNOT else 0,
						TempC = m.temp,
						Source = "METAR (ölçüm)",
						Station = string.format("%s · %.1f km", id, distanceKm(lat, lon, m.lat, m.lon)),
						ObservedAt = m.reportTime or "",
					}
				end
			end
		end
	end
	error("güncel METAR yok")
end

local function fromMetNorway(lat: number, lon: number): Reading
	local d = get(string.format("https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=%.4f&lon=%.4f", lat, lon))
	local ts = d.properties.timeseries[1]
	local details = ts.data.instant.details
	return {
		SpeedMs = details.wind_speed,
		FromDeg = details.wind_from_direction,
		GustMs = details.wind_speed_of_gust or 0,
		TempC = details.air_temperature,
		Source = "MET Norway (tahmin)",
		Station = "model",
		ObservedAt = ts.time,
	}
end

local function fromOpenMeteo(lat: number, lon: number): Reading
	local d = get(string.format(
		"https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=wind_speed_10m,wind_direction_10m,wind_gusts_10m,temperature_2m&wind_speed_unit=ms",
		lat, lon))
	local c = d.current
	return {
		SpeedMs = c.wind_speed_10m,
		FromDeg = c.wind_direction_10m,
		GustMs = c.wind_gusts_10m or 0,
		TempC = c.temperature_2m,
		Source = "Open-Meteo (tahmin)",
		Station = "model",
		ObservedAt = c.time,
	}
end

local function manual(reason: string): Reading
	return {
		SpeedMs = W.MANUAL.SPEED_MS,
		FromDeg = W.MANUAL.FROM_DEG,
		GustMs = W.MANUAL.GUST_MS,
		TempC = nil,
		Source = "MANUEL (" .. reason .. ")",
		Station = "-",
		ObservedAt = "",
	}
end

local function publish(r: Reading, errors: { string })
	weather:SetAttribute("SpeedMs", r.SpeedMs)
	weather:SetAttribute("FromDeg", r.FromDeg)
	weather:SetAttribute("GustMs", r.GustMs)
	weather:SetAttribute("TempC", r.TempC)
	weather:SetAttribute("Source", r.Source)
	weather:SetAttribute("Station", r.Station)
	weather:SetAttribute("ObservedAt", r.ObservedAt)
	weather:SetAttribute("FetchedAt", DateTime.now():ToIsoDate())
	weather:SetAttribute("Errors", table.concat(errors, " | "))
	print(string.format("[WeatherService] %s %s: %.1f m/s from %s°, gust %.1f m/s%s", r.Source, r.Station, r.SpeedMs,
		if r.FromDeg >= 0 then string.format("%03d", math.round(r.FromDeg) % 360) else "VRB", r.GustMs,
		if #errors > 0 then "  (atlanan: " .. table.concat(errors, " | ") .. ")" else ""))
end

local function refresh()
	if W.MODE ~= "LIVE" or not W.GEO then
		publish(manual(if W.MODE ~= "LIVE" then "ayar" else "konum yok"), {})
		return
	end
	local lat, lon = W.GEO[1], W.GEO[2]
	local errors = {}
	for _, source in ipairs({ { "METAR", fromMetar }, { "MET", fromMetNorway }, { "Open-Meteo", fromOpenMeteo } }) do
		local ok, result = pcall((source[2] :: any), lat, lon)
		if ok then
			publish(result, errors)
			return
		end
		local message = tostring(result):gsub("^.-:%d+: ", "") -- drop the script path prefix
		table.insert(errors, (source[1] :: string) .. ": " .. message)
	end
	publish(manual("çevrimdışı"), errors)
end

publish(manual("başlatılıyor"), {})
task.spawn(function()
	while true do
		refresh()
		task.wait(W.REFRESH_SEC)
	end
end)
