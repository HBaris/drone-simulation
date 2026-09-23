"""Check any mission file (.waypoints / .plan — from sim2mission, TEI GCS, QGC, Mission Planner) against a
mapped site's buildings and terrain before flying it.

  python tools/check_mission.py gorev.waypoints --map scripts/maps/Bahcelievler.luau
  python tools/check_mission.py gorev.plan --map scripts/maps/Bahcelievler.luau --clearance 8 --rtl-alt 30

Exit code 1 when the path comes closer than --clearance to a roof or the ground.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from dronebridge import obstacles  # noqa: E402


def report(site, home, items, clearance, rtl_alt):
    segments = obstacles.mission_path(items, home, rtl_alt, site)
    conflicts = obstacles.check(site, segments, clearance)
    home_amsl = home[2] or site.ground_amsl(*site.to_enu(home[0], home[1]))
    print(f"Engel kontrolü: {len(segments)} rota parçası, {len(site.buildings)} bina parçası, emniyet payı {clearance:.0f} m, "
          f"RTL {rtl_alt:.0f} m")
    for c in obstacles.summarize(conflicts):
        need = c.obstacle_top_amsl + clearance - home_amsl  # relative altitude that would clear it
        print(f"  ✗ {c.phase}: {c.obstacle} çatısı {c.obstacle_top_amsl:.1f} m AMSL, drone {c.drone_amsl:.1f} m "
              f"({c.shortfall + clearance:.1f} m eksik pay) @ {c.lat:.6f}, {c.lon:.6f} → en az ~{need:.0f} m göreli irtifa")
    if not conflicts:
        print("  ✓ Rota haritadaki binalardan ve araziden emniyet payı kadar uzak.")
    print("  (OSM: ağaç, direk, elektrik hattı yok; yüksekliği bilinmeyen binalar 12 m sayıldı — sahada da kontrol edin.)")
    return conflicts


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mission", type=Path)
    ap.add_argument("--map", type=Path, required=True, help="scripts/maps/<Site>.luau")
    ap.add_argument("--clearance", type=float, default=5.0, help="m above roofs / ground")
    ap.add_argument("--rtl-alt", type=float, default=30.0, help="RTL_ALT on the drone (m)")
    args = ap.parse_args(argv)
    site = obstacles.SiteMap.load(args.map)
    home, items = obstacles.read_mission_file(args.mission)
    return 1 if report(site, home, items, args.clearance, args.rtl_alt) else 0


if __name__ == "__main__":
    sys.exit(main())
