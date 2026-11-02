# Drunken OS <-> Poco Minecraft Server Bridge Rehberi

Bu dosya, **Drunken OS Otopilot / Aviyonik Geliştirici Ajanı** için hazırlanmış canlı sunucu ve test köprüsüdür.
Artık yazdığınız kodları manuel kopyalamaya gerek kalmadan **doğrudan tek komutla sunucuya gönderebilir, otonom uçuş testleri yapabilir ve telemetri loglarını canlı inceleyebilirsiniz.**

---

## 🚀 Hızlı Kullanım Komutları (`python3 bridge.py`)

Projenin ana dizininde aşağıdaki komutları terminalden çalıştırabilirsiniz:

### 1. Kodu Telefona Gönderme ve Aviyonik Sistemini Yeniden Başlatma
```bash
python3 bridge.py push
```
* `apps/`, `lib/`, `clients/` ve `blackbox.lua` dosyalarını paketler.
* ADB üzerinden Poco F7 Android telefonundaki ComputerCraft #15 bilgisayarına aktarır.
* Computer #15'i otomatik yeniden başlatarak yeni kodları canlıya alır.

### 2. Canlı Sunucu, Gemi ve Telemetri Durumu
```bash
python3 bridge.py status
```
* Skyfire'ın anlık konumunu ($X, Y, Z$), Euler açılarını ($Yaw, Pitch, Roll$), hızını, kütlesini ve donma durumunu (`frozen`) gösterir.

### 3. Otonom Uçuş Testi (Güvenlik Korumalı)
```bash
python3 bridge.py test --seconds 15
```
* Geminin donmasını çözer (`unfreeze`).
* Belirtilen süre boyunca 5 Hz frekansla anlık telemetriyi ($Y, Pitch, Roll, V_y$) izler ve ekrana yazar.
* **Otomatik Acil Durum Sigortası (Tripwire):** Gemi $Y < 120$ altına düşerse veya $|Pitch| > 55^\circ$ aşarsa testi anında durdurur, gemiyi dondurur ve iskeleye geri teleport eder (Rescue).
* Süre bitiminde gemiyi dondurur (`freeze`) ve test özetini `flight_trials.md` dosyasına kaydeder.

### 4. İskele Kurtarma (Dock Reset / Rescue)
```bash
python3 bridge.py rescue
```
* Gemi herhangi bir nedenle savrulursa veya boşluğa düşerse, gemiyi ve oyuncuları güvenle ana iskele koordinatlarına `(1116.7, 184.64, -242.8)` geri taşır ve dondurur.

### 5. Hızlı Dondurma ve Çözme
```bash
python3 bridge.py freeze      # En yakın gemiyi zınk diye dondurur
python3 bridge.py unfreeze    # Geminin donmasını çözer
```

### 6. Kara Kutuyu (Flight Log) İnceleme
```bash
python3 bridge.py logs -n 30  # Computer #15'teki flight_log.csv dosyasının son 30 satırını gösterir
```

---

## ⚠️ Kritik Donanım ve Fizik Parametreleri (Geliştirici Notu)

Lütfen otopilot algoritmalarınızı (`lib/avionics.lua` ve `apps/flight_control.lua`) tasarlarken aşağıdaki fiziksel kısıtları göz önünde bulundurun:

1. **Gemi Kütlesi ve İtki:**
   * **Toplam Kütle:** $13,709.25\text{ kg}$
   * **Aşağı Yönlü Ağırlık Kuvveti:** $150,766\text{ pN}$ ($\approx 150.77\text{ kN}$)
   * **Motor Sayısı:** 8 Create Pervanesi (4 koaksiyel çift: FL, FR, RL, RR)

2. **Mekanik Dişli Yönleri (INVERT KRİTİK NOTU):**
   * **FL (Controller 7 - Sol Ön):** Standart yön (`+128`) $\rightarrow$ `invert = false`
   * **FR (Controller 8 - Sağ Ön):** Ters simetrik dişli (`-128`) $\rightarrow$ **`invert = true` OLMALIDIR!**
   * **RL (Controller 5 - Sol Arka):** Ters simetrik dişli (`-128`) $\rightarrow$ **`invert = true` OLMALIDIR!**
   * **RR (Controller 6 - Sağ Arka):** Standart yön (`+128`) $\rightarrow$ `invert = false`
   *(Eğer FR ve RL motorları ters çevrilmezse, lift üretmek yerine yukarı doğru vakum yaparak gemiyi geriye takla attırır!)*

3. **Gimbal Sensörü Yönü:**
   * Gimbal sensörünün Pitch okuması havacılık standartlarına göre terstir.
   * `avionics_iomap.cfg` içerisinde `gimbalMode = 2` (**PCHT** - Pitch Ters) olarak ayarlanmalıdır.

4. **İskele Koordinatları:**
   * Konum: `X: 1116.70, Y: 184.64, Z: -242.80`
   * Yön: `Yaw: 180.0°` (Tam Kuzey), `Pitch: 0.0°` (Sıfır eğim)
