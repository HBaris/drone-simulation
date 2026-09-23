"""WGS84 coordinate conversions between the simulator's local ENU frame and GPS.

The simulator exports positions in meters East/North/Up relative to the home
(launch) point. On the real field the home point is the drone's actual GPS
position, so every mission point is re-anchored there. Conversion goes through
ECEF, so it stays accurate for long (multi-km) routes as well.
"""

from math import atan2, cos, degrees, hypot, radians, sin, sqrt

WGS84_A = 6378137.0
WGS84_F = 1 / 298.257223563
WGS84_E2 = WGS84_F * (2 - WGS84_F)


def geodetic_to_ecef(lat_deg, lon_deg, h):
    lat, lon = radians(lat_deg), radians(lon_deg)
    n = WGS84_A / sqrt(1 - WGS84_E2 * sin(lat) ** 2)
    x = (n + h) * cos(lat) * cos(lon)
    y = (n + h) * cos(lat) * sin(lon)
    z = (n * (1 - WGS84_E2) + h) * sin(lat)
    return x, y, z


def ecef_to_geodetic(x, y, z):
    lon = atan2(y, x)
    p = hypot(x, y)
    lat = atan2(z, p * (1 - WGS84_E2))
    h = 0.0
    for _ in range(10):
        n = WGS84_A / sqrt(1 - WGS84_E2 * sin(lat) ** 2)
        h = p / cos(lat) - n
        lat = atan2(z, p * (1 - WGS84_E2 * n / (n + h)))
    return degrees(lat), degrees(lon), h


def enu_to_geodetic(east, north, up, lat0, lon0, h0=0.0):
    """Local ENU offset (m) from (lat0, lon0, h0) -> (lat, lon, ellipsoid height)."""
    x0, y0, z0 = geodetic_to_ecef(lat0, lon0, h0)
    sl, cl = sin(radians(lat0)), cos(radians(lat0))
    so, co = sin(radians(lon0)), cos(radians(lon0))
    dx = -so * east - sl * co * north + cl * co * up
    dy = co * east - sl * so * north + cl * so * up
    dz = cl * north + sl * up
    return ecef_to_geodetic(x0 + dx, y0 + dy, z0 + dz)


def geodetic_to_enu(lat, lon, h, lat0, lon0, h0=0.0):
    x, y, z = geodetic_to_ecef(lat, lon, h)
    x0, y0, z0 = geodetic_to_ecef(lat0, lon0, h0)
    dx, dy, dz = x - x0, y - y0, z - z0
    sl, cl = sin(radians(lat0)), cos(radians(lat0))
    so, co = sin(radians(lon0)), cos(radians(lon0))
    east = -so * dx + co * dy
    north = -sl * co * dx - sl * so * dy + cl * dz
    up = cl * co * dx + cl * so * dy + sl * dz
    return east, north, up
