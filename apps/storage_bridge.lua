-- startup.lua / apps/storage_bridge.lua
-- STANDALONE AE2 (Quantum Autocrafter) <-> Refined Storage (Unlimited Type Archive) Bridge
-- Zero external dependencies. Supports Advanced Peripherals 1.18 - 1.21+ (meBridge/me_bridge, rsBridge/rs_bridge).

local CONFIG_PATH = "/storage_bridge.cfg"

local DEFAULT_CFG = {
    meBufferDir    = "east",  -- Barrel, ME Bridge'in hangi yonunde? (veya agdaki peripheral adi)
    rsBufferDir    = "west",  -- Barrel, RS Bridge'in hangi yonunde? (veya agdaki peripheral adi)
    autoCleanME    = true,    -- ME hucrelerindeki tekil/nadir esyalari otomatik RS'ye arsivle
    cleanThreshold = 32,      -- ME'de bu adetten az olan (ve hammadde olmayan) esyalar RS'ye tasinir
    cleanInterval  = 5.0      -- Otomatik temizlik periyodu (saniye)
}

local cfg = {}
for k, v in pairs(DEFAULT_CFG) do
    cfg[k] = v
end

local DIRECTIONS = { "north", "south", "east", "west", "up", "down" }
local ME_TYPES   = { "me_bridge", "meBridge", "advancedperipherals:me_bridge" }
local RS_TYPES   = { "rs_bridge", "rsBridge", "advancedperipherals:rs_bridge" }

-- ME sisteminde HER ZAMAN kalmasi gereken anahtar kelimeler (Surekli uretilen kaynaklar ve ara parcalar)
local PROTECTED_KEYWORDS = {
    "ingot", "nugget", "dust", "gem", "crystal", "quartz", "redstone", "glowstone",
    "diamond", "emerald", "coal", "charcoal", "silicon", "processor", "printed",
    "circuit", "plate", "gear", "rod", "wire", "sheet", "alloy", "casing", "shaft",
    "cogwheel", "belt", "pipe", "cable", "glass", "planks", "log", "cobblestone",
    "stone", "sand", "gravel", "iron", "gold", "copper", "zinc", "brass", "andesite",
    "certus", "fluix", "sky_stone", "ender_pearl", "blaze", "slime", "rubber", "plastic",
    "block", "ore", "raw_", "essence", "seed", "shard", "polymer", "steel", "titanium"
}

local DEFAULT_COLORS = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32,
    pink = 64, gray = 128, lightGray = 256, cyan = 512, purple = 1024,
    blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768
}

local DEFAULT_KEYS = {
    up = 200, down = 208, left = 203, right = 205,
    pageUp = 201, pageDown = 209,
    c = 46, d = 32, a = 30, f2 = 60, f3 = 61, f5 = 63, backspace = 14
}

-- Konfigurasyon Yukleme / Kaydetme
local function loadConfig()
    for k, v in pairs(DEFAULT_CFG) do
        cfg[k] = v
    end
    if fs and fs.exists and fs.exists(CONFIG_PATH) then
        local f = fs.open(CONFIG_PATH, "r")
        if f then
            local raw = f.readAll()
            f.close()
            if textutils and textutils.unserialize then
                local ok, data = pcall(textutils.unserialize, raw)
                if ok and type(data) == "table" then
                    for k, v in pairs(data) do
                        cfg[k] = v
                    end
                end
            end
        end
    end
    return cfg
end

local function saveConfig()
    if fs and fs.open and textutils and textutils.serialize then
        local f = fs.open(CONFIG_PATH, "w")
        if f then
            f.write(textutils.serialize(cfg))
            f.close()
            return true
        end
    end
    return false
end

loadConfig()

-- Coklu surum uyumlu peripheral bulucu (me_bridge / meBridge, rs_bridge / rsBridge)
local function findBridge(typeList, hintPattern)
    if not peripheral then return nil, nil end

    if peripheral.find then
        for _, ptype in ipairs(typeList) do
            local ok, found = pcall(peripheral.find, ptype)
            if ok and found then
                local pname = peripheral.getName and peripheral.getName(found) or ptype
                return found, pname
            end
        end
    end

    if peripheral.getNames then
        local okNames, names = pcall(peripheral.getNames)
        if okNames and type(names) == "table" then
            for _, name in ipairs(names) do
                local okType, ptype = pcall(peripheral.getType, name)
                if okType and type(ptype) == "string" then
                    local matched = false
                    for _, candidate in ipairs(typeList) do
                        if ptype == candidate then
                            matched = true
                            break
                        end
                    end
                    if not matched and hintPattern and string.find(string.lower(ptype), hintPattern, 1, true) then
                        matched = true
                    end
                    if not matched and peripheral.hasType then
                        for _, candidate in ipairs(typeList) do
                            local okHas, has = pcall(peripheral.hasType, name, candidate)
                            if okHas and has then
                                matched = true
                                break
                            end
                        end
                    end
                    if matched then
                        local okWrap, wrapped = pcall(peripheral.wrap, name)
                        if okWrap and wrapped then
                            return wrapped, name
                        end
                    end
                end
            end
        end
    end

    return nil, nil
end

local function findMonitor()
    if not peripheral then return nil end
    if peripheral.find then
        local ok, m = pcall(peripheral.find, "monitor")
        if ok and m then return m end
    end
    if peripheral.getNames then
        local okNames, names = pcall(peripheral.getNames)
        if okNames and type(names) == "table" then
            for _, name in ipairs(names) do
                local okType, ptype = pcall(peripheral.getType, name)
                if okType and ptype == "monitor" then
                    local okWrap, wrapped = pcall(peripheral.wrap, name)
                    if okWrap and wrapped then return wrapped end
                end
            end
        end
    end
    return nil
end

local function getAttachedPeripheralSummary()
    if not peripheral or not peripheral.getNames then return "yok" end
    local ok, names = pcall(peripheral.getNames)
    if not ok or type(names) ~= "table" or #names == 0 then
        return "yok"
    end
    local parts = {}
    for i = 1, math.min(#names, 4) do
        local n = names[i]
        local t = peripheral.getType and peripheral.getType(n) or "?"
        table.insert(parts, tostring(n) .. "(" .. tostring(t) .. ")")
    end
    if #names > 4 then
        table.insert(parts, "+" .. (#names - 4))
    end
    return table.concat(parts, ", ")
end

-- Donanim Bulucu
local me, meName = findBridge(ME_TYPES, "mebridge")
local rs, rsName = findBridge(RS_TYPES, "rsbridge")
local mon = findMonitor()

if mon then
    pcall(function() mon.setTextScale(0.5) end)
end

local unifiedList = {}
local craftableSet = {}
local statusMsg = "Sistem Hazir. [Sag/Sol]: Aktar | [C]: Craft | [D]: Simdi Temizle"

local function refreshPeripherals()
    me, meName = findBridge(ME_TYPES, "mebridge")
    rs, rsName = findBridge(RS_TYPES, "rsbridge")
    mon = findMonitor()
    if mon then
        pcall(function() mon.setTextScale(0.5) end)
    end
    return me, rs, mon
end

-- Esyanin ME'de korunmasi gereken bir hammadde/uretim parcasi olup olmadigini kontrol eder
local function isProtectedResource(itemName, isCraftable, meCount)
    if isCraftable then return true end -- Autocrafting pattern'i olan hicbir seyi RS'ye atma!
    if (meCount or 0) > (cfg.cleanThreshold or 32) then return true end -- Yuksek stoklu kaynaklari ME'de tut

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

local function isCardinalDir(target)
    for _, d in ipairs(DIRECTIONS) do
        if d == target then return true end
    end
    return false
end

local function extractMovedCount(ok, res)
    if not ok then return 0 end
    if type(res) == "number" then
        return (res > 0) and res or 0
    elseif type(res) == "table" then
        local c = res.count or res.amount or 0
        return (type(c) == "number" and c > 0) and c or 0
    end
    return 0
end

local function tryTransferCall(primary, secondary, itemFilter, target)
    if type(primary) == "function" then
        local ok, res = pcall(primary, itemFilter, target)
        local moved = extractMovedCount(ok, res)
        if moved > 0 then return moved end
    end
    if type(secondary) == "function" then
        local ok, res = pcall(secondary, itemFilter, target)
        local moved = extractMovedCount(ok, res)
        if moved > 0 then return moved end
    end
    return 0
end

local function safeExport(bridge, itemFilter, targetDir)
    if not bridge or not targetDir then return 0 end
    if isCardinalDir(targetDir) then
        return tryTransferCall(bridge.exportItem, bridge.exportItemToPeripheral, itemFilter, targetDir)
    end
    return tryTransferCall(bridge.exportItemToPeripheral, bridge.exportItem, itemFilter, targetDir)
end

local function safeImport(bridge, itemFilter, sourceDir)
    if not bridge or not sourceDir then return 0 end
    if isCardinalDir(sourceDir) then
        return tryTransferCall(bridge.importItem, bridge.importItemFromPeripheral, itemFilter, sourceDir)
    end
    return tryTransferCall(bridge.importItemFromPeripheral, bridge.importItem, itemFilter, sourceDir)
end

-- Legacy (listItems/listCraftableItems) ve Modern Unified (getItems/getCraftableItems) API okuyuculari
local function fetchItems(bridge)
    if not bridge then return nil, nil end
    local lastErr = nil

    if type(bridge.listItems) == "function" then
        local ok, res, err = pcall(bridge.listItems)
        if ok and type(res) == "table" then
            return res, nil
        elseif not ok then
            lastErr = tostring(res)
        elseif err then
            lastErr = tostring(err)
        end
    end

    if type(bridge.getItems) == "function" then
        local ok, res, err = pcall(bridge.getItems)
        if ok and type(res) == "table" then
            return res, nil
        end
        local ok2, res2, err2 = pcall(bridge.getItems, {})
        if ok2 and type(res2) == "table" then
            return res2, nil
        end
        if not ok2 then
            lastErr = tostring(res2)
        elseif err2 then
            lastErr = tostring(err2)
        elseif not ok then
            lastErr = tostring(res)
        elseif err then
            lastErr = tostring(err)
        end
    end

    return nil, lastErr
end

local function fetchCraftables(bridge)
    if not bridge then return nil end

    if type(bridge.listCraftableItems) == "function" then
        local ok, res = pcall(bridge.listCraftableItems)
        if ok and type(res) == "table" then return res end
    end

    if type(bridge.getCraftableItems) == "function" then
        local ok, res = pcall(bridge.getCraftableItems)
        if ok and type(res) == "table" then return res end
        local ok2, res2 = pcall(bridge.getCraftableItems, {})
        if ok2 and type(res2) == "table" then return res2 end
    end

    return nil
end

local function scanCraftables()
    craftableSet = {}
    local list = fetchCraftables(me)
    if type(list) == "table" then
        for _, item in ipairs(list) do
            if type(item) == "table" then
                local name = item.name or item.id
                if name then
                    craftableSet[name] = item.displayName or name
                end
            end
        end
    end
    return craftableSet
end

local function scanInventories(searchQuery)
    me, meName = findBridge(ME_TYPES, "mebridge")
    rs, rsName = findBridge(RS_TYPES, "rsbridge")
    scanCraftables()

    local map = {}
    local q = (type(searchQuery) == "string") and string.lower(searchQuery) or ""

    local function matches(name, label)
        if q == "" then return true end
        return string.find(string.lower(label), q, 1, true) ~= nil
            or string.find(string.lower(name), q, 1, true) ~= nil
    end

    local meItems, meErr = fetchItems(me)
    if type(meItems) == "table" then
        for _, item in ipairs(meItems) do
            if type(item) == "table" then
                local name = item.name or item.id or "unknown"
                local label = item.displayName or name
                local count = item.amount or item.count or 0
                local craftable = (item.isCraftable == true) or (craftableSet[name] ~= nil)
                if craftable and not craftableSet[name] then
                    craftableSet[name] = label
                end
                if matches(name, label) then
                    if not map[name] then
                        map[name] = {
                            name = name,
                            displayName = label,
                            meCount = count,
                            rsCount = 0,
                            total = count,
                            isCraftable = craftable,
                            isProtected = isProtectedResource(name, craftable, count)
                        }
                    else
                        map[name].meCount = map[name].meCount + count
                        map[name].total = map[name].meCount + map[name].rsCount
                        map[name].isCraftable = map[name].isCraftable or craftable
                        map[name].isProtected = isProtectedResource(name, map[name].isCraftable, map[name].meCount)
                    end
                end
            end
        end
    end

    local rsItems, rsErr = fetchItems(rs)
    if type(rsItems) == "table" then
        for _, item in ipairs(rsItems) do
            if type(item) == "table" then
                local name = item.name or item.id or "unknown"
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

    -- Stokta 0 olan ama ME'de Pattern'i (tarifi) bulunan esyalari da listeye ekle
    for cName, cLabel in pairs(craftableSet) do
        if not map[cName] and matches(cName, cLabel) then
            map[cName] = {
                name = cName,
                displayName = cLabel,
                meCount = 0,
                rsCount = 0,
                total = 0,
                isCraftable = true,
                isProtected = true
            }
        end
    end

    -- Donanim ve ag sagligi uyarisi
    if not me or not rs then
        local attached = getAttachedPeripheralSummary()
        if not me and not rs then
            statusMsg = "HATA: ME/RS Bridge yok! Bagli:[" .. attached .. "] (Modem sag tik)"
        elseif not me then
            statusMsg = "HATA: ME Bridge yok! Bagli:[" .. attached .. "]"
        else
            statusMsg = "HATA: RS Bridge yok! Bagli:[" .. attached .. "]"
        end
    elseif meErr or rsErr then
        statusMsg = "AG HATASI: " .. tostring(meErr or rsErr)
    end

    local list = {}
    for _, v in pairs(map) do
        table.insert(list, v)
    end
    table.sort(list, function(a, b)
        if a.isCraftable ~= b.isCraftable then
            return a.isCraftable
        end
        if a.total ~= b.total then
            return a.total > b.total
        end
        return (a.name or "") < (b.name or "")
    end)
    unifiedList = list
    return list
end

local function hasSourceStock(bridge, itemName, isME)
    for _, entry in ipairs(unifiedList) do
        if entry.name == itemName then
            return isME and ((entry.meCount or 0) > 0) or ((entry.rsCount or 0) > 0)
        end
    end
    if bridge and type(bridge.getItem) == "function" then
        local ok, info = pcall(bridge.getItem, { name = itemName })
        if ok and type(info) == "table" and ((info.amount or info.count or 0) > 0) then
            return true
        end
    end
    local items = fetchItems(bridge)
    if type(items) == "table" then
        for _, item in ipairs(items) do
            if type(item) == "table" and (item.name or item.id) == itemName then
                if (item.amount or item.count or 0) > 0 then
                    return true
                end
            end
        end
    end
    return false
end

local function getCandidateTargets(currentDir)
    local candidates = {}
    local seen = {}
    if currentDir then seen[currentDir] = true end

    for _, d in ipairs(DIRECTIONS) do
        if not seen[d] then
            seen[d] = true
            table.insert(candidates, d)
        end
    end

    if peripheral and peripheral.getNames then
        local ok, names = pcall(peripheral.getNames)
        if ok and type(names) == "table" then
            for _, name in ipairs(names) do
                if not seen[name] and name ~= meName and name ~= rsName then
                    local lowerName = string.lower(name)
                    local ptype = peripheral.getType and peripheral.getType(name) or ""
                    local lowerType = string.lower(tostring(ptype))
                    if string.find(lowerName, "barrel", 1, true)
                        or string.find(lowerName, "chest", 1, true)
                        or string.find(lowerType, "barrel", 1, true)
                        or string.find(lowerType, "chest", 1, true) then
                        seen[name] = true
                        table.insert(candidates, name)
                    end
                end
            end
        end
    end

    return candidates
end

local function transferItem(itemName, amount, direction)
    if not me or not rs then
        statusMsg = "HATA: ME Bridge veya RS Bridge bagli degil!"
        return 0
    end
    if not itemName then return 0 end

    local remaining = amount or 64
    local totalMoved = 0
    local dirUpdated = false

    while remaining > 0 do
        local batch = math.min(remaining, 64)
        local filter = { name = itemName, count = batch }
        local exported = 0

        if direction == "ME_TO_RS" then
            exported = safeExport(me, filter, cfg.meBufferDir)
            if exported == 0 and totalMoved == 0 and hasSourceStock(me, itemName, true) then
                for _, cand in ipairs(getCandidateTargets(cfg.meBufferDir)) do
                    local testExp = safeExport(me, filter, cand)
                    if testExp > 0 then
                        exported = testExp
                        cfg.meBufferDir = cand
                        dirUpdated = true
                        break
                    end
                end
            end
            if exported > 0 then
                local imported = safeImport(rs, { name = itemName, count = exported }, cfg.rsBufferDir)
                if imported == 0 then
                    for _, cand in ipairs(getCandidateTargets(cfg.rsBufferDir)) do
                        local testImp = safeImport(rs, { name = itemName, count = exported }, cand)
                        if testImp > 0 then
                            imported = testImp
                            cfg.rsBufferDir = cand
                            dirUpdated = true
                            break
                        end
                    end
                end
                if imported == 0 then
                    safeImport(me, { name = itemName, count = exported }, cfg.meBufferDir)
                    exported = 0
                end
            end
        elseif direction == "RS_TO_ME" then
            exported = safeExport(rs, filter, cfg.rsBufferDir)
            if exported == 0 and totalMoved == 0 and hasSourceStock(rs, itemName, false) then
                for _, cand in ipairs(getCandidateTargets(cfg.rsBufferDir)) do
                    local testExp = safeExport(rs, filter, cand)
                    if testExp > 0 then
                        exported = testExp
                        cfg.rsBufferDir = cand
                        dirUpdated = true
                        break
                    end
                end
            end
            if exported > 0 then
                local imported = safeImport(me, { name = itemName, count = exported }, cfg.meBufferDir)
                if imported == 0 then
                    for _, cand in ipairs(getCandidateTargets(cfg.meBufferDir)) do
                        local testImp = safeImport(me, { name = itemName, count = exported }, cand)
                        if testImp > 0 then
                            imported = testImp
                            cfg.meBufferDir = cand
                            dirUpdated = true
                            break
                        end
                    end
                end
                if imported == 0 then
                    safeImport(rs, { name = itemName, count = exported }, cfg.rsBufferDir)
                    exported = 0
                end
            end
        else
            break
        end

        if exported <= 0 then break end
        totalMoved = totalMoved + exported
        remaining = remaining - exported
    end

    if dirUpdated then
        saveConfig()
    end

    if totalMoved > 0 then
        if dirUpdated then
            statusMsg = string.format("OTOMATIK YON [%s/%s] -> %d x %s", cfg.meBufferDir, cfg.rsBufferDir, totalMoved, itemName)
        else
            statusMsg = string.format("AKTARILDI: %d x %s (%s)", totalMoved, itemName, direction)
        end
    else
        statusMsg = "UYARI: 0 esya aktarildi! [F2]/[F3] ile Barrel yonlerini kontrol edin."
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
    if not entry or not entry.name then
        return false
    end
    -- Eger esyanin kendisi veya stogu RS'de varsa once biraz ME'ye cekmeyi dene
    if (entry.rsCount or 0) > 0 and (entry.meCount or 0) == 0 then
        transferItem(entry.name, math.min(64, entry.rsCount), "RS_TO_ME")
    end
    local qty = craftAmount or 10
    local ok, res = pcall(me.craftItem, { name = entry.name, count = qty })
    if ok and res then
        statusMsg = string.format("QUANTUM CRAFT BASLADI: %d x %s", qty, entry.displayName or entry.name)
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
    local C = _G.colors or DEFAULT_COLORS
    local w, h = t.getSize()
    w = w or 51
    h = h or 19

    t.setBackgroundColor(C.black)
    t.clear()

    -- 1. Baslik
    t.setCursorPos(1, 1)
    t.setBackgroundColor(C.blue)
    t.setTextColor(C.white)
    t.clearLine()
    local modeStr = cfg.autoCleanME and "[OTO-ARSIV: ACIK]" or "[OTO-ARSIV: KAPALI]"
    t.write((" STANDALONE ME <-> RS BRIDGE " .. modeStr):sub(1, w))

    -- 2. Durum ve Yon Bilgisi
    t.setCursorPos(1, 2)
    t.setBackgroundColor(C.gray)
    t.setTextColor(C.white)
    t.clearLine()
    local meOk = me and "ME:OK" or "ME:YOK"
    local rsOk = rs and "RS:OK" or "RS:YOK"
    local infoStr = string.format(" %s(%s) | %s(%s) | Esik:<=%d | Ara:[%s]",
        meOk, cfg.meBufferDir, rsOk, cfg.rsBufferDir, cfg.cleanThreshold or 32, search or "")
    t.write(infoStr:sub(1, w))

    -- 3. Tablo Basligi
    t.setCursorPos(1, 3)
    t.setBackgroundColor(C.lightGray)
    t.setTextColor(C.black)
    t.clearLine()
    local hdrStr = string.format(" %-20s | %7s | %7s | %6s", "ESYA ([*]Pattern)", "AE2(ME)", "RS(Ars)", "TOPLAM")
    t.write(hdrStr:sub(1, w))

    -- 4. Esya Listesi
    local listRows = math.max(1, h - 6)
    for i = 1, listRows do
        local idx = (scrollOffset or 0) + i
        local entry = unifiedList[idx]
        t.setCursorPos(1, 3 + i)
        if entry then
            if idx == selectedIdx then
                t.setBackgroundColor(C.cyan)
                t.setTextColor(C.black)
            else
                t.setBackgroundColor(C.black)
                if entry.isCraftable then
                    t.setTextColor(C.yellow)
                elseif not entry.isProtected then
                    t.setTextColor(C.orange) -- RS'ye arsivlenecek tekil esyalar
                else
                    t.setTextColor(C.white)
                end
            end
            t.clearLine()
            local prefix = entry.isCraftable and "[*]" or (entry.isProtected and " + " or " ~ ")
            local disp = string.sub(prefix .. (entry.displayName or entry.name), 1, 20)
            local rowStr = string.format(" %-20s | %7d | %7d | %6d", disp, entry.meCount, entry.rsCount, entry.total)
            t.write(rowStr:sub(1, w))
        else
            t.setBackgroundColor(C.black)
            t.clearLine()
        end
    end

    -- 5. Kisayol Cubugu
    t.setCursorPos(1, h - 1)
    t.setBackgroundColor(C.gray)
    t.setTextColor(C.yellow)
    t.clearLine()
    t.write((" [Sag]:ME->RS [Sol]:RS->ME [C]:Craft [D]:Temizle [A]:Oto [F2]:Yon"):sub(1, w))

    -- 6. Alt Durum Mesaji
    t.setCursorPos(1, h)
    t.setBackgroundColor(C.black)
    t.setTextColor(C.lime)
    t.clearLine()
    t.write((" " .. (statusMsg or "")):sub(1, w))
end

-- Ana Dongu
local function main()
    local C = _G.colors or DEFAULT_COLORS
    local K = _G.keys or DEFAULT_KEYS

    refreshPeripherals()

    local search = ""
    local selectedIdx = 1
    local scrollOffset = 0
    scanInventories(search)
    local cleanTimer = os.startTimer(cfg.cleanInterval or 5.0)

    while true do
        local _, h = term.getSize()
        h = h or 19
        local listRows = math.max(1, h - 6)

        -- Clamp selection & scroll within current list bounds
        local totalItems = #unifiedList
        if totalItems == 0 then
            selectedIdx = 1
            scrollOffset = 0
        else
            if selectedIdx > totalItems then selectedIdx = totalItems end
            if selectedIdx < 1 then selectedIdx = 1 end
            if selectedIdx <= scrollOffset then
                scrollOffset = math.max(0, selectedIdx - 1)
            elseif selectedIdx > scrollOffset + listRows then
                scrollOffset = selectedIdx - listRows
            end
            if scrollOffset > math.max(0, totalItems - listRows) then
                scrollOffset = math.max(0, totalItems - listRows)
            end
            if scrollOffset < 0 then scrollOffset = 0 end
        end

        drawTarget(term, search, selectedIdx, scrollOffset)
        if mon then
            pcall(drawTarget, mon, search, selectedIdx, scrollOffset)
        end

        local ev, p1 = os.pullEvent()
        if ev == "terminate" then
            break
        elseif ev == "timer" and p1 == cleanTimer then
            if cfg.autoCleanME then
                scanInventories(search)
                local freed = defragmentMETypesToRS()
                if freed > 0 then
                    scanInventories(search)
                end
            end
            cleanTimer = os.startTimer(cfg.cleanInterval or 5.0)

        elseif ev == "key" and p1 ~= nil then
            if K.up and p1 == K.up and selectedIdx > 1 then
                selectedIdx = selectedIdx - 1
            elseif K.down and p1 == K.down and selectedIdx < #unifiedList then
                selectedIdx = selectedIdx + 1
            elseif K.pageUp and p1 == K.pageUp then
                selectedIdx = math.max(1, selectedIdx - listRows)
                scrollOffset = math.max(0, scrollOffset - listRows)
            elseif K.pageDown and p1 == K.pageDown then
                selectedIdx = math.min(math.max(1, #unifiedList), selectedIdx + listRows)
                scrollOffset = math.max(0, math.min(math.max(0, #unifiedList - listRows), scrollOffset + listRows))
            elseif K.right and p1 == K.right and unifiedList[selectedIdx] then
                transferItem(unifiedList[selectedIdx].name, 64, "ME_TO_RS")
                scanInventories(search)
            elseif K.left and p1 == K.left and unifiedList[selectedIdx] then
                transferItem(unifiedList[selectedIdx].name, 64, "RS_TO_ME")
                scanInventories(search)
            elseif K.c and p1 == K.c and unifiedList[selectedIdx] then
                triggerQuantumCraft(unifiedList[selectedIdx], 10)
            elseif K.d and p1 == K.d then
                scanInventories(search)
                defragmentMETypesToRS()
                scanInventories(search)
            elseif K.a and p1 == K.a then
                cfg.autoCleanME = not cfg.autoCleanME
                saveConfig()
                statusMsg = "Otomatik ME Tip Temizleyici: " .. (cfg.autoCleanME and "ACIK" or "KAPALI")
            elseif K.f2 and p1 == K.f2 then
                cfg.meBufferDir = cycleDir(cfg.meBufferDir)
                saveConfig()
                statusMsg = "ME Buffer Yonu degisti: " .. cfg.meBufferDir .. " ([F3] ile RS yonunu degistirin)"
            elseif K.f3 and p1 == K.f3 then
                cfg.rsBufferDir = cycleDir(cfg.rsBufferDir)
                saveConfig()
                statusMsg = "RS Buffer Yonu degisti: " .. cfg.rsBufferDir
            elseif K.f5 and p1 == K.f5 then
                scanInventories(search)
                if me and rs then
                    statusMsg = "Envanter listesi yenilendi."
                end
            elseif K.backspace and p1 == K.backspace then
                search = string.sub(search, 1, -2)
                selectedIdx = 1
                scrollOffset = 0
                scanInventories(search)
            end

        elseif ev == "char" and type(p1) == "string" then
            if not ({ c = true, C = true, a = true, A = true, d = true, D = true })[p1] then
                search = search .. p1
                selectedIdx = 1
                scrollOffset = 0
                scanInventories(search)
            end
        end
    end

    term.setBackgroundColor(C.black)
    term.setTextColor(C.white)
    return true
end

-- CC:Tweaked uzerinde dogrudan startup.lua veya storage_bridge.lua olarak calistirildiginda baslat
if shell and shell.getRunningProgram then
    local running = shell.getRunningProgram() or ""
    if running:match("storage_bridge") or running:match("startup%.lua$") or running == "startup" then
        main()
    end
end

return {
    CONFIG_PATH = CONFIG_PATH,
    DIRECTIONS = DIRECTIONS,
    ME_TYPES = ME_TYPES,
    RS_TYPES = RS_TYPES,
    PROTECTED_KEYWORDS = PROTECTED_KEYWORDS,
    loadConfig = loadConfig,
    saveConfig = saveConfig,
    findBridge = findBridge,
    refreshPeripherals = refreshPeripherals,
    isProtectedResource = isProtectedResource,
    safeExport = safeExport,
    safeImport = safeImport,
    fetchItems = fetchItems,
    fetchCraftables = fetchCraftables,
    scanCraftables = scanCraftables,
    scanInventories = scanInventories,
    transferItem = transferItem,
    defragmentMETypesToRS = defragmentMETypesToRS,
    triggerQuantumCraft = triggerQuantumCraft,
    cycleDir = cycleDir,
    drawTarget = drawTarget,
    main = main,
    run = main,
    getConfig = function() return cfg end,
    getStatus = function() return statusMsg end,
    setStatus = function(msg) statusMsg = msg end,
    getUnifiedList = function() return unifiedList end,
    getCraftableSet = function() return craftableSet end
}
