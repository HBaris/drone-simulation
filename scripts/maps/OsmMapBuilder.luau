--!strict
-- OsmMapBuilder.luau
-- Builds a real neighbourhood from a tools/osm2roblox.py data module (edit-time, like
-- BuildIstanbulMap). Usage from the Command Bar:
--   local B = require(game.ServerStorage.MapData.OsmMapBuilder)
--   B.build(require(game.ServerStorage.MapData.Bahcelievler), Vector3.new(6000, 0, 0))
-- Map data (c) OpenStreetMap contributors, ODbL 1.0.

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

-- Vertical prism over a ground triangle, from two wedges (EgoMoose's triangle method; the wedge
-- X axis is the triangle normal, so X size = extrusion height).
local function prism(a: Vector3, b: Vector3, c: Vector3, height: number, parent: Instance, color: Color3, material: Enum.Material): BasePart?
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
	local h = math.abs(ab:Dot(up))
	local lift = Vector3.new(0, height / 2, 0)
	local first: BasePart? = nil
	for i, spec in ipairs({ { (a + b) / 2, right, back, math.abs(ab:Dot(back)) }, { (a + c) / 2, -right, -back, math.abs(ac:Dot(back)) } }) do
		local w = newPart("WedgePart", parent)
		w.Name = "Tri" .. i
		w.Size = Vector3.new(height, h, spec[4] :: number)
		w.CFrame = CFrame.fromMatrix((spec[1] :: Vector3) + lift, spec[2] :: Vector3, up, spec[3] :: Vector3)
		w.Color = color
		w.Material = material
		first = first or w
	end
	return first
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

	local ground = newPart("Part", folder)
	ground.Name = "Ground"
	ground.Size = Vector3.new(data.Radius * 2 + 400, 2, data.Radius * 2 + 400)
	ground.Position = origin - Vector3.new(0, 1, 0)
	ground.Color = GROUND_COLOR
	ground.Material = Enum.Material.Pavement

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = folder
	local focusFolder = Instance.new("Model")
	focusFolder.Name = "FocusArea"
	focusFolder.Parent = folder

	local focusName = data.FocusLabel or "FocusBuilding" -- shows up in crash messages
	local tallestFocus: BasePart? = nil
	local focusHeight = 0
	for i, r in ipairs(records(data.Boxes)) do
		local cx, cz, w, d, yaw, h, focus = r[1], r[2], r[3], r[4], r[5], r[6], r[7]
		local p = newPart("Part", if focus == 1 then focusFolder else buildings)
		p.Name = if focus == 1 then focusName else "Building"
		p.Size = Vector3.new(w, h, d)
		p.CFrame = CFrame.new(origin + Vector3.new(cx, h / 2, cz)) * CFrame.Angles(0, yaw, 0)
		p.Color = if focus == 1 then FOCUS_COLOR else BUILDING_COLORS[(i % #BUILDING_COLORS) + 1]
		p.Material = Enum.Material.Concrete
		if focus == 1 and (not tallestFocus or h > focusHeight) then
			tallestFocus, focusHeight = p, h
		end
	end
	for i, r in ipairs(records(data.Tris)) do
		local y = origin.Y
		local a = origin + Vector3.new(r[1], 0, r[2])
		local b = origin + Vector3.new(r[3], 0, r[4])
		local c = origin + Vector3.new(r[5], 0, r[6])
		local color = if r[8] == 1 then FOCUS_COLOR else BUILDING_COLORS[(i % #BUILDING_COLORS) + 1]
		local m = Instance.new("Model")
		m.Name = if r[8] == 1 then focusName else "Building"
		m.Parent = if r[8] == 1 then focusFolder else buildings
		local wedge = prism(Vector3.new(a.X, y, a.Z), Vector3.new(b.X, y, b.Z), Vector3.new(c.X, y, c.Z), r[7], m, color, Enum.Material.Concrete)
		if wedge and r[8] == 1 and (not tallestFocus or r[7] > focusHeight) then
			tallestFocus, focusHeight = wedge, r[7]
		end
	end

	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = folder
	for _, r in ipairs(records(data.Roads)) do
		local a = origin + Vector3.new(r[1], 0.05, r[2])
		local b = origin + Vector3.new(r[3], 0.05, r[4])
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
		local y = origin.Y
		prism(Vector3.new(origin.X + r[1], y, origin.Z + r[2]), Vector3.new(origin.X + r[3], y, origin.Z + r[4]),
			Vector3.new(origin.X + r[5], y, origin.Z + r[6]), 0.15, green, GREEN_COLOR, Enum.Material.Grass)
	end

	-- Launch pad at the chosen open spot
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
		gui.StudsOffsetWorldSpace = Vector3.new(0, focusHeight / 2 + 8, 0) -- world up (wedge axes are rotated)
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
		label.Text = "🏥 " .. (data.FocusLabel or data.Name)
		label.Parent = gui
	end

	local credit = Instance.new("StringValue")
	credit.Name = "Attribution"
	credit.Value = "Map data (c) OpenStreetMap contributors, ODbL 1.0"
	credit.Parent = folder
	return folder
end

return OsmMapBuilder
