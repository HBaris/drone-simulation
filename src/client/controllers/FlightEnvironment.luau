--!strict
-- FlightEnvironment.luau
-- Raycasts the world around the drone: ground height below it (for take-off / landing) and
-- obstacles along its movement (buildings, bridge towers, sea) for crash detection.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local FlightEnvironment = {}

local DRONE_HALF_HEIGHT = 0.4 -- studs from the model pivot to the landing gear
local GROUND_PROBE = 2000

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = false

local function refreshFilter()
	local ignore: { Instance } = {}
	local swarm = Workspace:FindFirstChild("DroneSwarm")
	if swarm then
		table.insert(ignore, swarm)
	end
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if character then
		table.insert(ignore, character)
	end
	params.FilterDescendantsInstances = ignore
end

-- Resting height of the drone pivot on whatever is below `pos` (nil over the void), and the hit.
function FlightEnvironment.groundY(pos: Vector3): (number?, RaycastResult?)
	refreshFilter()
	local hit = Workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -GROUND_PROBE, 0), params)
	if not hit then
		return nil, nil
	end
	return hit.Position.Y + DRONE_HALF_HEIGHT, hit
end

-- First obstacle between two drone positions (padded by the drone's size), or nil.
function FlightEnvironment.obstacleBetween(fromPos: Vector3, toPos: Vector3): RaycastResult?
	local delta = toPos - fromPos
	if delta.Magnitude < 1e-3 then
		return nil
	end
	refreshFilter()
	local padded = delta + delta.Unit * 1.2
	return Workspace:Raycast(fromPos, padded, params)
end

return FlightEnvironment
