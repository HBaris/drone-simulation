import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

try:
    import numpy as np

    from dronebridge import show
except ImportError:  # numpy / scipy not installed
    show = None


@unittest.skipIf(show is None, "numpy + scipy gerekli (pip install numpy scipy)")
class ShowPlanTests(unittest.TestCase):
    SEQ = [("sphere", 3, "#00f"), ("heart", 3, "#f00"), ("star", 3, "#ff0"), ("ring", 3, "#f00")]

    def test_shapes_keep_spacing_and_count(self):
        for name, make in show.SHAPES.items():
            pts = make(300, 3.0)
            self.assertEqual(len(pts), 300, name)
            self.assertGreaterEqual(show.min_spacing(pts), 3.0 - 1e-6, name)

    def test_planned_show_never_closer_than_capt_bound(self):
        s = show.plan(200, self.SEQ, spacing=3.0)
        rep = show.verify(s, min_sep=2.0)
        self.assertTrue(rep.ok, rep.problems)
        self.assertGreaterEqual(rep.min_separation, 3.0 / math.sqrt(2) - 0.01)

    def test_verify_catches_unassigned_transition(self):
        # Same targets without the optimal assignment (drone i -> point i, like the old Roblox show)
        s = show.plan(200, self.SEQ, spacing=3.0)
        ring = s.keyframes[5]
        ring.positions = show.ring(200, 3.0) + [0, 0, 30]
        rep = show.verify(s, min_sep=2.0)
        self.assertFalse(rep.ok)
        self.assertTrue(rep.violations)
        self.assertLess(rep.min_separation, 1.0)

    def test_ceiling_and_limits(self):
        s = show.plan(200, self.SEQ, spacing=3.0)
        rep = show.verify(s, 2.0, show.Limits(ceiling=40))
        self.assertIn("tavan", " ".join(rep.problems))
        lim = show.Limits()
        for a, b in zip(s.keyframes, s.keyframes[1:]):
            T = b.t_arrive - a.t_depart
            d = b.positions - a.positions
            peak_h = 1.875 * np.hypot(d[:, 0], d[:, 1]).max() / T
            self.assertLessEqual(peak_h, lim.v_h + 1e-6, b.name)

    def test_start_end_on_ground_and_file(self):
        s = show.plan(50, self.SEQ[:1], spacing=3.0)
        np.testing.assert_allclose(s.position_at(0)[:, 2], 0)
        np.testing.assert_allclose(s.position_at(s.duration + 5)[:, 2], 0, atol=1e-9)
        doc = show.to_json(s, (41.0, 28.8, 35.0))
        self.assertEqual(doc["drones"], 50)
        self.assertEqual(len(doc["keyframes"][0]["positions"]), 50)


if __name__ == "__main__":
    unittest.main()
