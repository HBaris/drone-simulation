--!strict
-- FlightManager.server.luau
-- Server-side coordinator for Drone Swarm Spawning, Choreography Execution, and Remote Network API.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local FlightMath = require(ReplicatedStorage:WaitForChild("FlightMath"))
local FormationGenerator = require(ReplicatedStorage:WaitForChild("FormationGenerator"))
local DataExporter = require(ReplicatedStorage:WaitForChild("DataExporter"))
local DroneSpawner = require(script.Parent:WaitForChild("DroneSpawner"))

-- Network Remotes Setup
local NetworkFolder = ReplicatedStorage:FindFirstChild("DroneNetwork")
if not NetworkFolder then
	NetworkFolder = Instance.new("Folder")
	NetworkFolder.Name = "DroneNetwork"
	NetworkFolder.Parent = ReplicatedStorage
end

local function getOrCreateRemote<T>(className: string, name: string): T
	local remote = NetworkFolder:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = NetworkFolder
	end
	return remote :: any
end

local StartFlightEvent = getOrCreateRemote("RemoteEvent", "StartFlight")
local StopFlightEvent = getOrCreateRemote("RemoteEvent", "StopFlight")
local SetFormationEvent = getOrCreateRemote("RemoteEvent", "SetFormation")
local ExportDataFunction = getOrCreateRemote("RemoteFunction", "ExportMissionData")

-- Workspace Container
local SwarmFolder = Workspace:FindFirstChild("DroneSwarm")
if not SwarmFolder then
	SwarmFolder = Instance.new("Folder")
	SwarmFolder.Name = "DroneSwarm"
	SwarmFolder.Parent = Workspace
end

-- Active State
type ActiveDroneState = {
	Id: number,
	Model: Model,
	CurrentPos: Vector3,
	TargetPos: Vector3,
	CurrentColor: Color3,
	DelayRemaining: number,
	Speed: number,
}

local activeDrones: { [number]: ActiveDroneState } = {}
local isSimulating = false
local currentWaypoints: { FlightMath.Waypoint } = {}

-- Ensure N drones exist in SwarmFolder
local function syncDroneCount(count: number)
	count = math.clamp(count, 1, DroneConfig.SWARM.MAX_DRONES)

	-- Destroy excess drones
	for id, state in pairs(activeDrones) do
		if id > count then
			if state.Model then
				state.Model:Destroy()
			end
			activeDrones[id] = nil
		end
	end

	-- Create missing drones
	local isLowDetail = count > 200
	for id = 1, count do
		if not activeDrones[id] then
			local model = DroneSpawner.createQuadcopterModel(id, not isLowDetail)
			local spawnPos = Vector3.new((id % 20) * 4, 1, math.floor(id / 20) * 4)
			model:PivotTo(CFrame.new(spawnPos))
			model.Parent = SwarmFolder

			activeDrones[id] = {
				Id = id,
				Model = model,
				CurrentPos = spawnPos,
				TargetPos = spawnPos,
				CurrentColor = DroneConfig.DRONE_MODEL.LED_DEFAULT_COLOR,
				DelayRemaining = 0,
				Speed = DroneConfig.FLIGHT.MAX_HORIZONTAL_SPEED,
			}
		end
	end
end

-- Handle Formations
SetFormationEvent.OnServerEvent:Connect(function(player, formationType: string, count: number, scale: number?)
	print(string.format("[FlightManager] Player %s requested formation '%s' with %d drones.", player.Name, formationType, count))
	syncDroneCount(count)

	local center = Vector3.new(0, 0, 0)
	local targets: { FormationGenerator.DroneTarget } = {}

	if formationType == "Grid" then
		targets = FormationGenerator.createGrid(count, center, 4 * (scale or 1))
	elseif formationType == "Circle" then
		targets = FormationGenerator.createCircle(count, center, nil, nil)
	elseif formationType == "Heart" then
		targets = FormationGenerator.createHeart(count, center, scale or 1.5)
	elseif formationType == "Sphere" then
		targets = FormationGenerator.createSphere(count, center, 25 * (scale or 1))
	elseif formationType == "Helix" then
		targets = FormationGenerator.createHelix(count, center)
	end

	for _, tgt in ipairs(targets) do
		local drone = activeDrones[tgt.DroneId]
		if drone then
			drone.TargetPos = tgt.TargetPosition
			drone.DelayRemaining = tgt.Delay
			drone.CurrentColor = tgt.TargetColor

			-- Update LED immediately
			local ledPart = drone.Model:FindFirstChild("ShowLED") :: Part?
			if ledPart then
				ledPart.Color = tgt.TargetColor
				local light = ledPart:FindFirstChild("LightSource") :: PointLight?
				if light then
					light.Color = tgt.TargetColor
				end
			end
		end
	end

	isSimulating = true
end)

-- Handle Single / Multi Waypoint Path Flight
StartFlightEvent.OnServerEvent:Connect(function(player, waypoints: { FlightMath.Waypoint })
	if not waypoints or #waypoints < 2 then
		warn("[FlightManager] Need at least 2 waypoints to start flight.")
		return
	end

	currentWaypoints = waypoints
	syncDroneCount(1) -- Single drone editor run
	isSimulating = true
	print(string.format("[FlightManager] Starting flight along %d waypoints.", #waypoints))
end)

StopFlightEvent.OnServerEvent:Connect(function()
	isSimulating = false
	print("[FlightManager] Simulation stopped. Landing drones.")
	for _, drone in pairs(activeDrones) do
		local groundPos = Vector3.new(drone.CurrentPos.X, 1.0, drone.CurrentPos.Z)
		drone.TargetPos = groundPos
		drone.Model:PivotTo(CFrame.new(groundPos))
	end
end)

-- Export Mission to Client
ExportDataFunction.OnServerInvoke = function(player, formatType: string)
	if #currentWaypoints < 2 then
		return "Hata: Dışa aktarılacak aktif bir rota bulunamadı. Lütfen önce waypoint ekleyin."
	end

	local mission = DataExporter.generateMissionFromPath(1, currentWaypoints)
	if formatType == "CSV" then
		return DataExporter.exportToCSV(mission)
	else
		return DataExporter.exportToJSON(mission)
	end
end

-- Swarm Movement Heartbeat Loop (60 FPS kinematic path solver)
local elapsedTime = 0
RunService.Heartbeat:Connect(function(dt: number)
	if not isSimulating then
		return
	end

	elapsedTime += dt

	-- Batch move collection for maximum engine performance
	local partsToMove: { BasePart } = {}
	local targetCFrames: { CFrame } = {}

	for id, drone in pairs(activeDrones) do
		if drone.DelayRemaining > 0 then
			drone.DelayRemaining -= dt
			continue
		end

		local delta = (drone.TargetPos - drone.CurrentPos)
		local dist = delta.Magnitude

		if dist > 0.05 then
			local step = math.min(dist, drone.Speed * dt)
			local dir = delta.Unit
			drone.CurrentPos += dir * step

			-- Bank tilt and forward rotation
			local lookAt = drone.CurrentPos + (if dir.Magnitude > 0.1 then Vector3.new(dir.X, 0, dir.Z) else Vector3.new(0, 0, -1))
			local baseCF = CFrame.lookAt(drone.CurrentPos, lookAt)
			local tiltCF = FlightMath.computeDroneTilt(dir * drone.Speed, dir * 5, baseCF)
			local finalCF = baseCF * tiltCF

			table.insert(partsToMove, drone.Model.PrimaryPart :: BasePart)
			table.insert(targetCFrames, finalCF)
		end
	end

	if #partsToMove > 0 then
		Workspace:BulkMoveTo(partsToMove, targetCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

print("[FlightManager] Drone Swarm Flight Coordinator successfully initialized.")
