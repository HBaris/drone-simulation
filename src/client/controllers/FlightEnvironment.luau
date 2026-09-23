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

-- Fraction of the sky blocked around `pos` (0 open .. 1 urban canyon): rays toward where GPS satellites
-- sit (35° elevation, 12 azimuths) that hit a building within 70 m. Drives the GPS model's multipath.
local SKY_RAYS = 12
local SKY_ELEVATION = math.rad(35)
local SKY_RANGE = 70 * 3.5
function FlightEnvironment.skyObstruction(pos: Vector3): number
	refreshFilter()
	local blocked = 0
	for k = 0, SKY_RAYS - 1 do
		local az = k * 2 * math.pi / SKY_RAYS
		local dir = Vector3.new(math.cos(az) * math.cos(SKY_ELEVATION), math.sin(SKY_ELEVATION), math.sin(az) * math.cos(SKY_ELEVATION))
		if Workspace:Raycast(pos, dir * SKY_RANGE, params) then
			blocked += 1
		end
	end
	return blocked / SKY_RAYS
end

return FlightEnvironment
