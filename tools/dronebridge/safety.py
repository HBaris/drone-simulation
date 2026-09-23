"""Pre-flight checks on a mission before it is written for the real drone.

ERROR findings block file generation; the limits themselves are CLI options so
changing them is always an explicit decision. Defaults follow common hobby
rules: 120 m altitude and staying within visual line of sight.
"""

from dataclasses import dataclass
from math import dist, hypot


@dataclass
class Limits:
    max_alt_m: float = 120.0
    max_distance_m: float = 500.0
    max_speed_ms: float = 12.0
    min_wp_alt_m: float = 3.0
    max_items: int = 500
    max_flight_min: float = 8.0


@dataclass
class Finding:
    level: str  # "ERROR" | "WARN"
    message: str


def check(waypoints, limits, takeoff_alt):
    findings = []
    if not waypoints:
        return [Finding("ERROR", "Havada geçen hiçbir nokta yok (kayıt sadece yerde mi?).")]

    top = max(w.up for w in waypoints)
    if top > limits.max_alt_m:
        findings.append(Finding("ERROR", f"Maksimum irtifa {top:.1f} m > sınır {limits.max_alt_m:.0f} m."))

    far = max(hypot(w.east, w.north) for w in waypoints)
    if far > limits.max_distance_m:
        findings.append(Finding("ERROR", f"Kalkış noktasından {far:.0f} m uzaklaşılıyor > sınır {limits.max_distance_m:.0f} m."))

    below = [i for i, w in enumerate(waypoints, 1) if w.up < 0]
    if below:
        findings.append(Finding("ERROR", f"Kalkış noktasının altına inen noktalar var (waypoint {below[:5]}). Gerçekte yere çarpar."))
    low = [i for i, w in enumerate(waypoints, 1) if 0 <= w.up < limits.min_wp_alt_m]
    if low:
        findings.append(Finding("WARN", f"{len(low)} nokta {limits.min_wp_alt_m:.0f} m altında (ilk: {low[:5]}). Engel riskine dikkat."))

    fast = [w.speed for w in waypoints if w.speed and w.speed > limits.max_speed_ms]
    if fast:
        findings.append(Finding("WARN", f"{len(fast)} bacakta hız {max(fast):.1f} m/s; {limits.max_speed_ms:.0f} m/s ile sınırlandı."))

    if len(waypoints) > limits.max_items:
        findings.append(Finding("WARN", f"{len(waypoints)} waypoint çok fazla; --tolerance değerini artırın."))

    path = takeoff_alt + sum(
        dist((a.east, a.north, a.up), (b.east, b.north, b.up)) for a, b in zip(waypoints, waypoints[1:])
    ) + hypot(waypoints[0].east, waypoints[0].north)
    speeds = [w.speed for w in waypoints if w.speed]
    avg_speed = min(sum(speeds) / len(speeds), limits.max_speed_ms) if speeds else 5.0
    minutes = (path / avg_speed + sum(w.hold_s for w in waypoints)) / 60
    if minutes > limits.max_flight_min:
        findings.append(Finding("WARN", f"Tahmini uçuş süresi {minutes:.1f} dk > batarya bütçesi {limits.max_flight_min:.0f} dk."))
    return findings
