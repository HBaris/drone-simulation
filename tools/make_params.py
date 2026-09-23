"""Starter ArduCopter parameter file for the TEI F450, from the simulator's findings.

  python tools/make_params.py --base drone.param -o tei_onerilen.param   # names/units from the drone's own dump
  python tools/make_params.py --compare drone.param                       # what differs on the drone
  python tools/make_params.py -o tei_onerilen.param                       # no dump: ArduCopter 4.6 names (warns)

Get drone.param from Mission Planner (Config > Full Parameter List > Save) or QGroundControl
(Parameters > Tools > Save to file). Load the result with "Load from file" and review before writing.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from dronebridge import params  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", type=Path, help="parameter dump from the drone (Mission Planner or QGC format)")
    ap.add_argument("--compare", type=Path, help="only show where the drone differs from the recommendation")
    ap.add_argument("-o", "--output", type=Path, help="write a Mission Planner .param file")
    args = ap.parse_args(argv)

    dump_path = args.compare or args.base
    current = params.parse_param_file(dump_path.read_text(encoding="utf-8-sig")) if dump_path else None
    resolved = params.resolve(params.RECOMMENDED, set(current) if current is not None else None)

    if current is None:
        print("UYARI: drone parametre dökümü verilmedi → ArduCopter 4.6 adları yazılıyor. ArduCopter 4.7 bazı adları "
              "SI birimlere geçirdi (ör. RTL_ALT[cm] → RTL_ALT_M[m]); drone'un dökümüyle (--base) tekrar üretin.")
    missing = [s for s, name, _ in resolved if name is None]
    for s in missing:
        print(f"  ! '{s.key}' için drone'da uygun ad yok (adaylar: {', '.join(n for n, _ in s.candidates)})")

    if args.compare:
        rows = params.compare(resolved, current)
        print(f"{'Parametre':<18} {'Drone':>10} {'Öneri':>10}  Neden")
        for name, cur, rec, reason in rows:
            print(f"{name:<18} {'-' if cur is None else params.fmt(cur):>10} {params.fmt(rec):>10}  {reason}")
        print(f"{len(rows)} fark · {len(resolved) - len(rows)} parametre zaten önerilen değerde")

    if args.output:
        header = ["TEI F450 başlangıç parametreleri — drone-simulation/tools/make_params.py",
                  "Kaynak: simülasyon bulguları (CLAUDE.md) + ArduPilot önerileri. Yüklemeden önce gözden geçirin.",
                  f"Ad kümesi: {'drone dökümü ' + str(dump_path) if dump_path else 'ArduCopter 4.6 (doğrulanmadı)'}",
                  *params.NOTES]
        args.output.write_text(params.write_mission_planner(resolved, header), encoding="utf-8")
        print(f"Yazıldı: {args.output} ({len(resolved) - len(missing)} parametre)")
    for note in params.NOTES:
        print("Not: " + note)
    return 0


if __name__ == "__main__":
    sys.exit(main())
