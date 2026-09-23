--!strict
-- DroneConfig.luau
-- Global configuration parameters for Drone Flight & Swarm Show Simulation

-- Simulation sites. ACTIVE_SITE picks the launch pad (HOME) the drone starts from.
-- Real-world sites are built from OpenStreetMap (tools/osm2roblox.py -> scripts/maps/) and carry the
-- launch pad's GPS position so exported flights can be placed exactly where they were simulated.
local SITES = {
	-- Fictional Bosphorus demo map (scripts/BuildIstanbulMap.luau) — NOT to scale
	ISTANBUL_DEMO = { HOME = Vector3.new(-220, 4.0, 0), HOME_GEO = nil :: { number }?, WEATHER_GEO = { 41.045, 29.034 } },
	-- Real Bahçelievler around the state hospital, map origin (6000, 0, 0); pad from osm2roblox
	-- HOME_GEO = { lat, lon, ground m AMSL } of the pad (SRTM terrain; 0.7 stud = pad + landing gear)
	BAHCELIEVLER = {
		HOME = Vector3.new(6000 - 273.7, 33.2 + 0.7, -115.8),
		HOME_GEO = { 41.0065415, 28.8434376, 34.8 },
		WEATHER_GEO = { 41.0065415, 28.8434376 },
	},
}
local ACTIVE_SITE = "BAHCELIEVLER"

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

	-- Real-drone bridge: every exported flight is expressed relative to this launch point.
	-- On the field it is replaced by the drone's real GPS home (tools/sim2mission.py --home).
	ACTIVE_SITE = ACTIVE_SITE,
	HOME = {
		SIM_POSITION = SITES[ACTIVE_SITE].HOME, -- launch pad (drone resting height)
		GEO = SITES[ACTIVE_SITE].HOME_GEO, -- { lat, lon, AMSL } of the pad for real-world sites, else nil
	},

	-- Live weather (server WeatherService). Needs "Allow HTTP Requests" in Game Settings > Security.
	WEATHER = {
		MODE = "LIVE", -- "LIVE" or "MANUAL"
		GEO = SITES[ACTIVE_SITE].WEATHER_GEO,
		-- Observed wind first: METAR stations nearest to the site (LTBA Atatürk ~3 km from Bahçelievler)
		METAR_STATIONS = { "LTBA", "LTFJ", "LTFM" },
		METAR_MAX_AGE_MIN = 90,
		REFRESH_SEC = 600, -- MET Norway asks clients not to poll more often than their data updates
		MANUAL = { SPEED_MS = 0, FROM_DEG = 0, GUST_MS = 0 },
		-- Wind profile: 10 m reports (open airport / model grid, z0 ~0.03 m) carried to a 100 m blending
		-- height, then down again over the city with urban roughness.
		SOURCE_Z0_M = 0.03,
		SITE_Z0_M = 1.0,
		BLEND_HEIGHT_M = 100,
		TURBULENCE_INTENSITY = 0.25, -- sigma / mean over a city when no gust is reported
		EDDY_LENGTH_M = 40,
		STRONG_WIND_MS = 10, -- panel warning threshold at flight altitude
	},

	-- Airframe & power system: "TEI F450 Otonom Devriye İHA" (rasperiypi/ docs): F450 Quad-X,
	-- 4x MT2808 (KV unknown), 10" 3-blade props, Skywalker 30 A PWM ESCs, 4S 5000 mAh,
	-- Power Module V1.0, Pixhawk 2.4.8 + Raspberry Pi 5 + IMX500 camera + Storm32 gimbal.
	-- Values marked "est." are estimates until measured. Motor numbering follows ArduPilot Quad-X.
	AIRFRAME = {
		MASS_KG = 2.1, -- all-up weight estimate from the build guide
		MAX_THRUST_PER_MOTOR_N = 9.27, -- guide: thrust/weight ~1.8 -> hover ~55 % (est.)
		MAX_MOTOR_RPM = 9500, -- est.: MT2808 KV unknown
		MAX_MOTOR_CURRENT_A = 15.0, -- est.: gives ~26 A hover, ~9 min usable flight
		AVIONICS_CURRENT_A = 1.5, -- Pixhawk + Pi 5 + IMX500 + GPS + gimbal at 14.8 V (est.)
		ESC_TELEMETRY = false, -- Skywalker PWM ESCs report nothing; per-motor values are estimates
		ARM_LENGTH_M = 0.225, -- F450: 450 mm motor-to-motor diagonal
		INERTIA_KGM2 = 0.035,
		DRAG_COEFF = 0.04, -- m/s² per (m/s)²: ~22° lean at 10 m/s (frame + gimbal, est.)
		MOT_SPIN_ARM = 0.10, -- ArduPilot default idle output when armed
		AMBIENT_TEMP_C = 22,
		BATTERY_CELLS = 4,
		BATTERY_CAPACITY_MAH = 5000,
		BATTERY_RESISTANCE_OHM = 0.035, -- whole pack
	},

	-- Autopilot behaviour, mirroring ArduPilot Copter 4.6 defaults (converted to meters).
	-- Copter 4.7 renames them to SI units (e.g. WPNAV_SPEED -> WP_SPD, RTL_ALT -> RTL_ALT_M).
	AUTOPILOT = {
		WPNAV_SPEED = 6.0,     -- m/s cruise (ArduPilot default 10; tools/make_params.py recommends 6 for the F450)
		WPNAV_SPEED_UP = 2.5,  -- m/s
		WPNAV_SPEED_DN = 1.5,  -- m/s
		WPNAV_ACCEL = 2.5,     -- m/s²
		WPNAV_RADIUS = 2.0,    -- m, waypoint reached
		TAKEOFF_ALT = 5.0,     -- m, same default as tools/sim2mission.py --takeoff-alt
		RTL_ALT = 30.0,        -- m above home (default 15 would hit 21 m buildings around the Bahçelievler pad)
		RTL_LOIT_TIME = 5.0,   -- s hover over home before landing
		LAND_SPEED = 0.5,      -- m/s final descent
		LAND_SPEED_HIGH = 1.5, -- m/s above LAND_ALT_LOW (0 in ArduPilot = WPNAV_SPEED_DN)
		LAND_ALT_LOW = 10.0,   -- m
		YAW_RATE = 90.0,       -- deg/s
		ANGLE_MAX = 30.0,      -- deg lean limit (ArduPilot default)
		DISARM_DELAY = 10.0,   -- s on the ground before motors stop (ArduPilot default)
	},

	-- Failsafes (ArduPilot parameter names). Voltages are the usual 3.5 / 3.3 V-per-cell setup,
	-- not ArduPilot defaults (BATT_LOW_VOLT defaults to 10.5 V) — set them on the real drone too.
	FAILSAFE = {
		BATT_LOW_VOLT = 14.0,  -- 3.5 V/cell -> RTL
		BATT_CRT_VOLT = 13.2,  -- 3.3 V/cell -> LAND
		BATT_LOW_TIMER = 10.0, -- s below the threshold before acting
		FENCE_RADIUS = 300.0,  -- m from home -> RTL
		FENCE_ALT_MAX = 100.0, -- m above home -> RTL
		CRASH_SPEED = 3.0,     -- m/s: touching anything faster than this is a crash
	},

	-- Local MAVLink bridge (tools/mavlink_bridge.py): the sim appears to ground stations as ArduCopter.
	-- Only reachable from Studio (localhost); needs "Allow HTTP Requests".
	BRIDGE = {
		ENABLED = true,
		URL = "http://127.0.0.1:34874/sim/state",
		RATE_HZ = 5, -- Roblox allows ~500 HTTP requests/min per server
		RETRY_SEC = 3, -- back-off while the bridge is not running
	},

	-- Flight Blackbox Recorder (manual flights -> real drone missions)
	RECORDER = {
		SAMPLE_RATE_HZ = 10,
		MAX_DURATION_SEC = 900, -- 15 min; longer copies get too big for the clipboard modal
	},

	-- Export Formats
	EXPORT = {
		VERSION = "1.0",
		DEFAULT_FORMAT = "JSON", -- Options: "JSON", "CSV", "MAVLINK_MISSION"
	}
}

return table.freeze(DroneConfig)
