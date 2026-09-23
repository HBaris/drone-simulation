"""Obstacle check against the real Bahçelievler map module (scripts/maps/Bahcelievler.luau)."""

import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import sim2mission  # noqa: E402
from dronebridge import mission, obstacles  # noqa: E402
from dronebridge.simplify import Waypoint  # noqa: E402

MAP = ROOT / "scripts" / "maps" / "Bahcelievler.luau"
HOME = mission.Home(41.0065415, 28.8434376, 34.8)


def path_items(waypoints, takeoff):
    items = mission.build_items(waypoints, HOME, takeoff)
    return [{"command": i.command, "frame": i.frame, "lat": i.params[4], "lon": i.params[5], "alt": i.params[6]}
            for i in items]


@unittest.skipUnless(MAP.exists(), "Bahçelievler map not generated")
class ObstacleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.site = obstacles.SiteMap.load(MAP)

    def run_check(self, waypoints, takeoff=5.0, clearance=5.0):
        segs = obstacles.mission_path(path_items(waypoints, takeoff), (HOME.lat, HOME.lon, HOME.amsl), 30.0, self.site)
        return obstacles.check(self.site, segs, clearance)

    def test_map_loads_with_terrain(self):
        self.assertGreater(len(self.site.buildings), 500)
        pad = self.site.ground_amsl(*self.site.to_enu(HOME.lat, HOME.lon))
        self.assertAlmostEqual(pad, 34.8, delta=0.5)

    def test_storm_route_that_crashed_in_studio_is_rejected(self):
        b = math.radians(200)
        conflicts = self.run_check([Waypoint(150 * math.sin(b), 150 * math.cos(b), 30.0)])
        self.assertTrue(conflicts)
        self.assertTrue(all(c.phase == "bacak 1" for c in conflicts))

    def test_hospital_is_named_when_flown_through(self):
        # straight over the tallest hospital building at 8 m above the pad (its roof is ~5.4 m above the pad)
        he, hn = self.site.to_enu(HOME.lat, HOME.lon)
        tallest = max((b for b in self.site.buildings if b.focus), key=lambda b: b.top_amsl)
        te, tn = (tallest.bbox[0] + tallest.bbox[2]) / 2, (tallest.bbox[1] + tallest.bbox[3]) / 2
        conflicts = self.run_check([Waypoint(te - he, tn - hn, 8.0)], takeoff=8.0)
        self.assertIn("BAHÇELİEVLER DEVLET HASTANESİ", {c.obstacle for c in conflicts})

    def test_high_orbit_is_clear(self):
        he, hn = self.site.to_enu(HOME.lat, HOME.lon)
        start = math.atan2(hn - 16, he + 10)
        pts = [Waypoint(-10 + 90 * math.cos(start - k * math.pi / 4) - he, 16 + 90 * math.sin(start - k * math.pi / 4) - hn, 40.0)
               for k in range(9)]
        self.assertEqual(self.run_check(pts, takeoff=30.0), [])

    def test_sim2mission_refuses_to_write_conflicting_mission(self):
        b = math.radians(200)
        samples, t = [], 0.0
        for k in range(301):  # climb while flying 150 m SSW, recorded at 10 Hz
            f = k / 300
            samples.append([round(t, 1), 150 * math.sin(b) * f, 150 * math.cos(b) * f, 5 + 25 * f if k else 0.0, 200])
            t += 0.1
        data = {"format": "drone-sim-flight", "version": 1, "source": "manual_recording", "site": "BAHCELIEVLER",
                "home_geo": [HOME.lat, HOME.lon, HOME.amsl], "columns": ["t", "e", "n", "u", "hdg"], "samples": samples}
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "firtina.json"
            src.write_text(json.dumps(data), encoding="utf-8")
            self.assertEqual(sim2mission.main([str(src)]), 1)
            self.assertFalse((Path(d) / "firtina.waypoints").exists())


if __name__ == "__main__":
    unittest.main()
