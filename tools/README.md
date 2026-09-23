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
