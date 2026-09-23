"""Pre-flight obstacle check: does a mission pass through buildings or terrain on a mapped site?

Uses the same map module the simulator builds (scripts/maps/<Site>.luau from tools/osm2roblox.py):
building footprints with heights, SRTM terrain. The whole flight path is walked at 1 m steps the way
ArduCopter flies it — vertical takeoff at home, straight legs between waypoints, then RTL (climb to
RTL altitude, straight home, descend) or LAND — and every point closer than `clearance` to a roof
or the ground is reported.

Limits: OSM heights (12 m where unknown), no trees, poles or wires — a pass here is necessary,
not sufficient; always check the route on the real site too.
"""

import json
import math
import re
from dataclasses import dataclass
from pathlib import Path

from .geo import enu_to_geodetic, geodetic_to_enu

STUDS_PER_METER = 3.5
NAV_WAYPOINT, NAV_LOITER_TIME, NAV_RTL, NAV_LAND, NAV_TAKEOFF = 16, 19, 20, 21, 22
REL_FRAMES = (3, 6)  # MAV_FRAME_GLOBAL_RELATIVE_ALT(_INT)


@dataclass
class Building:
    kind: str  # "box" | "tri"
    shape: tuple  # box: (e, n, w, d, yaw) ; tri: ((e,n),(e,n),(e,n))
    top_amsl: float
    focus: bool
    bbox: tuple  # (min_e, min_n, max_e, max_n)

    def contains(self, e, n):
        if not (self.bbox[0] <= e <= self.bbox[2] and self.bbox[1] <= n <= self.bbox[3]):
            return False
        if self.kind == "box":
            ce, cn, w, d, yaw = self.shape
            de, dn = e - ce, n - cn
            x = de * math.cos(yaw) + dn * math.sin(yaw)
            y = -de * math.sin(yaw) + dn * math.cos(yaw)
            return abs(x) <= w / 2 and abs(y) <= d / 2
        (ax, ay), (bx, by), (cx, cy) = self.shape
        d1 = (e - bx) * (ay - by) - (ax - bx) * (n - by)
        d2 = (e - cx) * (by - cy) - (bx - cx) * (n - cy)
        d3 = (e - ax) * (cy - ay) - (cx - ax) * (n - ay)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


class SiteMap:
    """Buildings and terrain of a site in ENU meters around the map centre, heights in m AMSL."""

    def __init__(self, center, center_amsl, buildings, terrain, focus_label=""):
        self.center, self.center_amsl = center, center_amsl
        self.buildings, self.terrain, self.focus_label = buildings, terrain, focus_label
        cell = 25.0
        self.cell, self.grid = cell, {}
        for b in buildings:  # spatial hash so each sample only tests nearby buildings
            for gx in range(int(b.bbox[0] // cell), int(b.bbox[2] // cell) + 1):
                for gy in range(int(b.bbox[1] // cell), int(b.bbox[3] // cell) + 1):
                    self.grid.setdefault((gx, gy), []).append(b)

    @classmethod
    def load(cls, path):
        text = Path(path).read_text(encoding="utf-8")

        def field(name, pattern):
            m = re.search(name + r"\s*=\s*" + pattern, text)
            return m.groups() if m else None

        clat, clon = (float(v) for v in field("CenterGeo", r"\{\s*([-\d.]+),\s*([-\d.]+)\s*\}"))
        home_y = float(field("Home", r"Vector3\.new\([-\d.]+,\s*([-\d.]+),")[0])
        geo = field("HomeGeo", r"\{\s*([-\d.]+),\s*([-\d.]+)(?:,\s*([-\d.]+))?\s*\}")
        home_amsl = float(geo[2]) if geo and geo[2] else 0.0
        center_amsl = home_amsl - home_y / STUDS_PER_METER
        label = (field("FocusLabel", r'"([^"]*)"') or [""])[0]
        s = STUDS_PER_METER

        def records(name):
            m = field(name, r'"([^"]*)"')
            return [[float(v) for v in r.split()] for r in m[0].split(";") if r.strip()] if m and m[0] else []

        buildings = []
        for cx, cz, w, d, yaw, h, focus, *rest in records("Boxes"):
            base = rest[0] if rest else 0.0
            e, n, w, d = cx / s, -cz / s, w / s, d / s
            r = math.hypot(w, d) / 2
            buildings.append(Building("box", (e, n, w, d, yaw), center_amsl + (base + h) / s, focus == 1,
                                      (e - r, n - r, e + r, n + r)))
        for x1, z1, x2, z2, x3, z3, h, focus, *rest in records("Tris"):
            base = rest[0] if rest else 0.0
            pts = ((x1 / s, -z1 / s), (x2 / s, -z2 / s), (x3 / s, -z3 / s))
            es, ns = [p[0] for p in pts], [p[1] for p in pts]
            buildings.append(Building("tri", pts, center_amsl + (base + h) / s, focus == 1,
                                      (min(es), min(ns), max(es), max(ns))))

        terrain = None
        info = field("Terrain", r"\{\s*Count\s*=\s*(\d+),\s*Step\s*=\s*([-\d.]+),\s*Half\s*=\s*([-\d.]+)\s*\}")
        heights = field("TerrainHeights", r'"([^"]*)"')
        if info and heights:
            count, step, half = int(info[0]), float(info[1]) / s, float(info[2]) / s
            values = [float(v) / s for v in heights[0].split()]
            terrain = (count, step, half, values)
        return cls((clat, clon), center_amsl, buildings, terrain, label)

    def ground_amsl(self, e, n):
        if not self.terrain:
            return self.center_amsl
        count, step, half, v = self.terrain
        fi = min(max((e + half) / step, 0), count - 1.001)
        fj = min(max((n + half) / step, 0), count - 1.001)
        i, j = int(fi), int(fj)
        ti, tj = fi - i, fj - j
        h = (v[j * count + i] * (1 - ti) * (1 - tj) + v[j * count + i + 1] * ti * (1 - tj)
             + v[(j + 1) * count + i] * (1 - ti) * tj + v[(j + 1) * count + i + 1] * ti * tj)
        return self.center_amsl + h

    def building_at(self, e, n):
        """Tallest building whose footprint contains (e, n), or None."""
        best = None
        for b in self.grid.get((int(e // self.cell), int(n // self.cell)), ()):
            if b.contains(e, n) and (best is None or b.top_amsl > best.top_amsl):
                best = b
        return best

    def to_enu(self, lat, lon):
        e, n, _ = geodetic_to_enu(lat, lon, 0.0, *self.center)
        return e, n


@dataclass
class Conflict:
    phase: str  # "kalkış", "bacak 3", "RTL dönüş", ...
    e: float
    n: float
    drone_amsl: float
    obstacle: str
    obstacle_top_amsl: float
    lat: float
    lon: float

    @property
    def shortfall(self):
        return self.obstacle_top_amsl - self.drone_amsl


def mission_path(items, home, rtl_alt, site):
    """items: [{"command", "frame", "lat", "lon", "alt"}] after the home item. home: (lat, lon, amsl).
    Returns [(phase, (e, n, amsl), (e, n, amsl))] straight segments in the site frame."""
    he, hn = site.to_enu(home[0], home[1])
    home_amsl = home[2] if home[2] else site.ground_amsl(he, hn)
    segments = []
    pos = (he, hn, home_amsl)
    leg = 0
    end = None
    for it in items:
        cmd = it["command"]
        rel = it["frame"] in REL_FRAMES
        alt = home_amsl + it["alt"] if rel else it["alt"]
        if cmd == NAV_TAKEOFF:
            nxt = (pos[0], pos[1], alt)
            segments.append(("kalkış", pos, nxt))
            pos = nxt
        elif cmd in (NAV_WAYPOINT, NAV_LOITER_TIME) and (it["lat"] or it["lon"]):
            e, n = site.to_enu(it["lat"], it["lon"])
            leg += 1
            nxt = (e, n, alt)
            segments.append((f"bacak {leg}", pos, nxt))
            pos = nxt
        elif cmd in (NAV_RTL, NAV_LAND):
            end = cmd
            break
    if end == NAV_LAND:
        segments.append(("iniş", pos, (pos[0], pos[1], site.ground_amsl(pos[0], pos[1]))))
    else:  # RTL (also ArduCopter's usual choice after a mission/failsafe)
        climb_to = max(pos[2], home_amsl + rtl_alt)
        top = (pos[0], pos[1], climb_to)
        segments.append(("RTL tırmanış", pos, top))
        segments.append(("RTL dönüş", top, (he, hn, climb_to)))
        segments.append(("RTL iniş", (he, hn, climb_to), (he, hn, home_amsl)))
    return segments


def check(site, segments, clearance=5.0, step=1.0):
    """Every 1 m sample closer than `clearance` to a roof (or the ground, away from takeoff/landing)."""
    conflicts = []
    for phase, a, b in segments:
        length = math.dist(a, b)
        count = max(1, int(length / step))
        vertical = math.hypot(b[0] - a[0], b[1] - a[1]) < 0.5
        for k in range(count + 1):
            t = k / count
            e, n, z = (a[i] + (b[i] - a[i]) * t for i in range(3))
            building = site.building_at(e, n)
            if building and z < building.top_amsl + clearance:
                name = site.focus_label if building.focus and site.focus_label else "bina"
                conflicts.append((phase, e, n, z, name, building.top_amsl))
            elif not vertical:  # the pad itself is ground contact by design
                ground = site.ground_amsl(e, n)
                if z < ground + clearance:
                    conflicts.append((phase, e, n, z, "arazi", ground))
    out = []
    for phase, e, n, z, name, top in conflicts:
        lat, lon, _ = enu_to_geodetic(e, n, 0.0, *site.center)
        out.append(Conflict(phase, e, n, z, name, top, lat, lon))
    return out


def summarize(conflicts):
    """One line per (phase, obstacle) with the worst shortfall — readable instead of hundreds of samples."""
    worst = {}
    for c in conflicts:
        key = (c.phase, c.obstacle, round(c.obstacle_top_amsl, 1))
        if key not in worst or c.shortfall > worst[key].shortfall:
            worst[key] = c
    return sorted(worst.values(), key=lambda c: -c.shortfall)


def read_mission_file(path):
    """.waypoints (QGC WPL 110) or .plan -> (home (lat, lon, amsl), items after home)."""
    text = Path(path).read_text(encoding="utf-8-sig")
    if text.lstrip().startswith("{"):
        m = json.loads(text)["mission"]
        home = tuple(m["plannedHomePosition"][:3])
        items = [{"command": it["command"], "frame": it["frame"], "lat": it["params"][4] or 0.0,
                  "lon": it["params"][5] or 0.0, "alt": it["params"][6] or 0.0}
                 for it in m["items"] if it.get("type") == "SimpleItem"]
        return home, items
    rows = [line.split("\t") if "\t" in line else line.split() for line in text.splitlines()[1:] if line.strip()]
    items = [{"command": int(r[3]), "frame": int(r[2]), "lat": float(r[8]), "lon": float(r[9]), "alt": float(r[10])}
             for r in rows]
    home = (items[0]["lat"], items[0]["lon"], items[0]["alt"])
    return home, items[1:]
