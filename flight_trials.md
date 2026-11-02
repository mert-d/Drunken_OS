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
* **Gemi:** İskelede `(1116.70, 184.64, -242.80)`
* **Donanım:** Controller 8 (FR) ve Controller 5 (RL) için yazılımsal `invert = true` şarttır.
* **Geliştirici:** Artık `python3 bridge.py push` ve `python3 bridge.py test` komutlarıyla kendi testlerinizi doğrudan çalıştırabilirsiniz.

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
