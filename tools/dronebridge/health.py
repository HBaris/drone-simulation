"""Drone health analysis from standard ArduPilot MAVLink telemetry — no ESC telemetry needed.

Works the same on the simulator bridge and on the real TEI drone (PWM ESCs):
- Hover motor balance (SERVO_OUTPUT_RAW while hovering): one motor working harder than the others
  points at a damaged prop, weak motor/ESC or a centre-of-gravity offset; a CW-vs-CCW difference
  points at twisted motor mounts (yaw imbalance).
- Hover throttle / thrust headroom, output saturation events.
- Battery: internal resistance from voltage sag vs current (linear fit), per-cell voltage, flight time left.
- VIBRATION, EKF_STATUS_REPORT, GPS quality when the vehicle sends them (the simulator does not).
- Session history: rising hover throttle over time = wear (props/motors) or added weight.
"""

import json
import math
import statistics
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

# Quad-X (ArduPilot numbering): motor -> (name, spin)
QUAD_X = {1: ("M1 ön-sağ", "CCW"), 2: ("M2 arka-sol", "CCW"), 3: ("M3 ön-sol", "CW"), 4: ("M4 arka-sağ", "CW")}
PWM_MIN, PWM_MAX = 1000, 2000

# Thresholds (ArduPilot wiki guidance where it exists)
IMBALANCE_WARN = 0.06  # a motor 6 % above the mean in hover
IMBALANCE_BAD = 0.12
YAW_IMBALANCE_WARN = 0.05  # CW vs CCW pair difference
HOVER_WARN = 0.65  # hover output above 65 % leaves little headroom
HOVER_BAD = 0.75
VIBE_WARN, VIBE_BAD = 30.0, 60.0  # m/s/s
RESISTANCE_WARN = 0.060  # ohm for a 4S pack (≈15 mΩ/cell)


@dataclass
class Finding:
    level: str  # OK | WARN | BAD | INFO
    topic: str
    message: str


@dataclass
class HoverSample:
    t: float
    outputs: list  # 0..1 per motor
    voltage: float


@dataclass
class HealthState:
    started: float = field(default_factory=time.time)
    hover: list = field(default_factory=list)
    battery: list = field(default_factory=list)  # (voltage, current)
    saturation_events: int = 0
    max_vibe: tuple = (0.0, 0.0, 0.0)
    clipping: tuple = (0, 0, 0)
    ekf_worst: float = 0.0
    gps_min_sats: int = 99
    gps_max_eph: float = 0.0
    cells: list = field(default_factory=list)
    used_mah: float = 0.0
    remaining_pct: int = -1
    capacity_mah: float = 5000.0
    flight_seconds: float = 0.0


class HealthMonitor:
    """Feed it pymavlink messages with `update(msg)`; read `report()` any time."""

    def __init__(self, motor_count=4, capacity_mah=5000.0, clock=time.time):
        self.n = motor_count
        self.s = HealthState(capacity_mah=capacity_mah)
        self.clock = clock
        self.armed = False
        self.last_alt = None
        self.last_alt_t = None
        self.climb = 0.0
        self.groundspeed = 0.0
        self.voltage = None
        self.current = None
        self.last_armed_t = None
        self.landed_state = None  # EXTENDED_SYS_STATE: 1 on ground, 2 in air, 3 takeoff, 4 landing
        self.rel_alt = None

    # --------------------------------------------------------------- ingest
    def update(self, msg):
        kind = msg.get_type()
        now = self.clock()
        if kind == "HEARTBEAT" and msg.get_srcComponent() == 1 and msg.type != 6:
            armed = bool(msg.base_mode & 128)
            if armed and self.last_armed_t is not None:
                self.s.flight_seconds += now - self.last_armed_t
            self.last_armed_t = now if armed else None
            self.armed = armed
        elif kind == "EXTENDED_SYS_STATE":
            self.landed_state = msg.landed_state
        elif kind == "GLOBAL_POSITION_INT":
            self.rel_alt = msg.relative_alt / 1000
        elif kind == "VFR_HUD":
            self.climb, self.groundspeed = msg.climb, msg.groundspeed
        elif kind == "SYS_STATUS":
            if msg.voltage_battery > 0:
                self.voltage = msg.voltage_battery / 1000
            if msg.current_battery >= 0:
                self.current = msg.current_battery / 100
            if self.voltage and self.current is not None and self.armed:
                self.s.battery.append((self.voltage, self.current))
                self.s.battery = self.s.battery[-3000:]
        elif kind == "BATTERY_STATUS":
            self.s.cells = [v / 1000 for v in msg.voltages if 0 < v < 65535]
            if msg.current_consumed >= 0:
                self.s.used_mah = msg.current_consumed
            self.s.remaining_pct = msg.battery_remaining
        elif kind == "SERVO_OUTPUT_RAW":
            outputs = [(getattr(msg, f"servo{i}_raw") - PWM_MIN) / (PWM_MAX - PWM_MIN) for i in range(1, self.n + 1)]
            if self.armed:
                if max(outputs) >= 0.95:
                    self.s.saturation_events += 1
                if self.is_hovering():
                    self.s.hover.append(HoverSample(now, outputs, self.voltage or 0))
                    self.s.hover = self.s.hover[-2000:]
        elif kind == "VIBRATION":
            self.s.max_vibe = tuple(max(a, b) for a, b in zip(self.s.max_vibe, (msg.vibration_x, msg.vibration_y, msg.vibration_z)))
            self.s.clipping = (msg.clipping_0, msg.clipping_1, msg.clipping_2)
        elif kind == "EKF_STATUS_REPORT":
            self.s.ekf_worst = max(self.s.ekf_worst, msg.velocity_variance, msg.pos_horiz_variance, msg.pos_vert_variance,
                                   msg.compass_variance)
        elif kind == "GPS_RAW_INT" and self.armed:
            self.s.gps_min_sats = min(self.s.gps_min_sats, msg.satellites_visible)
            if msg.eph not in (0, 65535):
                self.s.gps_max_eph = max(self.s.gps_max_eph, msg.eph / 100)

    def is_hovering(self):
        # Really airborne (idle motors on the ground are not a hover), still and level-ish
        in_air = self.landed_state == 2 if self.landed_state else (self.rel_alt or 0) > 2
        return in_air and self.groundspeed < 0.7 and abs(self.climb) < 0.3

    # --------------------------------------------------------------- analysis
    def hover_profile(self):
        if len(self.s.hover) < 10:
            return None
        means = [statistics.fmean(h.outputs[i] for h in self.s.hover) for i in range(self.n)]
        return means

    def single_motor_outlier(self, prof):
        """(motor, ratio to the other motors' mean) when one motor alone stands out, else None."""
        # Compare against the median: a single bad motor cannot drag the median like it drags the mean
        median = statistics.median(prof)
        devs = [abs(p - median) / median for p in prof]
        worst = max(range(len(prof)), key=lambda k: devs[k])
        rest = [d for k, d in enumerate(devs) if k != worst]
        if devs[worst] >= IMBALANCE_WARN and max(rest, default=0) <= devs[worst] / 3:
            others = [q for k, q in enumerate(prof) if k != worst]
            return worst + 1, prof[worst] / statistics.fmean(others)
        return None

    def internal_resistance(self):
        """R from sample-to-sample changes: dV = -R * dI. Differencing removes the slow open-circuit
        voltage decline as the pack empties, which a plain V-vs-I fit mistakes for less sag."""
        pts = self.s.battery[-600:]
        if len(pts) < 20:
            return None
        dv = [b[0] - a[0] for a, b in zip(pts, pts[1:])]
        di = [b[1] - a[1] for a, b in zip(pts, pts[1:])]
        den = sum(x * x for x in di)
        if den < 9:  # needs real current steps (throttle changes)
            return None
        return -sum(v * i for v, i in zip(dv, di)) / den

    def report(self):
        findings = []
        prof = self.hover_profile()
        if prof is None:
            findings.append(Finding("INFO", "hover", "Hover verisi yok (sabit havada durma bekleniyor)"))
        else:
            mean = statistics.fmean(prof)
            outlier = self.single_motor_outlier(prof)
            if outlier:
                i, ratio = outlier
                name, spin = QUAD_X.get(i, (f"M{i}", "?"))
                findings.append(Finding("BAD" if ratio - 1 >= IMBALANCE_BAD else "WARN", "diagnosis",
                                        f"{name} diğer üç motordan %{(ratio - 1) * 100:.1f} fazla çalışıyor → bu motor ≈%"
                                        f"{(1 - 1 / ratio) * 100:.0f} itki kaybetmiş (verim ≈ {1 / ratio:.2f}): pervaneyi (çatlak/balans), "
                                        f"motor rulmanını ve ESC'yi kontrol edin"))
            for i, p in enumerate(prof, start=1):
                dev = (p - mean) / mean if mean else 0
                level = "BAD" if abs(dev) >= IMBALANCE_BAD else "WARN" if abs(dev) >= IMBALANCE_WARN else "OK"
                name, spin = QUAD_X.get(i, (f"M{i}", "?"))
                hint = ""
                if level != "OK" and dev > 0:
                    hint = " — bu motor fazla çalışıyor: pervane hasarı/balansı, zayıf motor-ESC veya bu köşeye kaymış ağırlık merkezi"
                findings.append(Finding(level, f"motor{i}", f"{name} ({spin}) hover çıkışı %{p * 100:.1f} (ortalamadan {dev * 100:+.1f} %){hint}"))
            if self.n == 4 and outlier:
                findings.append(Finding("INFO", "yaw", f"CCW/CW ve ağırlık merkezi farkları M{outlier[0]} kaynaklı "
                                                       "(tek motor sorunu; montaj/CG değil)"))
            elif self.n == 4:
                ccw, cw = (prof[0] + prof[1]) / 2, (prof[2] + prof[3]) / 2
                yaw = (ccw - cw) / mean if mean else 0
                level = "WARN" if abs(yaw) >= YAW_IMBALANCE_WARN else "OK"
                side = "CCW" if yaw > 0 else "CW"
                findings.append(Finding(level, "yaw", f"CCW/CW dengesi {yaw * 100:+.1f} %"
                                        + (f" — {side} motorlar fazla çalışıyor: eğik motor montajı veya yaw trimi" if level != "OK" else "")))
                front, rear = (prof[0] + prof[2]) / 2, (prof[1] + prof[3]) / 2
                right, left = (prof[0] + prof[3]) / 2, (prof[1] + prof[2]) / 2
                findings.append(Finding("INFO", "cg", f"Ağırlık merkezi eğilimi: ön-arka {(front - rear) / mean * 100:+.1f} %, "
                                                      f"sağ-sol {(right - left) / mean * 100:+.1f} % (pozitif = ön/sağ ağır)"))
            level = "BAD" if mean >= HOVER_BAD else "WARN" if mean >= HOVER_WARN else "OK"
            findings.append(Finding(level, "thrust", f"Hover gazı %{mean * 100:.0f} → itki/ağırlık ≈ {1 / mean:.2f}"
                                    + (" — manevra payı az (ağır yük / zayıf pervane)" if level != "OK" else "")))
        if self.s.saturation_events:
            findings.append(Finding("WARN", "saturation", f"{self.s.saturation_events} örnekte bir motor %95+ (doyma): kontrol kaybı riski"))

        r = self.internal_resistance()
        if r is not None:
            level = "WARN" if r > RESISTANCE_WARN else "OK"
            findings.append(Finding(level, "battery", f"Batarya iç direnci ≈ {r * 1000:.0f} mΩ" + (" — yaşlanmış/soğuk paket" if level != "OK" else "")))
        if self.s.cells:
            spread = max(self.s.cells) - min(self.s.cells)
            level = "WARN" if spread > 0.05 else "OK"
            findings.append(Finding(level, "cells", f"Hücreler {', '.join(f'{c:.2f}' for c in self.s.cells)} V (fark {spread * 1000:.0f} mV)"))
        if self.s.battery and self.s.flight_seconds > 30:
            avg_i = statistics.fmean(c for _, c in self.s.battery[-300:])
            left_mah = self.s.capacity_mah * 0.8 - self.s.used_mah  # keep 20 % reserve
            if avg_i > 0.5:
                findings.append(Finding("INFO", "endurance", f"Ortalama {avg_i:.1f} A → %20 rezervle kalan ≈ {max(left_mah, 0) / avg_i * 60 / 1000:.1f} dk"))

        if self.s.max_vibe != (0.0, 0.0, 0.0):
            worst = max(self.s.max_vibe)
            level = "BAD" if worst >= VIBE_BAD else "WARN" if worst >= VIBE_WARN else "OK"
            findings.append(Finding(level, "vibration", f"Titreşim maks x/y/z {self.s.max_vibe[0]:.0f}/{self.s.max_vibe[1]:.0f}/{self.s.max_vibe[2]:.0f} m/s², clipping {self.s.clipping}"))
        else:
            findings.append(Finding("INFO", "vibration", "VIBRATION mesajı yok (simülasyon modellemiyor)"))
        if self.s.ekf_worst:
            level = "BAD" if self.s.ekf_worst >= 0.8 else "WARN" if self.s.ekf_worst >= 0.5 else "OK"
            findings.append(Finding(level, "ekf", f"EKF en kötü varyans {self.s.ekf_worst:.2f}"))
        if self.s.gps_min_sats != 99:
            level = "WARN" if self.s.gps_min_sats < 8 or self.s.gps_max_eph > 2 else "OK"
            findings.append(Finding(level, "gps", f"GPS en az {self.s.gps_min_sats} uydu, en kötü HDOP {self.s.gps_max_eph:.1f}"))
        return findings

    # --------------------------------------------------------------- history
    def session_summary(self):
        prof = self.hover_profile()
        return {"time": time.strftime("%Y-%m-%d %H:%M"), "flight_s": round(self.s.flight_seconds),
                "hover": [round(p, 4) for p in prof] if prof else None,
                "hover_mean": round(statistics.fmean(prof), 4) if prof else None,
                "hover_voltage": round(statistics.fmean(h.voltage for h in self.s.hover), 2) if self.s.hover else None,
                "resistance": self.internal_resistance()}


def compare_history(history, current):
    """Wear trend: hover output rising versus the first sessions (at similar battery voltage)."""
    past = [h for h in history if h.get("hover_mean")]
    if not past or not current.get("hover_mean"):
        return None
    baseline = statistics.fmean(h["hover_mean"] for h in past[:3])
    change = (current["hover_mean"] - baseline) / baseline
    level = "WARN" if change > 0.05 else "OK"
    return Finding(level, "wear", f"Hover gazı ilk oturumlara göre {change * 100:+.1f} %"
                   + (" — pervane/motor yıpranması veya eklenen ağırlık" if level != "OK" else ""))


def load_history(path):
    p = Path(path)
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else []


def save_history(path, history):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(history, indent=1, ensure_ascii=False), encoding="utf-8")


def to_json(findings):
    return [asdict(f) for f in findings]
