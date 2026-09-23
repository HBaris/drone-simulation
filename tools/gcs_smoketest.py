"""Scripted ground station that does exactly what TEI-Ground-Control does, for end-to-end tests.

  python tools/gcs_smoketest.py                 # against the simulator bridge (udpin:0.0.0.0:14550)
  python tools/gcs_smoketest.py --steps link    # only listen and print telemetry (safe on a real drone)

Steps: link (heartbeat + telemetry) · arm · takeoff (GUIDED, 15 m) · velocity (forward 3 m/s, like the
WASD keys) · mission (TEI layout: home, takeoff, 2 waypoints with 2 s hold, RTL; then AUTO) · motortest.
Do NOT run the flight steps against a real drone: they arm the motors.
"""

import argparse
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mavlink_bridge  # noqa: E402

mavutil = mavlink_bridge.import_pymavlink()
from dronebridge.geo import enu_to_geodetic  # noqa: E402


class Gcs:
    def __init__(self, url):
        self.m = mavutil.mavlink_connection(url, source_system=255, source_component=190)
        self.last_hb = 0
        self.telemetry = {}

    def pump(self, seconds, want=None):
        """Read for `seconds`, sending our GCS heartbeat at 1 Hz; return the first `want` message."""
        end = time.time() + seconds
        while time.time() < end:
            if time.time() - self.last_hb > 1:
                self.last_hb = time.time()
                self.m.mav.heartbeat_send(mavutil.mavlink.MAV_TYPE_GCS, mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
            msg = self.m.recv_match(blocking=True, timeout=0.2)
            if msg is None:
                continue
            kind = msg.get_type()
            self.telemetry[kind] = msg
            if kind == "STATUSTEXT":
                print(f"   [Pixhawk] {msg.text}")
            if want and kind in want:
                return msg
        return None

    def summary(self):
        t = self.telemetry
        hb, pos, vfr, sysst = t.get("HEARTBEAT"), t.get("GLOBAL_POSITION_INT"), t.get("VFR_HUD"), t.get("SYS_STATUS")
        servo = t.get("SERVO_OUTPUT_RAW")
        mode = mavutil.mode_string_v10(hb) if hb else "?"
        armed = bool(hb.base_mode & 128) if hb else False
        return (f"mode={mode} armed={armed} "
                + (f"lat={pos.lat / 1e7:.6f} lon={pos.lon / 1e7:.6f} rel={pos.relative_alt / 1000:.1f} m " if pos else "")
                + (f"gs={vfr.groundspeed:.1f} m/s hdg={vfr.heading} thr={vfr.throttle}% " if vfr else "")
                + (f"V={sysst.voltage_battery / 1000:.2f} " if sysst else "")
                + (f"PWM={[servo.servo1_raw, servo.servo2_raw, servo.servo3_raw, servo.servo4_raw]}" if servo else ""))

    def command(self, cmd, *params):
        p = list(params) + [0] * (7 - len(params))
        self.m.mav.command_long_send(self.m.target_system, self.m.target_component, cmd, 0, *p)
        ack = self.pump(3, {"COMMAND_ACK"})
        result = ack.result if ack else None
        print(f"   COMMAND {cmd} -> {'ACK ' + str(result) if ack else 'yanıt yok'}")
        return result

    def mode(self, name):
        mapping = self.m.mode_mapping()
        self.m.mav.set_mode_send(self.m.target_system, mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, mapping[name])
        self.pump(2)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default="udpin:0.0.0.0:14550")
    ap.add_argument("--steps", default="link,arm,takeoff,velocity,mission")
    args = ap.parse_args(argv)
    steps = args.steps.split(",")
    ML = mavutil.mavlink
    g = Gcs(args.url)

    print("1) Heartbeat bekleniyor…")
    hb = g.pump(20, {"HEARTBEAT"})
    if not hb:
        print("   Heartbeat yok — köprü ve Studio Play çalışıyor mu?")
        return 1
    g.m.target_system, g.m.target_component = hb.get_srcSystem(), hb.get_srcComponent()
    print(f"   Bağlandı: sistem {hb.get_srcSystem()} bileşen {hb.get_srcComponent()} tip {hb.type} autopilot {hb.autopilot}")
    g.m.mav.request_data_stream_send(g.m.target_system, g.m.target_component, ML.MAV_DATA_STREAM_ALL, 6, 1)
    g.pump(3)
    print("   " + g.summary())
    home = g.telemetry.get("GLOBAL_POSITION_INT")

    if "motortest" in steps:
        print("M) Motor testi: B (arka-sağ) %20, 2 sn")
        g.command(ML.MAV_CMD_DO_MOTOR_TEST, 2, 0, 20, 2, 0)
        g.pump(1)
        print("   " + g.summary())
        g.pump(2)

    if "arm" in steps:
        print("2) GUIDED + ARM")
        g.mode("GUIDED")
        g.command(ML.MAV_CMD_COMPONENT_ARM_DISARM, 1)
        g.pump(2)
        print("   " + g.summary())

    if "takeoff" in steps:
        print("3) Kalkış 15 m")
        g.command(ML.MAV_CMD_NAV_TAKEOFF, 0, 0, 0, 0, 0, 0, 15)
        for _ in range(12):
            g.pump(2)
            print("   " + g.summary())
            pos = g.telemetry.get("GLOBAL_POSITION_INT")
            if pos and pos.relative_alt > 14000:
                break

    if "velocity" in steps:
        print("4) İleri 3 m/s (gövde ekseni, TEI klavye komutu gibi) 6 sn, sonra bırak")
        mask = 0b0000011111000111
        end = time.time() + 6
        while time.time() < end:
            g.m.mav.set_position_target_local_ned_send(0, g.m.target_system, g.m.target_component,
                                                        ML.MAV_FRAME_BODY_NED, mask, 0, 0, 0, 3.0, 0, 0, 0, 0, 0, 0, 0.0)
            g.pump(0.25)
        print("   " + g.summary())
        g.pump(5)
        print("   (komutlar kesildi, 3 sn sonra durup konum tutmalı) " + g.summary())

    if "mission" in steps and home:
        lat0, lon0 = home.lat / 1e7, home.lon / 1e7
        wp1 = enu_to_geodetic(60, 0, 0, lat0, lon0)
        wp2 = enu_to_geodetic(60, 40, 0, lat0, lon0)
        items = [(ML.MAV_FRAME_GLOBAL, ML.MAV_CMD_NAV_WAYPOINT, lat0, lon0, 0.0, 0),
                 (ML.MAV_FRAME_GLOBAL_RELATIVE_ALT, ML.MAV_CMD_NAV_TAKEOFF, 0, 0, 25.0, 0),
                 (ML.MAV_FRAME_GLOBAL_RELATIVE_ALT, ML.MAV_CMD_NAV_WAYPOINT, wp1[0], wp1[1], 30.0, 2.0),
                 (ML.MAV_FRAME_GLOBAL_RELATIVE_ALT, ML.MAV_CMD_NAV_WAYPOINT, wp2[0], wp2[1], 30.0, 2.0),
                 (ML.MAV_FRAME_GLOBAL_RELATIVE_ALT, ML.MAV_CMD_NAV_RETURN_TO_LAUNCH, 0, 0, 0.0, 0)]
        print(f"5) Görev yükleniyor ({len(items)} öge, TEI biçimi)")
        g.m.mav.mission_count_send(g.m.target_system, g.m.target_component, len(items), 0)
        while True:
            msg = g.pump(5, {"MISSION_REQUEST_INT", "MISSION_REQUEST", "MISSION_ACK"})
            if msg is None:
                print("   zaman aşımı")
                break
            if msg.get_type() == "MISSION_ACK":
                print(f"   MISSION_ACK type={msg.type} ({'kabul' if msg.type == 0 else 'RED'})")
                break
            frame, cmd, lat, lon, alt, p1 = items[msg.seq]
            g.m.mav.mission_item_int_send(g.m.target_system, g.m.target_component, msg.seq, frame, cmd,
                                          1 if msg.seq == 1 else 0, 1, p1, 0, 0, 0, int(lat * 1e7), int(lon * 1e7), alt, 0)
        print("   AUTO")
        g.mode("AUTO")
        last_seq = None
        for _ in range(40):
            g.pump(2)
            cur = g.telemetry.get("MISSION_CURRENT")
            if cur and cur.seq != last_seq:
                last_seq = cur.seq
                print(f"   MISSION_CURRENT seq={cur.seq}")
            print("   " + g.summary())
            hb = g.telemetry.get("HEARTBEAT")
            if hb and mavutil.mode_string_v10(hb) == "RTL":
                print("   RTL'e geçti (görev bitti)")
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
