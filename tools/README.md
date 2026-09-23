# tools/ — Simülasyon → Pixhawk köprüsü

```bash
python tools/sim2mission.py ucus.json --home 41.0422,29.0068 --firmware ardupilot
```

- Girdi: simülatörden kopyalanan `drone-sim-flight` JSON (manuel kayıt veya rota).
- Çıktı: `ucus.plan` (QGroundControl) ve `ucus.waypoints` (Mission Planner / QGC).
- `--home`: drone'un sahada kalkacağı gerçek GPS konumu. Tüm görev buna göre yerleşir.
- Güvenlik sınırları: `--max-alt 120 --max-distance 500 --max-speed 12 --max-flight-min 8`.
  ERROR varsa dosya yazılmaz.
- Testler: `python -m unittest discover -s tools/tests`

Sadece Python standart kütüphanesi gerekir.

## MAVLink köprüsü (simülasyon ↔ yer istasyonu)

```bash
python tools/mavlink_bridge.py            # Studio Play + Allow HTTP Requests açık olmalı
python tools/gcs_smoketest.py             # TEI-Ground-Control'ün yaptıklarını sırayla dener
```
TEI-Ground-Control, QGroundControl veya Mission Planner'da UDP 14550'e bağlanın; simülasyon ArduCopter 4.7 quad olarak görünür.
`pymavlink` gerekir (`pip install pymavlink`).

## Sağlık izleyici (salt okunur)

```bash
python tools/mavlink_bridge.py --also udpout:127.0.0.1:14551   # simülasyon: GCS + izleyici
python tools/health_monitor.py --label "yeni pervaneler"         # oturum raporu + geçmişle kıyas
```
Gerçek drone'da: `--url udpin:0.0.0.0:14550` (GCS kapalıyken) veya Pi'de `--url /dev/serial0 --baud 57600`.

## Engel kontrolü

```bash
python tools/check_mission.py gorev.waypoints --map scripts/maps/Bahcelievler.luau
```
Rota binalara/araziye `--clearance` (varsayılan 5 m) kadar yaklaşırsa çakışmaları listeler ve 1 ile çıkar.
`sim2mission.py` bilinen bir sahanın kaydını dönüştürürken bu kontrolü otomatik yapar.
