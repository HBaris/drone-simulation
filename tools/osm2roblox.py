"""Build a Roblox map module of a real neighbourhood from OpenStreetMap.

Example:
  python tools/osm2roblox.py --name Bahcelievler --center 41.0062437,28.844367 --radius 350 \
      --focus-way 518497853 -o scripts/maps/Bahcelievler.luau

Buildings keep their real footprint: near-rectangular ones become one oriented box, other shapes
are ear-clipped into triangles (built from wedge pairs in Roblox). Heights come from `height`,
else `building:levels` x 3 m, else a default. Map data (c) OpenStreetMap contributors, ODbL.
With --terrain, SRTM 30 m elevation (OpenTopoData, free) is sampled on a grid, lightly smoothed
(in cities SRTM partly includes rooftops) and everything is placed on it: buildings stand on the
lowest ground under their footprint, roads and parks follow the slope.
"""

import argparse
import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from dronebridge.geo import enu_to_geodetic, geodetic_to_enu

# Public Overpass servers are often overloaded (HTTP 429/504), so mirrors are tried in order.
OVERPASS_SERVERS = ["https://overpass-api.de/api/interpreter",
                    "https://overpass.kumi.systems/api/interpreter",
                    "https://overpass.private.coffee/api/interpreter"]
DEM_URL = "https://api.opentopodata.org/v1/srtm30m"  # 100 points / request, 1 request / s
STUDS_PER_METER = 3.5
LEVEL_HEIGHT_M = 3.0
DEFAULT_HEIGHT_M = 12.0  # typical 4-storey Istanbul apartment when OSM has no height
ROAD_WIDTH_M = {"motorway": 16, "trunk": 14, "primary": 12, "secondary": 10, "tertiary": 8,
                "residential": 6, "unclassified": 6, "service": 4, "living_street": 5,
                "pedestrian": 4, "footway": 2, "path": 1.5, "cycleway": 2, "steps": 2}


def _overpass(query):
    body = urllib.parse.urlencode({"data": query}).encode()
    last_error = None
    for url in OVERPASS_SERVERS:
        req = urllib.request.Request(url, data=body, headers={"User-Agent": "drone-simulation-osm2roblox/0.1"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)["elements"]
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  {url}: {e} — sıradaki sunucu deneniyor", file=sys.stderr)
            last_error = e
    raise last_error


def fetch(lat, lon, radius, focus_way):
    # Two small queries instead of one big one: overloaded servers time out on the combined query.
    around = f"(around:{radius},{lat},{lon})"
    buildings = f'[out:json][timeout:90];(way["building"]{around};relation["building"]{around};);out tags geom;'
    others = (f'[out:json][timeout:90];(way["highway"]{around};way["leisure"~"park|garden|pitch|playground"]{around};'
              f'way["landuse"~"grass|recreation_ground|village_green"]{around};'
              f'{f"way({focus_way});" if focus_way else ""});out tags geom;')
    return {"elements": _overpass(buildings) + _overpass(others)}


# ---------- terrain ----------

class Terrain:
    """Heights (m, relative to the map centre) on a regular east/north grid, bilinear lookup."""

    def __init__(self, half, step, heights):
        self.half, self.step, self.h = half, step, heights  # heights[j][i]: j = north index, i = east index
        self.n = len(heights)

    @classmethod
    def flat(cls):
        return cls(0, 1, [[0.0]])

    def at(self, e, n):
        if self.n == 1:
            return self.h[0][0]
        fi = min(max((e + self.half) / self.step, 0), self.n - 1.001)
        fj = min(max((n + self.half) / self.step, 0), self.n - 1.001)
        i, j = int(fi), int(fj)
        ti, tj = fi - i, fj - j
        h = self.h
        return (h[j][i] * (1 - ti) * (1 - tj) + h[j][i + 1] * ti * (1 - tj)
                + h[j + 1][i] * (1 - ti) * tj + h[j + 1][i + 1] * ti * tj)


def fetch_dem(lat0, lon0, half, step):
    """Absolute SRTM elevations (m AMSL) on the grid, as heights[j][i]."""
    count = int(round(2 * half / step)) + 1
    coords = []
    for j in range(count):
        for i in range(count):
            lat, lon, _ = enu_to_geodetic(-half + i * step, -half + j * step, 0, lat0, lon0)
            coords.append(f"{lat:.6f},{lon:.6f}")
    values = []
    for k in range(0, len(coords), 100):
        url = f"{DEM_URL}?locations={'|'.join(coords[k:k + 100])}"
        req = urllib.request.Request(url, headers={"User-Agent": "drone-simulation-osm2roblox/0.1"})
        with urllib.request.urlopen(req, timeout=60) as r:
            values += [res["elevation"] or 0.0 for res in json.load(r)["results"]]
        time.sleep(1.1)
    return [values[j * count:(j + 1) * count] for j in range(count)]


def min_filter(grid):
    """3x3 minimum: SRTM is a surface model that partly sees rooftops in cities, the lowest sample
    in a ~90 m window is usually street level, so this approximates bare ground (DSM -> DTM)."""
    n = len(grid)
    return [[min(grid[y][x] for y in range(max(0, j - 1), min(n, j + 2)) for x in range(max(0, i - 1), min(n, i + 2)))
             for i in range(n)] for j in range(n)]


def smooth(grid):
    n = len(grid)
    out = [[0.0] * n for _ in range(n)]
    for j in range(n):
        for i in range(n):
            cells = [grid[y][x] for y in range(max(0, j - 1), min(n, j + 2)) for x in range(max(0, i - 1), min(n, i + 2))]
            out[j][i] = sum(cells) / len(cells)
    return out


# ---------- geometry helpers (2D, meters: x = east, y = north) ----------

def area(poly):
    """Signed shoelace area: positive for counter-clockwise rings."""
    return 0.5 * sum(poly[i - 1][0] * poly[i][1] - poly[i][0] * poly[i - 1][1] for i in range(len(poly)))


def clean(poly):
    if len(poly) > 1 and poly[0] == poly[-1]:
        poly = poly[:-1]
    out = []
    for p in poly:
        if not out or math.dist(p, out[-1]) > 0.05:
            out.append(p)
    if len(out) > 2 and math.dist(out[0], out[-1]) < 0.05:
        out.pop()
    if len(out) >= 3 and area(out) < 0:
        out.reverse()  # counter-clockwise
    return out


def convex_hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def min_area_rect(poly):
    """(cx, cy, width, depth, angle_rad, rect_area) of the minimum-area enclosing rectangle."""
    hull = convex_hull(poly)
    best = None
    for i in range(len(hull)):
        (x1, y1), (x2, y2) = hull[i], hull[(i + 1) % len(hull)]
        ang = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(-ang), math.sin(-ang)
        rx = [p[0] * c - p[1] * s for p in hull]
        ry = [p[0] * s + p[1] * c for p in hull]
        w, d = max(rx) - min(rx), max(ry) - min(ry)
        if best is None or w * d < best[5]:
            mx, my = (max(rx) + min(rx)) / 2, (max(ry) + min(ry)) / 2
            cx = mx * math.cos(ang) - my * math.sin(ang)
            cy = mx * math.sin(ang) + my * math.cos(ang)
            best = (cx, cy, w, d, ang, w * d)
    return best


def point_in_poly(p, poly):
    x, y = p
    inside = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i - 1], poly[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def ear_clip(poly):
    """Triangulate a simple CCW polygon; returns None if it fails (self-intersecting input)."""
    idx = list(range(len(poly)))
    tris = []

    def is_ear(i0, i1, i2):
        a, b, c = poly[i0], poly[i1], poly[i2]
        if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-9:
            return False
        return not any(point_in_poly(poly[j], [a, b, c]) for j in idx if j not in (i0, i1, i2))

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            if is_ear(i0, i1, i2):
                tris.append((poly[i0], poly[i1], poly[i2]))
                idx.pop(k)
                break
        else:
            return None
    if len(idx) == 3:
        tris.append(tuple(poly[i] for i in idx))
    return tris


def dist_to_poly(p, poly):
    if point_in_poly(p, poly):
        return 0.0
    best = math.inf
    for i in range(len(poly)):
        a, b = poly[i - 1], poly[i]
        ab = (b[0] - a[0], b[1] - a[1])
        l2 = ab[0] ** 2 + ab[1] ** 2
        t = 0 if l2 == 0 else max(0, min(1, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / l2))
        best = min(best, math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t)))
    return best


# ---------- OSM -> local geometry ----------

def parse_height(tags):
    h = tags.get("height")
    if h:
        m = re.match(r"^\s*([\d.]+)", h)
        if m:
            return float(m.group(1))
    lv = tags.get("building:levels")
    if lv:
        m = re.match(r"^\s*([\d.]+)", lv)
        if m:
            return float(m.group(1)) * LEVEL_HEIGHT_M + 1.0
    return DEFAULT_HEIGHT_M


def to_local(geom, lat0, lon0):
    pts = []
    for g in geom:
        e, n, _ = geodetic_to_enu(g["lat"], g["lon"], 0, lat0, lon0)
        pts.append((e, n))
    return pts


def outer_rings(el, lat0, lon0):
    if el["type"] == "way":
        return [to_local(el["geometry"], lat0, lon0)]
    return [to_local(m["geometry"], lat0, lon0) for m in el.get("members", [])
            if m.get("role") == "outer" and m.get("geometry")]


def s(v):
    return f"{v * STUDS_PER_METER:.1f}".rstrip("0").rstrip(".")


def build(data, lat0, lon0, radius, focus_way, terrain=None):
    terrain = terrain or Terrain.flat()

    def ty(p):  # terrain height under a point, in studs
        return s(terrain.at(p[0], p[1]))

    focus = []
    buildings, roads, greens = [], [], []
    for el in data["elements"]:
        tags = el.get("tags", {})
        if focus_way and el["type"] == "way" and el["id"] == focus_way:
            focus = clean(to_local(el["geometry"], lat0, lon0))
        if "building" in tags:
            for ring in outer_rings(el, lat0, lon0):
                ring = clean(ring)
                if len(ring) >= 3 and area(ring) > 4:
                    buildings.append((ring, parse_height(tags), tags))
        elif "highway" in tags and el["type"] == "way":
            width = ROAD_WIDTH_M.get(tags["highway"])
            if width:
                roads.append((to_local(el["geometry"], lat0, lon0), width))
        elif el["type"] == "way" and ("leisure" in tags or "landuse" in tags):
            ring = clean(to_local(el["geometry"], lat0, lon0))
            if len(ring) >= 3:
                greens.append(ring)

    boxes, tris, stats = [], [], {"box": 0, "tri": 0, "fallback": 0, "focus": 0}
    for ring, h, tags in buildings:
        cx = sum(p[0] for p in ring) / len(ring)
        cy = sum(p[1] for p in ring) / len(ring)
        flag = 1 if focus and point_in_poly((cx, cy), focus) else 0
        stats["focus"] += flag
        base = s(min(terrain.at(*p) for p in ring))  # stands on the lowest ground under it
        rect = min_area_rect(ring)
        fill = area(ring) / rect[5] if rect[5] > 0 else 1
        pieces = None if fill >= 0.85 else ear_clip(ring)
        if pieces:
            stats["tri"] += 1
            for a, b, c in pieces:
                tris.append(" ".join([s(a[0]), s(-a[1]), s(b[0]), s(-b[1]), s(c[0]), s(-c[1]), s(h), str(flag), base]))
        else:
            stats["box" if fill >= 0.85 else "fallback"] += 1
            bx, by, w, d, ang = rect[:5]
            # Roblox: X = east, Z = south; yaw about +Y turns X toward -Z, i.e. east toward north
            boxes.append(" ".join([s(bx), s(-by), s(w), s(d), f"{ang:.4f}", s(h), str(flag), base]))

    road_segs = []
    for line, width in roads:
        for a, b in zip(line, line[1:]):
            if math.hypot(*a) < radius + 50 or math.hypot(*b) < radius + 50:
                road_segs.append(" ".join([s(a[0]), s(-a[1]), s(b[0]), s(-b[1]), s(width), ty(a), ty(b)]))

    green_tris = []
    for ring in greens:
        for a, b, c in (ear_clip(ring) or []):
            green_tris.append(" ".join([s(a[0]), s(-a[1]), s(b[0]), s(-b[1]), s(c[0]), s(-c[1]), ty(a), ty(b), ty(c)]))

    home = pick_home([b[0] for b in buildings], greens, focus, radius)
    return boxes, tris, road_segs, green_tris, home, stats


def pick_home(footprints, greens, focus, radius, clearance=12.0):
    """Open spot near the focus area (≥ clearance m from every building), preferring green areas."""
    target = (sum(p[0] for p in focus) / len(focus), sum(p[1] for p in focus) / len(focus)) if focus else (0, 0)
    near = [f for f in footprints if min(math.hypot(p[0] - target[0], p[1] - target[1]) for p in f) < 260]
    best = None
    for gx in range(-250, 251, 4):
        for gy in range(-250, 251, 4):
            p = (target[0] + gx, target[1] + gy)
            if math.hypot(*p) > radius - 30:
                continue
            if any(dist_to_poly(p, f) < clearance for f in near):
                continue
            score = math.hypot(gx, gy) - (60 if any(point_in_poly(p, g) for g in greens) else 0)
            if best is None or score < best[0]:
                best = (score, p)
    return best[1] if best else target


def write_module(path, name, label, lat0, lon0, radius, boxes, tris, roads, greens, home, terrain, center_amsl):
    hlat, hlon, _ = enu_to_geodetic(home[0], home[1], 0, lat0, lon0)
    home_h = terrain.at(*home)
    terrain_fields = []
    if terrain.n > 1:
        flat = [s(v) for row in terrain.h for v in row]
        terrain_fields = [
            f"\t-- Terrain grid: {terrain.n}x{terrain.n} points, row-major from south-west, heights relative to the centre",
            f"\tTerrain = {{ Count = {terrain.n}, Step = {s(terrain.step)}, Half = {s(terrain.half)} }},",
            f'\tTerrainHeights = "{" ".join(flat)}",',
        ]
    lines = [
        f"-- AUTO-GENERATED by tools/osm2roblox.py — do not edit by hand.",
        f"-- Map data (c) OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright).",
        "return {",
        f'\tName = "{name}",',
        f'\tFocusLabel = "{label or name}",',
        f"\tCenterGeo = {{ {lat0}, {lon0} }},",
        f"\tRadius = {radius * STUDS_PER_METER:.0f},",
        f"\tHome = Vector3.new({s(home[0])}, {s(home_h)}, {s(-home[1])}), -- launch pad (ground), relative to the map origin",
        f"\tHomeGeo = {{ {hlat:.7f}, {hlon:.7f}, {center_amsl + home_h:.1f} }}, -- lat, lon, ground m AMSL",
        "\t-- Boxes: cx cz width depth yaw height focus baseY ; Tris: x1 z1 x2 z2 x3 z3 height focus baseY",
        "\t-- Roads: x1 z1 x2 z2 width y1 y2 ; Green: x1 z1 x2 z2 x3 z3 y1 y2 y3   (studs, relative to origin)",
        *terrain_fields,
        f'\tBoxes = "{";".join(boxes)}",',
        f'\tTris = "{";".join(tris)}",',
        f'\tRoads = "{";".join(roads)}",',
        f'\tGreen = "{";".join(greens)}",',
        "}",
    ]
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    return hlat, hlon, home_h


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", required=True)
    ap.add_argument("--center", required=True, help="enlem,boylam")
    ap.add_argument("--radius", type=float, default=350, help="m")
    ap.add_argument("--focus-way", type=int, help="OSM way id of the area to highlight (e.g. the hospital)")
    ap.add_argument("--focus-label", help="label shown above the highlighted area")
    ap.add_argument("-o", "--output", type=Path, required=True)
    ap.add_argument("--cache", type=Path, help="save/load the raw Overpass JSON here (DEM goes next to it)")
    ap.add_argument("--terrain", action="store_true", help="add SRTM 30 m terrain elevation")
    ap.add_argument("--terrain-step", type=float, default=30.0, help="m between elevation samples")
    args = ap.parse_args(argv)
    lat0, lon0 = (float(v) for v in args.center.split(","))

    if args.cache and args.cache.exists():
        data = json.loads(args.cache.read_text(encoding="utf-8"))
    else:
        data = fetch(lat0, lon0, args.radius, args.focus_way)
        if args.cache:
            args.cache.write_text(json.dumps(data), encoding="utf-8")

    terrain, center_amsl = Terrain.flat(), 0.0
    if args.terrain:
        half = args.radius + 60
        dem_cache = args.cache.with_name(args.cache.stem + "_dem.json") if args.cache else None
        if dem_cache and dem_cache.exists():
            dem = json.loads(dem_cache.read_text(encoding="utf-8"))
        else:
            dem = fetch_dem(lat0, lon0, half, args.terrain_step)
            if dem_cache:
                dem_cache.write_text(json.dumps(dem), encoding="utf-8")
        grid = smooth(min_filter(dem))
        mid = len(grid) // 2
        center_amsl = grid[mid][mid]
        terrain = Terrain(half, args.terrain_step, [[v - center_amsl for v in row] for row in grid])
        flat = [v for row in terrain.h for v in row]
        print(f"Arazi: {terrain.n}x{terrain.n} SRTM noktası, merkez {center_amsl:.1f} m AMSL, "
              f"yükseklik farkı {min(flat):+.1f} … {max(flat):+.1f} m")

    boxes, tris, roads, greens, home, stats = build(data, lat0, lon0, args.radius, args.focus_way, terrain)
    hlat, hlon, home_h = write_module(args.output, args.name, args.focus_label, lat0, lon0, args.radius,
                                      boxes, tris, roads, greens, home, terrain, center_amsl)
    print(f"Binalar: {stats['box']} kutu + {stats['tri']} üçgenlenmiş ({len(tris)} üçgen) + {stats['fallback']} yedek kutu; "
          f"odak alanında {stats['focus']} bina | {len(roads)} yol parçası | {len(greens)} yeşil üçgen")
    print(f"Kalkış noktası: {home[0]:.1f} m doğu, {home[1]:.1f} m kuzey, zemin {home_h:+.1f} m "
          f"({center_amsl + home_h:.1f} m AMSL) → {hlat:.6f}, {hlon:.6f}")
    print(f"Yazıldı: {args.output} ({args.output.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
