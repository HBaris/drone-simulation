"""Live drone health monitor (read-only: it never sends anything to the vehicle).

  python tools/health_monitor.py                               # simulator: bridge started with --also udpout:127.0.0.1:14551
  python tools/health_monitor.py --url udpin:0.0.0.0:14550     # real drone via tei_kopru (close the GCS first)
  python tools/health_monitor.py --url /dev/serial0 --baud 57600   # on the Raspberry Pi (use mavlink-router to share)

Prints a report every few seconds; on exit (Ctrl+C or --duration) saves the session to the history file
and compares hover throttle with earlier sessions (wear trend).
"""

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mavlink_bridge  # noqa: E402
from dronebridge import health  # noqa: E402

ICON = {"OK": "✅", "WARN": "⚠️ ", "BAD": "❌", "INFO": "ℹ️ "}


def print_report(findings, header):
    print("\n" + header)
    for f in findings:
        print(f"  {ICON.get(f.level, '  ')} [{f.topic}] {f.message}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default="udpin:0.0.0.0:14551")
    ap.add_argument("--baud", type=int, default=57600)
    ap.add_argument("--capacity", type=float, default=5000, help="battery mAh")
    ap.add_argument("--duration", type=float, default=0, help="seconds to run (0 = until Ctrl+C)")
    ap.add_argument("--interval", type=float, default=10, help="seconds between reports")
    ap.add_argument("--history", default=str(Path(__file__).resolve().parent.parent / ".cache" / "health_history.json"))
    ap.add_argument("--label", default="", help="note stored with the session (e.g. 'yeni pervaneler')")
    args = ap.parse_args(argv)

    mavutil = mavlink_bridge.import_pymavlink()
    link = mavutil.mavlink_connection(args.url, baud=args.baud, source_system=254, source_component=190)
    monitor = health.HealthMonitor(capacity_mah=args.capacity)
    print(f"Dinleniyor: {args.url} (salt okunur)")
    start = time.time()
    last_report = start
    try:
        while not args.duration or time.time() - start < args.duration:
            try:
                msg = link.recv_match(blocking=True, timeout=0.5)
            except OSError:
                msg = None
            if msg is not None:
                monitor.update(msg)
            if time.time() - last_report >= args.interval:
                last_report = time.time()
                print_report(monitor.report(), f"— {time.strftime('%H:%M:%S')} · uçuş {monitor.s.flight_seconds:.0f} sn · "
                                               f"{len(monitor.s.hover)} hover örneği —")
    except KeyboardInterrupt:
        pass

    findings = monitor.report()
    history = health.load_history(args.history)
    session = monitor.session_summary()
    session["label"] = args.label
    trend = health.compare_history(history, session)
    if trend:
        findings.append(trend)
    print_report(findings, "=== OTURUM RAPORU ===")
    if session["hover"]:
        history.append(session)
        health.save_history(args.history, history)
        print(f"Oturum kaydedildi: {args.history} ({len(history)} oturum)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
