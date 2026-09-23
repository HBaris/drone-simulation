"""Turn a dense 10 Hz flight recording into a short waypoint list.

A flight controller cannot replay thousands of setpoints from a mission, so the
recorded track is reduced with Ramer-Douglas-Peucker (3D). Points where the
pilot hovered are always kept and carry a hold time, and every kept point
remembers the average speed the pilot flew to reach it.
"""

from dataclasses import dataclass
from math import dist


@dataclass
class Waypoint:
    east: float
    north: float
    up: float
    speed: float | None = None  # m/s used on the leg that ends at this point
    hold_s: float = 0.0


def _point_segment_distance(p, a, b):
    ab = [b[i] - a[i] for i in range(3)]
    ap = [p[i] - a[i] for i in range(3)]
    ab_len2 = sum(c * c for c in ab)
    if ab_len2 == 0:
        return dist(p, a)
    t = max(0.0, min(1.0, sum(ap[i] * ab[i] for i in range(3)) / ab_len2))
    closest = [a[i] + ab[i] * t for i in range(3)]
    return dist(p, closest)


def rdp_indices(points, tolerance, keep=()):
    """Indices kept by Ramer-Douglas-Peucker; `keep` indices are always kept."""
    n = len(points)
    if n <= 2:
        return list(range(n))
    forced = sorted({0, n - 1, *keep})
    kept = set(forced)
    # Simplify each span between forced points independently (iterative, no recursion limit).
    for start, end in zip(forced, forced[1:]):
        stack = [(start, end)]
        while stack:
            s, e = stack.pop()
            max_d, max_i = 0.0, -1
            for i in range(s + 1, e):
                d = _point_segment_distance(points[i], points[s], points[e])
                if d > max_d:
                    max_d, max_i = d, i
            if max_d > tolerance and max_i != -1:
                kept.add(max_i)
                stack.append((s, max_i))
                stack.append((max_i, e))
    return sorted(kept)


def find_hovers(samples, min_duration_s, speed_threshold=0.3):
    """Return [(first_index, last_index)] runs where the drone stayed still."""
    hovers = []
    run_start = None
    for i in range(1, len(samples)):
        dt = samples[i][0] - samples[i - 1][0]
        speed = dist(samples[i][1:4], samples[i - 1][1:4]) / dt if dt > 0 else 0.0
        if speed < speed_threshold:
            if run_start is None:
                run_start = i - 1
        else:
            if run_start is not None and samples[i - 1][0] - samples[run_start][0] >= min_duration_s:
                hovers.append((run_start, i - 1))
            run_start = None
    if run_start is not None and samples[-1][0] - samples[run_start][0] >= min_duration_s:
        hovers.append((run_start, len(samples) - 1))
    return hovers


def recording_to_waypoints(samples, tolerance_m=1.5, hover_min_s=2.0):
    """samples: [[t, east, north, up, heading], ...] -> list[Waypoint]."""
    if not samples:
        return []
    hovers = find_hovers(samples, hover_min_s)
    hover_hold = {}
    keep = set()
    for first, last in hovers:
        hover_hold[first] = samples[last][0] - samples[first][0]
        keep.add(first)
        keep.add(last)

    points = [tuple(s[1:4]) for s in samples]
    # Everything after a hover's first sample up to its last is covered by the hold time.
    inside_hover = {i for first, last in hovers for i in range(first + 1, last + 1)}
    indices = [i for i in rdp_indices(points, tolerance_m, keep) if i not in inside_hover]
    hover_end = {first: last for first, last in hovers}

    waypoints = []
    prev = None
    for idx in indices:
        t, e, n, u = samples[idx][:4]
        speed = None
        if prev is not None:
            leg_t = t - samples[prev][0]
            leg_d = sum(dist(points[i], points[i + 1]) for i in range(prev, idx))
            speed = leg_d / leg_t if leg_t > 0 else None
        waypoints.append(Waypoint(e, n, u, speed, hover_hold.get(idx, 0.0)))
        # The next leg starts when the hover ends, not when it began.
        prev = hover_end.get(idx, idx)
    return waypoints
