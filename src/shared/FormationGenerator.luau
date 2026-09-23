--!strict
-- FormationGenerator.luau
-- Pre-calculated 3D Swarm Formations for up to 800+ Light Show Drones

local DroneConfig = require(script.Parent.DroneConfig)

local FormationGenerator = {}

export type DroneTarget = {
	DroneId: number,
	TargetPosition: Vector3,
	TargetColor: Color3,
	Delay: number, -- Staggered takeoff delay
}

-- 1. Grid Formation (Matrix on ground or hovering plane)
function FormationGenerator.createGrid(
	droneCount: number,
	center: Vector3,
	spacing: number?,
	altitude: number?,
	color: Color3?
): { DroneTarget }
	local dist = spacing or 4.0
	local alt = altitude or DroneConfig.FLIGHT.TAKEOFF_ALTITUDE
	local baseColor = color or DroneConfig.DRONE_MODEL.LED_DEFAULT_COLOR

	local cols = math.ceil(math.sqrt(droneCount))
	local rows = math.ceil(droneCount / cols)
	local targets: { DroneTarget } = {}

	local startX = center.X - ((cols - 1) * dist) / 2
	local startZ = center.Z - ((rows - 1) * dist) / 2

	for i = 1, droneCount do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)

		local pos = Vector3.new(startX + col * dist, center.Y + alt, startZ + row * dist)
		table.insert(targets, {
			DroneId = i,
			TargetPosition = pos,
			TargetColor = baseColor,
			Delay = (col + row) * 0.05, -- Wave takeoff
		})
	end

	return targets
end

-- 2. Concentric Rings / Circle Formation
function FormationGenerator.createCircle(
	droneCount: number,
	center: Vector3,
	radius: number?,
	altitude: number?,
	color: Color3?
): { DroneTarget }
	local r = radius or (droneCount * 0.8)
	local alt = altitude or DroneConfig.FLIGHT.TAKEOFF_ALTITUDE
	local baseColor = color or Color3.fromRGB(0, 200, 255)
	local targets: { DroneTarget } = {}

	for i = 1, droneCount do
		local angle = ((i - 1) / droneCount) * (2 * math.pi)
		local x = center.X + math.cos(angle) * r
		local z = center.Z + math.sin(angle) * r

		table.insert(targets, {
			DroneId = i,
			TargetPosition = Vector3.new(x, center.Y + alt, z),
			TargetColor = baseColor,
			Delay = (i / droneCount) * 1.5,
		})
	end

	return targets
end

-- 3. 3D Heart Formation (Show Classic)
function FormationGenerator.createHeart(
	droneCount: number,
	center: Vector3,
	scale: number?,
	altitude: number?,
	color: Color3?
): { DroneTarget }
	local s = scale or 1.5
	local alt = altitude or (DroneConfig.FLIGHT.TAKEOFF_ALTITUDE + 20)
	local redColor = color or Color3.fromRGB(255, 30, 80)
	local targets: { DroneTarget } = {}

	for i = 1, droneCount do
		local t = ((i - 1) / droneCount) * (2 * math.pi)
		-- Parametric heart curve equation:
		-- x = 16 * sin^3(t)
		-- y = 13 * cos(t) - 5 * cos(2t) - 2 * cos(3t) - cos(4t)
		local hx = 16 * (math.sin(t) ^ 3)
		local hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)

		local pos = Vector3.new(center.X + hx * s, center.Y + alt + hy * s, center.Z)
		table.insert(targets, {
			DroneId = i,
			TargetPosition = pos,
			TargetColor = redColor,
			Delay = math.abs(math.sin(t)) * 1.0,
		})
	end

	return targets
end

-- 4. 3D Sphere / Globe Formation (Fibonacci Lattice Distribution)
function FormationGenerator.createSphere(
	droneCount: number,
	center: Vector3,
	radius: number?,
	altitude: number?
): { DroneTarget }
	local r = radius or 25.0
	local alt = altitude or (DroneConfig.FLIGHT.TAKEOFF_ALTITUDE + 35)
	local targets: { DroneTarget } = {}
	local phi = math.pi * (3 - math.sqrt(5)) -- Golden angle

	for i = 1, droneCount do
		local y = 1 - ((i - 1) / (droneCount - 1)) * 2 -- y goes from 1 to -1
		local radiusAtY = math.sqrt(1 - y * y)
		local theta = phi * (i - 1)

		local x = math.cos(theta) * radiusAtY
		local z = math.sin(theta) * radiusAtY

		local worldPos = Vector3.new(center.X + x * r, center.Y + alt + y * r, center.Z + z * r)
		-- Rainbow gradient by latitude:
		local hue = (y + 1) / 2
		local col = Color3.fromHSV(hue, 0.85, 1.0)

		table.insert(targets, {
			DroneId = i,
			TargetPosition = worldPos,
			TargetColor = col,
			Delay = (i / droneCount) * 2.0,
		})
	end

	return targets
end

-- 5. Double Helix (DNA Spiral) Formation
function FormationGenerator.createHelix(
	droneCount: number,
	center: Vector3,
	height: number?,
	radius: number?
): { DroneTarget }
	local h = height or 60.0
	local r = radius or 12.0
	local targets: { DroneTarget } = {}
	local strandCount = math.floor(droneCount / 2)

	for strand = 1, 2 do
		local strandOffset = (strand - 1) * math.pi
		local strandColor = if strand == 1 then Color3.fromRGB(0, 255, 255) else Color3.fromRGB(255, 0, 200)

		for i = 1, strandCount do
			local id = (strand - 1) * strandCount + i
			local prog = (i - 1) / (strandCount - 1)
			local angle = prog * (4 * math.pi) + strandOffset
			local y = center.Y + DroneConfig.FLIGHT.TAKEOFF_ALTITUDE + prog * h
			local x = center.X + math.cos(angle) * r
			local z = center.Z + math.sin(angle) * r

			table.insert(targets, {
				DroneId = id,
				TargetPosition = Vector3.new(x, y, z),
				TargetColor = strandColor,
				Delay = prog * 2.0,
			})
		end
	end

	return targets
end

return table.freeze(FormationGenerator)
