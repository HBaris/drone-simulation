"""TEI-Ground-Control add-ons (rasperiypi/, local only): mission files and hover diagnosis, without Qt."""

import json
import sys
import tempfile
import unittest
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEI = ROOT / "rasperiypi" / "TEI-Ground-Control"
sys.path.insert(0, str(ROOT / "tools"))
if TEI.exists():
    sys.path.insert(0, str(TEI))

try:
    import tei_gorev_dosya as gd
    import tei_saglik
except ImportError:  # the TEI project is not part of this repo
    gd = None

import sim2mission  # noqa: E402
from tests.test_bridge import synthetic_recording  # noqa: E402


@dataclass
class Tel:  # the fields of tei_gcs.Telemetry that tei_saglik uses
    armed: bool = True
    alt_rel: float = 15.0
    climb: float = 0.0
    groundspeed: float = 0.2
    motor_pwm: list = field(default_factory=lambda: [1556] * 4)


@unittest.skipIf(gd is None, "rasperiypi/TEI-Ground-Control not present")
class TeiMissionFileTests(unittest.TestCase):
    def sim_mission(self, fmt):
        d = Path(tempfile.mkdtemp())
        src = d / "ucus.json"
        src.write_text(json.dumps(synthetic_recording()), encoding="utf-8")
        sim2mission.main([str(src), "--home", "41.0065415,28.8434376,34.8", "--format", fmt])
        return d / ("ucus." + fmt)

    def test_sim2mission_waypoints_open_in_tei(self):
        ev, kalkis, noktalar, uyarilar = gd.haritaya(gd.oku(self.sim_mission("waypoints")))
        self.assertAlmostEqual(ev[0], 41.0065415, places=6)
        self.assertEqual(kalkis, 5.0)
        self.assertGreaterEqual(len(noktalar), 2)
        self.assertTrue(any("Hız değişimi" in u for u in uyarilar))  # TEI drops DO_CHANGE_SPEED: user is told

    def test_sim2mission_plan_open_in_tei(self):
        ev, kalkis, noktalar, _ = gd.haritaya(gd.oku(self.sim_mission("plan")))
        self.assertEqual(kalkis, 5.0)
        self.assertGreaterEqual(len(noktalar), 2)
        self.assertAlmostEqual(noktalar[0][2], 10.0, delta=0.5)

    def test_tei_export_roundtrip(self):
        pts = [(41.0070, 28.8440, 20.0), (41.0072, 28.8450, 25.0)]
        with tempfile.TemporaryDirectory() as d:
            yol = Path(d) / "gorev.waypoints"
            gd.yaz(yol, gd.tei_gorevi((41.0065, 28.8434), 15, pts))
            lines = yol.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[0], "QGC WPL 110")
            ev, kalkis, noktalar, uyarilar = gd.haritaya(gd.oku(yol))
        self.assertEqual(kalkis, 15.0)
        self.assertEqual([p[2] for p in noktalar], [20.0, 25.0])
        self.assertEqual(uyarilar, [])


@unittest.skipIf(gd is None, "rasperiypi/TEI-Ground-Control not present")
class TeiHoverDiagnosisTests(unittest.TestCase):
    def test_weak_motor_in_tei_panel(self):
        a = tei_saglik.HoverAnaliz()
        for _ in range(40):
            a.ekle(Tel(motor_pwm=[1561, 1654, 1556, 1561]))
        level, text = a.teshis()
        self.assertEqual(level, "KÖTÜ")
        self.assertIn("M2", text)

    def test_ground_idle_not_counted(self):
        a = tei_saglik.HoverAnaliz()
        for _ in range(40):
            a.ekle(Tel(alt_rel=0.0, motor_pwm=[1100] * 4))
        self.assertEqual(a.teshis()[0], "BEKLE")


if __name__ == "__main__":
    unittest.main()
