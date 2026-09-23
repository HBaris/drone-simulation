--!strict
-- DroneConfig.luau
-- Global configuration parameters for Drone Flight & Swarm Show Simulation

local DroneConfig = {
	-- World & Physics Scale
	-- In Roblox, standard scale: 1 stud ≈ 0.28 meters (or 1 stud = 0.5m in custom flight models).
	-- Here we define conversion factor for real-world drone translation:
	STUDS_PER_METER = 3.5, -- ~0.285m per stud

	-- Physical Drone Properties
	DRONE_MODEL = {
		FRAME_SIZE = Vector3.new(2.4, 0.5, 2.4), -- Studs (X, Y, Z)
		BODY_COLOR = Color3.fromRGB(30, 30, 35),
		ROTOR_RADIUS = 0.7,
		ROTOR_RPM = 4800,
		LED_DEFAULT_COLOR = Color3.fromRGB(0, 255, 120), -- Neon Green
		LED_BRIGHTNESS = 2.0,
		COLLISION_RADIUS = 2.0, -- Minimum distance between drones (studs)
	},

	-- Flight Kinematics & Limits (Real drone physical limits)
	FLIGHT = {
		MAX_HORIZONTAL_SPEED = 20.0, -- studs/sec (~6 m/s)
		MAX_CLIMB_SPEED = 12.0,      -- studs/sec (~3.5 m/s)
		MAX_DESCENT_SPEED = 8.0,     -- studs/sec (~2.3 m/s)
		MAX_ACCELERATION = 15.0,     -- studs/sec^2
		MAX_TILT_ANGLE = 30.0,       -- degrees (pitch/roll when moving fast)
		MAX_YAW_RATE = 120.0,        -- degrees/sec
		TAKEOFF_ALTITUDE = 15.0,     -- Default hover altitude above ground
		RETURN_TO_HOME_ALT = 25.0,   -- Safe transit altitude
	},

	-- Swarm Performance (Supports up to 800+ drones)
	SWARM = {
		MAX_DRONES = 800,
		BATCH_UPDATE_SIZE = 100,     -- Chunk size for BulkMoveTo
		USE_CLIENT_INTERPOLATION = true,
		SYNC_RATE_HZ = 30,           -- Network replication frequency (Server -> Client)
		SIMULATION_STEP_DT = 1 / 60, -- 60 FPS physics tick
	},

	-- Visual & LED Show Settings
	LIGHT_SHOW = {
		ENABLE_TRAILS = true,
		TRAIL_LIFETIME = 0.8,
		COLOR_PALETTES = {
			CYAN_PINK = { Color3.fromRGB(0, 255, 255), Color3.fromRGB(255, 0, 128) },
			GOLD_WHITE = { Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 255, 255) },
			RAINBOW = {
				Color3.fromRGB(255, 0, 0),
				Color3.fromRGB(255, 127, 0),
				Color3.fromRGB(255, 255, 0),
				Color3.fromRGB(0, 255, 0),
				Color3.fromRGB(0, 0, 255),
				Color3.fromRGB(75, 0, 130),
				Color3.fromRGB(148, 0, 211),
			},
			TURKISH_FLAG = { Color3.fromRGB(230, 0, 0), Color3.fromRGB(255, 255, 255) },
		},
	},

	-- Export Formats
	EXPORT = {
		VERSION = "1.0",
		DEFAULT_FORMAT = "JSON", -- Options: "JSON", "CSV", "MAVLINK_MISSION"
	}
}

return table.freeze(DroneConfig)
