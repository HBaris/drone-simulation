# Antigravity'nin Şu Ana Kadar Yaptıkları ve Yapacakları
> **Proje**: 3D Yazıcı Destekli Fiziksel Drone Geliştirme & Roblox İstanbul Uçuş / Sürü Gösteri Simülatörü  
> **Repo**: https://github.com/HBaris/drone-simulation.git  
> **Tarih**: 23 Eylül 2026  
> **Devreden**: Google Antigravity AI  
> **Devralan**: Claude Code

---

## 📌 Proje Vizyonu ve Nihai Hedefler
1. **Fiziksel Drone Üretimi**: Kullanıcı 3D yazıcı ile kendi parçalarını basıp ilk test uçuşunu tamamladı. Nihai hedef sıfırdan özel donanımlı drone üretmek.
2. **Roblox Simülasyonu**: Uçuş rotalarının önce simülatörde test edilmesi, ardından bu simülasyonların kaydedilip gerçek dronların uçuş kartlarına (PX4, ArduPilot, Betaflight, ESP32) aktarılması.
3. **İstanbul Sahası**: Dronun gerçekçi bir İstanbul ortamında (Boğaziçi, Galata, köprüler) test edilmesi.
4. **Sürü (Swarm Light Show)**: 1 dronla başlayıp 2, 3... 800 drona kadar gökyüzünde ışık gösterisi koreografileri oluşturabilme.

---

## 🛠️ 1. Antigravity'nin Şu Ana Kadar Yaptıkları (Tamamlananlar)

### A) Mimari ve Kod Kalitesi Kuralları
- **Dosya Sınırı Kuralı**: Tek dosyada **en fazla 800 satır** kuralı konuldu ve uygulandı.
- **Mevcut Durum**: Projedeki tüm Luau dosyaları **70 ile 271 satır** arasındadır (`scripts/check_line_limits.py` ile denetlenmektedir).
- **Rojo Desteği**: `default.project.json` tam yapılandırıldı.

### B) İstanbul Ortamı (`scripts/BuildIstanbulMap.luau`)
- **İstanbul Boğazı**: 2400 stud uzunluğunda, yansımalı deniz suyu (`BosphorusSea`).
- **Boğaziçi Köprüsü**: Boğazın üzerinde asma köprü kuleleri ve yolu (`IstanbulBridge`).
- **Galata Kulesi**: Avrupa yakası tepesinde (`GalataTower`).
- **Sahil & Şehir**: Avrupa ve Anadolu sahil kordonları, asfalt sahil yolları ve şehir binaları (`CityBuildings`).
- **Drone Helipad Üssü**: Sahilde kalkış istasyonu (`DroneLaunchPad`, `Vector3.new(-220, 3, 0)`).
- **Işıklandırma**: 17:48 İstanbul günbatımı altın saat (Atmosphere, Bloom, SunRays).

### C) FPV Drone Uçuş Fiziği & Pilot Modu
- **`src/client/controllers/DronePilotController.client.luau`**:
  - Oyuncu doğrudan drone kamerasından (FPV) veya 3. şahıs takip kamerasından (Chase Cam) uçar.
  - **Kontroller**:
    - `W / S`: Pitch (Burun aşağı hızlanma / yukarı fren)
    - `A / D`: Roll (Sağa / sola yatış ve kayma)
    - `Space / LeftShift`: Gaz / İrtifa (Yüksel / Alçal)
    - `Q / E`: Yaw (Kendi etrafında 360° dönüş)
    - `C`: Kamera modu değiştir (FPV ↔ Chase Cam)
    - `M`: Manuel Uçuş ↔ Waypoint Rota Modu geçişi
  - Aerodinamik sürüklenme (drag), otomatik seviyeleme (Angle Mode), hızla senkronize pervane sesi.
- **`src/client/ui/FPVOverlay.luau`**:
  - Suni Ufuk Çizgisi (Artificial Horizon Ladder)
  - Hız göstergesi ($m/s$ ve $km/h$)
  - İrtifa göstergesi ($m$)
  - 360° Pusula / Heading ($N, NE, E...$)
  - 4S LiPo batarya voltajı ve uçuş modu göstergesi

### D) Rota & Waypoint Motoru
- **`src/shared/FlightMath.luau`**: Catmull-Rom spline eğrileri, pitch/roll eğim hesapları, metrik ENU koordinat çeviricisi ($1\text{ stud} = 0.285\text{ m}$).
- **`src/client/visuals/PathVisualizer.luau`**: 3D sahnede neon silindir waypoint işaretçileri ve ışıklı rota çizgileri.
- **`src/client/ui/EditorUI.luau`**: Rota paneli ve veri dışa aktarım modalları.

### E) Donanım Dışa Aktarım Altyapısı (`src/shared/DataExporter.luau`)
- Simülasyon rotalarını zaman damgalı ($t$), metrik ($X, Y, Z$ metre ENU), açı ($Yaw^\circ$) ve RGB LED formatında **JSON** ve **CSV** olarak dışa aktarır.

### F) Sürü (Swarm) Motoru Altyapısı
- **`src/shared/FormationGenerator.luau`**: Kalp, 3D Küre (Fibonacci lattice), DNA Çift Spirali, Çember, Matris formasyon matematiği.
- **`src/server/FlightManager.server.luau`**: `Workspace:BulkMoveTo` ile 800 drona kadar kasmayan 60 FPS sunucu döngüsü (Varsayılan olarak tek drone açık, sürü kullanıcı isteyince açılır).

---

## 🚀 2. Claude Code İçin Yapılacaklar Listesi (Kaldığımız Yer & Eksikler)

Simülasyonun temelleri sağlam bir şekilde kuruldu ancak **derin fiziksel düşünme, detaylı uçuş kaydı ve gerçek drone donanımına aktarım** konularında aşağıdaki adımlar gereklidir:

### 1. Detaylı Drone Fiziği ve Özellikleri (Gerçek Drone Dinamikleri)
- [ ] **Frame & Donanım Özellikleri**: Drone'a gerçek dünyadaki karşılığını tanımlayın (örn. 5 inç / 7 inç karbon şasi, motor KV değeri, pervane boyutu/adımı, batarya ağırlığı).
- [ ] **Acro / Rate Modu Desteği**: Şu an "Angle (Self-level)" modu var. Gerçek FPV pilotları için açı hızı tabanlı (deg/s) Acro modu eklenebilir.
- [ ] **Rüzgar & Türbülans Simülasyonu**: İstanbul Boğazı üzerinden eserken rüzgar vektörü ($X, Z$) ve rastgele türbülans dalgalanmaları ekleyin.
- [ ] **Çarpışma & Hasar (Collision)**: Binalara, köprü kulelerine veya suya çarpıldığında motorların durması veya hasar alması.

### 2. Uçuş Kaydedici (Flight Flight Blackbox Recorder)
- [ ] **Manuel Uçuşu Kaydetme**: Kullanıcı W/A/S/D ile İstanbul'da serbest uçarken "Kaydı Başlat" (REC) tuşuna basıldığında her $100\text{ ms}$'de bir ($10\text{ Hz}$) drone'un $X, Y, Z, Yaw, Pitch, Roll, Throttle$ durumunu bir diziye kaydetmeli.
- [ ] **Tekrar Oynatma (Replay Mode)**: Kaydedilen uçuşu birebir aynı rotada ve hızda otomatik oynatabilme.

### 3. Simülasyonu Gerçek Drone'a Yükleme (Hardware Bridge)
- [ ] **Koordinat Eşleme (Roblox $\to$ GPS WGS84)**:
  - Helipad referans noktası: İstanbul Enlem/Boylam (örn. $41.0422^\circ\text{ N}, 29.0068^\circ\text{ E}$).
  - Simülasyonda uçulan metre koordinatlarını gerçek GPS enlem/boylam ve irtifaya dönüştürme.
- [ ] **Uçuş Kartı Formatları**:
  - **QGroundControl / PX4**: `.plan` veya `.waypoints` (MAVLink Mission Protocol WPL 110) formatında dışa aktarım.
  - **INAV / Betaflight**: Otonom rota veya Blackbox uyumluluğu.
  - **Özel ESP32 / Arduino**: Wi-Fi veya SD kart üzerinden okunabilir kompakt binary veya JSON/CSV dizisi.

### 4. Proje Kuralları Hatırlatması
> [!IMPORTANT]
> **Kural**: Projedeki hiçbir dosya **800 satırı geçemez**. Kod eklerken yeni özellikler için modüler yapıyı koruyun (`src/client/controllers/`, `src/client/ui/`, `src/shared/`, vb.).
> Kontrol etmek için: `python scripts/check_line_limits.py` komutunu çalıştırabilirsiniz.
