--!strict
-- BuildIstanbulMap.luau
-- Constructs an immersive Istanbul Bosphorus environment with the Bosphorus Bridge, Galata Tower, coastline, and city blocks.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

print("[IstanbulBuilder] Constructing Istanbul Environment...")

-- Clean up any previous map folder
local existingMap = Workspace:FindFirstChild("IstanbulEnvironment")
if existingMap then existingMap:Destroy() end

local mapFolder = Instance.new("Folder")
mapFolder.Name = "IstanbulEnvironment"
mapFolder.Parent = Workspace

-- 1. Realistic Istanbul Lighting & Atmosphere (Golden Hour over Bosphorus)
Lighting.ClockTime = 17.8 -- Sunset / Golden Hour
Lighting.Brightness = 2.2
Lighting.OutdoorAmbient = Color3.fromRGB(120, 110, 100)
Lighting.GeographicLatitude = 41.0 -- Istanbul Latitude!

local sky = Lighting:FindFirstChildOfClass("Sky")
if not sky then
	sky = Instance.new("Sky")
	sky.Parent = Lighting
end
sky.CelestialBodiesShown = true

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end
atmosphere.Density = 0.32
atmosphere.Offset = 0.25
atmosphere.Color = Color3.fromRGB(220, 190, 160)
atmosphere.Decay = Color3.fromRGB(150, 120, 100)
atmosphere.Glare = 0.4
atmosphere.Haze = 1.2

local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
bloom.Intensity = 0.6
bloom.Size = 24
bloom.Threshold = 1.8
bloom.Parent = Lighting

local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
sunRays.Intensity = 0.15
sunRays.Spread = 0.8
sunRays.Parent = Lighting

-- 2. The Bosphorus Strait (İstanbul Boğazı - Deep Blue Reflective Sea)
local sea = Instance.new("Part")
sea.Name = "BosphorusSea"
sea.Size = Vector3.new(380, 8, 2400)
sea.Position = Vector3.new(0, -4, 0)
sea.Material = Enum.Material.Glass
sea.Color = Color3.fromRGB(15, 65, 110)
sea.Transparency = 0.25
sea.Reflectance = 0.35
sea.Anchored = true
sea.CanCollide = false
sea.CastShadow = false
sea.Parent = mapFolder

-- Sea Floor (dark sand/rock under water)
local seaFloor = Instance.new("Part")
seaFloor.Name = "SeaFloor"
seaFloor.Size = Vector3.new(420, 4, 2400)
seaFloor.Position = Vector3.new(0, -8, 0)
seaFloor.Material = Enum.Material.Slate
seaFloor.Color = Color3.fromRGB(20, 25, 30)
seaFloor.Anchored = true
seaFloor.Parent = mapFolder

-- 3. Coastlines & Quays (Avrupa & Anadolu Yakası Rıhtımları)
local function createCoast(side: string, centerX: number)
	local coastFolder = Instance.new("Folder")
	coastFolder.Name = side .. "Coast"
	coastFolder.Parent = mapFolder

	-- Quay Promenade (Kordon boyu)
	local quay = Instance.new("Part")
	quay.Name = "Promenade"
	quay.Size = Vector3.new(80, 3, 2400)
	quay.Position = Vector3.new(centerX, 0.5, 0)
	quay.Material = Enum.Material.Concrete
	quay.Color = Color3.fromRGB(140, 140, 145)
	quay.Anchored = true
	quay.Parent = coastFolder

	-- Seawall edge
	local wallX = if centerX < 0 then centerX + 40 else centerX - 40
	local seawall = Instance.new("Part")
	seawall.Name = "Seawall"
	seawall.Size = Vector3.new(2, 4, 2400)
	seawall.Position = Vector3.new(wallX, 1, 0)
	seawall.Material = Enum.Material.Cobblestone
	seawall.Color = Color3.fromRGB(100, 100, 105)
	seawall.Anchored = true
	seawall.Parent = coastFolder

	-- Coastal Highway (Sahil Yolu)
	local roadX = if centerX < 0 then centerX - 60 else centerX + 60
	local road = Instance.new("Part")
	road.Name = "CoastalRoad"
	road.Size = Vector3.new(50, 1, 2400)
	road.Position = Vector3.new(roadX, 0.6, 0)
	road.Material = Enum.Material.Asphalt
	road.Color = Color3.fromRGB(35, 35, 40)
	road.Anchored = true
	road.Parent = coastFolder

	-- Urban Ground behind coastal road
	local cityGroundX = if centerX < 0 then centerX - 260 else centerX + 260
	local cityGround = Instance.new("Part")
	cityGround.Name = "CityGround"
	cityGround.Size = Vector3.new(360, 2, 2400)
	cityGround.Position = Vector3.new(cityGroundX, 0.5, 0)
	cityGround.Material = Enum.Material.Concrete
	cityGround.Color = Color3.fromRGB(90, 92, 95)
	cityGround.Anchored = true
	cityGround.Parent = coastFolder
end

createCoast("Avrupa", -230) -- European Side
createCoast("Anadolu", 230)  -- Asian Side

-- 4. Drone Helipad Launch Station (Avrupa Yakası Sahilinde Başlangıç Üssü)
local helipad = Instance.new("Part")
helipad.Name = "DroneLaunchPad"
helipad.Size = Vector3.new(24, 1.2, 24)
helipad.Position = Vector3.new(-220, 2.0, 0)
helipad.Material = Enum.Material.Metal
helipad.Color = Color3.fromRGB(30, 32, 38)
helipad.Anchored = true
helipad.Parent = mapFolder

-- Glowing Helipad Circle / H Decal
local padDecal = Instance.new("Part")
padDecal.Name = "PadMarker"
padDecal.Shape = Enum.PartType.Cylinder
padDecal.Size = Vector3.new(0.2, 18, 18)
padDecal.Position = Vector3.new(-220, 2.7, 0)
padDecal.CFrame = CFrame.new(-220, 2.7, 0) * CFrame.Angles(0, 0, math.rad(90))
padDecal.Material = Enum.Material.Neon
padDecal.Color = Color3.fromRGB(0, 255, 180)
padDecal.Anchored = true
padDecal.CanCollide = false
padDecal.Parent = helipad

local padLight = Instance.new("PointLight")
padLight.Color = Color3.fromRGB(0, 255, 180)
padLight.Range = 25
padLight.Brightness = 2.0
padLight.Parent = padDecal

-- 5. Reposition and Anchor Inserted Istanbul Landmarks
-- A) Galata Kulesi
local galata = Workspace:FindFirstChild("GalataTower")
if galata then
	galata.Parent = mapFolder
	-- Galata stands on the European side hill looking towards the Bosphorus
	galata:PivotTo(CFrame.new(-380, 1.0, -180) * CFrame.Angles(0, math.rad(45), 0))
	for _, part in ipairs(galata:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	print("[IstanbulBuilder] Galata Tower placed at European hill (-380, 1, -180).")
end

-- B) Boğaziçi Köprüsü (Istanbul Bridge)
local bridge = Workspace:FindFirstChild("IstanbulBridge")
if bridge then
	bridge.Parent = mapFolder
	-- Bridge spans across X = -200 (Avrupa) to X = 200 (Anadolu) at Z = 250
	bridge:PivotTo(CFrame.new(0, 15, 250) * CFrame.Angles(0, math.rad(90), 0))
	for _, part in ipairs(bridge:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	print("[IstanbulBuilder] Istanbul Bridge positioned spanning across Bosphorus.")
end

-- C) City Buildings (Replicate along European & Asian streets)
local cityModel = Workspace:FindFirstChild("CityBuildings")
if cityModel then
	cityModel.Parent = mapFolder
	cityModel:PivotTo(CFrame.new(-320, 1.0, 50))
	for _, part in ipairs(cityModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	-- Clone a block on Asian side too
	local asianCity = cityModel:Clone()
	asianCity.Name = "AsianSideBuildings"
	asianCity:PivotTo(CFrame.new(320, 1.0, 80) * CFrame.Angles(0, math.pi, 0))
	asianCity.Parent = mapFolder
	print("[IstanbulBuilder] City Buildings populated on both sides.")
end

-- 6. Set SpawnLocation on the Drone Helipad
local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
if not spawn then
	spawn = Instance.new("SpawnLocation")
	spawn.Parent = Workspace
end
spawn.Size = Vector3.new(12, 1, 12)
spawn.Position = Vector3.new(-220, 2.5, 0)
spawn.Material = Enum.Material.SmoothPlastic
spawn.Color = Color3.fromRGB(20, 20, 20)
spawn.Transparency = 1
spawn.Anchored = true
spawn.CanCollide = false

print("[IstanbulBuilder] ✅ Istanbul Map successfully created!")
