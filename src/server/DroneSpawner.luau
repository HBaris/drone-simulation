--!strict
-- DroneSpawner.luau
-- Procedural Quadcopter Model Generator with LED Light Show emitters and optimized LODs.

local DroneConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("DroneConfig"))

local DroneSpawner = {}

-- Weld everything to the anchored chassis: the swarm/show loops BulkMoveTo only the PrimaryPart,
-- and separately anchored parts (LED, arms, rotors) would stay behind on the ground.
local function weldToChassis(model: Model, chassis: BasePart)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= chassis then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = chassis
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
			part.Massless = true
		end
	end
end

-- Creates a sleek procedural Quadcopter Model
function DroneSpawner.createQuadcopterModel(droneId: number, isHighDetail: boolean?): Model
	local highDetail = if isHighDetail ~= nil then isHighDetail else true
	local model = Instance.new("Model")
	model.Name = string.format("Drone_%03d", droneId)

	-- 1. Main Central Chassis (Root Part)
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(1.2, 0.35, 1.2)
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.Color = Color3.fromRGB(25, 25, 28)
	chassis.CastShadow = false
	chassis.Anchored = true
	chassis.CanCollide = false
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- 2. Powerful Bottom LED Show Light (The star of light shows)
	local led = Instance.new("Part")
	led.Name = "ShowLED"
	led.Shape = Enum.PartType.Ball
	led.Size = Vector3.new(0.6, 0.6, 0.6)
	led.Material = Enum.Material.Neon
	led.Color = DroneConfig.DRONE_MODEL.LED_DEFAULT_COLOR
	led.CastShadow = false
	led.Anchored = true
	led.CanCollide = false
	led.CFrame = chassis.CFrame * CFrame.new(0, -0.2, 0)
	led.Parent = model

	local pointLight = Instance.new("PointLight")
	pointLight.Name = "LightSource"
	pointLight.Color = led.Color
	pointLight.Brightness = DroneConfig.DRONE_MODEL.LED_BRIGHTNESS
	pointLight.Range = 18
	pointLight.Shadows = false
	pointLight.Parent = led

	-- Light trail for visual choreography arcs
	if DroneConfig.LIGHT_SHOW.ENABLE_TRAILS then
		local att0 = Instance.new("Attachment")
		att0.Position = Vector3.new(0, -0.3, 0)
		att0.Parent = led

		local att1 = Instance.new("Attachment")
		att1.Position = Vector3.new(0, 0.3, 0)
		att1.Parent = led

		local trail = Instance.new("Trail")
		trail.Name = "LightTrail"
		trail.Attachment0 = att0
		trail.Attachment1 = att1
		trail.Color = ColorSequence.new(led.Color)
		trail.Lifetime = DroneConfig.LIGHT_SHOW.TRAIL_LIFETIME
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		trail.Parent = led
	end

	-- If low detail mode (used for massive swarms > 300 drones), return early to maximize FPS
	if not highDetail then
		weldToChassis(model, chassis)
		return model
	end

	-- 3. Quadcopter Arms (X Configuration)
	local armOffsets = {
		-- Forward is -Z. ArduPilot numbers (DroneHealthModel.MOTORS) are mapped by position.
		Vector3.new(0.9, 0, 0.9),   -- Rear-Right (ArduPilot M4)
		Vector3.new(-0.9, 0, 0.9),  -- Rear-Left  (ArduPilot M2)
		Vector3.new(0.9, 0, -0.9),  -- Front-Right (ArduPilot M1)
		Vector3.new(-0.9, 0, -0.9), -- Front-Left  (ArduPilot M3)
	}

	for i, offset in ipairs(armOffsets) do
		-- Arm strut
		local arm = Instance.new("Part")
		arm.Name = "Arm_" .. i
		arm.Size = Vector3.new(0.2, 0.15, 1.2)
		arm.Material = Enum.Material.SmoothPlastic
		arm.Color = Color3.fromRGB(40, 40, 45)
		arm.Anchored = true
		arm.CanCollide = false
		arm.CFrame = chassis.CFrame * CFrame.new(offset.X * 0.5, 0, offset.Z * 0.5) * CFrame.Angles(0, math.atan2(offset.X, offset.Z), 0)
		arm.Parent = model

		-- Motor Pod
		local motor = Instance.new("Part")
		motor.Name = "Motor_" .. i
		motor.Shape = Enum.PartType.Cylinder
		motor.Size = Vector3.new(0.35, 0.4, 0.4)
		motor.Material = Enum.Material.Metal
		motor.Color = Color3.fromRGB(15, 15, 15)
		motor.Anchored = true
		motor.CanCollide = false
		-- Align cylinder vertically
		motor.CFrame = chassis.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
		motor.Parent = model

		-- Rotor Blade Disc
		local rotor = Instance.new("Part")
		rotor.Name = "Rotor_" .. i
		rotor.Shape = Enum.PartType.Cylinder
		rotor.Size = Vector3.new(0.04, 1.1, 1.1)
		rotor.Material = Enum.Material.Glass
		rotor.Color = Color3.fromRGB(200, 200, 200)
		rotor.Transparency = 0.65
		rotor.Anchored = true
		rotor.CanCollide = false
		rotor.CFrame = chassis.CFrame * CFrame.new(offset + Vector3.new(0, 0.22, 0)) * CFrame.Angles(0, 0, math.rad(90))
		rotor.Parent = model
	end

	weldToChassis(model, chassis)
	return model
end

return table.freeze(DroneSpawner)
