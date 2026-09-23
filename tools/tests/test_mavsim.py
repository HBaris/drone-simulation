"""ArduCopter emulator tests: a fake GCS sends exactly what TEI-Ground-Control sends."""

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

try:
    import mavlink_bridge
    mavutil = mavlink_bridge.import_pymavlink()
    from pymavlink.dialects.v20 import ardupilotmega as mavlink
except ImportError:  # pragma: no cover
    mavlink = None

from dronebridge import geo  # noqa: E402

HOME = (41.0065415, 28.8434376, 34.8)


class Sink:
    """File-like buffer the emulator writes MAVLink bytes into."""

    def __init__(self):
        self.data = bytearray()

    def write(self, b):
        self.data += b


class Clock:
    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        return self.t


@unittest.skipIf(mavlink is None, "pymavlink not available")
class EmulatorTests(unittest.TestCase):
    def setUp(self):
        from dronebridge.mavsim import ArduCopterEmulator
        self.sink = Sink()
        self.mav = mavlink.MAVLink(self.sink, srcSystem=1, srcComponent=1)
        self.clock = Clock()
        self.emu = ArduCopterEmulator(self.mav, *HOME, clock=self.clock)
        self.gcs = mavlink.MAVLink(Sink(), srcSystem=255, srcComponent=190)
        self.parser = mavlink.MAVLink(None)
        self.state(mode="MANUAL", armed=False, on_ground=True)

    def state(self, **kw):
        s = {"mode": "MANUAL", "armed": False, "e": 0.0, "n": 0.0, "u": 0.0, "home_u": 0.0, "heading": 0.0,
             "voltage": 16.4, "current": 1.0, "remaining": 98, "motors": [0, 0, 0, 0], "on_ground": True}
        s.update(kw)
        self.emu.update_state(s)

    def send(self, msg):
        """Pack a GCS message and feed the parsed copy (with real header) to the emulator."""
        buf = msg.pack(self.gcs)
        self.emu.handle(self.parser.parse_buffer(buf)[0])

    def sent(self, kind=None):
        msgs = self.parser.parse_buffer(bytes(self.sink.data)) or []
        self.sink.data.clear()
        return [m for m in msgs if kind is None or m.get_type() == kind]

    # ---------------------------------------------------------------- tests
    def test_heartbeat_reports_arducopter_quad_mode_and_arming(self):
        self.state(mode="AUTO", armed=True, on_ground=False)
        self.emu.send_heartbeat(self.emu.state)
        hb = self.sent("HEARTBEAT")[-1]
        self.assertEqual(hb.type, mavlink.MAV_TYPE_QUADROTOR)
        self.assertEqual(hb.autopilot, mavlink.MAV_AUTOPILOT_ARDUPILOTMEGA)
        self.assertEqual(hb.custom_mode, 3)
        self.assertTrue(hb.base_mode & mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
        self.assertEqual(hb.get_srcComponent(), mavlink.MAV_COMP_ID_AUTOPILOT1)  # TEI filters on this

    def test_arm_then_guided_takeoff(self):
        self.send(self.gcs.command_long_encode(1, 1, 400, 0, 1, 0, 0, 0, 0, 0, 0))
        self.assertEqual(self.emu.pop_commands(), [{"type": "arm"}])
        self.state(armed=True)
        # takeoff outside GUIDED is refused, like ArduCopter
        self.send(self.gcs.command_long_encode(1, 1, 22, 0, 0, 0, 0, 0, 0, 0, 10))
        self.assertEqual(self.sent("COMMAND_ACK")[-1].result, mavlink.MAV_RESULT_DENIED)
        self.send(self.gcs.set_mode_encode(1, mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 4))
        self.send(self.gcs.command_long_encode(1, 1, 22, 0, 0, 0, 0, 0, 0, 0, 10))
        cmds = self.emu.pop_commands()
        self.assertEqual(cmds[0]["type"], "mode")
        self.assertEqual(cmds[0]["mode"], "GUIDED")
        self.assertEqual(cmds[1], {"type": "takeoff", "alt": 10.0})

    def test_takeoff_right_after_arm_ack_is_accepted(self):
        # TEI/QGC send TAKEOFF as soon as ARM is ACKed, before the next simulator state arrives
        self.send(self.gcs.set_mode_encode(1, mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 4))
        self.send(self.gcs.command_long_encode(1, 1, 400, 0, 1, 0, 0, 0, 0, 0, 0))
        self.send(self.gcs.command_long_encode(1, 1, 22, 0, 0, 0, 0, 0, 0, 0, 15))
        self.assertEqual(self.sent("COMMAND_ACK")[-1].result, mavlink.MAV_RESULT_ACCEPTED)
        self.assertEqual([c["type"] for c in self.emu.pop_commands()], ["mode", "arm", "takeoff"])

    def test_body_velocity_is_rotated_by_heading(self):
        self.state(armed=True, mode="GUIDED", heading=90.0, on_ground=False)
        mask = 0b0000011111000111  # TEI: velocity + yaw rate
        self.send(self.gcs.set_position_target_local_ned_encode(0, 1, 1, mavlink.MAV_FRAME_BODY_NED, mask,
                                                                0, 0, 0, 2.0, 0, -1.0, 0, 0, 0, 0, 0.5))
        v = self.emu.pop_commands()[0]
        self.assertAlmostEqual(v["ve"], 2.0, places=5)  # facing east, forward = east
        self.assertAlmostEqual(v["vn"], 0.0, places=5)
        self.assertAlmostEqual(v["vu"], 1.0, places=5)  # NED down -1 = up 1
        self.assertAlmostEqual(v["yaw_rate"], math.degrees(0.5), places=4)

    def tei_mission_upload(self):
        """TEI GCS: home, takeoff 20 m, two waypoints with 2 s hold, RTL."""
        wp1 = geo.enu_to_geodetic(100, 0, 0, HOME[0], HOME[1])
        wp2 = geo.enu_to_geodetic(100, 50, 0, HOME[0], HOME[1])
        items = [(0, 16, HOME[0], HOME[1], 0.0, 0), (3, 22, 0, 0, 20.0, 0),
                 (3, 16, wp1[0], wp1[1], 25.0, 2.0), (3, 16, wp2[0], wp2[1], 25.0, 2.0), (3, 20, 0, 0, 0.0, 0)]
        self.send(self.gcs.mission_count_encode(1, 1, len(items), 0))
        for seq, (frame, cmd, lat, lon, alt, p1) in enumerate(items):
            req = self.sent("MISSION_REQUEST_INT")[-1]
            self.assertEqual(req.seq, seq)
            self.send(self.gcs.mission_item_int_encode(1, 1, seq, frame, cmd, 1 if seq == 1 else 0, 1, p1, 0, 0, 0,
                                                       int(lat * 1e7), int(lon * 1e7), alt, 0))
        return items

    def test_tei_mission_upload_and_auto_start(self):
        self.tei_mission_upload()
        ack = self.sent("MISSION_ACK")[-1]
        self.assertEqual(ack.type, mavlink.MAV_MISSION_ACCEPTED)
        self.send(self.gcs.set_mode_encode(1, mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 3))
        mission = self.emu.pop_commands()[0]
        self.assertEqual(mission["type"], "mission")
        self.assertEqual(mission["takeoff_alt"], 20.0)
        self.assertEqual(mission["end"], "RTL")
        self.assertEqual(len(mission["points"]), 2)
        p1, p2 = mission["points"]
        self.assertAlmostEqual(p1["e"], 100, delta=0.05)
        self.assertAlmostEqual(p2["n"], 50, delta=0.05)
        self.assertEqual(p1["u"], 25.0)
        self.assertEqual(p1["hold"], 2.0)

    def test_mission_download_returns_uploaded_items(self):
        items = self.tei_mission_upload()
        self.sent()
        self.send(self.gcs.mission_request_list_encode(1, 1, 0))
        self.assertEqual(self.sent("MISSION_COUNT")[-1].count, len(items))
        self.send(self.gcs.mission_request_int_encode(1, 1, 2, 0))
        item = self.sent("MISSION_ITEM_INT")[-1]
        self.assertEqual(item.command, 16)
        self.assertEqual(item.param1, 2.0)

    def test_auto_without_mission_is_refused(self):
        self.send(self.gcs.set_mode_encode(1, mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED, 3))
        self.assertEqual(self.emu.pop_commands(), [])
        self.assertTrue(any(b"Mission yok" in m.text.encode() if isinstance(m.text, str) else b"Mission yok" in m.text
                            for m in self.sent("STATUSTEXT")))

    def test_motor_test_uses_arducopter_test_order(self):
        self.send(self.gcs.command_long_encode(1, 1, 209, 0, 2, 0, 20, 3, 0, 0, 0))
        cmd = self.emu.pop_commands()[0]
        self.assertEqual(cmd["motor"], 4)  # test B = rear-right = Quad-X motor 4
        self.assertEqual(cmd["pct"], 20)

    def test_motor_test_refused_while_armed(self):
        self.state(armed=True)
        self.send(self.gcs.command_long_encode(1, 1, 209, 0, 1, 0, 20, 3, 0, 0, 0))
        self.assertEqual(self.sent("COMMAND_ACK")[-1].result, mavlink.MAV_RESULT_DENIED)

    def test_gcs_failsafe_triggers_rtl_after_timeout(self):
        self.send(self.gcs.heartbeat_encode(mavlink.MAV_TYPE_GCS, mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0))
        self.state(armed=True, mode="GUIDED", on_ground=False)
        self.assertEqual(self.emu.pop_commands(), [])
        self.clock.t += 6  # FS_GCS_TIMEOUT = 5 s
        self.state(armed=True, mode="GUIDED", on_ground=False)
        cmd = self.emu.pop_commands()[0]
        self.assertEqual((cmd["type"], cmd["mode"]), ("mode", "RTL"))

    def test_param_set_is_applied_to_simulator(self):
        self.send(self.gcs.param_set_encode(1, 1, b"WPNAV_SPEED", 600, mavlink.MAV_PARAM_TYPE_REAL32))
        self.assertEqual(self.emu.pop_commands(), [{"type": "param", "name": "cruise_speed", "value": 6.0}])
        self.assertEqual(self.sent("PARAM_VALUE")[-1].param_value, 600)

    def test_stream_contains_position_in_real_coordinates(self):
        self.state(e=100.0, n=0.0, u=30.0, home_u=0.0, armed=True, on_ground=False, mode="AUTO")
        for _ in range(10):
            self.emu.send_stream()
        pos = self.sent("GLOBAL_POSITION_INT")[-1]
        e, n, _ = geo.geodetic_to_enu(pos.lat / 1e7, pos.lon / 1e7, 0, HOME[0], HOME[1])
        self.assertAlmostEqual(e, 100, delta=0.05)
        self.assertEqual(pos.relative_alt, 30000)
        self.assertAlmostEqual(pos.alt / 1000, HOME[2] + 30, places=2)


if __name__ == "__main__":
    unittest.main()
