"""Recommended ArduCopter parameters for the TEI F450, derived from what the simulator showed.

ArduCopter 4.7 renamed several parameters to SI units (e.g. RTL_ALT [cm] -> RTL_ALT_M [m]); the exact set per
release was not verifiable, so names are never guessed: each setting lists candidate (name, scale) pairs and the
one present in the drone's own parameter dump is used. Without a dump, ArduCopter 4.6 names are written.
"""

from dataclasses import dataclass


@dataclass
class Setting:
    key: str
    value: float  # in SI units (m, m/s, s, V, ...), except where the unit says otherwise
    unit: str
    candidates: list  # [(param name, factor to multiply the SI value by)], newest names first
    reason: str


# Values: simulator findings (docs/CLAUDE.md) + ArduPilot guidance. Heights assume Bahçelievler (tallest
# building within 150 m of the pad ~21 m).
RECOMMENDED = [
    Setting("frame_class", 1, "", [("FRAME_CLASS", 1)], "Quad"),
    Setting("frame_type", 1, "", [("FRAME_TYPE", 1)], "X"),
    Setting("wp_speed", 6.0, "m/s", [("WP_SPD", 1), ("WPNAV_SPEED", 100)],
            "Simülasyon: 2,1 kg F450 10 m/s'de 4-5 m/s karşı rüzgârda yatış sınırına dayanıyor"),
    Setting("rtl_alt", 30.0, "m", [("RTL_ALT_M", 1), ("RTL_ALT", 100)],
            "Ped çevresinde 21 m bina var; 15 m (varsayılan) RTL binaya çarpar"),
    Setting("rtl_speed", 5.0, "m/s", [("RTL_SPD", 1), ("RTL_SPEED", 100)], "Eve dönüş rüzgâra karşı olabilir; pay bırak"),
    Setting("rtl_loit_time", 5.0, "s", [("RTL_LOIT_TIME", 1000)], "İnişten önce ev üstünde bekleme"),
    Setting("land_speed", 0.5, "m/s", [("LAND_SPD_FINAL", 1), ("LAND_SPEED", 100)], "Son iniş hızı"),
    Setting("angle_max", 30.0, "deg", [("ATC_ANGLE_MAX", 1), ("ANGLE_MAX", 100)], "ArduPilot varsayılanı; F450 için yeterli"),
    Setting("batt_monitor", 4, "", [("BATT_MONITOR", 1)], "Power Module V1.0: analog voltaj + akım"),
    Setting("batt_capacity", 5000, "mAh", [("BATT_CAPACITY", 1)], "4S 5000 mAh"),
    Setting("batt_arm_volt", 15.2, "V", [("BATT_ARM_VOLT", 1)], "3,8 V/hücre altında ARM etme"),
    Setting("batt_low_volt", 14.0, "V", [("BATT_LOW_VOLT", 1)], "3,5 V/hücre → RTL"),
    Setting("batt_crt_volt", 13.2, "V", [("BATT_CRT_VOLT", 1)], "3,3 V/hücre → LAND"),
    Setting("batt_low_timer", 10, "s", [("BATT_LOW_TIMER", 1)], "Tırmanıştaki anlık sarkma tetiklemesin"),
    Setting("batt_fs_low_act", 2, "", [("BATT_FS_LOW_ACT", 1)], "Düşük batarya → RTL"),
    Setting("batt_fs_crt_act", 1, "", [("BATT_FS_CRT_ACT", 1)], "Kritik batarya → LAND"),
    Setting("fence_enable", 1, "", [("FENCE_ENABLE", 1)], "Sanal sınır açık"),
    Setting("fence_type", 3, "", [("FENCE_TYPE", 1)], "İrtifa + çember"),
    Setting("fence_radius", 300, "m", [("FENCE_RADIUS", 1)], "Görüş hattı (VLOS) içinde kal"),
    Setting("fence_alt_max", 100, "m", [("FENCE_ALT_MAX", 1)], "SHGM sınırı 120 m; pay bırak"),
    Setting("fence_action", 1, "", [("FENCE_ACTION", 1)], "İhlalde RTL"),
    Setting("fs_gcs_enable", 1, "", [("FS_GCS_ENABLE", 1)],
            "RC yok: Wi-Fi/yer istasyonu koparsa tek güvence bu (5 sn → RTL). Simülasyonda doğrulandı"),
    Setting("fs_gcs_timeout", 5, "s", [("FS_GCS_TIMEOUT", 1)], "Yer istasyonu heartbeat zaman aşımı"),
    Setting("fs_thr_enable", 1, "", [("FS_THR_ENABLE", 1)], "RC alıcı takılınca: sinyal kaybında RTL"),
    Setting("disarm_delay", 10, "s", [("DISARM_DELAY", 1)], "İnişten sonra motorları durdur"),
    Setting("mot_hover_learn", 2, "", [("MOT_HOVER_LEARN", 1)], "Hover gazını öğren ve kaydet (sim tahmini %55)"),
    Setting("mot_thst_hover", 0.55, "", [("MOT_THST_HOVER", 1)], "Başlangıç değeri: simülasyon + montaj kılavuzu"),
    Setting("fs_crash_check", 1, "", [("FS_CRASH_CHECK", 1)], "Kaza sonrası motorları kes"),
    Setting("serial2_protocol", 2, "", [("SERIAL2_PROTOCOL", 1)], "Pi TELEM2: MAVLink2"),
    Setting("serial2_baud", 57, "", [("SERIAL2_BAUD", 1)], "57600 (tei_kopru ile aynı)"),
]

NOTES = [
    "RC alıcı yokken ArduPilot ARM öncesi RC kontrolleri nedeniyle ARM'ı reddedebilir; ARMING_CHECK'i gevşetmek yerine "
    "bir RC alıcı + kumanda takılması önerilir (FS_THR_ENABLE ancak o zaman anlamlı).",
    "Harmonik çentik filtresi (INS_HNTCH_*): ESC telemetrisi olmadığından MODE=1 (gaz tabanlı), INS_HNTCH_REF=MOT_THST_HOVER; "
    "frekans ilk uçuşun FFT/log analiziyle belirlenmeli — değer uydurulmadı.",
    "Bu dosya bir başlangıç önerisidir: yüklemeden önce Mission Planner/QGC'de parametreleri tek tek gözden geçirin.",
]


def parse_param_file(text):
    """Mission Planner (NAME,VALUE) or QGroundControl (sys comp NAME VALUE type) parameter dump -> {name: value}."""
    params = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "," in line:
            name, value = line.split(",")[:2]
        else:
            cols = line.split()
            if len(cols) >= 4 and cols[0].isdigit():
                name, value = cols[2], cols[3]
            elif len(cols) >= 2:
                name, value = cols[0], cols[1]
            else:
                continue
        try:
            params[name.strip()] = float(value)
        except ValueError:
            continue
    return params


def resolve(settings, available=None):
    """-> [(setting, param name or None, value in that parameter's units)]. `available`: names on the drone."""
    out = []
    for s in settings:
        chosen = None
        if available is not None:
            chosen = next(((n, f) for n, f in s.candidates if n in available), None)
        else:
            chosen = s.candidates[-1]  # oldest (4.6) name when there is nothing to check against
        out.append((s, chosen[0] if chosen else None, s.value * chosen[1] if chosen else None))
    return out


def fmt(v):
    return str(int(v)) if float(v).is_integer() else f"{v:.4g}"


def write_mission_planner(resolved, header):
    lines = [f"# {h}" for h in header]
    for s, name, value in resolved:
        if name:
            lines.append(f"{name},{fmt(value)}")
    return "\n".join(lines) + "\n"


def compare(resolved, current):
    """Rows (name, current, recommended, reason) where the drone differs or lacks the parameter."""
    rows = []
    for s, name, value in resolved:
        if not name:
            rows.append((s.candidates[0][0] + "?", None, s.value, "drone'da bu ayarın adı bulunamadı: " + s.reason))
        elif name not in current or abs(current[name] - value) > 1e-6 * max(1, abs(value)):
            rows.append((name, current.get(name), value, s.reason))
    return rows
