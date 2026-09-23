--!strict
-- OsmMapBuilder.luau
-- Builds a real neighbourhood from a tools/osm2roblox.py data module (edit-time, like
-- BuildIstanbulMap). Usage from the Command Bar:
--   local B = require(game.ServerStorage.MapData.OsmMapBuilder)
--   B.build(require(game.ServerStorage.MapData.Bahcelievler), Vector3.new(6000, 0, 0))
-- Map data (c) OpenStreetMap contributors, ODbL 1.0. Terrain: SRTM 30 m via OpenTopoData.

local Workspace = game:GetService("Workspace")

local OsmMapBuilder = {}

local BUILDING_COLORS = {
	Color3.fromRGB(214, 205, 190), Color3.fromRGB(196, 184, 168), Color3.fromRGB(226, 220, 208),
	Color3.fromRGB(184, 170, 160), Color3.fromRGB(205, 196, 178), Color3.fromRGB(170, 162, 150),
}
local FOCUS_COLOR = Color3.fromRGB(245, 245, 250) -- hospital: white
local ROAD_COLOR = Color3.fromRGB(58, 60, 66)
local GREEN_COLOR = Color3.fromRGB(96, 140, 72)
local GROUND_COLOR = Color3.fromRGB(150, 146, 138)
local TERRAIN_SLAB = 3 -- studs of thickness under the terrain surface

local function records(packed: string): { { number } }
	local out = {}
	for rec in string.gmatch(packed, "[^;]+") do
		local nums = {}
		for v in string.gmatch(rec, "%S+") do
			table.insert(nums, tonumber(v) :: number)
		end
		table.insert(out, nums)
	end
	return out
end

local function newPart(className: string, parent: Instance): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Solid triangular slab whose top face is the triangle a-b-c (any orientation), `thickness` deep,
-- built from two wedges (EgoMoose's triangle method: the wedge X axis is the triangle normal).
local function slab(a: Vector3, b: Vector3, c: Vector3, thickness: number, parent: Instance, color: Color3, material: Enum.Material): BasePart?
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ab.Magnitude < 1e-3 or ac.Magnitude < 1e-3 or bc.Magnitude < 1e-3 then
		return nil
	end
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local normalUp = if right.Y >= 0 then right else -right
	local sink = -normalUp * (thickness / 2) -- wedges are centred on the plane; push them below it
	local first: BasePart? = nil
	for i, spec in ipairs({ { (a + b) / 2, right, back, math.abs(ab:Dot(back)) }, { (a + c) / 2, -right, -back, math.abs(ac:Dot(back)) } }) do
		local w = newPart("WedgePart", parent)
		w.Name = "Tri" .. i
		w.Size = Vector3.new(thickness, height, spec[4] :: number)
		w.CFrame = CFrame.fromMatrix((spec[1] :: Vector3) + sink, spec[2] :: Vector3, up, spec[3] :: Vector3)
		w.Color = color
		w.Material = material
		first = first or w
	end
	return first
end

local function buildTerrain(data: any, origin: Vector3, parent: Instance): number
	local info = data.Terrain
	local heights = {}
	for v in string.gmatch(data.TerrainHeights, "%S+") do
		table.insert(heights, tonumber(v) :: number)
	end
	local n, step, half = info.Count, info.Step, info.Half
	local function point(i: number, j: number): Vector3
		-- row-major from the south-west corner: i = east index, j = north index (Roblox -Z is north)
		return origin + Vector3.new(-half + i * step, heights[j * n + i + 1], half - j * step)
	end
	local minY = math.huge
	for _, h in ipairs(heights) do
		minY = math.min(minY, h)
	end
	for j = 0, n - 2 do
		for i = 0, n - 2 do
			local p00, p10, p01, p11 = point(i, j), point(i + 1, j), point(i, j + 1), point(i + 1, j + 1)
			slab(p00, p10, p11, TERRAIN_SLAB, parent, GROUND_COLOR, Enum.Material.Pavement)
			slab(p00, p11, p01, TERRAIN_SLAB, parent, GROUND_COLOR, Enum.Material.Pavement)
		end
	end
	return minY
end

function OsmMapBuilder.build(data: any, origin: Vector3): Model
	local existing = Workspace:FindFirstChild("Map_" .. data.Name)
	if existing then
		existing:Destroy()
	end
	-- Persistent so clients always have every building, even far from the player's character:
	-- the drone's ground and obstacle raycasts must never miss a building that was not streamed in.
	local folder = Instance.new("Model")
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	folder.Name = "Map_" .. data.Name
	folder:SetAttribute("OriginX", origin.X)
	folder:SetAttribute("OriginY", origin.Y)
	folder:SetAttribute("OriginZ", origin.Z)
	folder.Parent = Workspace

	local ground = Instance.new("Folder")
	ground.Name = "Terrain"
	ground.Parent = folder
	local floorY = 0
	if data.Terrain then
		floorY = buildTerrain(data, origin, ground) - TERRAIN_SLAB
	end
	-- Flat underlay beyond (and below) the terrain grid so nothing falls into the void
	local underlay = newPart("Part", ground)
	underlay.Name = "Underlay"
	underlay.Size = Vector3.new(data.Radius * 2 + 800, 2, data.Radius * 2 + 800)
	underlay.Position = origin + Vector3.new(0, floorY - 1, 0)
	underlay.Color = GROUND_COLOR
	underlay.Material = Enum.Material.Pavement

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = folder
	local focusFolder = Instance.new("Model")
	focusFolder.Name = "FocusArea"
	focusFolder.Parent = folder

	local focusName = data.FocusLabel or "FocusBuilding" -- shows up in crash messages
	local tallestFocus: BasePart? = nil
	local focusTop = -math.huge
	for i, r in ipairs(records(data.Boxes)) do
		local cx, cz, w, d, yaw, h, focus, base = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8] or 0
		local p = newPart("Part", if focus == 1 then focusFolder else buildings)
		p.Name = if focus == 1 then focusName else "Building"
		p.Size = Vector3.new(w, h, d)
		p.CFrame = CFrame.new(origin + Vector3.new(cx, base + h / 2, cz)) * CFrame.Angles(0, yaw, 0)
		p.Color = if focus == 1 then FOCUS_COLOR else BUILDING_COLORS[(i % #BUILDING_COLORS) + 1]
		p.Material = Enum.Material.Concrete
		if focus == 1 and base + h > focusTop then
			tallestFocus, focusTop = p, base + h
		end
	end
	for i, r in ipairs(records(data.Tris)) do
		local h, focus, base = r[7], r[8], r[9] or 0
		local top = origin.Y + base + h
		local m = Instance.new("Model")
		m.Name = if focus == 1 then focusName else "Building"
		m.Parent = if focus == 1 then focusFolder else buildings
		local color = if focus == 1 then FOCUS_COLOR else BUILDING_COLORS[(i % #BUILDING_COLORS) + 1]
		local wedge = slab(
			Vector3.new(origin.X + r[1], top, origin.Z + r[2]),
			Vector3.new(origin.X + r[3], top, origin.Z + r[4]),
			Vector3.new(origin.X + r[5], top, origin.Z + r[6]),
			h, m, color, Enum.Material.Concrete
		)
		if wedge and focus == 1 and base + h > focusTop then
			tallestFocus, focusTop = wedge, base + h
		end
	end

	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = folder
	for _, r in ipairs(records(data.Roads)) do
		local a = origin + Vector3.new(r[1], (r[6] or 0) + 0.08, r[2])
		local b = origin + Vector3.new(r[3], (r[7] or 0) + 0.08, r[4])
		local len = (b - a).Magnitude
		if len > 0.1 then
			local p = newPart("Part", roads)
			p.Name = "Road"
			p.Size = Vector3.new(r[5], 0.1, len + r[5] * 0.5)
			p.CFrame = CFrame.lookAt((a + b) / 2, b)
			p.Color = ROAD_COLOR
			p.Material = Enum.Material.Asphalt
			p.CanCollide = false
		end
	end

	local green = Instance.new("Folder")
	green.Name = "Green"
	green.Parent = folder
	for _, r in ipairs(records(data.Green)) do
		slab(
			origin + Vector3.new(r[1], (r[7] or 0) + 0.12, r[2]),
			origin + Vector3.new(r[3], (r[8] or 0) + 0.12, r[4]),
			origin + Vector3.new(r[5], (r[9] or 0) + 0.12, r[6]),
			0.15, green, GREEN_COLOR, Enum.Material.Grass
		)
	end

	-- Launch pad at the chosen open spot (data.Home already includes the terrain height)
	local pad = newPart("Part", folder)
	pad.Name = "LaunchPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.3, 10, 10)
	pad.CFrame = CFrame.new(origin + data.Home + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = Color3.fromRGB(0, 200, 140)
	pad.Material = Enum.Material.Neon
	pad.CanCollide = false

	if tallestFocus then
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 260, 0, 40)
		-- world-space offset from the part centre to 8 studs above the roof (wedge axes are rotated)
		gui.StudsOffsetWorldSpace = Vector3.new(0, origin.Y + focusTop + 8 - (tallestFocus :: BasePart).Position.Y, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 2500
		gui.Parent = tallestFocus
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = Color3.fromRGB(200, 30, 40)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = "🏥 " .. focusName
		label.Parent = gui
	end

	local credit = Instance.new("StringValue")
	credit.Name = "Attribution"
	credit.Value = "Map data (c) OpenStreetMap contributors, ODbL 1.0 · Elevation: SRTM 30 m (OpenTopoData)"
	credit.Parent = folder
	return folder
end

return OsmMapBuilder
