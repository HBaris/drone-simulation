"""Collision-free drone light show planning (many drones, one computer).

A show is a list of keyframes: every drone's position at that moment, then a hold. Between keyframes each
drone flies a straight line and all drones share one smooth time profile (minimum jerk), so they leave and
arrive together. Which drone goes to which target point is solved as an optimal assignment minimizing the
sum of squared distances. This is CAPT (Turpin, Michael & Kumar, "Concurrent assignment and planning of
trajectories for multiple robots", IJRR 2014): if all start points and all goal points are at least
`spacing` apart, drones stay at least spacing / sqrt(2) apart for the whole transition. We do not rely on
the proof alone: `verify` samples the whole show at 10 Hz and reports every pair that comes too close.

Coordinates are meters, ENU, relative to the show center on the ground (x east, y north, z up). Vertical
shapes are drawn in the x-z plane, facing an audience standing south of the center.

Needs numpy + scipy (pip install numpy scipy).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy.optimize import linear_sum_assignment
from scipy.spatial import cKDTree

SQRT3 = math.sqrt(3.0)


# --- shapes ------------------------------------------------------------------------------------------

def _hex_lattice(half_w: float, half_h: float, d: float) -> np.ndarray:
    """Hexagonal lattice points with nearest-neighbour distance d covering [-half_w, half_w] x [-half_h, half_h]."""
    rows = int(half_h / (d * SQRT3 / 2)) + 1
    cols = int(half_w / d) + 2
    pts = []
    for r in range(-rows, rows + 1):
        v = r * d * SQRT3 / 2
        shift = d / 2 if r % 2 else 0.0
        for c in range(-cols, cols + 1):
            pts.append((c * d + shift, v))
    return np.array(pts, float)


def _fill(inside, extent: tuple[float, float], n: int, d: float) -> np.ndarray:
    """n points of a hex lattice (spacing d) inside a normalized 2-D shape, scaled just large enough."""
    ex, ey = extent

    def count(scale):
        p = _hex_lattice(ex * scale, ey * scale, d)
        return p[inside(p[:, 0] / scale, p[:, 1] / scale)]

    lo, hi = d, d * 4
    while len(count(hi)) < n:
        lo, hi = hi, hi * 2
    for _ in range(40):
        mid = (lo + hi) / 2
        if len(count(mid)) >= n:
            hi = mid
        else:
            lo = mid
    pts = count(hi)
    if len(pts) > n:  # drop the surplus evenly instead of eroding one edge
        pts = pts[np.round(np.linspace(0, len(pts) - 1, n)).astype(int)]
    return pts


def _vertical(inside, extent: tuple[float, float], n: int, spacing: float, layers: int) -> np.ndarray:
    """A 2-D shape in the x-z plane, repeated in `layers` parallel planes `spacing` apart (y), so 800
    drones fit under the ceiling. Lowest drone at z = 0."""
    per = math.ceil(n / layers)
    uv = _fill(inside, extent, per, spacing)
    pts = np.vstack([np.column_stack([uv[:, 0], np.full(per, (k - (layers - 1) / 2) * spacing), uv[:, 1]])
                     for k in range(layers)])
    if len(pts) > n:
        pts = pts[np.round(np.linspace(0, len(pts) - 1, n)).astype(int)]
    pts[:, 2] -= pts[:, 2].min()
    return pts


def heart(n: int, spacing: float, layers: int = 2) -> np.ndarray:
    return _vertical(lambda x, y: (x * x + y * y - 1) ** 3 - x * x * y ** 3 <= 0, (1.2, 1.3), n, spacing, layers)


def ring(n: int, spacing: float, layers: int = 2) -> np.ndarray:
    return _vertical(lambda x, y: (x * x + y * y <= 1) & (x * x + y * y >= 0.3), (1.0, 1.0), n, spacing, layers)


def star(n: int, spacing: float, layers: int = 2) -> np.ndarray:
    def inside(x, y):
        ang = np.arctan2(x, y)
        r = np.hypot(x, y)
        k = np.abs(((ang / (2 * math.pi / 5)) % 1.0) - 0.5) * 2  # 0 at a tip, 1 between tips
        return r <= 1.0 / (1.0 + 1.3 * k)
    return _vertical(inside, (1.0, 1.0), n, spacing, layers)


def grid(n: int, spacing: float, alt: float = 0.0) -> np.ndarray:
    """Horizontal square grid (also the launch layout on the ground when alt = 0)."""
    cols = math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)
    pts = [((i % cols - (cols - 1) / 2) * spacing, (i // cols - (rows - 1) / 2) * spacing, alt) for i in range(n)]
    return np.array(pts, float)


def sphere(n: int, spacing: float, center_alt: float = 0.0) -> np.ndarray:
    """Fibonacci sphere, radius grown until neighbours are `spacing` apart."""
    i = np.arange(n)
    y = 1 - 2 * (i + 0.5) / n
    r_xy = np.sqrt(1 - y * y)
    th = math.pi * (3 - math.sqrt(5)) * i
    unit = np.column_stack([np.cos(th) * r_xy, np.sin(th) * r_xy, y])
    radius = spacing * math.sqrt(n / (4 * math.pi))
    while min_spacing(unit * radius) < spacing:
        radius *= 1.02
    return unit * radius + np.array([0, 0, center_alt])


SHAPES = {"heart": heart, "ring": ring, "star": star, "sphere": sphere, "grid": grid}


def min_spacing(points: np.ndarray) -> float:
    if len(points) < 2:
        return math.inf
    d, _ = cKDTree(points).query(points, k=2)
    return float(d[:, 1].min())


# --- show --------------------------------------------------------------------------------------------

@dataclass
class Limits:
    v_h: float = 5.0  # m/s horizontal
    v_up: float = 2.5
    v_dn: float = 1.5
    accel: float = 2.0  # m/s^2
    ceiling: float = 120.0  # m above the show center (SHGM limit; tighter on real permits)
    radius: float = 300.0  # m horizontal from the show center


@dataclass
class Keyframe:
    name: str
    positions: np.ndarray  # (n, 3), row i = drone i
    color: str = "#00ff78"
    hold: float = 0.0
    t_arrive: float = 0.0
    t_depart: float = 0.0


@dataclass
class Show:
    spacing: float
    keyframes: list[Keyframe] = field(default_factory=list)

    @property
    def n(self) -> int:
        return len(self.keyframes[0].positions)

    @property
    def duration(self) -> float:
        return self.keyframes[-1].t_depart

    def position_at(self, t: float) -> np.ndarray:
        kfs = self.keyframes
        for a, b in zip(kfs, kfs[1:]):
            if t <= a.t_depart:
                return a.positions
            if t < b.t_arrive:
                tau = (t - a.t_depart) / (b.t_arrive - a.t_depart)
                return a.positions + minjerk(tau) * (b.positions - a.positions)
        return kfs[-1].positions


def minjerk(tau):
    return tau ** 3 * (10 - 15 * tau + 6 * tau * tau)


def transition_time(a: np.ndarray, b: np.ndarray, lim: Limits) -> float:
    """Shortest shared duration keeping every drone inside the speed and acceleration limits.
    Minimum jerk peaks at 1.875 L/T speed and 5.77 L/T^2 acceleration."""
    d = b - a
    h = np.hypot(d[:, 0], d[:, 1])
    up = np.clip(d[:, 2], 0, None)
    dn = np.clip(-d[:, 2], 0, None)
    full = np.linalg.norm(d, axis=1)
    t = max(1.875 * h.max() / lim.v_h, 1.875 * up.max() / lim.v_up, 1.875 * dn.max() / lim.v_dn,
            math.sqrt(5.7735 * full.max() / lim.accel))
    return max(t, 1.0)


def assign(current: np.ndarray, targets: np.ndarray) -> np.ndarray:
    """Targets reordered so row i is where drone i should go (min sum of squared distances)."""
    cost = ((current[:, None, :] - targets[None, :, :]) ** 2).sum(axis=2)
    rows, cols = linear_sum_assignment(cost)
    out = np.empty_like(targets)
    out[rows] = targets[cols]
    return out


def plan(n: int, sequence: list[tuple[str, float, str]], spacing: float = 3.0, ground_spacing: float | None = None,
         launch_alt: float = 10.0, show_alt: float = 30.0, lim: Limits | None = None) -> Show:
    """Ground grid -> vertical take-off -> each (shape, hold s, color) -> back to the grid -> vertical landing."""
    lim = lim or Limits()
    gs = ground_spacing or spacing
    ground = grid(n, gs, 0.0)
    show = Show(spacing=spacing)
    show.keyframes.append(Keyframe("ground", ground, "#303030"))
    show.keyframes.append(Keyframe("launch", ground + [0, 0, launch_alt], "#ffffff", hold=2.0))
    for name, hold, color in sequence:
        pts = SHAPES[name](n, spacing)
        pts[:, 2] += show_alt - pts[:, 2].min()  # lowest drone of every shape at show_alt
        show.keyframes.append(Keyframe(name, assign(show.keyframes[-1].positions, pts), color, hold=hold))
    show.keyframes.append(Keyframe("return", assign(show.keyframes[-1].positions, ground + [0, 0, launch_alt]), "#ffffff", hold=2.0))
    last = show.keyframes[-1].positions
    show.keyframes.append(Keyframe("landed", last - [0, 0, launch_alt], "#303030"))

    t = 0.0
    for i, kf in enumerate(show.keyframes):
        if i:
            t += transition_time(show.keyframes[i - 1].positions, kf.positions, lim)
        kf.t_arrive = t
        t += kf.hold
        kf.t_depart = t
    return show


# --- verification ------------------------------------------------------------------------------------

@dataclass
class Report:
    min_separation: float
    min_separation_t: float
    violations: list[tuple[float, int, int, float]]  # (t, drone a, drone b, distance), first per pair
    max_alt: float
    max_radius: float
    problems: list[str]

    @property
    def ok(self) -> bool:
        return not self.problems


def verify(show: Show, min_sep: float, lim: Limits | None = None, rate_hz: float = 10.0) -> Report:
    lim = lim or Limits()
    worst, worst_t = math.inf, 0.0
    seen: dict[tuple[int, int], tuple[float, float]] = {}
    max_alt = max_r = 0.0
    first_air = show.keyframes[1].t_arrive  # everyone at launch altitude
    last_air = show.keyframes[-1].t_arrive - 1e-6
    steps = int(show.duration * rate_hz) + 1
    for k in range(steps):
        t = k / rate_hz
        p = show.position_at(t)
        max_alt = max(max_alt, float(p[:, 2].max()))
        max_r = max(max_r, float(np.hypot(p[:, 0], p[:, 1]).max()))
        if t < first_air or t > last_air:
            continue  # on the ground / vertical climb: spacing is the ground grid's
        tree = cKDTree(p)
        d, _ = tree.query(p, k=2)
        m = float(d[:, 1].min())
        if m < worst:
            worst, worst_t = m, t
        if m < min_sep:
            for a, b in tree.query_pairs(min_sep):
                dist = float(np.linalg.norm(p[a] - p[b]))
                if (a, b) not in seen:
                    seen[(a, b)] = (t, dist)
    problems = []
    if seen:
        problems.append(f"{len(seen)} drone çifti {min_sep:.1f} m'den yakına giriyor (en yakın {worst:.2f} m, t={worst_t:.1f} s)")
    if max_alt > lim.ceiling:
        problems.append(f"tavan aşılıyor: {max_alt:.0f} m > {lim.ceiling:.0f} m")
    if max_r > lim.radius:
        problems.append(f"alan dışına çıkılıyor: {max_r:.0f} m > {lim.radius:.0f} m")
    gs = min_spacing(show.keyframes[0].positions)
    if gs < min_sep:
        problems.append(f"yerdeki kalkış ızgarası {gs:.2f} m aralıklı (< {min_sep:.1f} m)")
    violations = sorted((t, a, b, d) for (a, b), (t, d) in seen.items())
    return Report(worst, worst_t, violations, max_alt, max_r, problems)


# --- export ------------------------------------------------------------------------------------------

def to_json(show: Show, center_geo: tuple[float, float, float] | None = None) -> dict:
    """Compact show file: per keyframe every drone's position; the player interpolates with minimum jerk."""
    return {
        "format": "drone-show",
        "version": 1,
        "profile": "minjerk",
        "frame": "ENU meters from the show center (x east, y north, z up)",
        "center_geo": list(center_geo) if center_geo else None,
        "drones": show.n,
        "spacing_m": show.spacing,
        "duration_s": round(show.duration, 2),
        "keyframes": [
            {
                "name": kf.name,
                "color": kf.color,
                "t_arrive": round(kf.t_arrive, 3),
                "t_depart": round(kf.t_depart, 3),
                "positions": [[round(float(v), 2) for v in p] for p in kf.positions],
            }
            for kf in show.keyframes
        ],
    }
