"""Read the simulator's `drone-sim-flight` JSON and turn it into airborne waypoints.

Format (version 1), written by src/shared/FlightPackage.luau:
  {"format": "drone-sim-flight", "version": 1, "source": "manual_recording" | "waypoint_route",
   "frame": "ENU_m_relative_to_home",
   "columns": ["t", "e", "n", "u", "hdg"], "samples": [[t, e, n, u, hdg], ...],   # recording
   "waypoints": [{"e": .., "n": .., "u": .., "speed": ..}, ...]}                  # route
"""

import json
from dataclasses import dataclass
from math import hypot

from .simplify import Waypoint, recording_to_waypoints

FORMAT_NAME = "drone-sim-flight"
GROUND_ALT_M = 1.0  # below this (relative to home) the drone counts as landed


@dataclass
class ParsedFlight:
    source: str
    waypoints: list  # airborne waypoints, takeoff/landing excluded
    landed_at_end: bool
    duration_s: float
    raw_count: int


def load(path):
    # utf-8-sig: files pasted into Windows Notepad often start with a BOM.
    with open(path, encoding="utf-8-sig") as fh:
        data = json.load(fh)
    if data.get("format") != FORMAT_NAME:
        raise ValueError(f"Beklenen format '{FORMAT_NAME}', gelen: {data.get('format')!r}")
    if data.get("version") != 1:
        raise ValueError(f"Desteklenmeyen sürüm: {data.get('version')!r}")
    return data


def parse(data, tolerance_m=1.5, hover_min_s=2.0):
    if data["source"] == "manual_recording":
        samples = data["samples"]
        airborne = [i for i, s in enumerate(samples) if s[3] >= GROUND_ALT_M]
        if not airborne:
            return ParsedFlight("manual_recording", [], False, 0.0, len(samples))
        first, last = airborne[0], airborne[-1]
        flight = samples[first:last + 1]
        waypoints = recording_to_waypoints(flight, tolerance_m, hover_min_s)
        duration = samples[-1][0] - samples[0][0]
        return ParsedFlight("manual_recording", waypoints, last < len(samples) - 1, duration, len(samples))

    if data["source"] == "waypoint_route":
        waypoints = [Waypoint(w["e"], w["n"], w["u"], w.get("speed")) for w in data["waypoints"]]
        return ParsedFlight("waypoint_route", waypoints, False, 0.0, len(waypoints))

    raise ValueError(f"Bilinmeyen kaynak: {data['source']!r}")


def trim_vertical(waypoints, takeoff_alt, landed, radius_m=2.0):
    """Drop the recorded climb above home and the final descent; TAKEOFF / LAND do those.

    Returns (waypoints, landing_point). landing_point is the last recorded point.
    """
    if not waypoints:
        return [], None
    landing = waypoints[-1]
    wps = list(waypoints)

    # Leading climb-out above home: keep only its top, and only if above takeoff altitude.
    run = 0
    while run < len(wps) and hypot(wps[run].east, wps[run].north) < radius_m:
        run += 1
    if run:
        top = wps[run - 1]
        wps = ([top] if top.up > takeoff_alt else []) + wps[run:]

    # Trailing descent onto the landing spot: keep only the point where it started.
    run = 0
    while landed and run < len(wps) and hypot(wps[-1 - run].east - landing.east, wps[-1 - run].north - landing.north) < radius_m:
        run += 1
    if run > 1:
        wps = wps[:len(wps) - run + 1]
    return wps, landing
