# Drunken OS Skyfire Uçuş Deneyleri Tarihçesi (Flight Trials Log)

Bu dosya, Poco F7 sunucusundaki "Skyfire" gemisinin autonomous Hover test sonuçlarını ve donanım kalibrasyon geçmişini içerir.

| Deneme | Tarih / Saat | Yapılan Değişiklik | Sonuç / Davranış | Teşhis |
| :--- | :--- | :--- | :--- | :--- |
| **#1 - #8** | Önceki testler | İlk PID ve Hover kodları | Geriye takla atma | Gimbal sensörünün ters okuması (`gimbalMode=0`) tespit edildi. |
| **#9** | 20:19 | Gimbal modu `PCHT` yapıldı | İrtifa düşüşü ve sola yatma | Sol/sağ motor yönlerinde asimetri görüldü. |
| **#10** | 20:38 | Delta-Sigma & 8 Rotor modeli uygulandı | Pitch $+67^\circ$ dikilme | 4 motorun 2'sinin (`FR` ve `RL`) mekanik dişlilerinin şematikte ters olduğu anlaşıldı. |
| **#11** | 20:41 | Delta-Sigma test tekrarı | Pitch $+69.8^\circ$ dikilme | Motor invert ayarları teyit edildi. |
| **#12** | 20:47 | **FR ve RL motorları `invert=true` yapıldı** | **MÜKEMMEL STABİL HOVER 🎯**<br>$Pitch = 0.00^\circ$, $V_x = V_y = V_z = 0.00\text{ m/s}$ (T+6s ile T+15s arası sıfır sapma) | Fiziksel model doğrulandı! Geminin ağırlık merkezi ve rotor itki vektörleri tam dengelendi. |
| **#13** | 20:53 | Kullanıcı testinde invert geçici kapandı | Pitch $+77.8^\circ$ dikilme | Invert ayarının zorunluluğu kanıtlandı. |
| **#14** | 20:58 | Kullanıcı sistemi devreye aldı | **STABİL HOVER 🎯**<br>$Y = 155.78$, $Pitch = 0.00^\circ$, $0.00\text{ m/s}$ kayma | Tam başarı. |

---

## 📌 Güncel Durum
* **Gemi:** Serbest Uçuşta `(1114.27, 211.50, -333.70)` — 🚀 AIRBORNE & ACTIVE!
* **Donanım:** 
  * Arka motorların (RL, RR) yelken (sail) sayısı artırıldı; ağırlık merkezi (CoM) geride olduğu için arka türbinlerin kaldırma kapasitesi yükseltildi.
  * Tüm motorlar normal yönde (`invert = false`) çalışmakta olup aşağı üfleyerek saf dikey kaldırma üretmektedir.
* **Yazılım:** CoM moment oranı ($0.5981$) + doğrudan $\omega_x$ açısal hız sönümleme + 20 Hz ANCHOR/HOVER otopilot döngüsü tam uyumla çalışıyor.

### Flight Trial (2026-11-02 22:37:15) — Canlı Serbest Uçuş & Sky Anchor
- **Result:** FULL AIRBORNE FLIGHT SUCCESS 🚀🎯
- **Altitude:** $Y = 211.47\text{ m}$ (Serbest hava seyri)
- **Pitch:** $+0.53^\circ$ (Mükemmele yakın yatay kilitlenme)
- **Roll:** $-0.02^\circ$ (Tam dengeli kanatlar)
- **Rotor Dağılımı:** Ön: ~130 RPM | Arka: 256 RPM (Maksimum arka itki desteği)
- **Mod:** `ANCHOR` (3D İstasyon Koruma)

### Flight Trial (2026-11-02 21:30:46)
- **Result:** STABLE HOVER 🎯
- **Duration:** 4.8s | **Altitude Drift:** -1.84m
- **Pitch:** Avg +0.00°, Max 0.00°
- **Roll:** Avg +128.57°, Max 180.00°

### Flight Trial (2026-11-02 21:42:26)
- **Result:** STABLE HOVER 🎯
- **Duration:** 15.0s | **Altitude Drift:** -0.72m
- **Pitch:** Avg -0.04°, Max 0.05°
- **Roll:** Avg +116.13°, Max 180.00°

### Flight Trial (2026-11-02 22:02:41)
- **Result:** STABLE HOVER 🎯
- **Duration:** 10.0s | **Altitude Drift:** +0.20m
- **Pitch:** Avg -0.03°, Max 0.05°
- **Roll:** Avg -145.23°, Max 180.00°

### Flight Trial (2026-11-02 22:04:18)
- **Result:** STABLE HOVER 🎯
- **Duration:** 10.0s | **Altitude Drift:** +0.90m
- **Pitch:** Avg +0.02°, Max 0.03°
- **Roll:** Avg -168.85°, Max 179.99°
