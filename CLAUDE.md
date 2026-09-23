# Claude Code Notları ve Yol Haritası

Bu dosya Claude Code tarafından doldurulacaktır. Antigravity'nin bıraktığı mevcut durum ve mimari detaylar için lütfen `ANTIGRAVITY_HANDOFF.md` dosyasını inceleyiniz.

---

## 📋 İlerleme — Yapılanlar / Yapılacaklar
> Her aşama bitince burası güncellenir. ✅ bitti · 🔄 sürüyor · ⏳ sırada

**Tamamlanan aşamalar**
- ✅ A1 · Uçuş kaydedici + `sim2mission.py` (.plan/.waypoints, güvenlik kontrolleri) — commit c373029
- ✅ A2 · ArduPilot tarzı otopilot (AUTO/RTL/LAND, failsafe), motor/batarya sağlık modeli, çarpışma — c373029
- ✅ A3 · Gerçek Bahçelievler haritası (OSM), Studio'da hastane çevresi test uçuşu — c373029
- ✅ A4 · SRTM arazi, canlı rüzgâr (METAR LTBA), TEI F450 profili — b9e8666

**TEI entegrasyonu (öneri listesi, sırayla)**
- ✅ T1 · MAVLink köprüsü: simülasyon UDP 14550'de ArduCopter 4.7 gibi görünür, TEI-Ground-Control değiştirilmeden uçurur
  (Studio'da doğrulandı: GUIDED→ARM→kalkış 15 m, gövde hız komutu, TEI biçimi görev yükleme + AUTO + RTL,
  motor testi PWM, GCS kopunca 5 sn'de RTL)
- ✅ T2 · Sağlık servisi (`tools/health_monitor.py` + `dronebridge/health.py`): hover motor dengesi, tek motor teşhisi
  (verim kaybı yüzdesi), CCW/CW, ağırlık merkezi, itki payı, doyma, iç direnç, hücreler, kalan süre, titreşim/EKF/GPS,
  oturum geçmişi (yıpranma). Studio'da doğrulandı: SIM_ENGINE_MUL=0.85 ile M2 → "≈%14 itki kaybı (verim 0.86)";
  iç direnç 35 mΩ (model 35 mΩ)
- ✅ T3 · TEI GCS'e "Sağlık" sekmesi (motor PWM, hücreler, titreşim, EKF, rüzgâr, hover teşhisi) + .waypoints/.plan
  içe/dışa aktarma. Kaynak: `integrations/tei-ground-control/` (modüller + `tei_gcs.patch`), yerelde uygulandı,
  yedek `tei_gcs.py.yedek-20260923`. Qt'siz mantık test edildi; **arayüz PySide6 olmadığı için çalıştırılamadı**
  (kullanıcı `BASLAT.bat` ile denemeli)
- ✅ T4 · `tools/make_params.py`: simülasyon bulgularından başlangıç parametreleri (WP 6 m/s, RTL 30 m, batarya/fence/
  GCS failsafe…). 4.7 adları tahmin edilmez: drone dökümü (`--base`) hangi adı içeriyorsa o ad + doğru birim kullanılır;
  `--compare` farkları listeler. Simülasyon da bu değerlere çekildi (6 m/s, RTL 30 m, ANGLE_MAX 30°).
- ✅ T5 · `tei_kopru.py`: yalnız hedef PC (+ `--izinli`) IP'sinden gelen komutlar Pixhawk'a gider, diğerleri reddedilir
  ve loglanır (test edildi). Asıl koruma için MAVLink2 imzalama önerildi; GCS failsafe parametrede ve simülasyonda.

**Sıradaki öneriler**
- ⏳ N1 · GPS/konum gürültüsü ve kentsel multipath simülasyonu (şu an hover 0,03 m — gerçekte ±1–2 m)
- ✅ N2 · Görev öncesi engel kontrolü (`dronebridge/obstacles.py`, `tools/check_mission.py`): rota ArduCopter'ın uçtuğu
  gibi (dikey kalkış, düz bacaklar, RTL tırmanış/dönüş/iniş) 1 m adımla harita binaları + SRTM araziye karşı taranır.
  `sim2mission.py` kaydın sahası biliniyorsa otomatik kontrol eder, çakışmada dosya yazmaz. Doğrulama: Studio'da
  binaya çarpan fırtına rotası reddedildi, şovdaki 40 m hastane turu temiz, aynı tur 15 m'de reddedildi.
- ✅ N3 · TEI GCS kullanıcının makinesinde açıldı (venv yeniden kuruldu), UDP ile simülasyona bağlandı, Sağlık sekmesi
  gerçek veriyle doldu (motorlar, hücreler). Havada teşhis satırı henüz uçurulmadı (aynı mantık testlerle doğrulandı).
  Kalan küçük kusur: TEI'nin kendi buton yerleşiminde pencere yüksekliği yetmeyince yazılar kesiliyor.
- ⏳ N4 · Şarj istasyonları arası otomatik rota planlayıcı (batarya modeli + istasyon grafiği)

---

## 📝 Claude Code Geliştirme Notları

<!-- Claude Code buraya yapacağı geliştirmeleri, uçuş kayıt mimarisini ve donanım aktarım notlarını ekleyebilir -->

### Donanım: "TEI F450 Otonom Devriye İHA" (kaynak: yerel `rasperiypi/` klasörü, repoya dahil değil)
- Pixhawk 2.4.8 klon (fmuv3), **ArduCopter 4.7.0** (4.7'de parametreler SI birime geçti: WPNAV_SPEED→WP_SPD vb.)
- F450 Quad-X, 4× MT2808 (KV bilinmiyor), 10" 3 kanatlı pervane, Skywalker 30 A **PWM ESC (telemetri yok)**
- 4S 5000 mAh, Power Module V1.0 (90 A analog akım), M8N GPS + I2C pusula, AUW ~2,1 kg, T/W ~1,8
- Raspberry Pi 5 8 GB ↔ TELEM2 UART 57600 (SERIAL2_PROTOCOL=2), kendi UDP köprüsü `tei_kopru.py` → PC UDP 14550,
  telefon hotspot'u üzerinden Wi-Fi. RC alıcı YOK, telemetri radyosu YOK. IMX500 AI kamera + Storm32 gimbal.
- Yer istasyonu: `TEI-Ground-Control` (PySide6 + pymavlink): HEARTBEAT/ATTITUDE/VFR_HUD/GLOBAL_POSITION_INT/
  SYS_STATUS/GPS_RAW_INT okur; motor başına veri, EKF, titreşim, BATTERY_STATUS göstermez; görev dosyası içe/dışa aktarma yok.
- `DroneConfig.AIRFRAME` bu drone'a göre ayarlandı (hover ~%55, ~9 dk kullanılabilir uçuş tahmini).

### Simülasyon → Gerçek Drone Akışı (v1, panoya kopyalama)
1. **Manuel uçuş**: FPV modunda `R` → kayıt başlar (10 Hz). Tekrar `R` → kayıt biter, "sim-flight" JSON'u penceresi açılır.
   `P` → son kaydı simülasyonda birebir tekrar oynatır.
   **Rota**: Editörde waypoint'leri koy → `🛰 GERÇEK DRONE'A AKTAR (Pixhawk)`.
2. Metni kopyala → `ucus.json` olarak kaydet.
3. `python tools/sim2mission.py ucus.json --home <enlem>,<boylam> --firmware ardupilot|px4`
   → `ucus.plan` + `ucus.waypoints`. `--home` = drone'un sahada **gerçekten kalkacağı** GPS noktası.
4. QGroundControl / Mission Planner ile Pixhawk'a yükle, haritada kontrol et, uç.

Tasarım kararları:
- Sim koordinatları **kalkış pedine göre** (DroneConfig.HOME) metre ENU'dur; Roblox İstanbul'u ölçekli değildir
  (Boğaz ≈ 690 m), bu yüzden rotalar gerçek İstanbul koordinatlarına değil sahadaki home noktasına oturtulur.
- GPS dönüşümü, sadeleştirme (RDP + hover tespiti), güvenlik kontrolleri Python'da (`tools/dronebridge/`) tek yerde;
  gelecekteki köprü sunucusu ve RPi yükleyicisi aynı çekirdeği kullanacak. Testler:
  `python -m unittest discover -s tools/tests`
- Güvenlik: 120 m irtifa, 500 m uzaklık, home altına inme → ERROR (dosya yazılmaz). Sınırlar CLI parametresi.
  `.plan` dosyasına home merkezli geofence çemberi eklenir.
- Kayıtta pilot yan/geri uçsa bile gerçek drone varsayılan olarak gidiş yönüne bakar (waypoint yaw = NaN).

### Uçuş Modları & Sağlık (ArduPilot davranışını taklit eder)
- Modlar: MANUAL · AUTO (TAKEOFF → düz bacaklar → RTL) · RTL (tırman RTL_ALT → eve düz → 5 sn bekle → in) · LAND · CRASHED.
  Parametreler ArduPilot adlarıyla `DroneConfig.AUTOPILOT` / `FAILSAFE`'de.
- Failsafe: düşük batarya (10 sn) → RTL, kritik → LAND, geofence 300 m / 100 m → RTL (ihlal başına bir kez).
- Pilot devralma: AUTO/RTL/LAND sırasında herhangi bir stick tuşu → MANUAL.
- Motor modeli (`DroneHealthModel`): ArduPilot Quad-X numaralandırma (M1 ön-sağ CCW, M2 arka-sol CCW, M3 ön-sol CW,
  M4 arka-sağ CW), her motor için çıkış %, RPM, akım, sıcaklık, doygunluk; 4S LiPo voltaj sarkması + mAh.
  Telemetri alanları MAVLink karşılıklarını yansıtır (SERVO_OUTPUT_RAW, ESC_TELEMETRY_1_TO_4, BATTERY_STATUS);
  köprü kurulunca HealthPanel gerçek drone verisini gösterecek.
- Çarpışma: raycast ile bina/kule/su/sert iniş tespiti → CRASHED. Arıza enjeksiyonu: K (motor-1), B (batarya).
- Tuşlar: H=RTL, L=LAND, X=kaza sonrası sıfırla.
- Başsız doğrulama (Studio Luau, 2026-09-23): kare/zikzak görevde maks. rota sapması 0,35 m, eve iniş 0,00 m,
  batarya failsafe 10 sn gecikmeli RTL, geofence 300 m'de RTL.

### Gerçek Saha: Bahçelievler (OpenStreetMap)
- `python tools/osm2roblox.py --name Bahcelievler --focus-label "BAHÇELİEVLER DEVLET HASTANESİ" --center 41.0062437,28.844367 --radius 350 --focus-way 518497853 -o scripts/maps/Bahcelievler.luau --cache .cache/bahcelievler_osm.json`
  → 509 bina (108 L/U şekilli bina üçgenlerle), 4 hastane binası, 285 yol parçası; kalkış pedi binalardan ≥12 m uzak açık alan.
- Studio'da kurulum: `ServerStorage.MapData` içine `OsmMapBuilder` + `Bahcelievler` modülleri, sonra
  `require(OsmMapBuilder).build(require(Bahcelievler), Vector3.new(6000, 0, 0))` → `Workspace.Map_Bahcelievler`.
- `DroneConfig.ACTIVE_SITE = "BAHCELIEVLER"`: drone pedden kalkar; kayıtlar `home_geo` (pedin GPS'i) taşır, böylece
  `sim2mission.py` `--home` olmadan görevi tam simüle edilen yere koyar.
- Sınırlamalar: arazi SRTM 30 m (bkz. Arazi bölümü); OSM'de yüksekliği olmayan binalar (hastane dahil) 12 m varsayıldı;
  çatı şekilleri, ağaçlar, direkler, elektrik hatları yok.
- Test kanalı: istemcide `ReplicatedStorage.DroneCommand` (BindableEvent: "mission" {Vector3}, "rtl", "land", "reset")
  ve `ReplicatedStorage.DroneTelemetry` öznitelikleri (Mode, Status, Position, AltM, SpeedMs, VoltageV, Motor1-4…).

### Arazi & Canlı Rüzgâr
- `osm2roblox.py --terrain`: SRTM 30 m (OpenTopoData), 3×3 min filtre (çatıları ayıklar) + yumuşatma; Bahçelievler'de
  -10 … +32 m kot farkı, ped 34,8 m AMSL. Binalar ayak izinin en alçak zemininde, yollar/parklar eğime uyar.
- `WeatherService` (sunucu, HTTP gerekli): METAR LTBA (ölçüm, 3,3 km) → MET Norway (tahmin) → Open-Meteo → MANUEL.
  Open-Meteo bu makineden (Cloudflare WARP paylaşımlı IP) günlük limit hatası veriyor; Roblox sunucuları da paylaşımlı IP.
- `WindModel`: 10 m rapor → 100 m karışım yüksekliği → kentsel log profil (z0=1 m); Perlin türbülans (hamleden σ).
- Fizik: sürükleme hava hızına göre; otopilot rüzgârı 2 sn gecikmeli tahmin eder (EKF gibi); yatış 35°'de doyar.
- Studio testi (METAR 020°/4,1 m/s): rota sapması 1,11 m, yatış 33°, motorlar ≤%84, 10 m/s seyirde kısmen doyma;
  pede 0,03 m iniş, 1075 mAh. Fırtına testi (12 m/s, hamle 17): yere göre hız 3–6 m/s'ye düştü, tırmanan bacak
  15 m'lik binaya çarptı → **gerçek görev öncesi engel kontrolünün değeri**.
- ÖNERİ: bu drone için görev hızı 5–6 m/s (10 m/s değil) ve kalkıştan sonra önce güvenli irtifaya dikey tırmanış.

### Bilinen Sorunlar
- GPS/konum gürültüsü yok → hover/iniş gerçekte olduğundan çok isabetli (0,03 m). Gerçekte ±1–2 m, binalar arası daha kötü.
- Studio arka plandayken render FPS düşüyor; dt 0.1 ile sınırlı olduğundan simülasyon yavaş çekimde akıyor (fizik doğru).
- Uçak/airframe değerleri (kütle, itki, batarya) TAHMİN — gerçek drone ölçülerine göre güncellenmeli.
- Sürü formasyonunda Drone_001 sunucu tarafından da hareket ettiriliyor ama istemci her karede kendisi konumlandırıyor
  (tek drone istemci otopilotuna ait). Sürü modunda Drone_001 formasyona katılmıyor.
- Tam istemci akışı (R/P/H/L/K/B tuşları, HealthPanel, kopyalama penceresi) henüz Studio'da Play ile denenmedi.
- Roblox TextBox'ın çok uzun kayıtları (15 dk ≈ 250 KB) kopyalayıp kopyalayamadığı doğrulanmadı.

### ❓ Açık Sorular (simülasyon bitince kullanıcıya sorulacak)
Cevaplananlar (rasperiypi/ dokümanlarından): firmware ArduCopter 4.7.0 · Pixhawk 2.4.8 klon · Skywalker PWM ESC
(telemetri yok) · Power Module V1.0 · F450/MT2808/10"×3/4S 5000 · M8N · radyo yok, Wi-Fi hotspot · RC yok ·
Pi 5 TELEM2 UART · IMX500 kamera, lidar yok.
Kalanlar:
1. MT2808 motorların **KV** değeri? (RPM ve itki modelini düzeltir)
2. Gerçek tartılmış kalkış ağırlığı ve bir hover testinde gaz yüzdesi / akım (modeli kalibre eder)?
3. Drone kime kayıtlı, **SHGM İHA kaydı ve pilot lisansı** var mı? (dokümanlarda hiç geçmiyor)
4. RC alıcı + kumanda eklenecek mi? (şu an Wi-Fi koparsa tek güvence GCS failsafe)
5. BLHeli_32/AM32 ESC'ye geçilir mi? (motor başına gerçek RPM/akım/sıcaklık ve titreşim filtresi için)
6. Mevcut ArduPilot parametre dosyası (.param) alınabilir mi? (failsafe/fence/hız ayarlarını simülasyonla eşlemek için)
7. Pi'nin 5 V / 3 A regülatörü Pi 5 için yetersiz (5 A ister) — değiştirilecek mi?

### Mevzuat & Saha Bulguları (araştırma 2026-09-23, ikincil kaynaklar — SHGM sitesine erişilemedi)
- Yeni SHT-İHA 30.07.2026'da yürürlüğe girdi; eski dronlar için uyum 31.07.2027'ye kadar. Sınıflar M0 (500 g–4 kg)…
  Lisans: P0 hobi VLOS 120 m / 3 km; **BVLOS / otonom / insan üstü uçuş P2 + operasyon izni** ister.
  Remote ID + geofence + İHATTYS entegrasyonu zorunlu; SHGM sertifikalı uçuş yazılımı şartı var → Pixhawk'la
  nasıl karşılanacağı açık soru. Uçuş bölgesi haritası: iha.shgm.gov.tr (İHATTYS, yeşil/turuncu/kırmızı).
- Bahçelievler Devlet Hastanesi (~41.0062, 28.8444) Atatürk Havalimanı 23 pist başına ~3,2 km; pist 05/23 hâlâ
  iş jetleri/devlet/TSK için aktif. Eski kurallara göre 9 km içi izne tabi → %90+ ihtimalle kırmızı/izinli bölge.
- OSM (Overpass, 22.09.2026): Bahçelievler kutusunda 6.017 bina, %82 `building:levels`, %81 `height` → OSM ile
  şehir rekonstrüksiyonu gerçekçi. Google Photorealistic 3D Tiles'ı Roblox'a aktarmak lisansa aykırı.
  Rüzgâr: Open-Meteo (10/80/120 m + hamle), trafik: OpenSky ADS-B.
- ArduPilot ESC telemetrisi: BLHeli32 / AM32 / BLHeli_S-Bluejay (bidirectional DShot), SERIALx_PROTOCOL=16.

### TEI Projesiyle Entegrasyon Planı
1. **MAVLink köprüsü (en yüksek değer)**: Python köprü sunucusu simülasyondaki drone'u UDP 14550'de ArduCopter gibi
   yayınlar (HEARTBEAT, ATTITUDE, GLOBAL_POSITION_INT, SYS_STATUS, BATTERY_STATUS, SERVO_OUTPUT_RAW, ESC_TELEMETRY);
   TEI-Ground-Control hiç değiştirilmeden simülasyonu uçurur (ARM, TAKEOFF, SET_MODE, görev yükleme).
2. **Sağlık paneli TEI GCS'e**: `_absorb` içine SERVO_OUTPUT_RAW / BATTERY_STATUS / VIBRATION / EKF_STATUS_REPORT
   eklenip motor başına panel; PWM ESC'de gerçek motor çıkışı (SERVO_OUTPUT_RAW) yine görülebilir.
3. **Motor dengesizliği tespiti (gerçek drone'da çalışır, ESC telemetrisi gerekmez)**: SERVO_OUTPUT_RAW hover'da
   motorlar arası fark, zamanla artan ortalama çıkış (pervane/motor yıpranması), VIBRATION + clipping, voltaj sarkması
   → iç direnç tahmini. Pi üzerinde çalışan "sağlık servisi" olarak.
4. **Görev dosyaları**: TEI GCS'e .waypoints/.plan içe-dışa aktarma; sim2mission çıktısı doğrudan yüklenir.
5. **Güvenlik açıkları**: `tei_kopru.py` hotspot'taki herkesten gelen UDP'yi uçuş kartına yazıyor (kimlik doğrulama yok,
   MAVLink2 signing önerilir); RC yok; GCS failsafe (FS_GCS_ENABLE) şart.
6. **Başlangıç .param dosyası**: simülasyon ayarlarından (FENCE, BATT_FS, RTL, WP hızı) ArduCopter 4.7 parametreleri üret.

### MAVLink Köprüsü (T1) — kullanım
1. Studio: Game Settings → Security → Allow HTTP Requests açık; Play.
2. `python tools/mavlink_bridge.py` (pymavlink gerekir: `pip install pymavlink`; yoksa `rasperiypi/…/venv`
   içindeki kopya otomatik bulunur). Köprü 127.0.0.1:34874'te HTTP dinler, MAVLink'i `udpout:127.0.0.1:14550`'e yollar.
3. TEI-Ground-Control / QGroundControl / Mission Planner → UDP 14550 → bağlan. Simülasyon "ArduCopter 4.7 Quad".
4. Sahte GCS ile uçtan uca test: `python tools/gcs_smoketest.py` (gerçek drone'a karşı sadece `--steps link`).
- Mimari: istemci (drone sim) → RemoteEvent `BridgeState` 5 Hz → `BridgeLink.server` → HTTP → köprü
  (`dronebridge/mavsim.py` ArduCopter emülatörü) → UDP MAVLink. Komutlar ters yönde `BridgeCommands` ile döner.
- Gönderilen: HEARTBEAT, ATTITUDE (10 Hz), GLOBAL_POSITION_INT, VFR_HUD, SERVO_OUTPUT_RAW (5 Hz), SYS_STATUS,
  GPS_RAW_INT (2 Hz), BATTERY_STATUS, HOME_POSITION, EXTENDED_SYS_STATE, MISSION_CURRENT, WIND (1 Hz), STATUSTEXT.
  ESC_TELEMETRY yalnız `--esc-telemetry` ile (TEI'nin PWM ESC'leri gönderemez); VIBRATION/EKF modellenmediği için yok.
- Karşılanan: ARM/DISARM (havada force gerekli), SET_MODE/DO_SET_MODE (STABILIZE/ALT_HOLD→MANUAL, LOITER/POSHOLD/BRAKE→
  GUIDED tut, GUIDED, AUTO, RTL, LAND), NAV_TAKEOFF (GUIDED'da), SET_POSITION_TARGET_LOCAL_NED (BODY/LOCAL hız + yaw rate,
  3 sn zaman aşımı), DO_REPOSITION, DO_MOTOR_TEST (A-B-C-D sırası), görev yükleme/indirme/silme, PARAM listesi/okuma/yazma
  (WPNAV_SPEED, RTL_ALT, FENCE_RADIUS canlı uygulanır), AUTOPILOT_VERSION, GCS failsafe (FS_GCS_TIMEOUT 5 sn → RTL).
- Gerçek ArduPilot'tan bilinçli farklar: AUTO yerde istenince simülasyon kendisi ARM edip kalkar (gerçekte AUTO_OPTIONS=0
  iken ARM + gaz gerekir); parametre adları 4.6 (4.7'de SI adlar); konum/GPS gürültüsü yok.
- Köprü yalnız Studio'da çalışır (canlı Roblox sunucusu kullanıcının PC'sindeki localhost'a erişemez).

### Sağlık Servisi (T2) — kullanım
- Simülasyon: `python tools/mavlink_bridge.py --also udpout:127.0.0.1:14551` + `python tools/health_monitor.py`
  (GCS 14550'de, izleyici 14551'de aynı anda).
- Gerçek drone: TEI GCS kapalıyken `--url udpin:0.0.0.0:14550`, ya da Pi'de `--url /dev/serial0 --baud 57600`
  (seri port paylaşımı için mavlink-router önerilir). İzleyici salt okunur, hiçbir mesaj göndermez.
- Arıza enjeksiyonu (SITL ile aynı adlar): PARAM_SET `SIM_ENGINE_FAIL` (0 tabanlı motor) + `SIM_ENGINE_MUL` (1 = sağlam).
- Teşhis mantığı: medyana göre tek motor sapıyorsa → o motor + verim tahmini (CCW/CW ve CG uyarıları bastırılır);
  çift farkı → montaj/yaw; ön-arka/sağ-sol → ağırlık merkezi. İç direnç ardışık örnek farklarından (dV = -R·dI).
- Oturumlar `.cache/health_history.json`'a yazılır; hover gazı ilk oturumlara göre %5+ artarsa yıpranma uyarısı.
- Gerçek drone'da ek: VIBRATION (>30/60 m/s²), clipping, EKF varyansı, GPS uydu/HDOP — simülasyon bunları üretmez.

### Güvenlik Notları (T5)
- `tei_kopru.py` artık varsayılan olarak yalnız hedef PC'den komut alır (`--izinli IP`, eski davranış `--herkese-acik`).
  Aynı ağda IP taklidi mümkün → Pixhawk'ta **MAVLink2 imzalama** (Mission Planner > Config > MAVLink Signing) açılmalı.
- `rasperiypi/adim3b-wifi-cozum.html` hotspot parolasını düz metin içeriyor → parola değiştirilmeli, rehberden çıkarılmalı.
- Pi'de SSH parola ile giriş açık → SSH anahtarına geçip parola girişini kapatmak önerilir.
- RC yok: FS_GCS_ENABLE=1 tek güvence; RC alıcı + FS_THR_ENABLE önerilir. Pi 5 regülatörü (3 A) yetersiz.

### Engel Kontrolü (N2) — kullanım
- `python tools/check_mission.py gorev.waypoints --map scripts/maps/Bahcelievler.luau [--clearance 5] [--rtl-alt 30]`
  → her türlü görev dosyası (TEI, QGC, Mission Planner, sim2mission). Çakışma varsa çıkış kodu 1.
- Bilinen tuzak: ped hastane zemininden 9,5 m yüksekte; göreli irtifalar pede göredir, binalar kendi zeminlerinde durur.
- Sınır: OSM'de ağaç/direk/hat yok, yüksekliği bilinmeyen bina 12 m → kontrolden geçmek gerekli ama yeterli değil.

### Yol Haritası
- [ ] **Yerel köprü sunucusu**: Studio → HttpService → `localhost` Python sunucusu; JSON'u otomatik kaydedip `.plan` üretir.
- [ ] **RPi yükleyici**: pymavlink/MAVSDK ile görevi doğrudan Pixhawk'a yükleme (home = aracın canlı GPS'i).
- [ ] **Şarj istasyonları & uzun uçuşlar**: Farklı ilçelerde şarj istasyonları olacak. Elle uçurmak ölçeklenmez →
  otomatik rota planlayıcı (istasyon grafiği, batarya modeli, bacak başına menzil kontrolü, istasyonda iniş/şarj/kalkış).
  Görevler home'a göre değil istasyonların mutlak GPS'ine göre üretilmeli; `geo.py` zaten ECEF tabanlı ve km'lerce doğru.
- [ ] Batarya/tüketim modeli (şu an güvenlik kontrolünde sabit 8 dk bütçe).
- [ ] **Gerçek mahalle üretici**: OSM Overpass (bina + yükseklik) + Copernicus DEM → Python → Roblox harita betiği.
- [ ] Canlı hava: Open-Meteo rüzgâr/hamle → simülasyonda rüzgâr vektörü + türbülans.
- [ ] Canlı hava trafiği: OpenSky ADS-B (ambulans helikopteri vb.) → yaklaşırsa RTL/uyarı.
- [ ] Kuş/martı riski: stokastik model (Nisan–Temmuz, çatı seviyesinde artan) + kaçınma/arıza tepkisi testi.
- [ ] Kentsel GPS çoklu yol hatası ve pusula sapması simülasyonu (en olası gerçek arıza kaynakları).
- [ ] Batarya sağlığı: döngü sayısı, iç direnç, hücre dengesizliği, sıcaklık; enerjiye göre "eve dönüş yeter mi" hesabı.
