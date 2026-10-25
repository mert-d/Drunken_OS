-- clients/ILS_Beacon_Tower.lua
-- Drunken OS - ATC Radar Scope, Runway ILS / Mooring Mast Beacon & Remote Command Tower Console
-- Supports Standard (Monochrome) & Advanced (Color) Terminals + Adaptive External Wall Monitors (1x1 to 4x4)

local CONFIG_PATH = "ils_beacon.conf"
local GITHUB_RAW_BASE = "https://raw.githubusercontent.com/MuhendizBey/Drunken_OS/main/"

local defaultConfig = {
    baseName      = "DRUNKEN-BASE-ALPHA",
    runwayId      = "RWY-36",
    thrX          = 0,     -- Pist esigi (Threshold) X koordinati
    thrY          = 68,    -- Pist esigi Y (Irtifa) koordinati
    thrZ          = 0,     -- Pist esigi Z koordinati
    rwyHeadingDeg = 0,     -- Pistin baktigi pusula acisi (0..359 derece)
    glideSlopeDeg = 8.0,   -- Suzulus acisi (derece)
    approachDist  = 80,    -- FAF baslangic yaklasma mesafesi (blok)
    mastX         = 0,     -- Zeplin / Mothership demirleme kulesi (Mooring Mast) X
    mastY         = 85,    -- Zeplin / Mothership demirleme irtifasi Y
    mastZ         = 0      -- Zeplin / Mothership demirleme kulesi Z
}

local function loadOrInitConfig()
    if fs and fs.exists and fs.exists(CONFIG_PATH) then
        local f = fs.open(CONFIG_PATH, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local data = textutils and textutils.unserialize and textutils.unserialize(raw)
            if type(data) == "table" then
                for k, v in pairs(defaultConfig) do
                    if data[k] == nil then data[k] = v end
                end
                return data
            end
        end
    end
    local copy = {}
    for k, v in pairs(defaultConfig) do copy[k] = v end
    if fs and fs.open and textutils and textutils.serialize then
        local f = fs.open(CONFIG_PATH, "w")
        if f then
            f.write(textutils.serialize(copy))
            f.close()
        end
    end
    return copy
end

local function saveConfig(cfg)
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

local function setColors(surf, fg, bg)
    if not surf then return end
    local isCol = surf.isColor and surf.isColor()
    if isCol then
        if fg then surf.setTextColor(fg) end
        if bg then surf.setBackgroundColor(bg) end
    else
        local inv = (bg == colors.white or bg == colors.cyan or bg == colors.lime or bg == colors.yellow or bg == colors.orange)
        surf.setTextColor(inv and colors.black or colors.white)
        surf.setBackgroundColor(inv and colors.white or colors.black)
    end
end

local function writeAt(surf, x, y, text, fg, bg)
    if not surf then return end
    local w, h = surf.getSize()
    if y < 1 or y > h or x > w then return end
    setColors(surf, fg, bg)
    surf.setCursorPos(x, y)
    surf.write(tostring(text):sub(1, math.max(0, w - x + 1)))
end

local function clearLineAt(surf, y, bg)
    if not surf then return end
    local w, h = surf.getSize()
    if y < 1 or y > h then return end
    setColors(surf, colors.white, bg or colors.black)
    surf.setCursorPos(1, y)
    surf.write(string.rep(" ", w))
end

local function findWirelessModem()
    if not (peripheral and peripheral.find) then return nil end
    local m = peripheral.find("modem", function(_, p) return p.isWireless and p.isWireless() end)
    if m then return m end
    return peripheral.find("modem")
end

local function findExternalMonitors()
    local list = {}
    if not (peripheral and peripheral.getNames) then return list end
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local m = peripheral.wrap(name)
            if m then
                pcall(function()
                    if m.setTextScale then
                        m.setTextScale(1.0)
                        local w, _ = m.getSize()
                        if w < 50 then
                            m.setTextScale(0.5)
                        end
                    end
                end)
                table.insert(list, m)
            end
        end
    end
    return list
end

local function detectTowerPos(cfg)
    if gps and gps.locate then
        local ok, x, y, z = pcall(gps.locate, 1.5)
        if ok and x and y and z then
            return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5), "GPS"
        end
    end
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            local p = peripheral.wrap(name)
            if p then
                local fn = p.getShipPosition or p.getPosition or p.getWorldPosition
                if type(fn) == "function" then
                    local ok, res, b, c = pcall(fn)
                    if ok and type(res) == "table" and (res.x or res[1]) then
                        return math.floor((res.x or res[1]) + 0.5),
                               math.floor((res.y or res[2]) + 0.5),
                               math.floor((res.z or res[3]) + 0.5),
                               name
                    elseif ok and type(res) == "number" and type(b) == "number" and type(c) == "number" then
                        return math.floor(res + 0.5), math.floor(b + 0.5), math.floor(c + 0.5), name
                    end
                end
            end
        end
    end
    return cfg.mastX or cfg.thrX or 0, cfg.mastY or cfg.thrY or 80, cfg.mastZ or cfg.thrZ or 0, nil
end

local function performOtaUpdate(setToastFn)
    if not (http and http.get) then
        setToastFn("HATA: HTTP API kapali veya internet yok!")
        return false
    end
    setToastFn("GitHub'dan guncel Kule yazilimi indiriliyor...")
    local url = GITHUB_RAW_BASE .. "clients/ILS_Beacon_Tower.lua?v=" .. tostring((os.epoch and os.epoch("utc")) or os.time())
    local ok, resp = pcall(http.get, url)
    if not (ok and resp and resp.getResponseCode and resp.getResponseCode() == 200) then
        setToastFn("HATA: GitHub baglantisi basarisiz oldu!")
        return false
    end
    local code = resp.readAll()
    if resp.close then pcall(resp.close) end
    if not code or #code < 200 then
        setToastFn("HATA: Indirilen dosya gecersiz!")
        return false
    end
    local targets = { "/clients/ILS_Beacon_Tower.lua", "clients/ILS_Beacon_Tower.lua" }
    local runningProg = shell and shell.getRunningProgram and shell.getRunningProgram()
    if runningProg and runningProg ~= "" then
        table.insert(targets, "/" .. runningProg)
    end
    local wrote = false
    for _, p in ipairs(targets) do
        local dir = fs.getDir(p)
        if dir and dir ~= "" and not fs.exists(dir) then
            pcall(fs.makeDir, dir)
        end
        local f = fs.open(p, "w")
        if f then
            f.write(code)
            f.close()
            wrote = true
        end
    end
    if wrote then
        setToastFn("GUNCELLEME TAMAM! 1 sn icinde yeniden baslatiliyor...")
        sleep(1.0)
        os.reboot()
        return true
    end
    setToastFn("HATA: Dosya diske yazilamadi!")
    return false
end

local CONFIG_FIELDS = {
    { key = "baseName",      label = "Us Adi (Base Name)",      type = "string" },
    { key = "runwayId",      label = "Pist Kodu (Runway ID)",   type = "string" },
    { key = "mastX",         label = "Direk X (Zeplin/Mship)",  type = "number", step = 5 },
    { key = "mastY",         label = "Direk Y (Hedef Irtifa)",  type = "number", step = 2 },
    { key = "mastZ",         label = "Direk Z (Zeplin/Mship)",  type = "number", step = 5 },
    { key = "thrX",          label = "Pist Esigi X (Ucak)",     type = "number", step = 5 },
    { key = "thrY",          label = "Pist Esigi Y (Irtifa)",   type = "number", step = 2 },
    { key = "thrZ",          label = "Pist Esigi Z (Ucak)",     type = "number", step = 5 },
    { key = "rwyHeadingDeg", label = "Pist Pruva Acisi (Deg)",  type = "number", step = 15, min = 0, max = 345 },
    { key = "approachDist",  label = "Yaklasma Mesafesi (m)",   type = "number", step = 10, min = 20, max = 500 }
}

local ZOOM_RANGES = { 50, 150, 300, 600, 1200 }
local SWEEP_CHARS = { "|", "/", "-", "\\" }

local function runTowerConsole(context)
    local parentTerm = (context and context.term) or term.current()
    local cfg = loadOrInitConfig()
    local modem = findWirelessModem()
    local modemName = modem and peripheral.getName(modem) or nil
    if modemName and rednet then
        pcall(rednet.open, modemName)
    end
    local monitors = findExternalMonitors()

    local activeTab = "RADAR" -- "RADAR", "TRAFFIC", "CONFIG"
    local zoomIdx = 2 -- 150m default
    local contacts = {} -- callsign -> telemetry table + lastSeenClock
    local sortedCallsigns = {}
    local selectedIdx = 1
    local targetAll = false
    local configCursor = 1
    local editingString = false
    local editBuffer = ""
    local statusToast = "ATC & ILS KULE HAZIR ([K]:Gemiden Konum Al | [R]:Eve Cagir)"
    local toastTicks = 80
    local beaconCount = 0
    local sweepStep = 1
    local atcLogs = { "Kule sistemi baslatildi. ILS 1Hz yayinda." }
    local running = true

    local function pushLog(entry)
        local tStr = string.format("%05.1fs", os.clock())
        table.insert(atcLogs, 1, "[" .. tStr .. "] " .. tostring(entry))
        while #atcLogs > 8 do
            table.remove(atcLogs)
        end
    end

    local function buildBeaconPacket()
        return {
            type          = "AVIONICS_ILS_BEACON",
            baseName      = cfg.baseName,
            runwayId      = cfg.runwayId,
            threshold     = { x = tonumber(cfg.thrX) or 0, y = tonumber(cfg.thrY) or 68, z = tonumber(cfg.thrZ) or 0 },
            rwyHeadingRad = math.rad(tonumber(cfg.rwyHeadingDeg) or 0),
            glideSlopeRad = math.rad(tonumber(cfg.glideSlopeDeg) or 8.0),
            approachDist  = tonumber(cfg.approachDist) or 80,
            zeppelinMast  = { x = tonumber(cfg.mastX) or 0, y = tonumber(cfg.mastY) or 85, z = tonumber(cfg.mastZ) or 0 },
            timestamp     = os.epoch and os.epoch("utc") or os.time()
        }
    end

    local function setToast(msg)
        statusToast = tostring(msg)
        toastTicks = 80
    end

    local function rebuildContactList()
        local now = os.clock()
        sortedCallsigns = {}
        for call, c in pairs(contacts) do
            if (now - (c.lastSeenClock or now)) > 15.0 then
                pushLog(call .. " radar menzilinden cikti.")
                contacts[call] = nil
            else
                table.insert(sortedCallsigns, call)
            end
        end
        table.sort(sortedCallsigns)
        if selectedIdx > #sortedCallsigns then
            selectedIdx = math.max(1, #sortedCallsigns)
        end
    end

    local function getSelectedContact()
        rebuildContactList()
        local call = sortedCallsigns[selectedIdx]
        return call and contacts[call] or nil
    end

    local function sendAtcCommand(cmd, extra)
        if not (rednet and rednet.isOpen and rednet.isOpen()) then
            setToast("HATA: Kablosuz Modem bulunamadi / kapali!")
            return
        end
        local sel = getSelectedContact()
        local tgt = (targetAll or not sel) and "ALL" or sel.callsign
        local pkt = {
            type      = "AVIONICS_ATC_CMD",
            target    = tgt,
            cmd       = cmd,
            beacon    = buildBeaconPacket(),
            timestamp = os.epoch and os.epoch("utc") or os.time()
        }
        if type(extra) == "table" then
            for k, v in pairs(extra) do pkt[k] = v end
        end
        pcall(rednet.broadcast, pkt, "DRUNKEN_ATC")
        local logMsg = string.format("KOMUT -> [%s]: %s", tgt, cmd)
        pushLog(logMsg)
        setToast("ATC EMRI GONDERILDI -> [" .. tgt .. "]: " .. cmd)
    end

    -- Adaptive External Wall Monitor Renderer (Supports 1x1 compact 15x10 monitors AND large wall boards)
    local function drawExternalMonitor(mon)
        if not mon then return end
        local w, h = mon.getSize()
        setColors(mon, colors.white, colors.black)
        mon.clear()
        rebuildContactList()

        local sweepCh = SWEEP_CHARS[sweepStep]
        local towerX = tonumber(cfg.mastX) or tonumber(cfg.thrX) or 0
        local towerZ = tonumber(cfg.mastZ) or tonumber(cfg.thrZ) or 0

        -- Compact 1x1 or 2x1 Monitor Mode (e.g., 15x10 at 0.5 scale)
        if w < 36 or h < 14 then
            clearLineAt(mon, 1, colors.blue)
            writeAt(mon, 1, 1, string.format("ATC [%s] %s", sweepCh, tostring(cfg.runwayId)):sub(1, w), colors.white, colors.blue)
            writeAt(mon, 1, 2, tostring(cfg.baseName):sub(1, w), colors.yellow, colors.black)
            writeAt(mon, 1, 3, string.format("DRK:%d,%d,%d", cfg.mastX, cfg.mastY, cfg.mastZ):sub(1, w), colors.lightGray, colors.black)
            writeAt(mon, 1, 4, string.rep("-", w), colors.gray, colors.black)

            if #sortedCallsigns == 0 then
                writeAt(mon, 1, 5, "TRAFIK: YOK", colors.gray, colors.black)
                writeAt(mon, 1, 6, "ILS YAYINDA", colors.lime, colors.black)
                writeAt(mon, 1, 7, string.format("PKT:#%d", beaconCount), colors.cyan, colors.black)
            else
                local sel = getSelectedContact() or contacts[sortedCallsigns[1]]
                if sel then
                    local dx = (tonumber(sel.pos and sel.pos.x) or 0) - towerX
                    local dz = (tonumber(sel.pos and sel.pos.z) or 0) - towerZ
                    local dist = math.sqrt(dx * dx + dz * dz)
                    writeAt(mon, 1, 5, (">" .. tostring(sel.callsign)):sub(1, w), colors.lime, colors.black)
                    writeAt(mon, 1, 6, string.format("MOD:%s", tostring(sel.mode or "MAN")):sub(1, w), colors.cyan, colors.black)
                    writeAt(mon, 1, 7, string.format("ALT:%.0fm V:%+.1f", tonumber(sel.altitude) or 0, tonumber(sel.vSpeed) or 0):sub(1, w), colors.white, colors.black)
                    writeAt(mon, 1, 8, string.format("DST:%.0fm S:%.1f", dist, tonumber(sel.speed) or 0):sub(1, w), colors.yellow, colors.black)
                end
            end
            if h >= 10 then
                clearLineAt(mon, h, colors.gray)
                writeAt(mon, 1, h, string.format("ARAC:%d MNZ:%dm", #sortedCallsigns, ZOOM_RANGES[zoomIdx]):sub(1, w), colors.white, colors.gray)
            end
            return
        end

        -- Large Multi-Block Wall Monitor Mode
        drawTerminalSurface(mon, true)
    end

    -- Main MFD Surface Renderer (51x19 Terminal or Large Monitor)
    function drawTerminalSurface(surf, isLargeMonitor)
        if not surf then return end
        local w, h = surf.getSize()
        setColors(surf, colors.white, colors.black)
        surf.clear()
        rebuildContactList()

        local sweepCh = SWEEP_CHARS[sweepStep]
        local modemOk = (modemName and rednet and rednet.isOpen and rednet.isOpen())
        local txBadge = modemOk and ("TX:" .. sweepCh .. " ON") or "TX:KAPALI"

        -- Row 1: Top Header Bar
        clearLineAt(surf, 1, colors.blue)
        writeAt(surf, 2, 1, string.format("DRUNKEN ATC & ILS KULE [%s]", tostring(cfg.baseName):sub(1, 20)), colors.white, colors.blue)
        writeAt(surf, math.max(2, w - #txBadge - 1), 1, txBadge, modemOk and colors.lime or colors.red, colors.blue)

        -- Row 2: MFD Navigation Tabs
        clearLineAt(surf, 2, colors.gray)
        if isLargeMonitor then
            writeAt(surf, 2, 2, string.format(
                "PIST:%s (%d,%d,%d) | DIREK:(%d,%d,%d) | MENZIL:%dm | AKTIF:%d",
                tostring(cfg.runwayId), cfg.thrX, cfg.thrY, cfg.thrZ,
                cfg.mastX, cfg.mastY, cfg.mastZ, ZOOM_RANGES[zoomIdx], #sortedCallsigns
            ), colors.yellow, colors.gray)
        else
            local function tabStyle(id)
                local active = (activeTab == id)
                return active and colors.black or colors.lightGray, active and colors.cyan or colors.gray
            end
            local f1, b1 = tabStyle("RADAR")
            local f2, b2 = tabStyle("TRAFFIC")
            local f3, b3 = tabStyle("CONFIG")
            writeAt(surf, 2,  2, "[1:RADAR & KOMUTA]", f1, b1)
            writeAt(surf, 21, 2, "[2:TRAFIK & LOG]",   f2, b2)
            writeAt(surf, 38, 2, "[3:KULE AYARI]",     f3, b3)
        end

        local towerX = tonumber(cfg.mastX) or tonumber(cfg.thrX) or 0
        local towerZ = tonumber(cfg.mastZ) or tonumber(cfg.thrZ) or 0

        -- TAB 2: FULL TRAFFIC TABLE & ATC RADIO LOG
        if activeTab == "TRAFFIC" and not isLargeMonitor then
            writeAt(surf, 2, 3, "CAGRI KODU  TIP   MOD     IRTIFA   DIKEY   MESAFE", colors.cyan, colors.black)
            writeAt(surf, 2, 4, string.rep("-", w - 2), colors.gray, colors.black)
            if #sortedCallsigns == 0 then
                writeAt(surf, 2, 6, " Su anda radarda aktif hava araci gorunmuyor.", colors.lightGray, colors.black)
            else
                for i = 1, math.min(6, #sortedCallsigns) do
                    local call = sortedCallsigns[i]
                    local c = contacts[call]
                    local isSel = (i == selectedIdx)
                    local dx = (tonumber(c.pos and c.pos.x) or 0) - towerX
                    local dz = (tonumber(c.pos and c.pos.z) or 0) - towerZ
                    local dist = math.sqrt(dx * dx + dz * dz)
                    local line = string.format(
                        "%s%-10s %-5s %-7s %5.0fm  %+5.1f  %5.0fm",
                        isSel and ">" or " ",
                        tostring(call):sub(1, 10),
                        tostring(c.vehicleType or "ZEP"):sub(1, 5),
                        tostring(c.mode or "MAN"):sub(1, 7),
                        tonumber(c.altitude) or 0,
                        tonumber(c.vSpeed) or 0,
                        dist
                    )
                    writeAt(surf, 2, 4 + i, line:sub(1, w - 2), isSel and colors.black or colors.white, isSel and colors.lime or colors.black)
                end
            end

            writeAt(surf, 2, 11, "--- SON KULE TELSIZ & TRANSPONDER KAYITLARI ---", colors.yellow, colors.black)
            for i = 1, math.min(4, #atcLogs) do
                writeAt(surf, 2, 11 + i, atcLogs[i]:sub(1, w - 2), colors.lightGray, colors.black)
            end

            writeAt(surf, 2, h - 2, string.rep("-", w - 2), colors.gray, colors.black)
            writeAt(surf, 2, h - 1, statusToast:sub(1, w - 2), colors.yellow, colors.black)
            writeAt(surf, 2, h, "[1]:Radar [3]:Ayar [Up/Dn]:Sec [R]:RTB [H]:Hover [B]:Park", colors.cyan, colors.black)
            return
        end

        -- TAB 3: INTERACTIVE ILS & TOWER CONFIGURATOR
        if activeTab == "CONFIG" and not isLargeMonitor then
            writeAt(surf, 2, 3, "ILS & DIREK AYARLARI ([Up/Dn]:Sec [Lt/Rt]:+-Deger [Enter]:Yaz)", colors.yellow, colors.black)
            local startIdx = math.max(1, math.min(configCursor - 4, math.max(1, #CONFIG_FIELDS - 8)))
            local row = 4
            for i = startIdx, math.min(#CONFIG_FIELDS, startIdx + 8) do
                local f = CONFIG_FIELDS[i]
                local isSel = (i == configCursor)
                local valStr = tostring(cfg[f.key] or "")
                if isSel and editingString then
                    valStr = editBuffer .. "_"
                end
                local line = string.format("%s %-25s : %-18s", isSel and ">" or " ", f.label, valStr)
                writeAt(surf, 2, row, line:sub(1, w - 2), isSel and colors.black or colors.white, isSel and colors.cyan or colors.black)
                row = row + 1
            end

            writeAt(surf, 2, h - 5, string.rep("-", w - 2), colors.gray, colors.black)
            writeAt(surf, 2, h - 4, "[K] Secili Geminin Konumunu Direk & Pist Yap (Tek Tus)", colors.lime, colors.black)
            writeAt(surf, 2, h - 3, "[P] GPS/Sensorden Konum Al | [U] GitHub OTA Guncelle", colors.cyan, colors.black)
            writeAt(surf, 2, h - 2, statusToast:sub(1, w - 2), colors.yellow, colors.black)
            writeAt(surf, 2, h - 1, string.format("AKTIF DIREK:(%d,%d,%d) PIST:(%d,%d,%d)", cfg.mastX, cfg.mastY, cfg.mastZ, cfg.thrX, cfg.thrY, cfg.thrZ), colors.lightGray, colors.black)
            writeAt(surf, 2, h, "[1]:Radara Don | [Enter]:Deger Yaz | [S]:Kaydet | [Q]:Cik", colors.white, colors.black)
            return
        end

        -- TAB 1: SPLIT-SCREEN PPI RADAR SCOPE & FLIGHT TELEMETRY DECK
        local mapW = 21
        local mapH = 11
        local mapLeft = 2
        local mapTop = 3
        local cx = mapLeft + math.floor(mapW / 2)
        local cy = mapTop + math.floor(mapH / 2)
        local range = ZOOM_RANGES[zoomIdx]

        -- Framed PPI Radar Scope with Compass Rose (N, S, W, E)
        local topHdr = string.format("+---[ N %4dm ]---+", range)
        writeAt(surf, mapLeft, mapTop, topHdr, colors.cyan, colors.black)
        for ry = 1, mapH - 2 do
            local yPos = mapTop + ry
            if yPos == cy then
                writeAt(surf, mapLeft, yPos, "W" .. string.rep(".", mapW - 2) .. "E", colors.gray, colors.black)
            else
                writeAt(surf, mapLeft, yPos, "|" .. string.rep(" ", mapW - 2) .. "|", colors.cyan, colors.black)
                writeAt(surf, cx, yPos, ".", colors.gray, colors.black)
            end
        end
        writeAt(surf, mapLeft, mapTop + mapH - 1, "+------[ S ]------+", colors.cyan, colors.black)

        -- Plot Tower Center (+)
        writeAt(surf, cx, cy, "+", colors.yellow, colors.black)

        -- Plot Tracked Aircraft on PPI Radar
        for idx, call in ipairs(sortedCallsigns) do
            local c = contacts[call]
            if c and c.pos then
                local dx = (tonumber(c.pos.x) or 0) - towerX
                local dz = (tonumber(c.pos.z) or 0) - towerZ
                local px = cx + math.floor((dx / range) * math.floor((mapW - 3) / 2) + 0.5)
                local py = cy + math.floor((dz / range) * math.floor((mapH - 3) / 2) + 0.5)
                px = math.max(mapLeft + 1, math.min(mapLeft + mapW - 2, px))
                py = math.max(mapTop + 1, math.min(mapTop + mapH - 2, py))

                local vType = tostring(c.vehicleType or "ZEPPELIN")
                local sym = (vType == "MOTHERSHIP" and "M") or (vType == "AIRCRAFT" and "A") or "Z"
                local isSel = (idx == selectedIdx)
                writeAt(
                    surf,
                    px,
                    py,
                    sym,
                    isSel and colors.black or colors.lime,
                    isSel and colors.lime or colors.black
                )
            end
        end

        -- Right Pane: Selected Ship Telemetry Card & Mini Strip
        local rightX = mapLeft + mapW + 1
        local rightW = math.max(10, w - rightX)
        local tgtHdr = targetAll and "HEDEF: [TUM FILO (ALL)]" or string.format("TRAFIK (%d ARAC AKTIF)", #sortedCallsigns)
        writeAt(surf, rightX, 3, tgtHdr:sub(1, rightW), targetAll and colors.orange or colors.cyan, colors.black)

        if #sortedCallsigns == 0 then
            writeAt(surf, rightX, 5, "Radarda aktif gemi yok.", colors.lightGray, colors.black)
            writeAt(surf, rightX, 6, "Gemide Flight Control", colors.gray, colors.black)
            writeAt(surf, rightX, 7, "acikken otomatik gorunur.", colors.gray, colors.black)
            writeAt(surf, rightX, 9, string.format("DIREK: (%d, %d, %d)", cfg.mastX, cfg.mastY, cfg.mastZ), colors.yellow, colors.black)
            writeAt(surf, rightX, 10, string.format("PIST : %s (%d,%d,%d)", tostring(cfg.runwayId), cfg.thrX, cfg.thrY, cfg.thrZ), colors.lightGray, colors.black)
            writeAt(surf, rightX, 11, string.format("ILS YAYIN: #%d (1Hz)", beaconCount), colors.lime, colors.black)
        else
            -- Show up to 2 selectable strips + detailed telemetry box for selected craft
            for i = 1, math.min(2, #sortedCallsigns) do
                local idx = (selectedIdx > 2) and (selectedIdx - 2 + i) or i
                local call = sortedCallsigns[idx]
                local c = contacts[call]
                if c then
                    local isSel = (idx == selectedIdx)
                    local dx = (tonumber(c.pos and c.pos.x) or 0) - towerX
                    local dz = (tonumber(c.pos and c.pos.z) or 0) - towerZ
                    local dist = math.sqrt(dx * dx + dz * dz)
                    local vTag = (c.vehicleType == "MOTHERSHIP" and "MSHP") or (c.vehicleType == "AIRCRAFT" and "AIR ") or "ZEP "
                    local strip = string.format(
                        "%s%-9s %s %-6s %3.0fm",
                        isSel and ">" or " ",
                        tostring(call):sub(1, 9),
                        vTag,
                        tostring(c.mode or "MAN"):sub(1, 6),
                        dist
                    )
                    writeAt(surf, rightX, 3 + i, strip:sub(1, rightW), isSel and colors.black or colors.white, isSel and colors.lime or colors.black)
                end
            end

            -- Selected Aircraft Detailed Telemetry Box
            local sel = getSelectedContact()
            if sel and sel.pos then
                local dx = (tonumber(sel.pos.x) or 0) - towerX
                local dz = (tonumber(sel.pos.z) or 0) - towerZ
                local calcDist = math.sqrt(dx * dx + dz * dz)
                local dist = (calcDist > 0.5) and calcDist or (tonumber(sel.modemDist) or calcDist)
                local brg = (math.deg(math.atan2(-dx, dz)) % 360)
                writeAt(surf, rightX, 6, string.rep("-", rightW), colors.gray, colors.black)
                writeAt(surf, rightX, 7, string.format("SECILI: %s (%s)", tostring(sel.callsign), tostring(sel.mode or "MAN")):sub(1, rightW), colors.yellow, colors.black)
                writeAt(surf, rightX, 8, string.format("POS : (%d, %d, %d)", math.floor(sel.pos.x), math.floor(sel.pos.y), math.floor(sel.pos.z)):sub(1, rightW), colors.white, colors.black)
                writeAt(surf, rightX, 9, string.format("ALT : %.1fm (TGT:%.0fm)", tonumber(sel.altitude) or 0, tonumber(sel.targetAlt or sel.altitude) or 0):sub(1, rightW), colors.cyan, colors.black)
                writeAt(surf, rightX, 10, string.format("VSI : %+5.1fm/s | SPD:%.1f", tonumber(sel.vSpeed) or 0, tonumber(sel.speed) or 0):sub(1, rightW), colors.lime, colors.black)
                writeAt(surf, rightX, 11, string.format("MESAFE: %.0fm | YON:%03.0fd", dist, brg):sub(1, rightW), colors.lightGray, colors.black)
                writeAt(surf, rightX, 12, string.format("FREN: %s | DIREK:%dm", sel.parkingBrake and "PARK" or "ACIK", cfg.mastY):sub(1, rightW), colors.lightGray, colors.black)
            end
        end

        -- Row 14: Divider + Tower Coordinates Summary
        writeAt(surf, 2, 14, string.format(
            "--[ DIREK:(%d,%d,%d) | PIST:%s | ILS:#%d ]--",
            cfg.mastX, cfg.mastY, cfg.mastZ, tostring(cfg.runwayId), beaconCount
        ):sub(1, w - 2), colors.gray, colors.black)

        -- Row 15: Toast Notification Banner
        clearLineAt(surf, 15, (toastTicks > 0) and colors.cyan or colors.black)
        writeAt(
            surf,
            2,
            15,
            (">> " .. statusToast):sub(1, w - 2),
            (toastTicks > 0) and colors.black or colors.yellow,
            (toastTicks > 0) and colors.cyan or colors.black
        )

        -- Rows 16-19: Bottom Remote Command Keybind Dock
        writeAt(surf, 2, 16, "[R]Eve Cagir(RTB)  [G]Kuleye Cek(LNAV) [H]Havada Tut", colors.lime, colors.black)
        writeAt(surf, 2, 17, "[L]Otonom Indir    [B]Acil Park/Fren   [+/-]Irtifa+-10", colors.cyan, colors.black)
        writeAt(surf, 2, 18, "[K]Gemiden KonumAl [0]INS Kalibre Et   [Z]Radar Menzil", colors.yellow, colors.black)
        writeAt(surf, 2, 19, "[1/2/3]Sekme [Up/Dn]Sec [A]Filo [U]OTA Guncelle [Q]Cik", colors.lightGray, colors.black)
    end

    local function renderAll()
        drawTerminalSurface(parentTerm, false)
        for _, mon in ipairs(monitors) do
            pcall(drawExternalMonitor, mon)
        end
    end

    local function captureSelectedShipAsTowerPos()
        local sel = getSelectedContact()
        if not sel or not sel.pos then
            setToast("HATA: Konumu alinacak aktif gemi radarda yok!")
            return
        end
        cfg.mastX = math.floor((tonumber(sel.pos.x) or 0) + 0.5)
        cfg.mastY = math.floor((tonumber(sel.pos.y) or 85) + 0.5)
        cfg.mastZ = math.floor((tonumber(sel.pos.z) or 0) + 0.5)
        cfg.thrX  = cfg.mastX
        cfg.thrY  = cfg.mastY
        cfg.thrZ  = cfg.mastZ
        if sel.heading then
            cfg.rwyHeadingDeg = math.floor((tonumber(sel.heading) or 0) + 0.5) % 360
        end
        saveConfig(cfg)
        local msg = string.format("%s konumu (%d,%d,%d) Kule Diregi yapildi!", tostring(sel.callsign), cfg.mastX, cfg.mastY, cfg.mastZ)
        pushLog(msg)
        setToast("KAYDEDILDI: " .. msg)
    end

    -- 1Hz ILS Beacon Broadcast & 4Hz UI Refresh Loop
    local function beaconAndRenderLoop()
        local subTick = 0
        while running do
            subTick = subTick + 1
            sweepStep = (sweepStep % #SWEEP_CHARS) + 1
            if toastTicks > 0 then toastTicks = toastTicks - 1 end

            if subTick % 4 == 1 then
                local packet = buildBeaconPacket()
                if rednet and rednet.isOpen and rednet.isOpen() then
                    pcall(rednet.broadcast, packet, "DRUNKEN_ILS")
                    beaconCount = beaconCount + 1
                end
            end

            renderAll()
            sleep(0.25)
        end
    end

    -- Rednet Receiver (DRUNKEN_RADAR ADS-B), Modem Distance Tracker & Operator Input Loop
    local lastModemDist = {}
    local function eventLoop()
        while running do
            local ev, p1, p2, p3, p4, p5 = os.pullEvent()
            if ev == "modem_message" then
                local replyCh, dist = p3, p5
                if type(replyCh) == "number" and type(dist) == "number" then
                    lastModemDist[replyCh] = dist
                end
            elseif ev == "rednet_message" then
                local senderId, msg, protocol = p1, p2, p3
                if protocol == "DRUNKEN_RADAR" and type(msg) == "table" and msg.type == "AVIONICS_ADSB" then
                    local call = tostring(msg.callsign or ("SHIP-" .. tostring(senderId)))
                    local isNew = (contacts[call] == nil)
                    msg.callsign = call
                    msg.senderId = senderId
                    msg.modemDist = lastModemDist[senderId]
                    msg.lastSeenClock = os.clock()
                    contacts[call] = msg
                    if isNew then
                        pushLog(string.format("%s (%s) radara girdi (%.0fm)", call, tostring(msg.vehicleType or "ZEP"), tonumber(msg.altitude) or 0))
                    end
                end
            elseif ev == "peripheral" or ev == "peripheral_detach" then
                modem = findWirelessModem()
                modemName = modem and peripheral.getName(modem) or nil
                if modemName and rednet then
                    pcall(rednet.open, modemName)
                end
                monitors = findExternalMonitors()
            elseif ev == "monitor_touch" then
                zoomIdx = (zoomIdx % #ZOOM_RANGES) + 1
                setToast("RADAR MENZILI: " .. tostring(ZOOM_RANGES[zoomIdx]) .. "m")
            elseif ev == "mouse_click" and not editingString then
                local _, mx, my = p1, p2, p3
                if my == 2 then
                    if mx <= 20 then activeTab = "RADAR"
                    elseif mx <= 37 then activeTab = "TRAFFIC"
                    else activeTab = "CONFIG" end
                end
            elseif ev == "char" and editingString then
                editBuffer = editBuffer .. tostring(p1)
            elseif ev == "key" then
                local key = p1
                if editingString then
                    if key == keys.enter then
                        local f = CONFIG_FIELDS[configCursor]
                        if f then
                            if f.type == "number" then
                                local n = tonumber(editBuffer)
                                if n then cfg[f.key] = n end
                            else
                                if #editBuffer > 0 then cfg[f.key] = editBuffer end
                            end
                            saveConfig(cfg)
                            setToast("AYAR KAYDEDILDI: " .. f.label)
                        end
                        editingString = false
                    elseif key == keys.backspace then
                        editBuffer = editBuffer:sub(1, math.max(0, #editBuffer - 1))
                    end
                else
                    if key == keys.q then
                        running = false
                    elseif key == keys.one then
                        activeTab = "RADAR"
                    elseif key == keys.two then
                        activeTab = "TRAFFIC"
                    elseif key == keys.three then
                        activeTab = "CONFIG"
                    elseif key == keys.tab then
                        if activeTab == "RADAR" then activeTab = "TRAFFIC"
                        elseif activeTab == "TRAFFIC" then activeTab = "CONFIG"
                        else activeTab = "RADAR" end
                    elseif key == keys.k then
                        captureSelectedShipAsTowerPos()
                    elseif key == keys.zero then
                        sendAtcCommand("INS_SYNC", {
                            pos = {
                                x = tonumber(cfg.mastX) or 0,
                                y = tonumber(cfg.mastY) or 85,
                                z = tonumber(cfg.mastZ) or 0
                            }
                        })
                    elseif key == keys.u then
                        performOtaUpdate(setToast)
                    elseif activeTab == "CONFIG" then
                        local f = CONFIG_FIELDS[configCursor]
                        if key == keys.up then
                            configCursor = math.max(1, configCursor - 1)
                        elseif key == keys.down then
                            configCursor = math.min(#CONFIG_FIELDS, configCursor + 1)
                        elseif key == keys.left and f and f.type == "number" then
                            local v = (tonumber(cfg[f.key]) or 0) - (f.step or 1)
                            if f.min then v = math.max(f.min, v) end
                            cfg[f.key] = v
                            saveConfig(cfg)
                        elseif key == keys.right and f and f.type == "number" then
                            local v = (tonumber(cfg[f.key]) or 0) + (f.step or 1)
                            if f.max then v = math.min(f.max, v) end
                            cfg[f.key] = v
                            saveConfig(cfg)
                        elseif key == keys.enter and f then
                            editingString = true
                            editBuffer = ""
                        elseif key == keys.p then
                            local x, y, z, src = detectTowerPos(cfg)
                            if src then
                                cfg.mastX, cfg.mastY, cfg.mastZ = x, y + 10, z
                                cfg.thrX, cfg.thrY, cfg.thrZ = x, y, z
                                saveConfig(cfg)
                                setToast(string.format("KONUM ALINDI (%s): (%d, %d, %d)", src, x, y, z))
                            else
                                setToast("GPS veya Gemi Okuyucu bulunamadi! [K] ile gemiden alin.")
                            end
                        elseif key == keys.s then
                            saveConfig(cfg)
                            setToast("ils_beacon.conf diske kaydedildi!")
                        end
                    else
                        if key == keys.up then
                            selectedIdx = math.max(1, selectedIdx - 1)
                        elseif key == keys.down then
                            selectedIdx = math.min(math.max(1, #sortedCallsigns), selectedIdx + 1)
                        elseif key == keys.z then
                            zoomIdx = (zoomIdx % #ZOOM_RANGES) + 1
                            setToast("RADAR MENZILI: " .. tostring(ZOOM_RANGES[zoomIdx]) .. "m")
                        elseif key == keys.a then
                            targetAll = not targetAll
                            setToast(targetAll and "KOMUT HEDEFI: TUM FILO (ALL)" or "KOMUT HEDEFI: SADECE SECILI ARAC")
                        elseif key == keys.r then
                            sendAtcCommand("RTB")
                        elseif key == keys.g then
                            sendAtcCommand("WAYPOINT", {
                                waypoint = {
                                    x = tonumber(cfg.mastX) or 0,
                                    y = tonumber(cfg.mastY) or 85,
                                    z = tonumber(cfg.mastZ) or 0
                                }
                            })
                        elseif key == keys.h then
                            sendAtcCommand("HOVER")
                        elseif key == keys.l then
                            sendAtcCommand("AUTOLAND")
                        elseif key == keys.b then
                            sendAtcCommand("PARK")
                        elseif key == keys.equals or key == keys.numPadAdd then
                            sendAtcCommand("ALT_DELTA", { delta = 10 })
                        elseif key == keys.minus or key == keys.numPadSubtract then
                            sendAtcCommand("ALT_DELTA", { delta = -10 })
                        end
                    end
                end
            end
        end
    end

    if parallel and parallel.waitForAny then
        parallel.waitForAny(beaconAndRenderLoop, eventLoop)
    else
        beaconAndRenderLoop()
    end

    setColors(parentTerm, colors.white, colors.black)
    parentTerm.clear()
    parentTerm.setCursorPos(1, 1)
end

if ... == nil then
    runTowerConsole(nil)
end

return { run = runTowerConsole }
