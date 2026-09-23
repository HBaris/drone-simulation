import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from dronebridge import health  # noqa: E402


class Msg:
    def __init__(self, kind, src_component=1, **fields):
        self.kind, self.src = kind, src_component
        self.__dict__.update(fields)

    def get_type(self):
        return self.kind

    def get_srcComponent(self):
        return self.src


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def fly_hover(monitor, clock, outputs, seconds=30, voltage=15.6, current=26.0, sag_per_amp=0.04):
    monitor.update(Msg("HEARTBEAT", type=2, base_mode=128 | 1))
    monitor.update(Msg("EXTENDED_SYS_STATE", landed_state=2))
    for k in range(int(seconds * 5)):
        clock.t += 0.2
        i = current + (6 if k % 20 < 10 else -6)  # some current variation for the resistance fit
        monitor.update(Msg("HEARTBEAT", type=2, base_mode=128 | 1))
        monitor.update(Msg("VFR_HUD", climb=0.0, groundspeed=0.2))
        monitor.update(Msg("SYS_STATUS", voltage_battery=int((voltage - sag_per_amp * i) * 1000), current_battery=int(i * 100)))
        pwm = {f"servo{m + 1}_raw": int(1000 + 1000 * o) for m, o in enumerate(outputs)}
        monitor.update(Msg("SERVO_OUTPUT_RAW", **pwm))


def by_topic(findings, topic):
    return next(f for f in findings if f.topic == topic)


class HealthTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.m = health.HealthMonitor(clock=self.clock)

    def test_balanced_hover_is_ok(self):
        fly_hover(self.m, self.clock, [0.556, 0.556, 0.556, 0.556])
        report = self.m.report()
        self.assertTrue(all(by_topic(report, f"motor{i}").level == "OK" for i in range(1, 5)))
        self.assertEqual(by_topic(report, "yaw").level, "OK")
        self.assertIn("1.80", by_topic(report, "thrust").message)  # thrust/weight = 1 / 0.556

    def test_weak_motor_is_flagged(self):
        # motor 2 lost 15 % efficiency: the controller drives it harder to hold attitude
        fly_hover(self.m, self.clock, [0.54, 0.54 / 0.85, 0.54, 0.54])
        m2 = by_topic(self.m.report(), "motor2")
        self.assertEqual(m2.level, "BAD")
        self.assertIn("fazla çalışıyor", m2.message)

    def test_single_weak_motor_is_quantified_not_blamed_on_mounts(self):
        fly_hover(self.m, self.clock, [0.561, 0.654, 0.556, 0.561])  # the Studio run with M2 at 85 %
        report = self.m.report()
        diag = by_topic(report, "diagnosis")
        self.assertIn("M2", diag.message)
        self.assertIn("verim ≈ 0.86", diag.message)
        self.assertEqual(by_topic(report, "yaw").level, "INFO")

    def test_yaw_imbalance_from_twisted_mounts(self):
        fly_hover(self.m, self.clock, [0.58, 0.58, 0.53, 0.53])  # CCW pair working harder
        self.assertEqual(by_topic(self.m.report(), "yaw").level, "WARN")

    def test_idle_on_ground_is_not_hover(self):
        self.m.update(Msg("HEARTBEAT", type=2, base_mode=128 | 1))
        self.m.update(Msg("EXTENDED_SYS_STATE", landed_state=1))
        for _ in range(50):
            self.m.update(Msg("VFR_HUD", climb=0.0, groundspeed=0.0))
            self.m.update(Msg("SERVO_OUTPUT_RAW", servo1_raw=1100, servo2_raw=1100, servo3_raw=1100, servo4_raw=1100))
        self.assertEqual(by_topic(self.m.report(), "hover").level, "INFO")

    def test_internal_resistance_estimate(self):
        fly_hover(self.m, self.clock, [0.55] * 4, sag_per_amp=0.04)
        r = by_topic(self.m.report(), "battery")
        self.assertIn("40 mΩ", r.message)

    def test_resistance_ignores_slow_discharge(self):
        # voltage also falls 0.5 V over the flight as the pack empties; R must still come out at 35 mΩ
        self.m.update(Msg("HEARTBEAT", type=2, base_mode=128 | 1))
        for k in range(300):
            i = 25 + (8 if k % 10 < 5 else -8)
            v = 16.0 - 0.5 * k / 300 - 0.035 * i
            self.m.update(Msg("SYS_STATUS", voltage_battery=int(v * 1000), current_battery=int(i * 100)))
        self.assertAlmostEqual(self.m.internal_resistance(), 0.035, delta=0.003)

    def test_wear_trend_against_history(self):
        history = [{"hover_mean": 0.55}, {"hover_mean": 0.555}]
        trend = health.compare_history(history, {"hover_mean": 0.60})
        self.assertEqual(trend.level, "WARN")


if __name__ == "__main__":
    unittest.main()
