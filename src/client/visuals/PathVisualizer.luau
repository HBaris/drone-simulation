--!strict
-- PathVisualizer.luau
-- Manages 3D workspace visualization: Waypoint markers, billboard labels, and neon trajectory paths.

local Workspace = game:GetService("Workspace")
local FlightMath = require(game:GetService("ReplicatedStorage"):WaitForChild("FlightMath"))

local PathVisualizer = {}

export type VisualizerState = {
	Markers: { Instance },
	PathParts: { Instance },
}

function PathVisualizer.new(): VisualizerState
	return {
		Markers = {},
		PathParts = {},
	}
end

-- Redraws the 3D neon trajectory lines between waypoints
function PathVisualizer.redrawTrajectory(state: VisualizerState, waypoints: { FlightMath.Waypoint })
	for _, part in ipairs(state.PathParts) do
		part:Destroy()
	end
	table.clear(state.PathParts)

	if #waypoints < 2 then
		return
	end

	for i = 1, #waypoints - 1 do
		local p1 = waypoints[i].Position
		local p2 = waypoints[i + 1].Position

		local line = Instance.new("Part")
		line.Name = "TrajectoryLine_" .. i
		line.Anchored = true
		line.CanCollide = false
		line.Material = Enum.Material.Neon
		line.Color = Color3.fromRGB(0, 255, 180)
		line.Transparency = 0.3

		local dist = (p2 - p1).Magnitude
		line.Size = Vector3.new(0.2, 0.2, dist)
		line.CFrame = CFrame.lookAt(p1 + (p2 - p1) * 0.5, p2)
		line.Parent = Workspace

		table.insert(state.PathParts, line)
	end
end

-- Adds a 3D waypoint marker with billboard index number
function PathVisualizer.addMarker(state: VisualizerState, position: Vector3, index: number): Instance
	local marker = Instance.new("Part")
	marker.Name = "WP_Marker_" .. index
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.3, 1.5, 1.5)
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(0, 255, 150)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

	local bbg = Instance.new("BillboardGui")
	bbg.Size = UDim2.new(0, 40, 0, 40)
	bbg.StudsOffset = Vector3.new(0, 1.5, 0)
	bbg.AlwaysOnTop = true
	bbg.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = tostring(index)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Parent = bbg

	marker.Parent = Workspace
	table.insert(state.Markers, marker)

	return marker
end

-- Clears all 3D markers and path lines
function PathVisualizer.clearAll(state: VisualizerState)
	for _, m in ipairs(state.Markers) do
		m:Destroy()
	end
	table.clear(state.Markers)

	for _, p in ipairs(state.PathParts) do
		p:Destroy()
	end
	table.clear(state.PathParts)
end

return table.freeze(PathVisualizer)
