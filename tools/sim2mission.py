"""Convert a simulator flight (drone-sim-flight JSON) into a Pixhawk mission.

Example:
  python tools/sim2mission.py ucus.json --home 41.0422,29.0068 --firmware ardupilot

Writes ucus.plan (QGroundControl) and ucus.waypoints (Mission Planner / QGC).
--home MUST be the real GPS position where the drone will be armed: the whole
mission is placed relative to it.
"""

import argparse
import sys
from pathlib import Path

from dronebridge import flightfile, mission, safety


def parse_home(text):
    parts = [float(p) for p in text.split(",")]
    if len(parts) not in (2, 3) or not (-90 <= parts[0] <= 90 and -180 <= parts[1] <= 180):
        raise argparse.ArgumentTypeError("--home 'enlem,boylam[,irtifa_amsl]' olmalı, ör. 41.0422,29.0068")
    return mission.Home(*parts)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path, help="Simülatörden kopyalanan uçuş JSON dosyası")
    ap.add_argument("--home", type=parse_home,
                    help="Gerçek kalkış noktası: enlem,boylam[,amsl]. Gerçek harita (ör. Bahçelievler) kayıtlarında "
                         "dosyadaki home_geo kullanılır.")
    ap.add_argument("--firmware", choices=sorted(mission.FIRMWARE_TYPES), default="ardupilot")
    ap.add_argument("--format", choices=["plan", "waypoints", "both"], default="both")
    ap.add_argument("-o", "--output", type=Path, help="Çıktı dosya adı (uzantısız)")
    ap.add_argument("--end", choices=["auto", "rtl", "land"], default="auto",
                    help="auto: kayıt yerde bittiyse orada iner, yoksa eve döner (RTL)")
    ap.add_argument("--takeoff-alt", type=float, default=5.0, help="Kalkış irtifası (m)")
    ap.add_argument("--tolerance", type=float, default=1.5, help="Rota sadeleştirme hassasiyeti (m)")
    ap.add_argument("--max-alt", type=float, default=safety.Limits.max_alt_m)
    ap.add_argument("--max-distance", type=float, default=safety.Limits.max_distance_m)
    ap.add_argument("--max-speed", type=float, default=safety.Limits.max_speed_ms)
    ap.add_argument("--max-flight-min", type=float, default=safety.Limits.max_flight_min)
    ap.add_argument("--no-fence", action="store_true", help=".plan dosyasına geofence çemberi ekleme")
    args = ap.parse_args(argv)

    data = flightfile.load(args.input)
    if args.home is None:
        if not data.get("home_geo"):
            ap.error("--home gerekli (bu kayıt kurgusal haritadan, gerçek konum bilgisi yok)")
        args.home = mission.Home(*data["home_geo"])
        print(f"Home: simülasyon sahasının kalkış pedi {args.home.lat:.6f}, {args.home.lon:.6f} "
              f"({data.get('site')}). Drone'u tam bu noktadan kaldırın.")
    parsed = flightfile.parse(data, tolerance_m=args.tolerance)
    landed = parsed.landed_at_end
    end = args.end if args.end != "auto" else ("land" if landed else "rtl")
    waypoints, landing = flightfile.trim_vertical(parsed.waypoints, args.takeoff_alt, landed=(end == "land"))

    limits = safety.Limits(args.max_alt, args.max_distance, args.max_speed, max_flight_min=args.max_flight_min)
    findings = safety.check(waypoints or parsed.waypoints, limits, args.takeoff_alt)

    print(f"Kaynak: {parsed.source} | {parsed.raw_count} ham nokta -> {len(waypoints)} waypoint | bitiş: {end.upper()}")
    for f in findings:
        print(f"  [{f.level}] {f.message}")
    if any(f.level == "ERROR" for f in findings):
        print("Görev dosyası YAZILMADI. Uçuşu veya sınırları düzeltin.", file=sys.stderr)
        return 1

    items = mission.build_items(waypoints, args.home, args.takeoff_alt, end=end, land_at=landing,
                                max_speed=args.max_speed)

    base = args.output or args.input.with_suffix("")
    if args.format in ("plan", "both"):
        fence = None if args.no_fence else args.max_distance + 20
        path = base.with_suffix(".plan")
        path.write_text(mission.to_qgc_plan(items, args.home, args.firmware, fence_radius_m=fence), encoding="utf-8")
        print(f"Yazıldı: {path}")
    if args.format in ("waypoints", "both"):
        path = base.with_suffix(".waypoints")
        path.write_text(mission.to_wpl110(items, args.home), encoding="utf-8")
        print(f"Yazıldı: {path}")
    print("UYARI: Simülasyondaki binalar gerçek sahayı temsil etmez. Rotayı QGroundControl haritasında "
          "gerçek engellere karşı kontrol edin; ilk uçuşu açık alanda ve kumandada RC override hazırken yapın.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
