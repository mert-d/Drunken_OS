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
local VIEW_MODES = { "TUMU", "STOK", "ME", "RS", "CRAFT", "ARSIV" }
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
    escape = 1, tab = 15, enter = 28, numPadEnter = 156,
    up = 200, down = 208, left = 203, right = 205,
    pageUp = 201, pageDown = 209,
    c = 46, d = 32, a = 30, f = 33, g = 34, q = 16,
    f2 = 60, f3 = 61, f5 = 63, backspace = 14
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

local masterMap = {}
local masterList = {}
local unifiedList = {}
local craftableSet = {}
local probeFailed = false
local lastTransferExported = false
local statusMsg = "Hazir! [F]:Ara [Tab]:Gorunum [G]:RS->ME Bosalt"

local function cleanDisplayName(label, fallback)
    local s = tostring(label or fallback or "unknown")
    s = s:gsub("^%[(.*)%]$", "%1")
    return s
end

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
                    craftableSet[name] = cleanDisplayName(item.displayName, name)
                end
            end
        end
    end
    return craftableSet
end

-- Bellek ici filtreleme ve siralama (0ms, hicbir peripheral cagrisi yapmaz)
local function applyFilter(searchQuery, viewFilter)
    local q = (type(searchQuery) == "string") and string.lower(searchQuery) or ""
    local vf = viewFilter or "TUMU"
    local list = {}

    for _, entry in ipairs(masterList) do
        local matchQuery = (q == "")
            or (string.find(string.lower(entry.displayName or ""), q, 1, true) ~= nil)
            or (string.find(string.lower(entry.name or ""), q, 1, true) ~= nil)

        if matchQuery then
            local matchView = true
            if vf == "ME" then
                matchView = (entry.meCount or 0) > 0
            elseif vf == "RS" then
                matchView = (entry.rsCount or 0) > 0
            elseif vf == "CRAFT" then
                matchView = (entry.isCraftable == true)
            elseif vf == "ARSIV" then
                matchView = (entry.meCount or 0) > 0 and (not entry.isProtected)
            end
            if matchView then
                table.insert(list, entry)
            end
        end
    end

    table.sort(list, function(a, b)
        if vf ~= "STOK" and a.isCraftable ~= b.isCraftable then
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

local function updateEntryCounts(itemName, deltaME, deltaRS)
    local entry = masterMap[itemName]
    if not entry then return end
    entry.meCount = math.max(0, (entry.meCount or 0) + (deltaME or 0))
    entry.rsCount = math.max(0, (entry.rsCount or 0) + (deltaRS or 0))
    entry.total = entry.meCount + entry.rsCount
    entry.isProtected = isProtectedResource(entry.name, entry.isCraftable, entry.meCount)
end

local function scanInventories(searchQuery, viewFilter)
    me, meName = findBridge(ME_TYPES, "mebridge")
    rs, rsName = findBridge(RS_TYPES, "rsbridge")
    scanCraftables()
    probeFailed = false

    local map = {}

    local meItems, meErr = fetchItems(me)
    if type(meItems) == "table" then
        for _, item in ipairs(meItems) do
            if type(item) == "table" then
                local name = item.name or item.id or "unknown"
                local label = cleanDisplayName(item.displayName, name)
                local count = item.amount or item.count or 0
                local craftable = (item.isCraftable == true) or (craftableSet[name] ~= nil)
                if craftable and not craftableSet[name] then
                    craftableSet[name] = label
                end
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

    local rsItems, rsErr = fetchItems(rs)
    if type(rsItems) == "table" then
        for _, item in ipairs(rsItems) do
            if type(item) == "table" then
                local name = item.name or item.id or "unknown"
                local label = cleanDisplayName(item.displayName, name)
                local count = item.amount or item.count or 0
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

    -- Stokta 0 olan ama ME'de Pattern'i (tarifi) bulunan esyalari da listeye ekle
    for cName, cLabel in pairs(craftableSet) do
        if not map[cName] then
            map[cName] = {
                name = cName,
                displayName = cleanDisplayName(cLabel, cName),
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

    masterMap = map
    local raw = {}
    for _, v in pairs(map) do
        table.insert(raw, v)
    end
    masterList = raw

    return applyFilter(searchQuery, viewFilter)
end

local function hasSourceStock(bridge, itemName, isME)
    local cached = masterMap[itemName]
    if cached then
        return isME and ((cached.meCount or 0) > 0) or ((cached.rsCount or 0) > 0)
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

local function transferBatchWithProbe(srcBridge, dstBridge, isMEtoRS, itemName, batch, allowProbe)
    local srcDir = isMEtoRS and cfg.meBufferDir or cfg.rsBufferDir
    local dstDir = isMEtoRS and cfg.rsBufferDir or cfg.meBufferDir
    local filter = { name = itemName, count = batch }
    local dirUpdated = false

    local exported = safeExport(srcBridge, filter, srcDir)
    if exported == 0 and allowProbe and not probeFailed and hasSourceStock(srcBridge, itemName, isMEtoRS) then
        for _, cand in ipairs(getCandidateTargets(srcDir)) do
            local testExp = safeExport(srcBridge, filter, cand)
            if testExp > 0 then
                exported = testExp
                srcDir = cand
                if isMEtoRS then cfg.meBufferDir = cand else cfg.rsBufferDir = cand end
                dirUpdated = true
                break
            end
        end
        if exported == 0 then
            probeFailed = true
        end
    end

    if exported <= 0 then
        return 0, dirUpdated, false
    end

    local toImport = exported
    local importedTotal = 0
    while toImport > 0 do
        local imp = safeImport(dstBridge, { name = itemName, count = toImport }, dstDir)
        if imp == 0 and importedTotal == 0 and allowProbe and not probeFailed then
            for _, cand in ipairs(getCandidateTargets(dstDir)) do
                local testImp = safeImport(dstBridge, { name = itemName, count = toImport }, cand)
                if testImp > 0 then
                    imp = testImp
                    dstDir = cand
                    if isMEtoRS then cfg.rsBufferDir = cand else cfg.meBufferDir = cand end
                    dirUpdated = true
                    break
                end
            end
            if imp == 0 then
                probeFailed = true
            end
        end
        if imp <= 0 then break end
        importedTotal = importedTotal + imp
        toImport = toImport - imp
    end

    -- Tamponda kalan aktarilamamis kismi kaynak aga geri al
    if importedTotal < exported then
        local leftover = exported - importedTotal
        safeImport(srcBridge, { name = itemName, count = leftover }, srcDir)
    end

    return importedTotal, dirUpdated, true
end

local function transferItem(itemName, amount, direction)
    lastTransferExported = false
    if not me or not rs then
        statusMsg = "HATA: ME Bridge veya RS Bridge bagli degil!"
        return 0
    end
    if not itemName then return 0 end

    local isMEtoRS = (direction == "ME_TO_RS")
    if not isMEtoRS and direction ~= "RS_TO_ME" then
        return 0
    end

    local srcBridge = isMEtoRS and me or rs
    local dstBridge = isMEtoRS and rs or me
    local remaining = amount or 64
    local totalMoved = 0
    local dirUpdated = false

    while remaining > 0 do
        local batch = math.min(remaining, 512)
        local moved, updated, didExport = transferBatchWithProbe(
            srcBridge, dstBridge, isMEtoRS, itemName, batch, (totalMoved == 0)
        )
        if didExport then lastTransferExported = true end
        if updated then dirUpdated = true end
        if moved <= 0 then break end
        totalMoved = totalMoved + moved
        remaining = remaining - moved
    end

    if totalMoved > 0 then
        if isMEtoRS then
            updateEntryCounts(itemName, -totalMoved, totalMoved)
        else
            updateEntryCounts(itemName, totalMoved, -totalMoved)
        end
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

local function defragmentMETypesToRS(maxTypes)
    if not me or not rs then return 0, 0 end
    local typesFreed = 0
    local itemsMoved = 0

    for _, entry in ipairs(masterList) do
        if (entry.meCount or 0) > 0 and not entry.isProtected then
            local moved = transferItem(entry.name, entry.meCount, "ME_TO_RS")
            if moved > 0 then
                typesFreed = typesFreed + 1
                itemsMoved = itemsMoved + moved
                if maxTypes and typesFreed >= maxTypes then
                    break
                end
            else
                -- Barrel erisilemez veya RS dolu ise donguyu kilitlemeden cik
                break
            end
        end
    end

    if typesFreed > 0 then
        statusMsg = string.format("ME TEMIZLENDI: %d tip (%d esya) RS'ye arsivlendi!", typesFreed, itemsMoved)
    end
    return typesFreed, itemsMoved
end

local function evacuateRSToME(maxTypes)
    if not me or not rs then
        statusMsg = "HATA: ME Bridge veya RS Bridge bagli degil!"
        return 0, 0, 0
    end

    if cfg.autoCleanME then
        cfg.autoCleanME = false
        saveConfig()
    end

    local typesMoved = 0
    local itemsMoved = 0
    local typesSkipped = 0

    for _, entry in ipairs(masterList) do
        local initialRsCount = entry.rsCount or 0
        if initialRsCount > 0 then
            local moved = transferItem(entry.name, initialRsCount, "RS_TO_ME")
            if moved > 0 then
                typesMoved = typesMoved + 1
                itemsMoved = itemsMoved + moved
                if moved < initialRsCount then
                    typesSkipped = typesSkipped + 1
                end
                if maxTypes and typesMoved >= maxTypes then
                    break
                end
            else
                typesSkipped = typesSkipped + 1
                if not lastTransferExported and probeFailed then
                    break
                end
            end
        end
    end

    if typesSkipped == 0 then
        statusMsg = string.format("RS->ME TAHLIYE: %d tip (%d esya) AE2'ye aktarildi! [OTO:KAP]", typesMoved, itemsMoved)
    else
        statusMsg = string.format("RS->ME KISMI: %d tip (%d esya) alindi, %d tip ME'ye sigmadi!", typesMoved, itemsMoved, typesSkipped)
    end
    return typesMoved, itemsMoved, typesSkipped
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

local function drawTarget(t, search, selectedIdx, scrollOffset, uiState)
    local C = _G.colors or DEFAULT_COLORS
    local w, h = t.getSize()
    w = w or 51
    h = h or 19
    uiState = uiState or {}

    local viewMode = uiState.viewMode or "TUMU"
    local searchFocused = uiState.searchFocused or false
    local qtyPrompt = uiState.qtyPrompt

    t.setBackgroundColor(C.black)
    t.clear()

    -- 1. Baslik + Gorunum Sekmesi
    t.setCursorPos(1, 1)
    t.setBackgroundColor(C.blue)
    t.setTextColor(C.white)
    t.clearLine()
    local modeStr = cfg.autoCleanME and "[OTO:ACIK]" or "[OTO:KAP]"
    local titleLeft = " ME <-> RS BRIDGE " .. modeStr
    local viewBadge = "[Tab:" .. viewMode .. "]"
    t.write(titleLeft:sub(1, math.max(1, w - #viewBadge - 1)))
    if w > #viewBadge + 2 then
        t.setCursorPos(w - #viewBadge, 1)
        t.setTextColor(C.yellow)
        t.write(viewBadge)
    end

    -- 2. Durum, Yon ve Arama Cubugu
    t.setCursorPos(1, 2)
    t.setBackgroundColor(C.gray)
    t.setTextColor(C.white)
    t.clearLine()
    local meOk = me and "ME:OK" or "ME:YOK"
    local rsOk = rs and "RS:OK" or "RS:YOK"
    local leftInfo = string.format(" %s(%s) %s(%s) | ", meOk, tostring(cfg.meBufferDir):sub(1, 5), rsOk, tostring(cfg.rsBufferDir):sub(1, 5))
    t.write(leftInfo:sub(1, w))
    if #leftInfo < w then
        t.setCursorPos(#leftInfo + 1, 2)
        if searchFocused then
            t.setBackgroundColor(C.blue)
            t.setTextColor(C.yellow)
        else
            t.setBackgroundColor(C.gray)
            t.setTextColor(C.white)
        end
        local searchBox = "Ara:[" .. (search or "") .. "]"
        t.write(searchBox:sub(1, w - #leftInfo))
    end

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

    -- 5. Kisayol / Arama / Ozel Miktar Cubugu
    t.setCursorPos(1, h - 1)
    if qtyPrompt then
        t.setBackgroundColor(C.blue)
        t.setTextColor(C.yellow)
        t.clearLine()
        local qtyLabel = (qtyPrompt.input ~= "" and qtyPrompt.input or "64")
        local pLine = string.format(" Miktar:[%s] [Sag]ME>RS [Sol]RS>ME [C]raft [Esc]Iptal", qtyLabel)
        t.write(pLine:sub(1, w))
    elseif searchFocused then
        t.setBackgroundColor(C.blue)
        t.setTextColor(C.yellow)
        t.clearLine()
        t.write((" ARAMA MODU: Yazin | [Enter/Yon]:Sec | [BS]:Sil"):sub(1, w))
    else
        t.setBackgroundColor(C.gray)
        t.setTextColor(C.yellow)
        t.clearLine()
        t.write((" [Sag]ME>RS [Sol]RS>ME [G]RSBosalt [C]raft [F]Ara"):sub(1, w))
    end

    -- 6. Alt Durum Mesaji
    t.setCursorPos(1, h)
    t.setBackgroundColor(C.black)
    t.setTextColor(C.lime)
    t.clearLine()
    if qtyPrompt then
        local targetName = qtyPrompt.entry and (qtyPrompt.entry.displayName or qtyPrompt.entry.name) or ""
        t.write((" Secili: " .. targetName .. " | [0-9]:Adet [A]:Tumu").sub(1, w))
    else
        t.write((" " .. (statusMsg or "")):sub(1, w))
    end
end

-- Ana Dongu
local function main()
    local C = _G.colors or DEFAULT_COLORS
    local K = _G.keys or DEFAULT_KEYS

    refreshPeripherals()

    local search = ""
    local viewModeIdx = 1
    local searchFocused = false
    local qtyPrompt = nil
    local skipNextChar = false
    local selectedIdx = 1
    local scrollOffset = 0

    scanInventories(search, VIEW_MODES[viewModeIdx])
    local cleanTimer = os.startTimer(cfg.cleanInterval or 5.0)

    local function currentViewMode()
        return VIEW_MODES[viewModeIdx] or "TUMU"
    end

    local function resolvePromptQty(prompt, defaultVal, allVal)
        if prompt.input == "all" then return allVal or defaultVal end
        local n = tonumber(prompt.input)
        if n and n > 0 then return math.floor(n) end
        return defaultVal
    end

    while true do
        local w, h = term.getSize()
        w = w or 51
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

        local uiState = {
            viewMode = currentViewMode(),
            searchFocused = searchFocused,
            qtyPrompt = qtyPrompt
        }
        drawTarget(term, search, selectedIdx, scrollOffset, uiState)
        if mon then
            pcall(drawTarget, mon, search, selectedIdx, scrollOffset, uiState)
        end

        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "terminate" then
            break
        elseif ev == "timer" and p1 == cleanTimer then
            if cfg.autoCleanME and not searchFocused and not qtyPrompt then
                scanInventories(search, currentViewMode())
                local freed = defragmentMETypesToRS(5)
                if freed > 0 then
                    applyFilter(search, currentViewMode())
                end
            end
            cleanTimer = os.startTimer(cfg.cleanInterval or 5.0)

        elseif ev == "mouse_scroll" then
            if not qtyPrompt and #unifiedList > 0 then
                if p1 < 0 and selectedIdx > 1 then
                    selectedIdx = selectedIdx - 1
                elseif p1 > 0 and selectedIdx < #unifiedList then
                    selectedIdx = selectedIdx + 1
                end
            end

        elseif ev == "mouse_click" and p1 == 1 then
            local cx, cy = p2 or 0, p3 or 0
            if cy == 1 and cx >= w - 12 then
                viewModeIdx = (viewModeIdx % #VIEW_MODES) + 1
                selectedIdx = 1; scrollOffset = 0
                applyFilter(search, currentViewMode())
                statusMsg = "Gorunum: " .. currentViewMode()
            elseif cy == 2 then
                if cx <= 13 then
                    cfg.meBufferDir = cycleDir(cfg.meBufferDir)
                    probeFailed = false
                    saveConfig()
                    statusMsg = "ME Buffer Yonu: " .. cfg.meBufferDir
                elseif cx <= 27 then
                    cfg.rsBufferDir = cycleDir(cfg.rsBufferDir)
                    probeFailed = false
                    saveConfig()
                    statusMsg = "RS Buffer Yonu: " .. cfg.rsBufferDir
                else
                    searchFocused = true
                    qtyPrompt = nil
                end
            elseif cy >= 4 and cy <= 3 + listRows then
                searchFocused = false
                qtyPrompt = nil
                local clickedIdx = scrollOffset + (cy - 3)
                if clickedIdx >= 1 and clickedIdx <= #unifiedList then
                    if selectedIdx == clickedIdx then
                        qtyPrompt = { entry = unifiedList[selectedIdx], input = "" }
                    else
                        selectedIdx = clickedIdx
                    end
                end
            elseif cy == h - 1 then
                if qtyPrompt then
                    if cx <= 23 then
                        local qty = resolvePromptQty(qtyPrompt, 64, qtyPrompt.entry.meCount)
                        local name = qtyPrompt.entry.name
                        qtyPrompt = nil
                        transferItem(name, qty, "ME_TO_RS")
                        applyFilter(search, currentViewMode())
                    elseif cx <= 35 then
                        local qty = resolvePromptQty(qtyPrompt, 64, qtyPrompt.entry.rsCount)
                        local name = qtyPrompt.entry.name
                        qtyPrompt = nil
                        transferItem(name, qty, "RS_TO_ME")
                        applyFilter(search, currentViewMode())
                    elseif cx <= 44 then
                        local qty = resolvePromptQty(qtyPrompt, 10, 64)
                        local entry = qtyPrompt.entry
                        qtyPrompt = nil
                        triggerQuantumCraft(entry, qty)
                    else
                        qtyPrompt = nil
                        statusMsg = "Iptal edildi."
                    end
                else
                    if cx >= 23 and cx <= 35 then
                        scanInventories(search, currentViewMode())
                        evacuateRSToME()
                        applyFilter(search, currentViewMode())
                    elseif cx >= 44 then
                        searchFocused = true
                    elseif unifiedList[selectedIdx] then
                        if cx <= 11 then
                            transferItem(unifiedList[selectedIdx].name, 64, "ME_TO_RS")
                            applyFilter(search, currentViewMode())
                        elseif cx <= 22 then
                            transferItem(unifiedList[selectedIdx].name, 64, "RS_TO_ME")
                            applyFilter(search, currentViewMode())
                        elseif cx <= 43 then
                            triggerQuantumCraft(unifiedList[selectedIdx], 10)
                        end
                    end
                end
            end

        elseif ev == "key" and p1 ~= nil then
            skipNextChar = false
            if qtyPrompt then
                if (K.escape and p1 == K.escape) or (K.q and p1 == K.q) then
                    qtyPrompt = nil
                    skipNextChar = true
                    statusMsg = "Iptal edildi."
                elseif K.backspace and p1 == K.backspace then
                    if qtyPrompt.input == "all" then
                        qtyPrompt.input = ""
                    else
                        qtyPrompt.input = string.sub(qtyPrompt.input, 1, -2)
                    end
                elseif K.a and p1 == K.a then
                    qtyPrompt.input = (qtyPrompt.input == "all") and "" or "all"
                    skipNextChar = true
                elseif K.right and p1 == K.right then
                    local qty = resolvePromptQty(qtyPrompt, 64, qtyPrompt.entry.meCount)
                    local name = qtyPrompt.entry.name
                    qtyPrompt = nil
                    transferItem(name, qty, "ME_TO_RS")
                    applyFilter(search, currentViewMode())
                elseif K.left and p1 == K.left then
                    local qty = resolvePromptQty(qtyPrompt, 64, qtyPrompt.entry.rsCount)
                    local name = qtyPrompt.entry.name
                    qtyPrompt = nil
                    transferItem(name, qty, "RS_TO_ME")
                    applyFilter(search, currentViewMode())
                elseif K.c and p1 == K.c then
                    local qty = resolvePromptQty(qtyPrompt, 10, 64)
                    local entry = qtyPrompt.entry
                    qtyPrompt = nil
                    skipNextChar = true
                    triggerQuantumCraft(entry, qty)
                elseif (K.enter and p1 == K.enter) or (K.numPadEnter and p1 == K.numPadEnter) then
                    qtyPrompt = nil
                end
            elseif searchFocused then
                if (K.enter and p1 == K.enter)
                    or (K.numPadEnter and p1 == K.numPadEnter)
                    or (K.escape and p1 == K.escape) then
                    searchFocused = false
                elseif K.up and p1 == K.up then
                    searchFocused = false
                    if selectedIdx > 1 then selectedIdx = selectedIdx - 1 end
                elseif K.down and p1 == K.down then
                    searchFocused = false
                    if selectedIdx < #unifiedList then selectedIdx = selectedIdx + 1 end
                elseif K.tab and p1 == K.tab then
                    viewModeIdx = (viewModeIdx % #VIEW_MODES) + 1
                    selectedIdx = 1; scrollOffset = 0
                    applyFilter(search, currentViewMode())
                    statusMsg = "Gorunum: " .. currentViewMode()
                elseif K.backspace and p1 == K.backspace then
                    search = string.sub(search, 1, -2)
                    selectedIdx = 1; scrollOffset = 0
                    applyFilter(search, currentViewMode())
                    if search == "" then searchFocused = false end
                elseif K.f2 and p1 == K.f2 then
                    cfg.meBufferDir = cycleDir(cfg.meBufferDir)
                    probeFailed = false
                    saveConfig()
                    statusMsg = "ME Buffer Yonu degisti: " .. cfg.meBufferDir
                elseif K.f3 and p1 == K.f3 then
                    cfg.rsBufferDir = cycleDir(cfg.rsBufferDir)
                    probeFailed = false
                    saveConfig()
                    statusMsg = "RS Buffer Yonu degisti: " .. cfg.rsBufferDir
                elseif K.f5 and p1 == K.f5 then
                    scanInventories(search, currentViewMode())
                    if me and rs then statusMsg = "Envanter listesi yenilendi." end
                end
            else
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
                elseif K.tab and p1 == K.tab then
                    viewModeIdx = (viewModeIdx % #VIEW_MODES) + 1
                    selectedIdx = 1; scrollOffset = 0
                    applyFilter(search, currentViewMode())
                    statusMsg = "Gorunum: " .. currentViewMode()
                elseif ((K.enter and p1 == K.enter) or (K.numPadEnter and p1 == K.numPadEnter)) and unifiedList[selectedIdx] then
                    qtyPrompt = { entry = unifiedList[selectedIdx], input = "" }
                elseif K.f and p1 == K.f then
                    searchFocused = true
                    skipNextChar = true
                elseif K.right and p1 == K.right and unifiedList[selectedIdx] then
                    transferItem(unifiedList[selectedIdx].name, 64, "ME_TO_RS")
                    applyFilter(search, currentViewMode())
                elseif K.left and p1 == K.left and unifiedList[selectedIdx] then
                    transferItem(unifiedList[selectedIdx].name, 64, "RS_TO_ME")
                    applyFilter(search, currentViewMode())
                elseif K.c and p1 == K.c and unifiedList[selectedIdx] then
                    skipNextChar = true
                    triggerQuantumCraft(unifiedList[selectedIdx], 10)
                elseif K.d and p1 == K.d then
                    skipNextChar = true
                    scanInventories(search, currentViewMode())
                    defragmentMETypesToRS()
                    applyFilter(search, currentViewMode())
                elseif K.g and p1 == K.g then
                    skipNextChar = true
                    scanInventories(search, currentViewMode())
                    evacuateRSToME()
                    applyFilter(search, currentViewMode())
                elseif K.a and p1 == K.a then
                    skipNextChar = true
                    cfg.autoCleanME = not cfg.autoCleanME
                    saveConfig()
                    statusMsg = "Otomatik ME Tip Temizleyici: " .. (cfg.autoCleanME and "ACIK" or "KAPALI")
                elseif K.f2 and p1 == K.f2 then
                    cfg.meBufferDir = cycleDir(cfg.meBufferDir)
                    probeFailed = false
                    saveConfig()
                    statusMsg = "ME Buffer Yonu degisti: " .. cfg.meBufferDir .. " ([F3] ile RS yonunu degistirin)"
                elseif K.f3 and p1 == K.f3 then
                    cfg.rsBufferDir = cycleDir(cfg.rsBufferDir)
                    probeFailed = false
                    saveConfig()
                    statusMsg = "RS Buffer Yonu degisti: " .. cfg.rsBufferDir
                elseif K.f5 and p1 == K.f5 then
                    scanInventories(search, currentViewMode())
                    if me and rs then
                        statusMsg = "Envanter listesi yenilendi."
                    end
                elseif K.backspace and p1 == K.backspace then
                    search = string.sub(search, 1, -2)
                    selectedIdx = 1; scrollOffset = 0
                    applyFilter(search, currentViewMode())
                end
            end

        elseif ev == "char" and type(p1) == "string" then
            if skipNextChar then
                skipNextChar = false
            elseif qtyPrompt then
                if p1:match("^%d$") and #qtyPrompt.input < 6 then
                    if qtyPrompt.input == "all" then qtyPrompt.input = "" end
                    qtyPrompt.input = qtyPrompt.input .. p1
                end
            elseif searchFocused then
                search = search .. p1
                selectedIdx = 1; scrollOffset = 0
                applyFilter(search, currentViewMode())
            else
                if p1 == "/" then
                    searchFocused = true
                elseif not ({ c = true, C = true, a = true, A = true, d = true, D = true, f = true, F = true, g = true, G = true })[p1] then
                    searchFocused = true
                    search = search .. p1
                    selectedIdx = 1; scrollOffset = 0
                    applyFilter(search, currentViewMode())
                end
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
    VIEW_MODES = VIEW_MODES,
    ME_TYPES = ME_TYPES,
    RS_TYPES = RS_TYPES,
    PROTECTED_KEYWORDS = PROTECTED_KEYWORDS,
    cleanDisplayName = cleanDisplayName,
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
    applyFilter = applyFilter,
    updateEntryCounts = updateEntryCounts,
    scanInventories = scanInventories,
    transferItem = transferItem,
    defragmentMETypesToRS = defragmentMETypesToRS,
    evacuateRSToME = evacuateRSToME,
    triggerQuantumCraft = triggerQuantumCraft,
    cycleDir = cycleDir,
    drawTarget = drawTarget,
    main = main,
    run = main,
    getConfig = function() return cfg end,
    getStatus = function() return statusMsg end,
    setStatus = function(msg) statusMsg = msg end,
    getUnifiedList = function() return unifiedList end,
    getMasterList = function() return masterList end,
    getCraftableSet = function() return craftableSet end
}
