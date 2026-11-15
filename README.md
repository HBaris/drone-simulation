# 🛸 Drone & Sürü (Swarm Light Show) Simülasyon Sistemi

> **English summary.** A drone and swarm light-show simulator built in Roblox (Luau, Rojo).
> - 3D waypoint editor with Catmull-Rom spline routes.
> - Real-time flight simulation with pitch / roll tilt and a live telemetry panel.
> - Swarm formations (heart, globe, helix, ring, grid) for up to **800 drones at 60 FPS**, using `Workspace:BulkMoveTo`.
> - Export of timed ENU coordinates, yaw and LED RGB values as JSON / CSV for real flight controllers.
>
> The details below are in Turkish.

Bu proje, 3D yazıcı ile üretilen fiziksel dronların uçuş öncesi test edilebilmesi, harita üzerinde 3D rota çizimi yapılabilmesi ve nihai olarak **800 adede kadar gösteri drone'unun (Drone Light Show)** senkronize koreografilerini oluşturmak amacıyla geliştirilmiş profesyonel bir simülasyon ve veri aktarım platformudur.

Simülatör ortamında tasarlanan rotalar ve ışık koreografileri, fiziksel dronların uçuş kontrol kartlarına (PX4, ArduPilot, Betaflight veya özel ESP32 kontrolcüler) yüklenebilir standart formatta (**JSON / CSV**) dışa aktarılır.

---

## 🌟 Temel Özellikler

- **🖱️ 3D Rota & Waypoint Editörü**:
  - Harita üzerinde fare ile tıklayarak 3D noktalar (Waypoint) ekleme.
  - İrtifa, dönüş açısı (Yaw) ve hedef hız belirleme.
  - Catmull-Rom spline eğrileriyle noktalar arası pürüzsüz rota çizgisi görselleştirmesi.
- **⚡ Gerçek Zamanlı Uçuş Simülasyonu**:
  - Dronların belirlenen rotayı otomatik olarak takip etmesi.
  - Hıza ve dönüşe göre gövdenin yatması (Pitch/Roll tilt dinamikleri).
  - Canlı telemetri paneli (İrtifa, hız, drone sayısı, FPS sayacı).
- **🎆 800 Drona Kadar Sürü & Işık Şovu (Swarm Show)**:
  - Hazır 3D formasyonlar: **Kalp**, **3D Küre (Globe)**, **DNA Spirali (Helix)**, **Çember (Ring)** ve **Matris Izgara (Grid)**.
  - **`Workspace:BulkMoveTo`** mimarisi sayesinde 800 drone Roblox'ta 60 FPS kasmadan çalışır.
  - Neon LED ışık kaynakları ve ışık izi (Light Trail) efektleri.
- **📤 Gerçek Dronlara Veri Aktarımı (Export Engine)**:
  - Tek tuşla koreografiyi **JSON** veya **CSV** olarak panoya kopyalama.
  - Zaman damgalı ($t$), metrik koordinatlı ($X, Y, Z$ metre ENU), açı ($Yaw^\circ$) ve LED RGB renk verisi çıktısı.

---

## 📁 Proje Dizin Yapısı

```
drone-simulation/
├── default.project.json       # Rojo proje yapılandırması
├── README.md                  # Proje dokümantasyonu
├── scripts/
│   ├── build_installer.py     # Roblox Studio yükleyicisini derleyen araç
│   └── InstallToStudio.luau   # Roblox Studio'ya tek tıkla kuran Luau scripti
└── src/
    ├── shared/
    │   ├── DroneConfig.luau          # Hız limitleri, fizik katsayıları ve ayarlar
    │   ├── FlightMath.luau           # Spline eğrileri, eğim hesapları ve koordinat dönüşümleri
    │   ├── FormationGenerator.luau   # 3D sürü formasyon matematiği
    │   └── DataExporter.luau         # Donanıma veri aktarma motoru (JSON/CSV)
    ├── server/
    │   ├── DroneSpawner.luau         # Parametrik 3D quadcopter ve LED modeli
    │   └── FlightManager.server.luau # Sürü koordinatörü ve uçuş motoru
    └── client/
        ├── WaypointEditor.client.luau# 3D Waypoint & Formasyon arayüzü
        └── DroneHUD.client.luau      # Canlı telemetri ve FPS göstergesi
```

---

## 🚀 Kurulum (Roblox Studio)

### Yöntem 1: Tek Tıkla Kurulum (Önerilen)
1. Roblox Studio'da yeni, temiz bir **Baseplate** açın.
2. `View` menüsünden **Command Bar** (Komut Çubuğu) penceresini açın.
3. Repodaki [`scripts/InstallToStudio.luau`](scripts/InstallToStudio.luau) dosyasının içeriğini kopyalayıp Command Bar'a yapıştırın ve Enter'a basın.
4. Tüm klasörler, scriptler ve ayarlar otomatik olarak `ReplicatedStorage`, `ServerScriptService` ve `StarterPlayerScripts` altına yerleşecektir.

### Yöntem 2: Rojo ile Canlı Senkronizasyon
Eğer bilgisayarınızda [Rojo](https://rojo.space/) kuruluysa:
```bash
rojo serve
```
Roblox Studio'da Rojo eklentisine basıp **Connect** dediğinizde repodaki tüm kodlar anında oyuna aktarılır.

---

## 🎮 Kullanım Kılavuzu

1. Roblox Studio'da **Play** (F5) tuşuna basarak oyunu başlatın.
2. Sol altta **⚡ DRONE SIMULATION STUDIO** paneli açılacaktır.

### A) Tekli Rota Çizimi & Uçuş Testi
- **Nokta Ekleme**: Zemine tıklayarak ardışık waypoint noktaları bırakın. 3D neon halkalar ve yol çizgisi belirecektir.
- **Uçuşu Başlat**: Dronunuz kalkış yapıp belirlediğiniz irtifada rotayı pürüzsüzce uçacaktır.
- **Dışa Aktar**: Uçuş bittiğinde `JSON DIŞA AKTAR` butonuna basarak rota koordinatlarını fiziksel drone kontrolcünüz için kopyalayabilirsiniz.

### B) Sürü (Swarm) & Gösteri Modu
- Panelin üstündeki **Sürü & Şov (800)** sekmesine geçin.
- Drone sayısını seçin (Örn: 50, 100, 300 veya 800).
- İstediğiniz 3D formasyon butonuna basın:
  - **❤ KALP**: Gökyüzünde parametrik kırmızı LED kalp şekli oluşturur.
  - **🌐 3D KÜRE**: Fibonacci dağılımı ile gökyüzünde dönen küre kümesi oluşturur.
  - **🧬 DNA SPİRALİ**: Çift sarmallı dönen renkli ışık şovu.
  - **⭕ ÇEMBER**: Halka formasyonu.

---

## 🔌 Donanım Entegrasyonu (Fiziksel Drone Formatı)

Export modülü, her drone için aşağıdaki standart veri çıktısını üretir:

```json
{
  "drone_id": 1,
  "sample_rate_hz": 10,
  "total_duration_sec": 18.5,
  "points": [
    {
      "t": 0.0,
      "x": 0.0,
      "y": 0.0,
      "z": 1.5,
      "yaw": 0.0,
      "r": 0,
      "g": 255,
      "b": 120
    },
    {
      "t": 0.1,
      "x": 0.35,
      "y": 0.82,
      "z": 4.3,
      "yaw": 24.5,
      "r": 0,
      "g": 255,
      "b": 120
    }
  ]
}
```

Bu veri, Python veya C++ ile yazacağınız bir yer istasyonu (GCS) yazılımı üzerinden Wi-Fi / ESP-NOW / Telemetri modülü ile doğrudan drone üzerindeki uçuş kartına kablosuz aktarılabilir.

---

## 🛠️ Gelecek Yol Haritası

- [x] Tekli drone waypoint ve spline rota çizimi
- [x] 800 drona kadar optimize sürü & formasyon motoru
- [x] JSON / CSV telemetri ve rota dışa aktarımı
- [ ] Özel 3D model (Blender'dan üretilen gerçek drone şasisi) entegrasyonu
- [ ] Müzik ile senkronize zaman çizelgesi (Timeline & Audio Sync)
- [ ] Rüzgar direnci ve engel (bina/ağaç) algılama & çarpışma önleme
