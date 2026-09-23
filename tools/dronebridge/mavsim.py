"""ArduCopter emulator: makes the Roblox simulation look like a real ArduCopter 4.7 flight controller.

The simulator posts its state (JSON, ENU meters relative to the launch pad); this module turns it
into the MAVLink stream a ground station expects (HEARTBEAT, ATTITUDE, GLOBAL_POSITION_INT, ...),
and turns ground-station messages (arm, mode, takeoff, velocity, mission upload/download,
motor test, parameters) into simple simulator commands. Transport-agnostic: `mav` is any
pymavlink MAVLink object, so tests can run it in memory.

Fidelity notes:
- ESC_TELEMETRY is only sent with esc_telemetry=True (the TEI drone's PWM ESCs cannot report it).
- VIBRATION / EKF_STATUS_REPORT are not sent: the simulator does not model them (no fake values).
- Parameters use ArduCopter 4.6 names (4.7 renamed several to SI units, e.g. WPNAV_SPEED -> WP_SPD).
"""

import math
import time

from .geo import enu_to_geodetic, geodetic_to_enu

# ArduCopter flight modes (custom_mode numbers)
COPTER_MODES = {"STABILIZE": 0, "ACRO": 1, "ALT_HOLD": 2, "AUTO": 3, "GUIDED": 4, "LOITER": 5, "RTL": 6,
                "CIRCLE": 7, "LAND": 9, "DRIFT": 11, "SPORT": 13, "POSHOLD": 16, "BRAKE": 17, "SMART_RTL": 21}
MODE_NAMES = {v: k for k, v in COPTER_MODES.items()}
# Modes the simulator can fly, per requested ArduCopter mode
SIM_MODE_FOR = {"STABILIZE": "MANUAL", "ALT_HOLD": "MANUAL", "ACRO": "MANUAL", "SPORT": "MANUAL", "DRIFT": "MANUAL",
                "LOITER": "HOLD", "POSHOLD": "HOLD", "BRAKE": "HOLD", "GUIDED": "GUIDED",
                "AUTO": "AUTO", "RTL": "RTL", "SMART_RTL": "RTL", "LAND": "LAND"}
# ArduPilot motor-test order (A, B, C, D clockwise from front-right) -> Quad-X motor number
MOTOR_TEST_ORDER = {1: 1, 2: 4, 3: 2, 4: 3}
FIRMWARE_VERSION = (4 << 24) | (7 << 16) | (0 << 8) | 255  # 4.7.0 official

DEFAULT_PARAMS = {
    "SYSID_THISMAV": 1, "FRAME_CLASS": 1, "FRAME_TYPE": 1,
    "WPNAV_SPEED": 1000, "WPNAV_SPEED_UP": 250, "WPNAV_SPEED_DN": 150, "WPNAV_ACCEL": 250, "WPNAV_RADIUS": 200,
    "RTL_ALT": 1500, "RTL_LOIT_TIME": 5000, "LAND_SPEED": 50, "LAND_SPEED_HIGH": 150, "ANGLE_MAX": 3500,
    "BATT_MONITOR": 4, "BATT_CAPACITY": 5000, "BATT_LOW_VOLT": 14.0, "BATT_CRT_VOLT": 13.2,
    "BATT_FS_LOW_ACT": 2, "BATT_FS_CRT_ACT": 1, "BATT_LOW_TIMER": 10,
    "FENCE_ENABLE": 1, "FENCE_TYPE": 3, "FENCE_RADIUS": 300, "FENCE_ALT_MAX": 100, "FENCE_ACTION": 1,
    "FS_GCS_ENABLE": 1, "FS_GCS_TIMEOUT": 5, "DISARM_DELAY": 10, "MOT_SPIN_ARM": 0.10,
}
# Parameters the simulator applies live (name -> simulator setting, unit conversion)
SIM_PARAMS = {"WPNAV_SPEED": ("cruise_speed", 0.01), "RTL_ALT": ("rtl_alt", 0.01), "FENCE_RADIUS": ("fence_radius", 1)}

ASCII_TR = str.maketrans("çğıöşüÇĞİÖŞÜâ—→", "cgiosuCGIOSUa->")

SEVERITY = {"EMERGENCY": 0, "CRITICAL": 2, "ERROR": 3, "WARNING": 4, "NOTICE": 5, "INFO": 6}

# MAVLink constants used here (numbers are stable across dialects)
MAV_TYPE_QUADROTOR, MAV_TYPE_GCS = 2, 6
MAV_AUTOPILOT_ARDUPILOTMEGA = 3
MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, MAV_MODE_FLAG_SAFETY_ARMED, MAV_MODE_FLAG_STABILIZE_ENABLED = 1, 128, 16
MAV_MODE_FLAG_GUIDED_ENABLED = 8
MAV_STATE_STANDBY, MAV_STATE_ACTIVE, MAV_STATE_CRITICAL, MAV_STATE_EMERGENCY = 3, 4, 5, 6
MAV_RESULT_ACCEPTED, MAV_RESULT_TEMPORARILY_REJECTED, MAV_RESULT_DENIED, MAV_RESULT_UNSUPPORTED, MAV_RESULT_FAILED = 0, 1, 2, 3, 4
MAV_MISSION_ACCEPTED, MAV_MISSION_ERROR, MAV_MISSION_UNSUPPORTED = 0, 1, 3
MAV_FRAME_GLOBAL, MAV_FRAME_LOCAL_NED, MAV_FRAME_MISSION, MAV_FRAME_GLOBAL_RELATIVE_ALT = 0, 1, 2, 3
MAV_FRAME_GLOBAL_INT, MAV_FRAME_GLOBAL_RELATIVE_ALT_INT = 5, 6
MAV_FRAME_BODY_NED, MAV_FRAME_BODY_OFFSET_NED = 8, 9
MAV_PARAM_TYPE_REAL32 = 9
CMD = {"NAV_WAYPOINT": 16, "NAV_LOITER_TIME": 19, "NAV_RETURN_TO_LAUNCH": 20, "NAV_LAND": 21, "NAV_TAKEOFF": 22,
       "DO_SET_MODE": 176, "DO_CHANGE_SPEED": 178, "DO_REPOSITION": 192, "DO_MOTOR_TEST": 209,
       "MISSION_START": 300, "COMPONENT_ARM_DISARM": 400, "REQUEST_AUTOPILOT_CAPABILITIES": 520,
       "REQUEST_MESSAGE": 512, "SET_MESSAGE_INTERVAL": 511, "PREFLIGHT_REBOOT_SHUTDOWN": 246}
FORCE_ARM_MAGIC = 21196
CAPABILITIES = 1 | 4 | 8 | 64 | 128 | 256 | 1024 | 8192  # MISSION_FLOAT/PARAM_FLOAT/MISSION_INT/COMMAND_INT/SET_POS_LOCAL/…/MAVLINK2
LANDED_ON_GROUND, LANDED_IN_AIR, LANDED_TAKEOFF, LANDED_LANDING = 1, 2, 3, 4


class ArduCopterEmulator:
    def __init__(self, mav, home_lat, home_lon, home_amsl=0.0, esc_telemetry=False, clock=time.monotonic):
        self.mav = mav
        self.home = (home_lat, home_lon, home_amsl)  # the simulator's launch pad
        self.esc_telemetry = esc_telemetry
        self.clock = clock
        self.boot = clock()
        self.state = None  # latest simulator state (dict)
        self.commands = []  # pending simulator commands
        self.requested_mode = "ALT_HOLD"  # what the GCS asked for (sim MANUAL covers several)
        self.params = dict(DEFAULT_PARAMS)
        self.param_names = sorted(self.params)
        self.mission = []  # stored MISSION_ITEM_INT dicts, seq 0 = home
        self.upload = None  # {"count", "items", "last", "type"}
        self.download_active = False
        self.gcs = None  # (system, component) of the last GCS heard
        self.gcs_last_heartbeat = None
        self.gcs_failsafe = False
        self.last_mode = None
        self.last_event = ""
        self.tick = 0
        self.seq_map = []  # simulator waypoint index -> mission seq

    # ------------------------------------------------------------------ helpers
    def ms(self):
        return int((self.clock() - self.boot) * 1000) & 0xFFFFFFFF

    def text(self, message, severity="INFO"):
        # ArduPilot sends ASCII; GCSs (pymavlink, TEI) garble UTF-8, so transliterate Turkish letters
        ascii_text = message.translate(ASCII_TR).encode("ascii", "replace")[:50]
        self.mav.statustext_send(SEVERITY[severity], ascii_text)

    def enu_to_global(self, e, n, u):
        lat, lon, _ = enu_to_geodetic(e, n, 0.0, self.home[0], self.home[1])
        return lat, lon, self.home[2] + u

    def global_to_enu(self, lat, lon):
        e, n, _ = geodetic_to_enu(lat, lon, 0.0, self.home[0], self.home[1])
        return e, n

    def push(self, command, **data):
        self.commands.append({"type": command, **data})

    def pop_commands(self):
        out, self.commands = self.commands, []
        return out

    # ----------------------------------------------------------- sim -> MAVLink
    def update_state(self, state):
        self.state = state
        mode = state.get("mode")
        if mode != self.last_mode:
            if self.last_mode is not None:
                self.text(f"Mode {self.mavlink_mode_name()}")
            self.last_mode = mode
        event = state.get("event") or ""
        if event and event != self.last_event:
            self.last_event = event
            upper = event.upper()
            level = "CRITICAL" if any(k in upper for k in ("KRİTİK", "ÇARPIŞMA", "ARIZA", "ZEMİN")) else \
                "WARNING" if any(k in upper for k in ("BATARYA", "GEOFENCE", "DÜŞÜK")) else "INFO"
            self.text(event[:50], level)
        if state.get("crash") and state.get("crash") != getattr(self, "_crash_sent", None):
            self._crash_sent = state["crash"]
            self.text(("Crash: " + state["crash"])[:50], "EMERGENCY")
        self.check_gcs_failsafe()

    def mavlink_mode_name(self):
        s = self.state or {}
        mode = s.get("mode", "MANUAL")
        if mode == "MANUAL":
            return self.requested_mode if SIM_MODE_FOR.get(self.requested_mode) == "MANUAL" else "ALT_HOLD"
        if mode == "GUIDED":
            return self.requested_mode if SIM_MODE_FOR.get(self.requested_mode) in ("HOLD", "GUIDED") else "GUIDED"
        if mode == "CRASHED":
            return "LAND"
        return mode if mode in COPTER_MODES else "ALT_HOLD"

    def send_stream(self):
        """Call at 10 Hz: sends each message at a realistic rate."""
        s = self.state
        if s is None:
            return
        self.tick += 1
        t = self.tick
        self.send_attitude(s)
        if t % 2 == 0:
            self.send_position(s)
            self.send_servo(s)
        if t % 5 == 0:
            self.send_sys_status(s)
            self.send_gps(s)
            if self.esc_telemetry:
                self.send_esc(s)
        if t % 10 == 0:
            self.send_heartbeat(s)
            self.send_battery(s)
            self.send_home(s)
            self.mav.extended_sys_state_send(0, self.landed_state(s))
            self.mav.mission_current_send(self.current_seq(s))
            wind = s.get("wind") or [0, 0, 0]
            speed = math.hypot(wind[0], wind[1])
            # WIND.direction: where the wind comes FROM, degrees
            self.mav.wind_send((math.degrees(math.atan2(-wind[0], -wind[1])) % 360), speed, wind[2])
        self.check_upload_timeout()

    def send_heartbeat(self, s):
        armed = s.get("armed", False)
        base = MAV_MODE_FLAG_CUSTOM_MODE_ENABLED | MAV_MODE_FLAG_STABILIZE_ENABLED
        if armed:
            base |= MAV_MODE_FLAG_SAFETY_ARMED
        if s.get("mode") in ("GUIDED", "AUTO", "RTL", "LAND"):
            base |= MAV_MODE_FLAG_GUIDED_ENABLED
        status = MAV_STATE_ACTIVE if armed else MAV_STATE_STANDBY
        if s.get("mode") == "CRASHED":
            status = MAV_STATE_EMERGENCY
        elif self.gcs_failsafe or "BATARYA" in (s.get("event") or "").upper():
            status = MAV_STATE_CRITICAL if armed else status
        self.mav.heartbeat_send(MAV_TYPE_QUADROTOR, MAV_AUTOPILOT_ARDUPILOTMEGA, base,
                                COPTER_MODES[self.mavlink_mode_name()], status)

    def send_attitude(self, s):
        heading = math.radians(s.get("heading", 0.0))
        yaw = (heading + math.pi) % (2 * math.pi) - math.pi
        self.mav.attitude_send(self.ms(), math.radians(s.get("roll", 0.0)), math.radians(s.get("pitch", 0.0)),
                               yaw, 0.0, 0.0, math.radians(s.get("yaw_rate", 0.0)))

    def send_position(self, s):
        lat, lon, amsl = self.enu_to_global(s["e"], s["n"], s["u"])
        rel = s["u"] - s.get("home_u", 0.0)
        ve, vn, vu = s.get("ve", 0.0), s.get("vn", 0.0), s.get("vu", 0.0)
        hdg = int(s.get("heading", 0.0) * 100) % 36000
        self.mav.global_position_int_send(self.ms(), int(lat * 1e7), int(lon * 1e7), int(amsl * 1000), int(rel * 1000),
                                          int(vn * 100), int(ve * 100), int(-vu * 100), hdg)
        wind = s.get("wind") or [0, 0, 0]
        airspeed = math.hypot(ve - wind[0], vn - wind[1])
        motors = s.get("motors") or [0, 0, 0, 0]
        throttle = int(round(100 * sum(motors) / max(len(motors), 1)))
        self.mav.vfr_hud_send(airspeed, math.hypot(ve, vn), int(s.get("heading", 0.0)) % 360, throttle, amsl, vu)

    def send_servo(self, s):
        motors = (s.get("motors") or []) + [0.0] * 8
        # PWM: disarmed motors sit at MOT_PWM_MIN (1000); 0 means "output not configured"
        pwm = [1000 + int(round(1000 * max(0.0, min(1.0, m)))) for m in motors[:4]] + [0, 0, 0, 0]
        self.mav.servo_output_raw_send(self.ms() * 1000 & 0xFFFFFFFF, 0, *pwm)

    def send_sys_status(self, s):
        sensors = 0x1 | 0x2 | 0x4 | 0x8 | 0x20 | 0x400 | 0x8000 | 0x200000  # gyro/acc/mag/baro/gps/.../battery/prearm
        self.mav.sys_status_send(sensors, sensors, sensors, 150, int(s.get("voltage", 0) * 1000),
                                 int(s.get("current", 0) * 100), int(s.get("remaining", 0)), 0, 0, 0, 0, 0, 0)

    def send_gps(self, s):
        lat, lon, amsl = self.enu_to_global(s["e"], s["n"], s["u"])
        ve, vn = s.get("ve", 0.0), s.get("vn", 0.0)
        cog = int((math.degrees(math.atan2(ve, vn)) % 360) * 100)
        self.mav.gps_raw_int_send(self.ms() * 1000, 3, int(lat * 1e7), int(lon * 1e7), int(amsl * 1000),
                                  90, 140, int(math.hypot(ve, vn) * 100), cog, 14)

    def send_battery(self, s):
        cell_mv = int(s.get("cell_v", s.get("voltage", 0) / 4) * 1000)
        voltages = [cell_mv] * 4 + [65535] * 6
        self.mav.battery_status_send(0, 1, 1, 32767, voltages, int(s.get("current", 0) * 100),
                                     int(s.get("used_mah", 0)), -1, int(s.get("remaining", 0)))

    def send_esc(self, s):
        temps = [int(t) for t in (s.get("temps") or [0] * 4)][:4]
        volts = [int(s.get("voltage", 0) * 100)] * 4
        currents = [int(c * 100) for c in (s.get("motor_currents") or [0] * 4)][:4]
        rpm = [int(r) for r in (s.get("rpm") or [0] * 4)][:4]
        self.mav.esc_telemetry_1_to_4_send(temps, volts, currents, [0] * 4, rpm, [0] * 4)

    def send_home(self, s):
        lat, lon, amsl = self.enu_to_global(s.get("home_e", 0.0), s.get("home_n", 0.0), s.get("home_u", 0.0))
        self.mav.home_position_send(int(lat * 1e7), int(lon * 1e7), int(amsl * 1000), 0, 0, 0, [1, 0, 0, 0], 0, 0, 0)

    def landed_state(self, s):
        if s.get("on_ground"):
            return LANDED_ON_GROUND
        mode = s.get("mode")
        if mode == "LAND" or (mode == "RTL" and "iniş" in (s.get("status") or "")):
            return LANDED_LANDING
        return LANDED_IN_AIR

    def current_seq(self, s):
        idx = s.get("mission_index", 0)
        if s.get("mode") != "AUTO" or not self.seq_map:
            return 0
        return self.seq_map[min(max(idx, 0), len(self.seq_map) - 1)]

    # ----------------------------------------------------------- GCS failsafe
    def check_gcs_failsafe(self):
        s = self.state or {}
        if not self.gcs_last_heartbeat or not self.params.get("FS_GCS_ENABLE"):
            return
        lost = self.clock() - self.gcs_last_heartbeat > self.params["FS_GCS_TIMEOUT"]
        if lost and not self.gcs_failsafe and s.get("armed") and s.get("mode") not in ("RTL", "LAND", "CRASHED"):
            self.gcs_failsafe = True
            self.text("GCS Failsafe: yer istasyonu koptu, RTL", "CRITICAL")
            self.push("mode", mode="RTL", reason="GCS FAILSAFE (yer istasyonu bağlantısı koptu)")
        elif not lost and self.gcs_failsafe:
            self.gcs_failsafe = False
            self.text("GCS Failsafe cleared", "INFO")

    # ----------------------------------------------------------- MAVLink -> sim
    def handle(self, msg):
        kind = msg.get_type()
        if kind == "BAD_DATA":
            return
        handler = getattr(self, "on_" + kind, None)
        if kind == "HEARTBEAT" and msg.type == MAV_TYPE_GCS:
            self.gcs = (msg.get_srcSystem(), msg.get_srcComponent())
            self.gcs_last_heartbeat = self.clock()
        if handler:
            handler(msg)

    def target(self, msg):
        return msg.get_srcSystem(), msg.get_srcComponent()

    def ack(self, command, result):
        self.mav.command_ack_send(command, result)

    def set_mode(self, name, reason=None):
        sim = SIM_MODE_FOR.get(name)
        if not sim:
            return False
        s = self.state or {}
        if sim == "AUTO":
            points = self.sim_mission()
            if not points:
                self.text("Mission yok — önce görev yükleyin", "WARNING")
                return False
            self.push("mission", **points)
        elif sim in ("RTL", "LAND") and not s.get("armed"):
            self.requested_mode = name
            return True  # accepted while disarmed, takes effect in the air
        else:
            self.push("mode", mode=sim, reason=reason or f"GCS: {name}")
        self.requested_mode = name
        return True

    def on_SET_MODE(self, msg):
        name = MODE_NAMES.get(msg.custom_mode)
        if not name or not self.set_mode(name):
            self.text(f"Mode change failed: {name or msg.custom_mode}", "WARNING")

    def on_COMMAND_LONG(self, msg):
        self.run_command(msg.command, [msg.param1, msg.param2, msg.param3, msg.param4, msg.param5, msg.param6, msg.param7])

    def on_COMMAND_INT(self, msg):
        self.run_command(msg.command, [msg.param1, msg.param2, msg.param3, msg.param4, msg.x / 1e7, msg.y / 1e7, msg.z])

    def run_command(self, command, p):
        s = self.state or {}
        result = MAV_RESULT_ACCEPTED
        if command == CMD["COMPONENT_ARM_DISARM"]:
            if p[0] >= 0.5:
                if s.get("mode") == "CRASHED":
                    self.text("PreArm: araç kaza sonrası, önce sıfırlayın (X)", "CRITICAL")
                    result = MAV_RESULT_FAILED
                elif s.get("armed"):
                    pass
                else:
                    self.push("arm")
            else:
                if s.get("armed") and not s.get("on_ground") and int(p[1]) != FORCE_ARM_MAGIC:
                    self.text("Disarm reddedildi: havada", "WARNING")
                    result = MAV_RESULT_DENIED
                else:
                    self.push("disarm")
        elif command == CMD["NAV_TAKEOFF"]:
            if not s.get("armed"):
                result = MAV_RESULT_DENIED
                self.text("Takeoff: önce ARM", "WARNING")
            elif SIM_MODE_FOR.get(self.requested_mode) != "GUIDED" and s.get("mode") != "GUIDED":
                result = MAV_RESULT_DENIED
                self.text("Takeoff sadece GUIDED modda", "WARNING")
            else:
                self.push("takeoff", alt=max(1.0, float(p[6])))
        elif command == CMD["DO_SET_MODE"]:
            name = MODE_NAMES.get(int(p[1]))
            result = MAV_RESULT_ACCEPTED if name and self.set_mode(name) else MAV_RESULT_FAILED
        elif command == CMD["MISSION_START"]:
            result = MAV_RESULT_ACCEPTED if self.set_mode("AUTO") else MAV_RESULT_FAILED
        elif command == CMD["NAV_RETURN_TO_LAUNCH"]:
            self.set_mode("RTL")
        elif command == CMD["NAV_LAND"]:
            self.set_mode("LAND")
        elif command == CMD["DO_REPOSITION"]:
            lat, lon, alt = p[4], p[5], p[6]
            if not s.get("armed"):
                result = MAV_RESULT_DENIED
            else:
                e, n = self.global_to_enu(lat, lon)
                self.push("goto", e=e, n=n, u=s.get("home_u", 0.0) + alt if alt else s.get("u", 0.0))
                self.requested_mode = "GUIDED"
        elif command == CMD["DO_MOTOR_TEST"]:
            if s.get("armed"):
                result = MAV_RESULT_DENIED
                self.text("Motor test: önce DISARM", "WARNING")
            else:
                motor = MOTOR_TEST_ORDER.get(int(p[0]))
                count = max(1, int(p[4]))
                for k in range(count):
                    m = MOTOR_TEST_ORDER.get(int(p[0]) + k)
                    if m:
                        self.push("motortest", motor=m, pct=float(p[2]) if int(p[1]) == 0 else 15.0,
                                  seconds=min(float(p[3]) or 2.0, 10.0), delay=k * (float(p[3]) or 2.0))
                if motor is None:
                    result = MAV_RESULT_DENIED
        elif command in (CMD["REQUEST_AUTOPILOT_CAPABILITIES"],) or (command == CMD["REQUEST_MESSAGE"] and int(p[0]) == 148):
            self.send_autopilot_version()
        elif command == CMD["REQUEST_MESSAGE"]:
            if int(p[0]) == 242:
                self.send_home(s or {"home_e": 0, "home_n": 0, "home_u": 0})
        elif command == CMD["SET_MESSAGE_INTERVAL"]:
            pass  # fixed-rate stream; accept so the GCS stops asking
        elif command == CMD["PREFLIGHT_REBOOT_SHUTDOWN"]:
            result = MAV_RESULT_DENIED
        else:
            result = MAV_RESULT_UNSUPPORTED
        self.ack(command, result)

    def send_autopilot_version(self):
        self.mav.autopilot_version_send(CAPABILITIES, FIRMWARE_VERSION, 0, 0, 0, b"sim\0\0\0\0\0", [0] * 8, [0] * 8,
                                        0x1209, 0x5741, 0)

    def on_SET_POSITION_TARGET_LOCAL_NED(self, msg):
        s = self.state or {}
        if not s.get("armed"):
            return
        mask = msg.type_mask
        velocity_ignored = mask & 0b111000 == 0b111000
        yaw_rate_ignored = bool(mask & 0b100000000000)
        if velocity_ignored:
            return
        vx, vy, vz = msg.vx, msg.vy, msg.vz  # NED or body forward/right/down
        if msg.coordinate_frame in (MAV_FRAME_BODY_NED, MAV_FRAME_BODY_OFFSET_NED):
            h = math.radians(s.get("heading", 0.0))
            vn = vx * math.cos(h) - vy * math.sin(h)
            ve = vx * math.sin(h) + vy * math.cos(h)
        else:
            vn, ve = vx, vy
        self.push("velocity", ve=ve, vn=vn, vu=-vz, yaw_rate=0.0 if yaw_rate_ignored else math.degrees(msg.yaw_rate))

    def on_REQUEST_DATA_STREAM(self, msg):
        pass  # the stream is always on at fixed rates

    # ----------------------------------------------------------- parameters
    def on_PARAM_REQUEST_LIST(self, msg):
        for i, name in enumerate(self.param_names):
            self.send_param(name, i)

    def on_PARAM_REQUEST_READ(self, msg):
        name = msg.param_id if isinstance(msg.param_id, str) else msg.param_id.decode()
        name = name.rstrip("\0")
        if msg.param_index >= 0 and msg.param_index < len(self.param_names) and not name:
            name = self.param_names[msg.param_index]
        if name in self.params:
            self.send_param(name, self.param_names.index(name))

    def on_PARAM_SET(self, msg):
        name = (msg.param_id if isinstance(msg.param_id, str) else msg.param_id.decode()).rstrip("\0")
        if name not in self.params:
            return
        self.params[name] = msg.param_value
        if name in SIM_PARAMS:
            setting, scale = SIM_PARAMS[name]
            self.push("param", name=setting, value=msg.param_value * scale)
        self.send_param(name, self.param_names.index(name))

    def send_param(self, name, index):
        self.mav.param_value_send(name.encode(), float(self.params[name]), MAV_PARAM_TYPE_REAL32,
                                  len(self.param_names), index)

    # ----------------------------------------------------------- missions
    def on_MISSION_COUNT(self, msg):
        mission_type = getattr(msg, "mission_type", 0)
        self.upload = {"count": msg.count, "items": [], "last": self.clock(), "type": mission_type,
                       "target": self.target(msg)}
        if msg.count == 0:
            self.finish_upload()
        else:
            self.mav.mission_request_int_send(*self.upload["target"], 0, mission_type)

    def on_MISSION_ITEM_INT(self, msg):
        self.store_item(msg, int_coords=True)

    def on_MISSION_ITEM(self, msg):
        self.store_item(msg, int_coords=False)

    def store_item(self, msg, int_coords):
        up = self.upload
        if not up or msg.seq != len(up["items"]):
            return
        lat = msg.x / 1e7 if int_coords else msg.x
        lon = msg.y / 1e7 if int_coords else msg.y
        up["items"].append({"seq": msg.seq, "frame": msg.frame, "command": msg.command, "p1": msg.param1,
                            "p2": msg.param2, "p3": msg.param3, "p4": msg.param4, "lat": lat, "lon": lon, "alt": msg.z,
                            "autocontinue": msg.autocontinue})
        up["last"] = self.clock()
        if len(up["items"]) < up["count"]:
            self.mav.mission_request_int_send(*up["target"], len(up["items"]), up["type"])
        else:
            self.finish_upload()

    def finish_upload(self):
        up, self.upload = self.upload, None
        if up["type"] == 0:
            self.mission = up["items"]
            self.text(f"Mission: {len(self.mission)} öge alındı")
        self.mav.mission_ack_send(*up["target"], MAV_MISSION_ACCEPTED, up["type"])

    def check_upload_timeout(self):
        if self.upload and self.clock() - self.upload["last"] > 5:
            self.text("Mission upload zaman aşımı", "WARNING")
            self.mav.mission_ack_send(*self.upload["target"], MAV_MISSION_ERROR, self.upload["type"])
            self.upload = None

    def on_MISSION_REQUEST_LIST(self, msg):
        mission_type = getattr(msg, "mission_type", 0)
        count = max(len(self.mission), 1) if mission_type == 0 else 0
        self.mav.mission_count_send(*self.target(msg), count, mission_type)

    def on_MISSION_REQUEST_INT(self, msg):
        self.send_item(msg, int_coords=True)

    def on_MISSION_REQUEST(self, msg):
        self.send_item(msg, int_coords=True)

    def send_item(self, msg, int_coords):
        items = self.mission or [self.home_item()]
        if not 0 <= msg.seq < len(items):
            return
        it = items[msg.seq]
        self.mav.mission_item_int_send(*self.target(msg), it["seq"], it["frame"], it["command"], 0,
                                       it.get("autocontinue", 1), it["p1"], it["p2"], it["p3"], it["p4"],
                                       int(it["lat"] * 1e7), int(it["lon"] * 1e7), it["alt"], 0)

    def home_item(self):
        return {"seq": 0, "frame": MAV_FRAME_GLOBAL, "command": CMD["NAV_WAYPOINT"], "p1": 0, "p2": 0, "p3": 0,
                "p4": 0, "lat": self.home[0], "lon": self.home[1], "alt": self.home[2]}

    def on_MISSION_CLEAR_ALL(self, msg):
        if getattr(msg, "mission_type", 0) == 0:
            self.mission = []
        self.mav.mission_ack_send(*self.target(msg), MAV_MISSION_ACCEPTED, getattr(msg, "mission_type", 0))

    def on_MISSION_SET_CURRENT(self, msg):
        pass

    def sim_mission(self):
        """Stored MAVLink mission -> simulator mission (ENU meters relative to the pad)."""
        home_u = (self.state or {}).get("home_u", 0.0)
        points, seq_map = [], [1]
        takeoff_alt, speed, end = None, None, "HOLD"  # ArduCopter holds at the last waypoint by default
        for it in self.mission[1:]:
            cmd, frame = it["command"], it["frame"]
            relative = frame in (MAV_FRAME_GLOBAL_RELATIVE_ALT, MAV_FRAME_GLOBAL_RELATIVE_ALT_INT)
            alt = it["alt"] + home_u if relative else it["alt"] - self.home[2]
            if cmd == CMD["NAV_TAKEOFF"]:
                takeoff_alt = it["alt"] if relative else it["alt"] - self.home[2] - home_u
                seq_map[0] = it["seq"]
            elif cmd in (CMD["NAV_WAYPOINT"], CMD["NAV_LOITER_TIME"]):
                if it["lat"] == 0 and it["lon"] == 0:
                    continue
                e, n = self.global_to_enu(it["lat"], it["lon"])
                points.append({"e": e, "n": n, "u": alt, "hold": float(it["p1"]), "speed": speed})
                seq_map.append(it["seq"])
            elif cmd == CMD["DO_CHANGE_SPEED"] and it["p2"] > 0:
                speed = float(it["p2"])
            elif cmd == CMD["NAV_RETURN_TO_LAUNCH"]:
                end = "RTL"
                break
            elif cmd == CMD["NAV_LAND"]:
                end = "LAND"
                if it["lat"] or it["lon"]:
                    e, n = self.global_to_enu(it["lat"], it["lon"])
                    points.append({"e": e, "n": n, "u": (points[-1]["u"] if points else home_u + 5), "hold": 0,
                                   "speed": speed})
                    seq_map.append(it["seq"])
                break
            else:
                self.text(f"Mission: komut {cmd} simülasyonda atlandı", "NOTICE")
        if not points:
            return None
        self.seq_map = seq_map
        return {"points": points, "takeoff_alt": takeoff_alt, "end": end}
