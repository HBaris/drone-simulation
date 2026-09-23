# TEI-Ground-Control eklentileri

TEI-Ground-Control (PySide6 + pymavlink yer istasyonu) için iki yeni modül ve küçük bir yama.
Asıl proje bu repoda değil (yerel `rasperiypi/TEI-Ground-Control/`); buradakiler sürüm takibi içindir.

| Dosya | Ne yapar |
|---|---|
| `tei_saglik.py` | **Sağlık** sekmesi: 4 motorun PWM çıkışı (üstten görünüş), hücre voltajları, harcanan mAh, titreşim, EKF, rüzgâr tahmini ve **hover teşhisi** (tek motor sorunu → itki kaybı %, CCW/CW farkı, itki payı). ESC telemetrisi gerekmez. |
| `tei_gorev_dosya.py` | Görev dosyası **içe/dışa aktarma**: QGC WPL 110 (`.waypoints`) ve QGC `.plan`. `sim2mission.py` çıktısı açılıp drone'a yüklenebilir; TEI'de çizilen görev Mission Planner / QGC / simülasyona taşınabilir. |
| `tei_kopru.patch` | **Güvenlik:** Pi köprüsü yalnız hedef PC'nin (ve `--izinli` verilenlerin) komutlarını Pixhawk'a iletir; diğer cihazlardan gelen paketler reddedilip loglanır. Eski davranış: `--herkese-acik`. |
| `tei_onerilen_ardupilot46.param` | `tools/make_params.py` çıktısı (drone dökümü olmadan, 4.6 adları). **4.7 için drone'un kendi parametre dökümüyle `--base` ile yeniden üretin.** |
| `tei_gcs.patch` | `tei_gcs.py` değişiklikleri: Telemetry'ye sağlık alanları, `_absorb` içinde SERVO_OUTPUT_RAW / BATTERY_STATUS / VIBRATION / EKF_STATUS_REPORT / WIND, "Sağlık" sekmesi, "Dosyadan Aç" / "Dosyaya Kaydet" butonları. |

Kurulum: iki `.py` dosyasını `tei_gcs.py` yanına kopyalayın, sonra `git apply tei_gcs.patch` (veya `patch -p1 < tei_gcs.patch`).
Orijinal dosyanın yedeği yerelde: `tei_gcs.py.yedek-20260923`.

Durum: Qt'siz mantık (`HoverAnaliz`, dosya okuma/yazma) `tools/tests/test_tei_integration.py` ile test edildi.
Arayüz kısmı yalnızca derlendi (`py_compile`); bu makinede PySide6 kurulu olmadığı için çalıştırılarak denenmedi —
`BASLAT.bat` ile açıp Sağlık sekmesine ve görev dosyası butonlarına bakılmalı.
