# Standalone AE2 (Ana Üretim & Quantum CPU) + RS (Sınırsız Tip Arşivi) Köprüsü (`startup.lua`)

Bu sistem **%100 Bağımsız (Standalone)** çalışır. Drunken OS sunucularına, kütüphanelerine veya telefon ağına ihtiyaç duymaz. Doğrudan depo odasındaki tek bir **Advanced Computer** içerisine `startup.lua` adıyla kaydedilip çalıştırılır.

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

* Ortadaki **Barrel (Fıçı)** bloğu hem `ME Bridge` hem de `RS Bridge` bloğuna doğrudan temas etmelidir.
* Varsayılan yönler: Barrel, ME Bridge'in **`east` (Doğu)** yönünde, RS Bridge'in ise **`west` (Batı)** yönündedir (Ekran içinden **`[F2]`** tuşuyla yönleri canlı değiştirebilirsiniz).

---

## 2. Tek Dosyalık Standalone Kod (`startup.lua`)

Bilgisayarda `edit startup.lua` yazıp aşağıdaki kodu doğrudan yapıştırabilirsiniz:

```lua
-- startup.lua
-- STANDALONE AE2 (Quantum Autocrafter) <-> Refined Storage (Unlimited Type Archive) Bridge
-- Zero external dependencies. Runs directly on any CC:Tweaked Advanced Computer.

local CONFIG_PATH = "/storage_bridge.cfg"

local cfg = {
    meBufferDir    = "east",  -- Barrel, ME Bridge'in hangi yönünde?
    rsBufferDir    = "west",  -- Barrel, RS Bridge'in hangi yönünde?
    autoCleanME    = true,    -- ME hücrelerindeki tekil/nadir eşyaları otomatik RS'ye arşivle
    cleanThreshold = 32,      -- ME'de bu adetten az olan (ve hammadde olmayan) eşyalar RS'ye taşınır
    cleanInterval  = 5.0      -- Otomatik temizlik periyodu (saniye)
}

local DIRECTIONS = { "north", "south", "east", "west", "up", "down" }

-- ME sisteminde HER ZAMAN kalması gereken anahtar kelimeler (Sürekli üretilen kaynaklar ve ara parçalar)
local PROTECTED_KEYWORDS = {
    "ingot", "nugget", "dust", "gem", "crystal", "quartz", "redstone", "glowstone",
    "diamond", "emerald", "coal", "charcoal", "silicon", "processor", "printed",
    "circuit", "plate", "gear", "rod", "wire", "sheet", "alloy", "casing", "shaft",
    "cogwheel", "belt", "pipe", "cable", "glass", "planks", "log", "cobblestone",
    "stone", "sand", "gravel", "iron", "gold", "copper", "zinc", "brass", "andesite",
    "certus", "fluix", "sky_stone", "ender_pearl", "blaze", "slime", "rubber", "plastic",
    "block", "ore", "raw_", "essence", "seed", "shard", "polymer", "steel", "titanium"
}

-- Konfigürasyon Yükleme / Kaydetme
local function loadConfig()
    if fs.exists(CONFIG_PATH) then
        local f = fs.open(CONFIG_PATH, "r")
        if f then
            local ok, data = pcall(textutils.unserialize, f.readAll())
            f.close()
            if ok and type(data) == "table" then
                for k, v in pairs(data) do cfg[k] = v end
            end
        end
    end
end

local function saveConfig()
    local f = fs.open(CONFIG_PATH, "w")
    if f then
        f.write(textutils.serialize(cfg))
        f.close()
    end
end

loadConfig()

-- Donanım Bulucu
local me = peripheral.find("meBridge")
local rs = peripheral.find("rsBridge")
local mon = peripheral.find("monitor")

if mon then
    pcall(function() mon.setTextScale(0.5) end)
end

local unifiedList = {}
local craftableSet = {}
local statusMsg = "Sistem Hazir. [Sag/Sol]: Aktar | [C]: Craft | [D]: Simdi Temizle"

-- Eşyanın ME'de korunması gereken bir hammadde/üretim parçası olup olmadığını kontrol eder
local function isProtectedResource(itemName, isCraftable, meCount)
    if isCraftable then return true end -- Autocrafting pattern'i olan hiçbir şeyi RS'ye atma!
    if meCount > (cfg.cleanThreshold or 32) then return true end -- Yüksek stoklu kaynakları ME'de tut

    local lower = string.lower(itemName or "")
    if string.find(lower, "^ae2:") or string.find(lower, "^megacells:") or string.find(lower, "^appflux:") then
        return true
    end
    for _, kw in ipairs(PROTECTED_KEYWORDS) do
        if string.find(lower, kw, 1, true) then
            return true
        end
    end
    return false
end

local function safeExport(bridge, itemFilter, targetDir)
    if not bridge then return 0 end
    if bridge.exportItemToPeripheral then
        local ok, res = pcall(bridge.exportItemToPeripheral, itemFilter, targetDir)
        if ok and type(res) == "number" and res > 0 then return res end
    end
    if bridge.exportItem then
        local ok, res = pcall(bridge.exportItem, itemFilter, targetDir)
        if ok and type(res) == "number" and res > 0 then return res end
    end
    return 0
end

local function safeImport(bridge, itemFilter, sourceDir)
    if not bridge then return 0 end
    if bridge.importItemFromPeripheral then
        local ok, res = pcall(bridge.importItemFromPeripheral, itemFilter, sourceDir)
        if ok and type(res) == "number" and res > 0 then return res end
    end
    if bridge.importItem then
        local ok, res = pcall(bridge.importItem, itemFilter, sourceDir)
        if ok and type(res) == "number" and res > 0 then return res end
    end
    return 0
end

local function scanCraftables()
    craftableSet = {}
    if me and me.listCraftableItems then
        local ok, list = pcall(me.listCraftableItems)
        if ok and type(list) == "table" then
            for _, item in ipairs(list) do
                if item.name then
                    craftableSet[item.name] = item.displayName or item.name
                end
            end
        end
    end
end

local function scanInventories(searchQuery)
    me = peripheral.find("meBridge")
    rs = peripheral.find("rsBridge")
    scanCraftables()

    local map = {}
    local q = searchQuery and string.lower(searchQuery) or ""

    local function matches(name, label)
        if q == "" then return true end
        return string.find(string.lower(label), q, 1, true) or string.find(string.lower(name), q, 1, true)
    end

    if me and me.listItems then
        local ok, meItems = pcall(me.listItems)
        if ok and type(meItems) == "table" then
            for _, item in ipairs(meItems) do
                local name = item.name or "unknown"
                local label = item.displayName or name
                local count = item.amount or item.count or 0
                local craftable = item.isCraftable or (craftableSet[name] ~= nil)
                if matches(name, label) then
                    map[name] = {
                        name = name,
                        displayName = label,
                        meCount = count,
                        rsCount = 0,
                        total = count,
                        isCraftable = craftable,
                        isProtected = isProtectedResource(name, craftable, count)
                    }
                end
            end
        end
    end

    if rs and rs.listItems then
        local ok, rsItems = pcall(rs.listItems)
        if ok and type(rsItems) == "table" then
            for _, item in ipairs(rsItems) do
                local name = item.name or "unknown"
                local label = item.displayName or name
                local count = item.amount or item.count or 0
                if matches(name, label) then
                    if not map[name] then
                        local craftable = (craftableSet[name] ~= nil)
                        map[name] = {
                            name = name,
                            displayName = label,
                            meCount = 0,
                            rsCount = count,
                            total = count,
                            isCraftable = craftable,
                            isProtected = isProtectedResource(name, craftable, 0)
                        }
                    else
                        map[name].rsCount = map[name].rsCount + count
                        map[name].total = map[name].meCount + map[name].rsCount
                    end
                end
            end
        end
    end

    local list = {}
    for _, v in pairs(map) do
        table.insert(list, v)
    end
    table.sort(list, function(a, b)
        if a.isCraftable ~= b.isCraftable then return a.isCraftable end
        return a.total > b.total
    end)
    unifiedList = list
    return list
end

local function transferItem(itemName, amount, direction)
    if not me or not rs then
        statusMsg = "HATA: ME Bridge veya RS Bridge bagli degil!"
        return 0
    end

    local remaining = amount or 64
    local totalMoved = 0

    while remaining > 0 do
        local batch = math.min(remaining, 64)
        local filter = { name = itemName, count = batch }
        local exported = 0

        if direction == "ME_TO_RS" then
            exported = safeExport(me, filter, cfg.meBufferDir)
            if exported > 0 then
                safeImport(rs, { name = itemName, count = exported }, cfg.rsBufferDir)
            end
        elseif direction == "RS_TO_ME" then
            exported = safeExport(rs, filter, cfg.rsBufferDir)
            if exported > 0 then
                safeImport(me, { name = itemName, count = exported }, cfg.meBufferDir)
            end
        end

        if exported <= 0 then break end
        totalMoved = totalMoved + exported
        remaining = remaining - exported
    end

    if totalMoved > 0 then
        statusMsg = string.format("AKTARILDI: %d x %s (%s)", totalMoved, itemName, direction)
    else
        statusMsg = "UYARI: 0 esya aktarildi! [F2] ile Barrel yonlerini kontrol edin."
    end
    return totalMoved
end

local function defragmentMETypesToRS()
    if not me or not rs then return 0, 0 end
    local typesFreed = 0
    local itemsMoved = 0

    for _, entry in ipairs(unifiedList) do
        if entry.meCount > 0 and not entry.isProtected then
            local moved = transferItem(entry.name, entry.meCount, "ME_TO_RS")
            if moved > 0 then
                typesFreed = typesFreed + 1
                itemsMoved = itemsMoved + moved
            end
        end
    end

    if typesFreed > 0 then
        statusMsg = string.format("ME TEMIZLENDI: %d tip (%d esya) RS'ye arsivlendi!", typesFreed, itemsMoved)
    end
    return typesFreed, itemsMoved
end

local function triggerQuantumCraft(entry, craftAmount)
    if not me or not me.craftItem then
        statusMsg = "HATA: ME Bridge craftItem desteklemiyor!"
        return false
    end
    -- Eğer eşyanın kendisi veya stoğu RS'de varsa önce biraz ME'ye çekmeyi dene
    if entry.rsCount > 0 and entry.meCount == 0 then
        transferItem(entry.name, math.min(64, entry.rsCount), "RS_TO_ME")
    end
    local ok, res = pcall(me.craftItem, { name = entry.name, count = craftAmount or 10 })
    if ok and res then
        statusMsg = string.format("QUANTUM CRAFT BASLADI: %d x %s", craftAmount or 10, entry.displayName)
        return true
    else
        statusMsg = "CRAFT HATA: Eksik ara malzeme veya CPU mesgul!"
        return false
    end
end

local function cycleDir(current)
    for i, d in ipairs(DIRECTIONS) do
        if d == current then
            return DIRECTIONS[(i % #DIRECTIONS) + 1]
        end
    end
    return "east"
end

local function drawTarget(t, search, selectedIdx, scrollOffset)
    local w, h = t.getSize()
    t.setBackgroundColor(colors.black)
    t.clear()

    -- 1. Başlık
    t.setCursorPos(1, 1)
    t.setBackgroundColor(colors.blue)
    t.setTextColor(colors.white)
    t.clearLine()
    local modeStr = cfg.autoCleanME and "[OTO-ARSIV: ACIK]" or "[OTO-ARSIV: KAPALI]"
    t.write(" STANDALONE ME <-> RS BRIDGE " .. modeStr)

    -- 2. Durum ve Yön Bilgisi
    t.setCursorPos(1, 2)
    t.setBackgroundColor(colors.gray)
    t.setTextColor(colors.white)
    t.clearLine()
    local meOk = me and "ME:OK" or "ME:YOK"
    local rsOk = rs and "RS:OK" or "RS:YOK"
    t.write(string.format(" %s(%s) | %s(%s) | Esik:<=%d | Ara:[%s]",
        meOk, cfg.meBufferDir, rsOk, cfg.rsBufferDir, cfg.cleanThreshold, search))

    -- 3. Tablo Başlığı
    t.setCursorPos(1, 3)
    t.setBackgroundColor(colors.lightGray)
    t.setTextColor(colors.black)
    t.clearLine()
    t.write(string.format(" %-20s | %7s | %7s | %6s", "ESYA ([*]Pattern)", "AE2(ME)", "RS(Ars)", "TOPLAM"))

    -- 4. Eşya Listesi
    local listRows = h - 6
    for i = 1, listRows do
        local idx = scrollOffset + i
        local entry = unifiedList[idx]
        t.setCursorPos(1, 3 + i)
        if entry then
            if idx == selectedIdx then
                t.setBackgroundColor(colors.cyan)
                t.setTextColor(colors.black)
            else
                t.setBackgroundColor(colors.black)
                if entry.isCraftable then
                    t.setTextColor(colors.yellow)
                elseif not entry.isProtected then
                    t.setTextColor(colors.orange) -- RS'ye arşivlenecek tekil eşyalar
                else
                    t.setTextColor(colors.white)
                end
            end
            t.clearLine()
            local prefix = entry.isCraftable and "[*]" or (entry.isProtected and " + " or " ~ ")
            local disp = string.sub(prefix .. (entry.displayName or entry.name), 1, 20)
            t.write(string.format(" %-20s | %7d | %7d | %6d", disp, entry.meCount, entry.rsCount, entry.total))
        end
    end

    -- 5. Kısayol Çubuğu
    t.setCursorPos(1, h - 1)
    t.setBackgroundColor(colors.gray)
    t.setTextColor(colors.yellow)
    t.clearLine()
    t.write(" [Sag]:ME->RS [Sol]:RS->ME [C]:Craft [D]:Temizle [A]:Oto [F2]:Yon")

    -- 6. Alt Durum Mesajı
    t.setCursorPos(1, h)
    t.setBackgroundColor(colors.black)
    t.setTextColor(colors.lime)
    t.clearLine()
    t.write(" " .. (statusMsg or ""))
end

-- Ana Döngü
local function main()
    local search = ""
    local selectedIdx = 1
    local scrollOffset = 0
    scanInventories(search)
    local cleanTimer = os.startTimer(cfg.cleanInterval or 5.0)

    while true do
        drawTarget(term, search, selectedIdx, scrollOffset)
        if mon then
            pcall(drawTarget, mon, search, selectedIdx, scrollOffset)
        end

        local _, h = term.getSize()
        local listRows = h - 6

        local ev, p1 = os.pullEvent()
        if ev == "timer" and p1 == cleanTimer then
            if cfg.autoCleanME then
                scanInventories(search)
                local freed = defragmentMETypesToRS()
                if freed > 0 then
                    scanInventories(search)
                end
            end
            cleanTimer = os.startTimer(cfg.cleanInterval or 5.0)

        elseif ev == "key" then
            if p1 == keys.up and selectedIdx > 1 then
                selectedIdx = selectedIdx - 1
                if selectedIdx <= scrollOffset then scrollOffset = math.max(0, selectedIdx - 1) end
            elseif p1 == keys.down and selectedIdx < #unifiedList then
                selectedIdx = selectedIdx + 1
                if selectedIdx > scrollOffset + listRows then scrollOffset = selectedIdx - listRows end
            elseif p1 == keys.pageUp then
                selectedIdx = math.max(1, selectedIdx - listRows)
                scrollOffset = math.max(0, scrollOffset - listRows)
            elseif p1 == keys.pageDown then
                selectedIdx = math.min(math.max(1, #unifiedList), selectedIdx + listRows)
                scrollOffset = math.max(0, math.min(math.max(0, #unifiedList - listRows), scrollOffset + listRows))
            elseif p1 == keys.right and unifiedList[selectedIdx] then
                transferItem(unifiedList[selectedIdx].name, 64, "ME_TO_RS")
                scanInventories(search)
            elseif p1 == keys.left and unifiedList[selectedIdx] then
                transferItem(unifiedList[selectedIdx].name, 64, "RS_TO_ME")
                scanInventories(search)
            elseif p1 == keys.c and unifiedList[selectedIdx] then
                triggerQuantumCraft(unifiedList[selectedIdx], 10)
            elseif p1 == keys.d then
                scanInventories(search)
                defragmentMETypesToRS()
                scanInventories(search)
            elseif p1 == keys.a then
                cfg.autoCleanME = not cfg.autoCleanME
                saveConfig()
                statusMsg = "Otomatik ME Tip Temizleyici: " .. (cfg.autoCleanME and "ACIK" or "KAPALI")
            elseif p1 == keys.f2 then
                cfg.meBufferDir = cycleDir(cfg.meBufferDir)
                saveConfig()
                statusMsg = "ME Buffer Yonu degisti: " .. cfg.meBufferDir .. " ([F3] ile RS yonunu degistirin)"
            elseif p1 == keys.f3 then
                cfg.rsBufferDir = cycleDir(cfg.rsBufferDir)
                saveConfig()
                statusMsg = "RS Buffer Yonu degisti: " .. cfg.rsBufferDir
            elseif p1 == keys.f5 then
                scanInventories(search)
                statusMsg = "Envanter listesi yenilendi."
            elseif p1 == keys.backspace then
                search = string.sub(search, 1, -2)
                selectedIdx = 1; scrollOffset = 0
                scanInventories(search)
            end

        elseif ev == "char" then
            if not ({ c=true, C=true, a=true, A=true, d=true, D=true })[p1] then
                search = search .. p1
                selectedIdx = 1; scrollOffset = 0
                scanInventories(search)
            end
        end
    end
end

main()
```