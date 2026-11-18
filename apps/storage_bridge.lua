-- startup.lua / apps/storage_bridge.lua
-- STANDALONE AE2 (Quantum Autocrafter) <-> Refined Storage (Unlimited Type Archive) Bridge
-- Zero external dependencies. Runs directly on any CC:Tweaked Advanced Computer.

local CONFIG_PATH = "/storage_bridge.cfg"

local DEFAULT_CFG = {
    meBufferDir    = "east",  -- Barrel, ME Bridge'in hangi yonunde?
    rsBufferDir    = "west",  -- Barrel, RS Bridge'in hangi yonunde?
    autoCleanME    = true,    -- ME hucrelerindeki tekil/nadir esyalari otomatik RS'ye arsivle
    cleanThreshold = 32,      -- ME'de bu adetten az olan (ve hammadde olmayan) esyalar RS'ye tasinir
    cleanInterval  = 5.0      -- Otomatik temizlik periyodu (saniye)
}

local cfg = {}
for k, v in pairs(DEFAULT_CFG) do
    cfg[k] = v
end

local DIRECTIONS = { "north", "south", "east", "west", "up", "down" }

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

-- Donanim Bulucu
local me = peripheral and peripheral.find and peripheral.find("meBridge") or nil
local rs = peripheral and peripheral.find and peripheral.find("rsBridge") or nil
local mon = peripheral and peripheral.find and peripheral.find("monitor") or nil

if mon then
    pcall(function() mon.setTextScale(0.5) end)
end

local unifiedList = {}
local craftableSet = {}
local statusMsg = "Sistem Hazir. [Sag/Sol]: Aktar | [C]: Craft | [D]: Simdi Temizle"

local function refreshPeripherals()
    me = peripheral and peripheral.find and peripheral.find("meBridge") or nil
    rs = peripheral and peripheral.find and peripheral.find("rsBridge") or nil
    mon = peripheral and peripheral.find and peripheral.find("monitor") or nil
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
                if type(item) == "table" and item.name then
                    craftableSet[item.name] = item.displayName or item.name
                end
            end
        end
    end
    return craftableSet
end

local function scanInventories(searchQuery)
    me = peripheral and peripheral.find and peripheral.find("meBridge") or nil
    rs = peripheral and peripheral.find and peripheral.find("rsBridge") or nil
    scanCraftables()

    local map = {}
    local q = (type(searchQuery) == "string") and string.lower(searchQuery) or ""

    local function matches(name, label)
        if q == "" then return true end
        return string.find(string.lower(label), q, 1, true) ~= nil
            or string.find(string.lower(name), q, 1, true) ~= nil
    end

    if me and me.listItems then
        local ok, meItems = pcall(me.listItems)
        if ok and type(meItems) == "table" then
            for _, item in ipairs(meItems) do
                if type(item) == "table" then
                    local name = item.name or "unknown"
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
    end

    if rs and rs.listItems then
        local ok, rsItems = pcall(rs.listItems)
        if ok and type(rsItems) == "table" then
            for _, item in ipairs(rsItems) do
                if type(item) == "table" then
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

local function transferItem(itemName, amount, direction)
    if not me or not rs then
        statusMsg = "HATA: ME Bridge veya RS Bridge bagli degil!"
        return 0
    end
    if not itemName then return 0 end

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
        else
            break
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
                statusMsg = "Envanter listesi yenilendi."
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
    PROTECTED_KEYWORDS = PROTECTED_KEYWORDS,
    loadConfig = loadConfig,
    saveConfig = saveConfig,
    refreshPeripherals = refreshPeripherals,
    isProtectedResource = isProtectedResource,
    safeExport = safeExport,
    safeImport = safeImport,
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
