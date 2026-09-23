import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import make_params  # noqa: E402
from dronebridge import params  # noqa: E402

MP_46 = "RTL_ALT,1500\nWPNAV_SPEED,1000\nANGLE_MAX,3000\nFS_GCS_ENABLE,0\nBATT_LOW_VOLT,10.5\n"
QGC_47 = "# Onboard parameters\n1\t1\tRTL_ALT_M\t15\t9\n1\t1\tWP_SPD\t10\t9\n1\t1\tFS_GCS_ENABLE\t1\t2\n"


class ParamTests(unittest.TestCase):
    def test_parse_both_formats(self):
        self.assertEqual(params.parse_param_file(MP_46)["RTL_ALT"], 1500)
        self.assertEqual(params.parse_param_file(QGC_47)["WP_SPD"], 10)

    def by_key(self, resolved, key):
        return next((name, value) for s, name, value in resolved if s.key == key)

    def test_old_names_and_centimetres_for_46_dump(self):
        r = params.resolve(params.RECOMMENDED, set(params.parse_param_file(MP_46)))
        self.assertEqual(self.by_key(r, "rtl_alt"), ("RTL_ALT", 3000))
        self.assertEqual(self.by_key(r, "wp_speed"), ("WPNAV_SPEED", 600))

    def test_new_si_names_for_47_dump(self):
        r = params.resolve(params.RECOMMENDED, set(params.parse_param_file(QGC_47)))
        self.assertEqual(self.by_key(r, "rtl_alt"), ("RTL_ALT_M", 30))
        self.assertEqual(self.by_key(r, "wp_speed"), ("WP_SPD", 6))
        self.assertEqual(self.by_key(r, "angle_max"), (None, None))  # not in this small dump: reported, not guessed

    def test_compare_lists_differences(self):
        current = params.parse_param_file(MP_46)
        rows = params.compare(params.resolve(params.RECOMMENDED, set(current)), current)
        names = [r[0] for r in rows]
        self.assertIn("FS_GCS_ENABLE", names)
        self.assertIn("BATT_LOW_VOLT", names)

    def test_cli_writes_mission_planner_file(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d) / "drone.param"
            base.write_text(MP_46, encoding="utf-8")
            out = Path(d) / "tei.param"
            make_params.main(["--base", str(base), "-o", str(out)])
            text = out.read_text(encoding="utf-8")
        self.assertIn("RTL_ALT,3000", text)
        self.assertIn("FS_GCS_ENABLE,1", text)
        self.assertNotIn("RTL_ALT_M", text)


if __name__ == "__main__":
    unittest.main()
