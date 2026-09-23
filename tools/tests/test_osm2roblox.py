import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import osm2roblox as o  # noqa: E402

SQUARE = [(0, 0), (10, 0), (10, 10), (0, 10)]  # counter-clockwise
L_SHAPE = [(0, 0), (20, 0), (20, 5), (5, 5), (5, 20), (0, 20)]


class GeometryTests(unittest.TestCase):
    def test_area_sign_is_positive_for_ccw(self):
        self.assertAlmostEqual(o.area(SQUARE), 100)
        self.assertAlmostEqual(o.area(list(reversed(SQUARE))), -100)

    def test_clean_makes_rings_ccw_and_drops_closing_point(self):
        ring = o.clean(list(reversed(SQUARE)) + [SQUARE[-1]])
        self.assertEqual(len(ring), 4)
        self.assertGreater(o.area(ring), 0)

    def test_min_area_rect_of_rotated_rectangle(self):
        a = math.radians(30)
        rect = [(x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a))
                for x, y in [(0, 0), (20, 0), (20, 8), (0, 8)]]
        cx, cy, w, d, ang, rect_area = o.min_area_rect(rect)
        self.assertAlmostEqual(rect_area, 160, places=3)
        self.assertAlmostEqual(sorted([w, d])[1], 20, places=3)
        # Either edge may be the reference: width runs along `ang`, so 30° ↔ 20 m or 120° ↔ 8 m.
        along_long_edge = abs(math.sin(ang - a)) < 1e-3
        self.assertAlmostEqual(w, 20 if along_long_edge else 8, places=3)
        mid = ((rect[0][0] + rect[2][0]) / 2, (rect[0][1] + rect[2][1]) / 2)
        self.assertAlmostEqual(cx, mid[0], places=3)
        self.assertAlmostEqual(cy, mid[1], places=3)

    def test_ear_clip_l_shape_covers_its_area(self):
        tris = o.ear_clip(o.clean(L_SHAPE))
        self.assertIsNotNone(tris)
        self.assertEqual(len(tris), len(L_SHAPE) - 2)
        self.assertAlmostEqual(sum(abs(o.area(list(t))) for t in tris), o.area(L_SHAPE))

    def test_parse_height(self):
        self.assertEqual(o.parse_height({"height": "21.5 m"}), 21.5)
        self.assertEqual(o.parse_height({"building:levels": "5"}), 16.0)
        self.assertEqual(o.parse_height({}), o.DEFAULT_HEIGHT_M)

    def test_home_is_clear_of_buildings(self):
        buildings = [[(x, y), (x + 8, y), (x + 8, y + 8), (x, y + 8)] for x in range(-100, 100, 20) for y in range(-100, 100, 20)
                     if not (x == 40 and y == 40)]
        home = o.pick_home(buildings, [], SQUARE, radius=300, clearance=5)
        self.assertTrue(all(o.dist_to_poly(home, b) >= 5 for b in buildings))


if __name__ == "__main__":
    unittest.main()
