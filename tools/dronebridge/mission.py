"""Build MAVLink mission items and write them as QGroundControl .plan / WPL 110 .waypoints.

Both files load in QGroundControl and Mission Planner and upload to a Pixhawk
running ArduPilot or PX4. Altitudes are relative to home (MAV_FRAME_GLOBAL_RELATIVE_ALT),
so the mission flies the same shape wherever the drone is armed.
"""

import json
from dataclasses import dataclass, field

from .geo import enu_to_geodetic

# MAVLink constants
MAV_CMD_NAV_WAYPOINT = 16
MAV_CMD_NAV_RETURN_TO_LAUNCH = 20
MAV_CMD_NAV_LAND = 21
MAV_CMD_NAV_TAKEOFF = 22
MAV_CMD_DO_CHANGE_SPEED = 178
MAV_FRAME_GLOBAL = 0
MAV_FRAME_MISSION = 2
MAV_FRAME_GLOBAL_RELATIVE_ALT = 3
MAV_TYPE_QUADROTOR = 2
FIRMWARE_TYPES = {"ardupilot": 3, "px4": 12}

NAN = float("nan")


@dataclass
class Home:
    lat: float
    lon: float
    amsl: float = 0.0  # home altitude above mean sea level (only informative for relative missions)


@dataclass
class MissionItem:
    command: int
    frame: int
    params: list = field(default_factory=lambda: [0.0] * 7)


def _position_item(command, wp, home, p1=0.0):
    lat, lon, _ = enu_to_geodetic(wp.east, wp.north, 0.0, home.lat, home.lon)
    return MissionItem(command, MAV_FRAME_GLOBAL_RELATIVE_ALT, [p1, 0.0, 0.0, NAN, lat, lon, round(wp.up, 2)])


def _speed_item(speed):
    return MissionItem(MAV_CMD_DO_CHANGE_SPEED, MAV_FRAME_MISSION, [1.0, speed, -1.0, 0.0, 0.0, 0.0, 0.0])


def build_items(waypoints, home, takeoff_alt, end="rtl", land_at=None, max_speed=12.0, speed_step=1.0):
    """waypoints: list[simplify.Waypoint] (airborne part only). end: 'rtl' | 'land'.

    land_at: where to land for end='land' (defaults to the last waypoint). Only its
    horizontal position is used; LAND descends vertically from the previous item.
    """
    items = [MissionItem(MAV_CMD_NAV_TAKEOFF, MAV_FRAME_GLOBAL_RELATIVE_ALT,
                         [0.0, 0.0, 0.0, NAN, home.lat, home.lon, round(takeoff_alt, 2)])]
    current_speed = None
    for wp in waypoints:
        if wp.speed is not None:
            speed = round(min(max(wp.speed, 1.0), max_speed) * 2) / 2
            if current_speed is None or abs(speed - current_speed) >= speed_step:
                items.append(_speed_item(speed))
                current_speed = speed
        items.append(_position_item(MAV_CMD_NAV_WAYPOINT, wp, home, p1=round(wp.hold_s, 1)))

    land_at = land_at or (waypoints[-1] if waypoints else None)
    if end == "land" and land_at:
        items.append(_position_item(MAV_CMD_NAV_LAND, land_at, home))
    else:
        items.append(MissionItem(MAV_CMD_NAV_RETURN_TO_LAUNCH, MAV_FRAME_MISSION))
    return items


def to_qgc_plan(items, home, firmware="ardupilot", cruise_speed=5.0, fence_radius_m=None):
    plan_items = []
    for i, item in enumerate(items, start=1):
        plan_items.append({
            "type": "SimpleItem",
            "autoContinue": True,
            "command": item.command,
            "doJumpId": i,
            "frame": item.frame,
            "params": [None if p != p else p for p in item.params],  # NaN -> null
        })
    fence = {"circles": [], "polygons": [], "version": 2}
    if fence_radius_m:
        fence["circles"].append({
            "circle": {"center": [home.lat, home.lon], "radius": fence_radius_m},
            "inclusion": True,
            "version": 1,
        })
    plan = {
        "fileType": "Plan",
        "version": 1,
        "groundStation": "QGroundControl",
        "geoFence": fence,
        "rallyPoints": {"points": [], "version": 2},
        "mission": {
            "version": 2,
            "firmwareType": FIRMWARE_TYPES[firmware],
            "vehicleType": MAV_TYPE_QUADROTOR,
            "cruiseSpeed": cruise_speed,
            "hoverSpeed": cruise_speed,
            "globalPlanAltitudeMode": 1,
            "plannedHomePosition": [home.lat, home.lon, home.amsl],
            "items": plan_items,
        },
    }
    return json.dumps(plan, indent=2)


def to_wpl110(items, home):
    def fmt(v):
        return "0" if v != v else f"{v:.8f}".rstrip("0").rstrip(".")

    lines = ["QGC WPL 110",
             f"0\t1\t{MAV_FRAME_GLOBAL}\t{MAV_CMD_NAV_WAYPOINT}\t0\t0\t0\t0\t"
             f"{fmt(home.lat)}\t{fmt(home.lon)}\t{fmt(home.amsl)}\t1"]
    for seq, item in enumerate(items, start=1):
        params = "\t".join(fmt(p) for p in item.params)
        lines.append(f"{seq}\t0\t{item.frame}\t{item.command}\t{params}\t1")
    return "\n".join(lines) + "\n"
