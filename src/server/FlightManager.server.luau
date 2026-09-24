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
local ShowPlayer = require(script.Parent:WaitForChild("ShowPlayer"))

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
local monitorSeparation: (dt: number) -> ()
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
			-- Drone 1 sits on the active site's launch pad (flown client-side); show drones line up
			-- in a grid beside it so the swarm takes off where the player is
			local pad = DroneConfig.HOME.SIM_POSITION
			local spawnPos = if id == 1 then pad else pad + Vector3.new(8 + ((id - 2) % 10) * 3, 0, math.floor((id - 2) / 10) * 3)
			model:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(0, math.rad(-90), 0))
			-- Real-site maps are far from the origin; without this the client never streams the swarm in
			model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
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

-- Initialize single drone on the Helipad by default (no automatic swarm!)
syncDroneCount(1)

-- Handle Formations
SetFormationEvent.OnServerEvent:Connect(function(player, formationType: string, count: number, scale: number?)
	print(string.format("[FlightManager] Player %s requested formation '%s' with %d drones.", player.Name, formationType, count))
	if formationType == "Planned" then
		-- Collision-free show from tools/plan_show.py; replaces the ad-hoc formation drones
		syncDroneCount(1)
		ShowPlayer.start(ShowPlayer.load(require(script.Parent:WaitForChild("ShowData") :: any)), SwarmFolder)
		isSimulating = true
		return
	end
	ShowPlayer.stop()
	-- Drone_001 belongs to the client autopilot, so the show uses drones 2..count+1
	count = math.clamp(count, 1, DroneConfig.SWARM.MAX_DRONES - 1)
	syncDroneCount(count + 1)

	local center = DroneConfig.HOME.SHOW_CENTER + Vector3.new(0, DroneConfig.HOME.SHOW_LIFT, 0)
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
		local drone = activeDrones[tgt.DroneId + 1]
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
	-- Keep the heartbeat running so show drones fly back to their slots instead of teleporting
	ShowPlayer.stop()
	print("[FlightManager] Simulation stopped. Landing drones.")
	for _, drone in pairs(activeDrones) do
		if drone.Id == 1 then
			continue -- flown client-side by the Autopilot (DronePilotController), which lands it itself
		end
		-- Return to the spawn grid beside the pad (flat ground there, unlike under the formation)
		local pad = DroneConfig.HOME.SIM_POSITION
		local slot = drone.Id - 2
		local groundPos = pad + Vector3.new(8 + (slot % 10) * 3, 0, math.floor(slot / 10) * 3)
		drone.TargetPos = groundPos
		drone.DelayRemaining = 0
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

-- Live drone-to-drone separation over every swarm/show drone except Drone_001 (client-flown), 2 Hz.
-- Published as DroneSwarm attributes MinSeparationM / ClosePairs for the HUD.
local sepClock = 0
monitorSeparation = function(dt: number)
	sepClock += dt
	if sepClock < 0.5 then
		return
	end
	sepClock = 0
	local positions = ShowPlayer.positions()
	for id, drone in pairs(activeDrones) do
		if id ~= 1 then
			table.insert(positions, drone.CurrentPos)
		end
	end
	if #positions < 2 then
		SwarmFolder:SetAttribute("MinSeparationM", nil)
		return
	end
	local best, close = ShowPlayer.separation(positions, DroneConfig.SWARM.MIN_SEPARATION_M)
	SwarmFolder:SetAttribute("MinSeparationM", if best < math.huge then best else nil)
	SwarmFolder:SetAttribute("ClosePairs", close)
end

-- Swarm Movement Heartbeat Loop (60 FPS kinematic path solver)
local elapsedTime = 0
RunService.Heartbeat:Connect(function(dt: number)
	if not isSimulating then
		return
	end

	elapsedTime += dt
	ShowPlayer.step(dt)
	monitorSeparation(dt)

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
