--!strict
-- DronePilotController.client.luau
-- Flies the primary drone (Drone_001) in every mode: pilot (FPV / chase cam), AUTO mission,
-- RTL and LAND via Autopilot. Also resolves ground / obstacle contact, runs the motor & battery
-- model, drives the OSD + health panel, and the blackbox recorder.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local DroneHealthModel = require(ReplicatedStorage:WaitForChild("DroneHealthModel"))
local WindModel = require(ReplicatedStorage:WaitForChild("WindModel"))
local uiFolder = script.Parent.Parent:WaitForChild("ui")
local FPVOverlay = require(uiFolder:WaitForChild("FPVOverlay"))
local EditorUI = require(uiFolder:WaitForChild("EditorUI"))
local HealthPanel = require(uiFolder:WaitForChild("HealthPanel"))
local FlightRecorder = require(script.Parent:WaitForChild("FlightRecorder"))
local Autopilot = require(script.Parent:WaitForChild("Autopilot"))
local DronePhysics = require(script.Parent:WaitForChild("DronePhysics"))
local FlightEnvironment = require(script.Parent:WaitForChild("FlightEnvironment"))
local GpsModel = require(script.Parent:WaitForChild("GpsModel"))
local BridgeClient = require(script.Parent:WaitForChild("BridgeClient"))

local S = DroneConfig.STUDS_PER_METER
local FS = DroneConfig.FAILSAFE

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local osd = FPVOverlay.create(playerGui)
local healthPanel = HealthPanel.create(osd.ScreenGui)
local recorder = FlightRecorder.new()
local telemetry = DroneHealthModel.new()
local DEFAULT_MODE_TEXT = osd.FlightModeText.Text

local isManualPilotActive = true -- pilot view & keyboard control (M toggles the route editor)
local cameraMode = "FPV" -- "FPV" or "CHASE"

-- Starts on the launch pad facing East towards the Bosphorus Bridge
local drone = DronePhysics.new(DroneConfig.HOME.SIM_POSITION, -90)
local onGroundTimer = 0
local crashReason = ""
local smoothedAccel = Vector3.zero
local lastRates = Vector3.zero -- roll, pitch, yaw rates (rad/s, ArduPilot signs)
local smoothedAngAccel = Vector3.zero
local flightClock = 0 -- drives the turbulence noise
local currentWind = Vector3.zero -- m/s at the drone, for the panel
-- What the flight controller believes (GPS + baro through the EKF): the autopilot flies on this
local gps = GpsModel.new()
local estPos = drone.Position
local skyTimer = 0
local gpsBadTimer = 0

-- Live telemetry as attributes (read by tests / Studio tools today, the bridge server later)
local telemetryOut = Instance.new("Configuration")
telemetryOut.Name = "DroneTelemetry"
telemetryOut.Parent = ReplicatedStorage
local telemetryTimer = 0
local streamTimer = 0

-- Command channel: BindableEvent:Fire("mission", { Vector3 }) | ("rtl") | ("land") | ("reset")
local commandEvent = Instance.new("BindableEvent")
commandEvent.Name = "DroneCommand"
commandEvent.Parent = ReplicatedStorage

local motorSound = Instance.new("Sound")
motorSound.Name = "DroneMotorSound"
motorSound.SoundId = "rbxassetid://9114223170" -- Quadcopter electric motor loop
motorSound.Volume = 0.5
motorSound.Looped = true
motorSound.Parent = Workspace

local function getPrimaryDrone(): Model?
	local swarm = Workspace:FindFirstChild("DroneSwarm")
	return if swarm then swarm:FindFirstChild("Drone_001") :: Model? else nil
end

-- Rotor discs of the model mapped to ArduPilot motor numbers by their position on the frame
local rotorCache: { model: Model?, rotors: { [number]: BasePart } } = { model = nil, rotors = {} }
local function rotorsFor(model: Model): { [number]: BasePart }
	if rotorCache.model ~= model and model.PrimaryPart then
		rotorCache.model = model
		rotorCache.rotors = {}
		for _, part in ipairs(model:GetChildren()) do
			if part:IsA("BasePart") and part.Name:match("^Rotor_") then
				local lp = model.PrimaryPart.CFrame:PointToObjectSpace(part.Position)
				local front, right = lp.Z < 0, lp.X > 0
				local index = if front and right then 1 elseif not front and not right then 2 elseif front then 3 else 4
				rotorCache.rotors[index] = part
			end
		end
	end
	return rotorCache.rotors
end

local IDLE_COLOR = Color3.fromRGB(200, 200, 200)
local HOVER_COLOR = Color3.fromRGB(0, 220, 255)
local HIGH_COLOR = Color3.fromRGB(255, 120, 0)
local function paintRotors(model: Model)
	for index, rotor in pairs(rotorsFor(model)) do
		local m = telemetry.Motors[index]
		if m.Failed then
			rotor.Color = Color3.fromRGB(120, 0, 0)
			rotor.Transparency = 0.2
		else
			local o = m.Output
			rotor.Color = if o < 0.35 then IDLE_COLOR:Lerp(HOVER_COLOR, o / 0.35) else HOVER_COLOR:Lerp(HIGH_COLOR, (o - 0.35) / 0.65)
			rotor.Transparency = 0.75 - 0.35 * o
		end
	end
end

local function stopRecordingAndExport()
	if recorder:stop() < 2 then
		return
	end
	EditorUI.showExportModal(osd.ScreenGui, recorder:encode(),
		string.format("Uçuş Kaydı %.0f sn → tools/sim2mission.py", recorder:duration()))
end

local function crash(reason: string)
	if Autopilot.Mode == "CRASHED" then
		return
	end
	crashReason = reason
	Autopilot.setMode("CRASHED", reason)
	if recorder.IsRecording then
		stopRecordingAndExport()
	end
end

-- Reset after a crash: back on the pad with a fresh battery and healthy motors
local function resetDrone()
	gps = GpsModel.new()
	gpsBadTimer = 0
	drone = DronePhysics.new(DroneConfig.HOME.SIM_POSITION, -90)
	telemetry = DroneHealthModel.new()
	crashReason = ""
	Autopilot.disarm()
	Autopilot.resetFailsafes()
	Autopilot.setMode("MANUAL", "sıfırlandı")
end

-- Ground-station motor tests (DO_MOTOR_TEST): only on the ground and disarmed
local motorTests: { { Motor: number, Pct: number, From: number, Till: number } } = {}
local clockNow = 0

local bridgeHooks: BridgeClient.Hooks = {
	Arm = function(): boolean
		if Autopilot.Mode == "CRASHED" then
			return false
		end
		Autopilot.arm(estPos) -- home = where the flight controller thinks it is
		return true
	end,
	Disarm = function(force: boolean)
		local airborne = onGroundTimer <= 0
		if airborne and not force then
			return
		end
		Autopilot.disarm()
		if airborne then
			crash("ZORLA DISARM — havada motorlar durdu")
		end
	end,
	Reset = function()
		resetDrone()
	end,
	Fault = function(motor: number, efficiency: number)
		-- SIM_ENGINE_MUL style: 1 restores the motor; applies to all motors when out of range
		for i, m in ipairs(telemetry.Motors) do
			if i == motor then
				m.Efficiency = math.clamp(efficiency, 0.05, 1)
			end
		end
	end,
	MotorTest = function(motor: number, pct: number, seconds: number, delay: number)
		if not Autopilot.Armed and telemetry.Motors[motor] then
			table.insert(motorTests, { Motor = motor, Pct = pct / 100, From = clockNow + delay, Till = clockNow + delay + seconds })
		end
	end,
}

local function runBridgeCommands(commands: { any })
	for _, c in ipairs(commands) do
		BridgeClient.execute(c, drone, bridgeHooks)
	end
end

-- Bridge link to the server (created by BridgeLink.server; absent when that script is not installed)
local bridgeStateEvent: RemoteEvent? = nil
task.spawn(function()
	local network = ReplicatedStorage:WaitForChild("DroneNetwork", 30)
	local stateEvent = network and network:WaitForChild("BridgeState", 30)
	local commands = network and network:WaitForChild("BridgeCommands", 30)
	if stateEvent and commands then
		local commandsEvent = commands :: RemoteEvent
		commandsEvent.OnClientEvent:Connect(runBridgeCommands)
		bridgeStateEvent = stateEvent :: RemoteEvent
	end
end)
local bridgeTimer = 0
local wasArmed = false
local lastYaw = drone.Yaw
local yawRate = 0

commandEvent.Event:Connect(function(command: string, arg: any)
	if command == "mission" then
		Autopilot.startMission(arg)
	elseif command == "exec" then
		runBridgeCommands(if arg.type then { arg } else arg) -- bridge-format command(s), for tests
	elseif command == "rtl" and Autopilot.Armed then
		Autopilot.setMode("RTL", "komut")
	elseif command == "land" and Autopilot.Armed then
		Autopilot.setMode("LAND", "komut")
	elseif command == "reset" then
		resetDrone()
	end
end)

local keysDown: { [Enum.KeyCode]: boolean } = {}
local STICK_KEYS = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.D] = true,
	[Enum.KeyCode.Space] = true, [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.Q] = true, [Enum.KeyCode.E] = true,
}

local function readSticks(): DronePhysics.StickInput
	local function axis(plus: Enum.KeyCode, minus: Enum.KeyCode): number
		return (if keysDown[plus] then 1 else 0) - (if keysDown[minus] then 1 else 0)
	end
	if not isManualPilotActive then
		return { Forward = 0, Right = 0, Up = 0, Yaw = 0 }
	end
	return {
		Forward = axis(Enum.KeyCode.W, Enum.KeyCode.S),
		Right = axis(Enum.KeyCode.D, Enum.KeyCode.A),
		Up = axis(Enum.KeyCode.Space, Enum.KeyCode.LeftShift),
		Yaw = axis(Enum.KeyCode.E, Enum.KeyCode.Q),
	}
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local code = input.KeyCode
	keysDown[code] = true

	if STICK_KEYS[code] and isManualPilotActive then
		-- Pilot override: touching the sticks takes control back from the autopilot
		if Autopilot.Mode == "AUTO" or Autopilot.Mode == "RTL" or Autopilot.Mode == "LAND" then
			Autopilot.setMode("MANUAL", "pilot kontrolü devraldı")
		end
	elseif code == Enum.KeyCode.C then
		cameraMode = if cameraMode == "FPV" then "CHASE" else "FPV"
	elseif code == Enum.KeyCode.H then
		if Autopilot.Armed then
			Autopilot.setMode("RTL", "pilot komutu")
		end
	elseif code == Enum.KeyCode.L then
		if Autopilot.Armed then
			Autopilot.setMode("LAND", "pilot komutu")
		end
	elseif code == Enum.KeyCode.K then
		-- Fault injection: motor 1 fails (a quad cannot survive this; a hexacopter could)
		telemetry.Motors[1].Failed = not telemetry.Motors[1].Failed
	elseif code == Enum.KeyCode.B then
		-- Fault injection: battery suddenly at ~22% (tests the low-battery failsafe)
		telemetry.UsedMah = math.max(telemetry.UsedMah, DroneConfig.AIRFRAME.BATTERY_CAPACITY_MAH * 0.78)
	elseif code == Enum.KeyCode.X and Autopilot.Mode == "CRASHED" then
		resetDrone()
	elseif code == Enum.KeyCode.R and isManualPilotActive and not recorder.IsReplaying then
		if recorder.IsRecording then
			stopRecordingAndExport()
		else
			recorder:start()
		end
	elseif code == Enum.KeyCode.P and isManualPilotActive and not recorder.IsRecording then
		if recorder.IsReplaying then
			recorder:stopReplay()
		else
			recorder:startReplay()
		end
	elseif code == Enum.KeyCode.M then
		isManualPilotActive = not isManualPilotActive
		osd.ToggleVisibility(isManualPilotActive)
		if not isManualPilotActive then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = player.Character and player.Character:FindFirstChild("Humanoid")
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	keysDown[input.KeyCode] = false
end)

local function isWater(hit: RaycastResult): boolean
	return hit.Material == Enum.Material.Water or hit.Instance.Name == "BosphorusSea"
end

-- Ground / obstacle contact after the drone moved from prevPos
local function resolveContacts(prevPos: Vector3)
	local hit = FlightEnvironment.obstacleBetween(prevPos, drone.Position)
	local speed = drone.Velocity.Magnitude / S
	if hit and hit.Normal.Y < 0.7 and Autopilot.Mode ~= "CRASHED" then
		-- OSM buildings made of triangle wedges carry their name on the parent model
		local inst = hit.Instance
		local name = if inst.Name:match("^Tri%d") and inst.Parent then inst.Parent.Name else inst.Name
		crash(string.format("ÇARPIŞMA: %s (%.1f m/s)", name, speed))
	end

	local groundY, groundHit = FlightEnvironment.groundY(drone.Position)
	if not groundY or drone.Position.Y > groundY then
		return
	end
	drone.Position = Vector3.new(drone.Position.X, groundY, drone.Position.Z)
	if Autopilot.Mode ~= "CRASHED" then
		if groundHit and isWater(groundHit) then
			crash("SUYA DÜŞTÜ")
		elseif speed > FS.CRASH_SPEED then
			crash(string.format("SERT TEMAS %.1f m/s", speed))
		end
	end
	drone.Velocity = Vector3.zero
	drone.Pitch, drone.Roll = 0, if Autopilot.Mode == "CRASHED" then drone.Roll else 0
end

-- GPS / baro estimate for this frame; sky obstruction is sampled twice a second (12 raycasts)
local function updateEstimate(dt: number)
	skyTimer += dt
	if skyTimer >= 0.5 then
		skyTimer = 0
		gps:setObstruction(FlightEnvironment.skyObstruction(drone.Position))
	end
	estPos = gps:step(dt, drone.Position)
	-- EKF failsafe (ArduPilot FS_EKF_ACTION = LAND): position estimate unusable for 3 s in an autonomous mode
	local bad = gps.Sats < DroneConfig.GPS.FAILSAFE_SATS or gps.Hdop > DroneConfig.GPS.FAILSAFE_HDOP
	gpsBadTimer = if bad and Autopilot.Armed then gpsBadTimer + dt else 0
	local autonomous = Autopilot.Mode == "AUTO" or Autopilot.Mode == "GUIDED" or Autopilot.Mode == "RTL"
	if gpsBadTimer > 3 and autonomous then
		Autopilot.setMode("LAND", string.format("GPS/EKF FAILSAFE (%d uydu, HDOP %.1f)", gps.Sats, gps.Hdop))
	end
end

local function stepFlight(dt: number)
	updateEstimate(dt)
	local wasOnGround = onGroundTimer > 0
	local groundY = FlightEnvironment.groundY(drone.Position)
	-- Wind at the drone's height above ground (sheltered to nothing while sitting on the pad)
	local agl = if groundY then (drone.Position.Y - groundY) / S else Autopilot.relAlt(drone.Position)
	flightClock += dt
	currentWind = if wasOnGround then Vector3.zero else WindModel.at(flightClock, agl)

	if Autopilot.Mode == "CRASHED" then
		if Autopilot.Armed then
			DronePhysics.stepCrash(drone, dt, currentWind)
		end
		return
	end

	-- With a rangefinder the autopilot knows its true height above ground; without one (TEI drone) it only
	-- has barometric altitude above home, so landing slows down by that instead.
	local guidanceGround = if groundY and DroneConfig.AIRFRAME.RANGEFINDER then groundY + (estPos.Y - drone.Position.Y) else nil
	local desired = Autopilot.guidance(dt, estPos, guidanceGround)
	if desired then
		-- The route editor's "start" arms for AUTO; every other autonomous mode needs an armed drone
		if Autopilot.Mode == "AUTO" then
			Autopilot.arm(estPos)
		end
		if Autopilot.Armed then
			DronePhysics.stepGuided(drone, dt, desired, currentWind, Autopilot.commandedYawRate())
			return
		end
		if groundY then
			drone.Position = Vector3.new(drone.Position.X, groundY, drone.Position.Z)
		end
		return
	end

	local sticks = readSticks()
	if not Autopilot.Armed then
		if sticks.Up > 0 then
			Autopilot.arm(estPos) -- throttle up on the pad arms the motors
		else
			if groundY then
				drone.Position = Vector3.new(drone.Position.X, groundY, drone.Position.Z) -- rest on the pad
			end
			return
		end
	end
	if wasOnGround and sticks.Up <= 0 then
		sticks = { Forward = 0, Right = 0, Up = sticks.Up, Yaw = sticks.Yaw } -- can't slide on the ground
	end
	DronePhysics.stepManual(drone, dt, sticks, currentWind)
	-- Fence avoidance: undo any part of this step that would carry the drone past the ceiling / circle
	local allowed = Autopilot.fenceLimitVelocity(estPos, drone.Velocity)
	if allowed ~= drone.Velocity then
		drone.Position += (allowed - drone.Velocity) * dt
		drone.Velocity = allowed
	end
end

-- Angular acceleration (rad/s², ArduPilot roll/pitch/yaw signs) for the motor mixer
local function updateAngularAccel(dt: number, prevPitch: number, prevRoll: number, prevYaw: number)
	if dt <= 0 then
		return
	end
	local rates = Vector3.new(
		math.rad(drone.Roll - prevRoll),
		-math.rad(drone.Pitch - prevPitch), -- sim pitch is nose-down positive
		-math.rad((drone.Yaw - prevYaw + 180) % 360 - 180) -- heading turns the other way
	) / dt
	smoothedAngAccel = smoothedAngAccel:Lerp((rates - lastRates) / dt, math.min(1, 10 * dt))
	lastRates = rates
end

RunService.RenderStepped:Connect(function(rawDt: number)
	local dt = math.min(rawDt, 0.1)
	local model = getPrimaryDrone()
	if not model or not model.PrimaryPart then
		return
	end

	local prevPos, prevVel = drone.Position, drone.Velocity
	local prevPitch, prevRoll, prevYaw = drone.Pitch, drone.Roll, drone.Yaw

	if recorder.IsReplaying then
		local finished
		drone.Position, drone.Yaw, drone.Pitch, drone.Roll, finished = recorder:stepReplay(dt)
		drone.Velocity = (drone.Position - prevPos) / dt
		estPos = drone.Position -- replaying a recording: no estimator in the loop
		if finished then
			recorder:stopReplay()
		end
	else
		stepFlight(dt)
		resolveContacts(prevPos)
	end

	-- Streaming: keep the world around the drone loaded on this client (it can fly far from the character)
	streamTimer += dt
	if streamTimer > 2 and Workspace.StreamingEnabled then
		streamTimer = 0
		local target = drone.Position
		task.spawn(function()
			pcall(function()
				player:RequestStreamAroundAsync(target)
			end)
		end)
	end
	if Autopilot.Armed and Autopilot.Mode ~= "CRASHED" and (drone.Position.Y - DroneConfig.HOME.SIM_POSITION.Y) / S < -50 then
		crash("ZEMİN YOK — kalkış noktasının 50 m altına indi (harita yüklenmemiş olabilir)")
	end

	-- Landed: disarm after DISARM_DELAY, the flight is over. The delay counts from arming (or
	-- touchdown), not from how long the drone sat on the pad before.
	local groundY = FlightEnvironment.groundY(drone.Position)
	local onGround = groundY ~= nil and drone.Position.Y <= groundY + 0.05
	if Autopilot.Armed and not wasArmed then
		onGroundTimer = 0
	end
	wasArmed = Autopilot.Armed
	onGroundTimer = if onGround then onGroundTimer + dt else 0
	if onGround and Autopilot.Armed and onGroundTimer > DroneConfig.AUTOPILOT.DISARM_DELAY
		and Autopilot.Mode ~= "AUTO" and not keysDown[Enum.KeyCode.Space] then
		Autopilot.disarm()
		if Autopilot.Mode == "LAND" or Autopilot.Mode == "RTL" then
			Autopilot.setMode("MANUAL", "indi, motorlar durdu")
		end
	end

	-- Motors & battery
	local thrustAccel = if recorder.IsReplaying then (drone.Velocity - prevVel) / dt / S else drone.ThrustAccel
	smoothedAccel = smoothedAccel:Lerp(thrustAccel, math.min(1, 8 * dt))
	updateAngularAccel(dt, prevPitch, prevRoll, prevYaw)
	local motorsRunning = Autopilot.Armed and Autopilot.Mode ~= "CRASHED"
	DroneHealthModel.step(telemetry, dt, smoothedAccel, smoothedAngAccel, motorsRunning)
	clockNow += dt
	for i = #motorTests, 1, -1 do
		local test = motorTests[i]
		if clockNow > test.Till or Autopilot.Armed then
			table.remove(motorTests, i)
		elseif clockNow >= test.From then
			local m = telemetry.Motors[test.Motor]
			local af = DroneConfig.AIRFRAME
			m.Output = test.Pct
			m.Rpm = af.MAX_MOTOR_RPM * math.sqrt(test.Pct)
			m.CurrentA = af.MAX_MOTOR_CURRENT_A * test.Pct ^ 1.5
			telemetry.CurrentA += m.CurrentA
		end
	end
	Autopilot.checkFailsafes(dt, estPos, telemetry.VoltageV) -- the fence works on the estimate, as on a real FC
	for _, m in ipairs(telemetry.Motors) do
		if m.Failed and Autopilot.Armed and not onGround then
			crash("MOTOR ARIZASI — quad 3 motorla uçamaz")
		end
	end

	if recorder.IsRecording and not recorder:step(dt, drone.Position, drone.Yaw, drone.Pitch, drone.Roll) then
		stopRecordingAndExport() -- duration limit reached
	end

	-- Model, rotors, camera
	local droneCF = DronePhysics.cframe(drone)
	model:PivotTo(droneCF)
	paintRotors(model)
	if isManualPilotActive then
		camera.CameraType = Enum.CameraType.Scriptable
		if cameraMode == "FPV" then
			camera.CFrame = droneCF * CFrame.new(0, 0.2, -0.9)
		else
			local chasePos = drone.Position - DronePhysics.forward(drone.Yaw) * 12 + Vector3.new(0, 4.5, 0)
			camera.CFrame = CFrame.lookAt(chasePos, drone.Position + Vector3.new(0, 1, 0))
		end
	end

	-- Sound follows the average motor output
	local avgOutput = 0
	for _, m in ipairs(telemetry.Motors) do
		avgOutput += m.Output / #telemetry.Motors
	end
	if motorsRunning and not motorSound.IsPlaying then
		motorSound:Play()
	elseif not motorsRunning and motorSound.IsPlaying then
		motorSound:Stop()
	end
	motorSound.PlaybackSpeed = 0.7 + avgOutput * 1.2

	-- OSD: altitude relative to the launch pad and compass heading, as the real drone reports them
	local altMeters = (drone.Position.Y - DroneConfig.HOME.SIM_POSITION.Y) / S
	osd.Update(drone.Velocity.Magnitude / S, altMeters, (-drone.Yaw) % 360, drone.Pitch, drone.Roll)
	if Autopilot.Mode == "CRASHED" then
		osd.FlightModeText.Text = "💥 " .. crashReason .. "  (X: sıfırla)"
	elseif recorder.IsRecording then
		osd.FlightModeText.Text = string.format("🔴 KAYIT %02d:%02d  (R: durdur)", recorder.Elapsed // 60, math.floor(recorder.Elapsed % 60))
	elseif recorder.IsReplaying then
		osd.FlightModeText.Text = string.format("▶ TEKRAR OYNATILIYOR %.0f / %.0f sn", recorder.ReplayTime, recorder:duration())
	elseif Autopilot.Mode ~= "MANUAL" then
		osd.FlightModeText.Text = "🛰 " .. Autopilot.Mode .. "  " .. Autopilot.Status
	else
		osd.FlightModeText.Text = DEFAULT_MODE_TEXT
	end

	telemetryTimer += dt
	if telemetryTimer >= 0.2 then
		telemetryTimer = 0
		telemetryOut:SetAttribute("Mode", Autopilot.Mode)
		telemetryOut:SetAttribute("Status", Autopilot.Status)
		telemetryOut:SetAttribute("Event", Autopilot.LastEvent)
		telemetryOut:SetAttribute("Armed", Autopilot.Armed)
		telemetryOut:SetAttribute("Position", drone.Position)
		telemetryOut:SetAttribute("EstPosition", estPos)
		telemetryOut:SetAttribute("GpsSats", gps.Sats)
		telemetryOut:SetAttribute("Hdop", gps.Hdop)
		telemetryOut:SetAttribute("GpsErrorM", gps:horizontalError())
		telemetryOut:SetAttribute("SkyObstruction", gps.Obstruction)
		telemetryOut:SetAttribute("AltM", altMeters)
		telemetryOut:SetAttribute("SpeedMs", drone.Velocity.Magnitude / S)
		telemetryOut:SetAttribute("HeadingDeg", (-drone.Yaw) % 360)
		telemetryOut:SetAttribute("VoltageV", telemetry.VoltageV)
		telemetryOut:SetAttribute("CurrentA", telemetry.CurrentA)
		telemetryOut:SetAttribute("UsedMah", telemetry.UsedMah)
		for i, m in ipairs(telemetry.Motors) do
			telemetryOut:SetAttribute("Motor" .. i, m.Output)
		end
		telemetryOut:SetAttribute("Crash", crashReason)
		telemetryOut:SetAttribute("WindAtDrone", currentWind)
		telemetryOut:SetAttribute("TiltSaturated", drone.Saturated)
		telemetryOut:SetAttribute("PitchDeg", drone.Pitch)
		telemetryOut:SetAttribute("RollDeg", drone.Roll)
	end

	-- MAVLink bridge: 5 Hz state to the server
	yawRate = yawRate + (((lastYaw - drone.Yaw + 180) % 360 - 180) / dt - yawRate) * math.min(1, 5 * dt)
	lastYaw = drone.Yaw
	bridgeTimer += dt
	local stateEvent = bridgeStateEvent
	if stateEvent and bridgeTimer >= 1 / DroneConfig.BRIDGE.RATE_HZ then
		bridgeTimer = 0
		stateEvent:FireServer(BridgeClient.buildState({
			Drone = drone, Telemetry = telemetry, Wind = currentWind, OnGround = onGround,
			EstPosition = estPos, GpsSats = gps.Sats, Hdop = gps.Hdop,
			Crash = crashReason, YawRate = yawRate,
		}))
	end

	local toHome = drone.Position - Autopilot.Home
	local weather = ReplicatedStorage:FindFirstChild("Weather")
	local bridge = ReplicatedStorage:FindFirstChild("Bridge")
	local bridgeStatus = if bridge then tostring(bridge:GetAttribute("Status")) else ""
	local gpsText = string.format("🛰 %d uydu · HDOP %.1f · ±%.1f m", gps.Sats, gps.Hdop, gps:horizontalError())
	local panelStatus = (if Autopilot.Status ~= "" then Autopilot.Status .. "  ·  " else "") .. gpsText
		.. (if bridgeStatus:match("^BAĞLI") then "  ·  📡 bağlı" else "")
	healthPanel.Update(telemetry, Autopilot.Mode, panelStatus, Autopilot.LastEvent,
		Vector3.new(toHome.X, 0, toHome.Z).Magnitude / S, {
			Report = WindModel.report(),
			Station = if weather then tostring(weather:GetAttribute("Station") or "-") else "-",
			AtDrone = currentWind,
			Saturated = drone.Saturated,
		})
end)

print("[DronePilotController] Drone flight controller ready (MANUAL / GUIDED / AUTO / RTL / LAND).")
