# Claude Code Notları ve Yol Haritası

Bu dosya Claude Code tarafından doldurulacaktır. Antigravity'nin bıraktığı mevcut durum ve mimari detaylar için lütfen `ANTIGRAVITY_HANDOFF.md` dosyasını inceleyiniz.

---

## 📝 Claude Code Geliştirme Notları

<!-- Claude Code buraya yapacağı geliştirmeleri, uçuş kayıt mimarisini ve donanım aktarım notlarını ekleyebilir -->

### Donanım: Pixhawk + Raspberry Pi
Fiziksel drone'da **Pixhawk** uçuş kartı (ArduPilot veya PX4) ve **Raspberry Pi** yardımcı bilgisayar var.
Görevler MAVLink mission olarak (QGroundControl `.plan`, WPL 110 `.waypoints`) yüklenir.

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
- Sınırlamalar: arazi düz kabul ediliyor (DEM yok); OSM'de yüksekliği olmayan binalar (hastane dahil) 12 m varsayıldı;
  çatı şekilleri, ağaçlar, direkler, elektrik hatları yok.
- Test kanalı: istemcide `ReplicatedStorage.DroneCommand` (BindableEvent: "mission" {Vector3}, "rtl", "land", "reset")
  ve `ReplicatedStorage.DroneTelemetry` öznitelikleri (Mode, Status, Position, AltM, SpeedMs, VoltageV, Motor1-4…).

### Bilinen Sorunlar
- Studio arka plandayken render FPS düşüyor; dt 0.1 ile sınırlı olduğundan simülasyon yavaş çekimde akıyor (fizik doğru).
- Uçak/airframe değerleri (kütle, itki, batarya) TAHMİN — gerçek drone ölçülerine göre güncellenmeli.
- Sürü formasyonunda Drone_001 sunucu tarafından da hareket ettiriliyor ama istemci her karede kendisi konumlandırıyor
  (tek drone istemci otopilotuna ait). Sürü modunda Drone_001 formasyona katılmıyor.
- Tam istemci akışı (R/P/H/L/K/B tuşları, HealthPanel, kopyalama penceresi) henüz Studio'da Play ile denenmedi.
- Roblox TextBox'ın çok uzun kayıtları (15 dk ≈ 250 KB) kopyalayıp kopyalayamadığı doğrulanmadı.

### ❓ Açık Sorular (simülasyon bitince kullanıcıya sorulacak)
1. Pixhawk'ta **ArduPilot mu PX4 mü** yüklü? Sürümü? (QGroundControl açılış ekranında görünür)
2. Pixhawk modeli (2.4.8 / Cube Orange / 6C / 6X…)? Hafıza & işlemci özellik desteğini belirler.
3. **ESC tipi**: BLHeli_S / BLHeli_32 / AM32? ESC telemetri kablosu veya bidirectional DShot var mı? (motor başına RPM/akım/sıcaklık için)
4. **Güç modülü / akım sensörü** var mı? (voltaj + akım + mAh için)
5. Frame boyutu, motor KV, pervane boyutu/adımı, toplam kalkış ağırlığı, batarya (hücre sayısı, mAh, C)?
6. GPS modülü (M8N / M9N / M10, pusulalı mı)? RTK var mı?
7. Telemetri radyosu (SiK 433/915 MHz, ELRS, Wi-Fi)? Kumanda ve alıcı modeli? RC failsafe ayarlı mı?
8. Raspberry Pi modeli ve Pixhawk'a nasıl bağlı (TELEM2 UART / USB)? Üzerinde ne kurulu (mavlink-router, MAVSDK, kamera)?
9. Drone kime kayıtlı, SHGM İHA kaydı ve pilot lisansı var mı?
10. Mesafe sensörü / lidar / kamera var mı (engelden kaçınma, hassas iniş için)?

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
