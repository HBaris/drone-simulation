"""Görev dosyası içe/dışa aktarma: QGroundControl WPL 110 (.waypoints) ve QGC .plan.

Qt kullanmaz (testi kolay). Böylece:
  - drone-simulation'daki `sim2mission.py` çıktısı TEI GCS'e açılıp gerçek drone'a yüklenebilir,
  - TEI'de çizilen görev Mission Planner / QGroundControl'e ve simülasyona taşınabilir.

İç biçim, tei_gcs.py'deki _gorev listesiyle aynıdır:
  {"frame", "cmd", "lat", "lon", "alt", "p1", "p2", "p3", "p4"}   (seq 0 = ev noktası)
"""

import json
import math
from pathlib import Path

NAV_WAYPOINT, NAV_LOITER_TIME, NAV_RTL, NAV_LAND, NAV_TAKEOFF = 16, 19, 20, 21, 22
DO_CHANGE_SPEED = 178
FRAME_GLOBAL, FRAME_MISSION, FRAME_REL = 0, 2, 3


def _num(v):
    """.plan NaN'ı null yazar; WPL'de 0 kullanılır."""
    return 0.0 if v is None or (isinstance(v, float) and math.isnan(v)) else float(v)


def oku(yol):
    """Dosyayı okur, öğe listesi döndürür (ilk öğe ev noktası)."""
    yol = Path(yol)
    metin = yol.read_text(encoding="utf-8-sig")
    if metin.lstrip().startswith("{"):
        return _oku_plan(json.loads(metin))
    return _oku_wpl(metin)


def _oku_wpl(metin):
    satirlar = [s for s in metin.splitlines() if s.strip()]
    if not satirlar or not satirlar[0].startswith("QGC WPL"):
        raise ValueError("QGC WPL 110 başlığı yok")
    ogeler = []
    for s in satirlar[1:]:
        c = s.split("\t") if "\t" in s else s.split()
        if len(c) < 12:
            raise ValueError(f"Bozuk satır: {s!r}")
        ogeler.append({"frame": int(c[2]), "cmd": int(c[3]), "p1": float(c[4]), "p2": float(c[5]),
                       "p3": float(c[6]), "p4": float(c[7]), "lat": float(c[8]), "lon": float(c[9]),
                       "alt": float(c[10])})
    return ogeler


def _oku_plan(plan):
    if plan.get("fileType") != "Plan":
        raise ValueError("QGroundControl .plan dosyası değil")
    m = plan["mission"]
    ev = m.get("plannedHomePosition") or [0, 0, 0]
    ogeler = [{"frame": FRAME_GLOBAL, "cmd": NAV_WAYPOINT, "p1": 0, "p2": 0, "p3": 0, "p4": 0,
               "lat": ev[0], "lon": ev[1], "alt": ev[2]}]
    for it in m["items"]:
        if it.get("type") != "SimpleItem":
            raise ValueError("Karmaşık görev öğeleri (survey vb.) desteklenmiyor")
        p = [_num(v) for v in it["params"]]
        ogeler.append({"frame": it["frame"], "cmd": it["command"], "p1": p[0], "p2": p[1], "p3": p[2],
                       "p4": p[3], "lat": p[4], "lon": p[5], "alt": p[6]})
    return ogeler


def yaz(yol, ogeler):
    """WPL 110 olarak yazar (Mission Planner, QGroundControl ve drone-simulation okur)."""
    satirlar = ["QGC WPL 110"]
    for seq, o in enumerate(ogeler):
        satirlar.append("\t".join([
            str(seq), "1" if seq == 0 else "0", str(o["frame"]), str(o["cmd"]),
            *(f"{_num(o.get(k, 0)):.6f}" for k in ("p1", "p2", "p3", "p4")),
            f"{o['lat']:.8f}", f"{o['lon']:.8f}", f"{o['alt']:.3f}", "1"]))
    Path(yol).write_text("\n".join(satirlar) + "\n", encoding="utf-8")


def haritaya(ogeler):
    """Öğe listesini TEI haritasının anladığı parçalara ayırır.

    Döner: (ev (lat, lon) | None, kalkış irtifası | None, [(lat, lon, alt), ...], uyarılar)
    Yalnız konumlu gezinti noktaları haritaya konur; hız değişimi, iniş vb. uyarı olarak bildirilir.
    """
    ev = (ogeler[0]["lat"], ogeler[0]["lon"]) if ogeler and (ogeler[0]["lat"] or ogeler[0]["lon"]) else None
    kalkis, noktalar, uyarilar = None, [], []
    for o in ogeler[1:]:
        if o["cmd"] == NAV_TAKEOFF:
            kalkis = o["alt"]
        elif o["cmd"] in (NAV_WAYPOINT, NAV_LOITER_TIME) and (o["lat"] or o["lon"]):
            if o["frame"] != FRAME_REL:
                uyarilar.append(f"Nokta {len(noktalar) + 1}: irtifa çerçevesi {o['frame']} (göreli değil)")
            noktalar.append((o["lat"], o["lon"], o["alt"]))
        elif o["cmd"] == NAV_RTL:
            pass  # TEI görevi zaten eve dönüşle bitirir
        elif o["cmd"] == DO_CHANGE_SPEED:
            uyarilar.append(f"Hız değişimi {o['p2']:.1f} m/s — TEI yüklerken uygulanmaz")
        elif o["cmd"] == NAV_LAND:
            uyarilar.append("Görev inişle bitiyor — TEI eve dönüşle bitirecek")
        else:
            uyarilar.append(f"Komut {o['cmd']} atlandı")
    return ev, kalkis, noktalar, uyarilar


def tei_gorevi(ev, kalkis_alt, noktalar, bekleme=2.0):
    """TEI'nin yüklediği görevin aynısı: ev, kalkış, noktalar (bekleme sn), eve dönüş."""
    ogeler = [{"frame": FRAME_GLOBAL, "cmd": NAV_WAYPOINT, "lat": ev[0], "lon": ev[1], "alt": 0.0},
              {"frame": FRAME_REL, "cmd": NAV_TAKEOFF, "lat": 0.0, "lon": 0.0, "alt": float(kalkis_alt)}]
    for lat, lon, alt in noktalar:
        ogeler.append({"frame": FRAME_REL, "cmd": NAV_WAYPOINT, "lat": lat, "lon": lon,
                       "alt": float(alt or kalkis_alt), "p1": bekleme})
    ogeler.append({"frame": FRAME_REL, "cmd": NAV_RTL, "lat": 0.0, "lon": 0.0, "alt": 0.0})
    return ogeler
