"""Local bridge: Roblox simulation <-> MAVLink ground stations (TEI-Ground-Control, QGroundControl, Mission Planner).

  Roblox Studio (BridgeLink.server)  --HTTP POST /sim/state (5 Hz)-->  this bridge  --UDP MAVLink-->  GCS :14550
                                     <--  pending sim commands  ---              <--  commands  ---

Run (Studio must allow HTTP requests; the bridge only listens on 127.0.0.1):
  python tools/mavlink_bridge.py                      # sends to udp 127.0.0.1:14550 (TEI GCS / QGC default)
  python tools/mavlink_bridge.py --gcs udpout:192.168.1.20:14550

In TEI-Ground-Control choose source "UDP" (udpin:0.0.0.0:14550) and connect: the simulator appears as an
ArduCopter 4.7 quad. Needs pymavlink (`pip install pymavlink`); a local copy is found automatically in
rasperiypi/TEI-Ground-Control/venv if present.
"""

import argparse
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def import_pymavlink():
    try:
        from pymavlink import mavutil  # noqa: F401
    except ImportError:
        local = ROOT.parent / "rasperiypi" / "TEI-Ground-Control" / "venv" / "Lib" / "site-packages"
        if local.exists():
            sys.path.append(str(local))
        os.environ.setdefault("MAVLINK20", "1")
    os.environ.setdefault("MAVLINK20", "1")
    from pymavlink import mavutil
    return mavutil


class Fanout:
    """File-like: every MAVLink packet the emulator writes goes to all links (GCS + monitors)."""

    def __init__(self, links):
        self.links = links

    def write(self, buf):
        for link in self.links:
            try:
                link.write(buf)
            except OSError:
                pass  # a listener that is not running yet


class Bridge:
    def __init__(self, gcs_url, home, esc_telemetry, extra_urls=()):
        mavutil = import_pymavlink()
        from dronebridge.mavsim import ArduCopterEmulator
        self.mavutil = mavutil
        self.links = [mavutil.mavlink_connection(url, source_system=1, source_component=1, dialect="ardupilotmega")
                      for url in (gcs_url, *extra_urls)]
        self.link = self.links[0]
        self.out = mavutil.mavlink.MAVLink(Fanout(self.links), srcSystem=1, srcComponent=1)
        self.home = home
        self.esc_telemetry = esc_telemetry
        self.emu = None if home is None else ArduCopterEmulator(self.out, *home, esc_telemetry=esc_telemetry)
        self.lock = threading.Lock()
        self.last_state_time = None
        self.running = True

    def ensure_emulator(self, state):
        if self.emu is None:
            geo = state.get("home_geo")
            if not geo:
                return False
            from dronebridge.mavsim import ArduCopterEmulator
            self.emu = ArduCopterEmulator(self.out, geo[0], geo[1], geo[2] if len(geo) > 2 else 0.0,
                                          esc_telemetry=self.esc_telemetry)
            print(f"[bridge] Home (simülasyon pedi): {geo}")
        return True

    def on_sim_state(self, state):
        with self.lock:
            if not self.ensure_emulator(state):
                return {"commands": [], "error": "home_geo yok (kurgusal harita?) — --home verin"}
            self.emu.update_state(state)
            self.last_state_time = time.monotonic()
            commands = self.emu.pop_commands()
            gcs_age = None if self.emu.gcs_last_heartbeat is None else time.monotonic() - self.emu.gcs_last_heartbeat
        for c in commands:
            print(f"[bridge] → sim: {c}")
        return {"commands": commands, "gcs_connected": gcs_age is not None and gcs_age < 3,
                "gcs_age": gcs_age}

    def receive(self):
        for link in self.links:
            try:
                msg = link.recv_match(blocking=False)
            except OSError:
                # Windows raises WinError 10022 on recvfrom before the UDP socket has sent anything,
                # and 10054 when the GCS port is closed; both just mean "nothing to read yet".
                msg = None
            if msg is not None:
                return msg
        return None

    def mavlink_loop(self):
        next_tick = time.monotonic()
        while self.running:
            msg = self.receive()
            while msg is not None:
                with self.lock:
                    if self.emu:
                        self.emu.handle(msg)
                msg = self.receive()
            now = time.monotonic()
            if now >= next_tick:
                next_tick = now + 0.1
                with self.lock:
                    fresh = self.last_state_time and now - self.last_state_time < 2
                    if self.emu and fresh:
                        self.emu.send_stream()
            time.sleep(0.005)


def make_handler(bridge):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/sim/state":
                self.send_error(404)
                return
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            try:
                reply = bridge.on_sim_state(json.loads(body))
                code = 200
            except Exception as exc:  # keep the bridge alive; report to Roblox
                reply, code = {"commands": [], "error": str(exc)}, 500
            data = json.dumps(reply).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            state = bridge.emu.state if bridge.emu else None
            data = json.dumps({"ok": True, "has_state": state is not None, "state": state}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass  # 5 requests/s would flood the console

    return Handler


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gcs", default="udpout:127.0.0.1:14550", help="pymavlink connection string to the ground station")
    ap.add_argument("--also", action="append", default=[],
                    help="extra MAVLink output, e.g. udpout:127.0.0.1:14551 for tools/health_monitor.py (repeatable)")
    ap.add_argument("--http-port", type=int, default=34874)
    ap.add_argument("--home", help="lat,lon,amsl — only for sites without home_geo")
    ap.add_argument("--esc-telemetry", action="store_true",
                    help="send ESC_TELEMETRY_1_TO_4 (the TEI drone's PWM ESCs cannot; off by default)")
    args = ap.parse_args(argv)
    home = tuple(float(v) for v in args.home.split(",")) if args.home else None

    sys.path.insert(0, str(ROOT))
    bridge = Bridge(args.gcs, home, args.esc_telemetry, args.also)
    threading.Thread(target=bridge.mavlink_loop, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", args.http_port), make_handler(bridge))
    print(f"[bridge] Roblox → http://127.0.0.1:{args.http_port}/sim/state   |   MAVLink → {', '.join([args.gcs, *args.also])}")
    print("[bridge] Studio'da Play'e basın; TEI-Ground-Control'de kaynak: UDP, bağlan.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        bridge.running = False
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
