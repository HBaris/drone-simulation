import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import sim2mission  # noqa: E402
from dronebridge import flightfile, geo, mission, safety, simplify  # noqa: E402

HOME = mission.Home(41.0422, 29.0068, 30.0)


def synthetic_recording(hz=10):
    """Ground 1 s -> climb to 10 m -> 50 m east at 5 m/s -> hover 3 s -> 30 m north -> descend & land."""
    samples, t = [], 0.0
    e = n = u = 0.0

    def emit(steps, de, dn, du):
        nonlocal t, e, n, u
        for _ in range(steps):
            t += 1 / hz
            e, n, u = e + de, n + dn, u + du
            samples.append([round(t, 2), round(e, 3), round(n, 3), round(u, 3), 90.0])

    samples.append([0.0, 0.0, 0.0, 0.0, 90.0])
    emit(10, 0, 0, 0)          # on the pad
    emit(30, 0, 0, 10 / 30)    # climb
    emit(100, 0.5, 0, 0)       # east, 5 m/s
    emit(30, 0, 0, 0)          # hover 3 s
    emit(60, 0, 0.5, 0)        # north, 5 m/s
    emit(30, 0, 0, -10 / 30)   # descend
    emit(10, 0, 0, 0)          # landed
    return {"format": "drone-sim-flight", "version": 1, "source": "manual_recording",
            "frame": "ENU_m_relative_to_home", "sample_rate_hz": hz,
            "columns": ["t", "e", "n", "u", "hdg"], "samples": samples}


class GeoTests(unittest.TestCase):
    def test_roundtrip_short_and_long(self):
        for e, n in [(10, 20), (-350, 480), (15000, -22000)]:  # up to charging-station distances
            lat, lon, h = geo.enu_to_geodetic(e, n, 0, HOME.lat, HOME.lon)
            e2, n2, _ = geo.geodetic_to_enu(lat, lon, h, HOME.lat, HOME.lon)
            self.assertAlmostEqual(e, e2, places=3)
            self.assertAlmostEqual(n, n2, places=3)

    def test_100m_north_is_about_0_0009_deg(self):
        lat, lon, _ = geo.enu_to_geodetic(0, 100, 0, HOME.lat, HOME.lon)
        self.assertAlmostEqual((lat - HOME.lat) * 111_000, 100, delta=0.5)
        self.assertAlmostEqual(lon, HOME.lon, places=9)


class SimplifyTests(unittest.TestCase):
    def test_straight_line_collapses(self):
        pts = [(i * 0.5, 0, 10) for i in range(200)]
        self.assertEqual(simplify.rdp_indices(pts, 0.5), [0, 199])

    def test_recording_becomes_few_waypoints_with_hover(self):
        parsed = flightfile.parse(synthetic_recording())
        self.assertTrue(parsed.landed_at_end)
        self.assertLess(len(parsed.waypoints), 10)
        holds = [w.hold_s for w in parsed.waypoints if w.hold_s]
        self.assertEqual(len(holds), 1)
        self.assertAlmostEqual(holds[0], 3.0, delta=0.3)
        corner = [w for w in parsed.waypoints if w.hold_s][0]
        self.assertAlmostEqual(corner.east, 50, delta=1)
        leg_speeds = [w.speed for w in parsed.waypoints[2:] if w.speed and w.up > 9]  # skip pad + climb
        self.assertTrue(all(abs(s - 5) < 0.6 for s in leg_speeds), leg_speeds)


class MissionTests(unittest.TestCase):
    def build(self):
        parsed = flightfile.parse(synthetic_recording())
        wps, landing = flightfile.trim_vertical(parsed.waypoints, 5.0, landed=True)
        return wps, mission.build_items(wps, HOME, 5.0, end="land", land_at=landing)

    def test_item_sequence(self):
        wps, items = self.build()
        cmds = [i.command for i in items]
        self.assertEqual(cmds[0], mission.MAV_CMD_NAV_TAKEOFF)
        self.assertEqual(cmds[-1], mission.MAV_CMD_NAV_LAND)
        self.assertIn(mission.MAV_CMD_DO_CHANGE_SPEED, cmds)
        # Climb and descent are handled by TAKEOFF/LAND, so no waypoint sits near the ground.
        self.assertTrue(all(w.up > 5 for w in wps), [w.up for w in wps])
        land = items[-1]
        e, n, _ = geo.geodetic_to_enu(land.params[4], land.params[5], 0, HOME.lat, HOME.lon)
        self.assertAlmostEqual(e, 50, delta=1)
        self.assertAlmostEqual(n, 30, delta=1)

    def test_wpl110_format(self):
        _, items = self.build()
        lines = mission.to_wpl110(items, HOME).splitlines()
        self.assertEqual(lines[0], "QGC WPL 110")
        self.assertEqual(len(lines), len(items) + 2)
        for seq, line in enumerate(lines[1:]):
            cols = line.split("\t")
            self.assertEqual(len(cols), 12)
            self.assertEqual(int(cols[0]), seq)

    def test_plan_is_valid_json_with_nulls_for_nan(self):
        _, items = self.build()
        plan = json.loads(mission.to_qgc_plan(items, HOME, fence_radius_m=520))
        self.assertEqual(plan["mission"]["firmwareType"], 3)
        self.assertIsNone(plan["mission"]["items"][0]["params"][3])
        self.assertEqual(plan["geoFence"]["circles"][0]["circle"]["radius"], 520)


class SafetyTests(unittest.TestCase):
    def test_altitude_and_distance_errors(self):
        wps = [simplify.Waypoint(0, 0, 150), simplify.Waypoint(900, 0, 20)]
        levels = [f.level for f in safety.check(wps, safety.Limits(), 5.0)]
        self.assertEqual(levels.count("ERROR"), 2)

    def test_below_home_is_error(self):
        wps = [simplify.Waypoint(10, 0, 10), simplify.Waypoint(20, 0, -2)]
        self.assertIn("ERROR", [f.level for f in safety.check(wps, safety.Limits(), 5.0)])


class CliTests(unittest.TestCase):
    def test_end_to_end_writes_both_files(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "ucus.json"
            src.write_text(json.dumps(synthetic_recording()), encoding="utf-8")
            self.assertEqual(sim2mission.main([str(src), "--home", "41.0422,29.0068"]), 0)
            self.assertTrue((Path(d) / "ucus.plan").exists())
            self.assertTrue((Path(d) / "ucus.waypoints").exists())

    def test_unsafe_flight_is_refused(self):
        data = synthetic_recording()
        for s in data["samples"]:
            s[3] *= 20  # 200 m peak
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "yuksek.json"
            src.write_text(json.dumps(data), encoding="utf-8")
            self.assertEqual(sim2mission.main([str(src), "--home", "41.0422,29.0068"]), 1)
            self.assertFalse((Path(d) / "yuksek.plan").exists())


if __name__ == "__main__":
    unittest.main()
