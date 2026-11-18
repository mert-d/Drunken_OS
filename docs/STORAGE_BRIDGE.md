# Standalone AE2 (Ana Üretim & Quantum CPU) + RS (Sınırsız Tip Arşivi) Köprüsü (`apps/storage_bridge.lua` / `startup.lua`)

Bu sistem **%100 Bağımsız (Standalone)** çalışır. Drunken OS sunucularına, kütüphanelerine veya telefon ağına ihtiyaç duymaz. Doğrudan depo odasındaki tek bir **Advanced Computer** içerisine `startup.lua` adıyla kaydedilip çalıştırılır.

* Advanced Peripherals **1.18 – 1.21+** sürümleriyle tam uyumludur:
  * Hem eski (`meBridge` / `rsBridge`, `listItems`, `listCraftableItems`, sayısal dönüş) hem de yeni Unified API (`me_bridge` / `rs_bridge`, `getItems`, `getCraftableItems`, `{ count = N }` tablo dönüşü) otomatik desteklenir.
* **0ms Bellek İçi Filtreleme:** Arama, sekme değiştirme ve ok tuşu transferleri donanımı her seferinde yeniden taramak yerine bellek içi önbellek (`applyFilter` / `updateEntryCounts`) üzerinde anında güncellenir.

---

## 1. Fiziksel Blok Yerleşimi (Topoloji)

```text
      [ ME Kablosu ]               [ RS Kablosu ]
            |                            |
      +-----------+   +----------+   +-----------+
      | ME Bridge |---|  BARREL  |---| RS Bridge |
      +-----------+   | (Buffer) |   +-----------+
            |         +----------+         |
            +--------------+---------------+
                           |
                 [ Advanced Computer ]
                 (İsteğe Bağlı Monitör)
```

* Ortadaki **Barrel (Fıçı)** bloğu hem `ME Bridge` hem de `RS Bridge` bloğuna doğrudan temas etmelidir (ya da aynı Wired Modem ağına bağlı olmalıdır).
* Varsayılan yönler: Barrel, ME Bridge'in **`east` (Doğu)** yönünde, RS Bridge'in ise **`west` (Batı)** yönündedir.
* **Otomatik Yön Algılama:** Aktarım sırasında varsayılan yön 0 eşya döndürürse sistem tüm 6 ana yönü (`north`, `south`, `east`, `west`, `up`, `down`) ve ağdaki Barrel/Chest birimlerini otomatik tarayıp doğru yönleri `/storage_bridge.cfg` dosyasına kaydeder. İsterseniz **`[F2]`** ve **`[F3]`** tuşlarıyla yönleri elle de değiştirebilirsiniz.

---

## 2. Bağlantı Sorun Giderme (Neden "ME:YOK / RS:YOK" Görünür?)

1. **Wired Modem Halkası Kırmızı Yanmıyor:** Bilgisayara, `ME Bridge`'e ve `RS Bridge`'e bağlı **Wired Modem** bloklarına sağ tıklayın (kenarı **kırmızı** olmalı). Bilgisayar terminalinde `peripherals` yazdığınızda `me_bridge_0` / `rs_bridge_0` (veya `meBridge_0` / `rsBridge_0`) görünmüyorsa modem kablo ağı aktif değildir.
2. **Sadece Kabloyu Değil, Tam Bloğu Kullanın:** Wired Modem için **Full Block Wired Modem** (`computercraft:wired_modem_full`) veya kablo ucundaki Wired Modem kullanın ve modem yüzünü açmayı unutmayın.
3. **ME/RS Ağ Gücü ve Kanalı:** Köprü algılandığı halde liste boşsa veya `AG HATASI` görünüyorsa; ME Bridge'in bir **ME Controller / ME Kablosu** (1 AE kanalı + enerji), RS Bridge'in ise çalışan bir **RS Controller** ağına bağlı olduğunu kontrol edin.
4. **Tampon Sandık Yönü (0 Eşya Aktarımı):** Barrel'ın **bilgisayara değil**, doğrudan **ME Bridge ve RS Bridge** bloklarına bitişik olması gerekir.

---

## 3. Kurulum

Bilgisayarda doğrudan GitHub'dan `startup.lua` olarak indirin:

```text
wget https://raw.githubusercontent.com/mert-d/Drunken_OS/main/apps/storage_bridge.lua startup.lua
reboot
```

Veya `Master_Installer.lua` üzerinden **Clients & Handhelds -> Standalone ME & RS Storage Bridge [STORAGE]** disketi oluşturup bilgisayara takın.

---

## 4. Kontroller (Klavye + Fare)

### Gezinme & Arama
* **`[Yukarı / Aşağı]` / `[PageUp / PageDown]` / `[Fare Tekerleği]`:** Listede gezinme
* **`[F]` veya `[/]` (veya 2. satırdaki `Ara:[...]` alanına tıklama):** Arama moduna odaklanır — bu moddayken `a`, `c`, `d`, `f` dahil **tüm harfler** doğrudan arama kutusuna yazılır (ör. `cadmium`, `draconic`, `andesite`). Aramadan çıkıp eşya seçmek için **`[Enter]`**, **`[Yukarı]`** veya **`[Aşağı]`** tuşuna basın.
* **`[Tab]` (veya sağ üst `[Tab:...]` sekmesine tıklama):** Görünüm filtresini anında değiştirir:
  * `TUMU` -> `STOK` (tamamen toplam stoka göre) -> `ME` -> `RS` -> `CRAFT` -> `ARSIV` (RS'ye taşınacak tekil eşyalar)

### Aktarım, Özel Miktar & Üretim
* **`[Sağ]` (`->`):** Seçili eşyadan 64 adet **ME -> RS** aktar
* **`[Sol]` (`<-`):** Seçili eşyadan 64 adet **RS -> ME** aktar
* **`[Enter]` (veya seçili satıra ikinci tıklama):** **Özel Miktar Menüsü** açar — rakam yazıp (`0-9`) ya da **`[A]`** ile `all` (tümü) seçip:
  * **`[Sağ]`:** Girilen miktarı **ME -> RS** aktar
  * **`[Sol]`:** Girilen miktarı **RS -> ME** aktar
  * **`[C]`:** Girilen miktar için **Quantum Craft** başlat
  * **`[Esc]` / `[Q]`:** İptal
* **`[C]`:** Quantum Craft — Seçili eşya ME'de 0 ama RS'de varsa önce 64 adete kadar ME'ye çeker, ardından `me.craftItem` ile 10x üretimi başlatır
* **`[D]`:** AE2 63-tip temizliği (`defragmentMETypesToRS`) — Pattern'i olmayan, `cleanThreshold` (varsayılan `32`) altındaki ve hammadde/korumalı listede yer almayan tekil eşyaları (`~` turuncu) otomatik RS'ye arşivler
* **`[A]`:** Otomatik arka plan ME tip temizleyicisini (`autoCleanME`) aç/kapat (arka plan döngüsü takılma olmaması için seferde en fazla 5 tip taşır ve arama/miktar modundayken beklemede kalır)
* **`[F2]` / `[F3]` (veya 2. satırdaki ME/RS yönüne tıklama):** Tampon yönünü canlı değiştir ve `/storage_bridge.cfg` dosyasına kaydet
* **`[F5]`:** Donanımı ve ağ envanterini yeniden tara
* **`[Ctrl+T]`:** Programdan çıkış
