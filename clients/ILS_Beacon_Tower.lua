-- clients/ILS_Beacon_Tower.lua
-- Drunken OS - ATC Radar Scope, Runway ILS / Mooring Mast Beacon & Remote Command Tower Console
-- Supports Standard (Monochrome) & Advanced (Color) Terminals + External Wall Monitors

local CONFIG_PATH = "ils_beacon.conf"

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
                    local w, _ = m.getSize()
                    if w < 36 and m.setTextScale then
                        m.setTextScale(0.5)
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

local function runTowerConsole(context)
    local parentTerm = (context and context.term) or term.current()
    local cfg = loadOrInitConfig()
    local modem = findWirelessModem()
    local modemName = modem and peripheral.getName(modem) or nil
    if modemName and rednet then
        pcall(rednet.open, modemName)
    end
    local monitors = findExternalMonitors()

    local activeTab = "RADAR" -- "RADAR" or "CONFIG"
    local zoomIdx = 2 -- 150m default
    local contacts = {} -- callsign -> telemetry table + lastSeen
    local sortedCallsigns = {}
    local selectedIdx = 1
    local targetAll = false
    local configCursor = 1
    local editingString = false
    local editBuffer = ""
    local statusToast = "ILS & ATC KULE AKTIF (1Hz Yayin + Canli Radar)"
    local toastTicks = 60
    local beaconCount = 0
    local running = true

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
        setToast(string.format("ATC EMRI GONDERILDI -> [%s]: %s", tgt, cmd))
    end

    local function drawSurface(surf, isWallMonitor)
        if not surf then return end
        local w, h = surf.getSize()
        setColors(surf, colors.white, colors.black)
        surf.clear()

        -- Top Title Bar
        clearLineAt(surf, 1, colors.blue)
        local modemBadge = (modemName and rednet and rednet.isOpen and rednet.isOpen()) and "TX:ON" or "TX:YOK"
        writeAt(surf, 2, 1, string.format("DRUNKEN ATC & ILS KULE [%s] %s", tostring(cfg.baseName), modemBadge), colors.white, colors.blue)

        -- Subheader / Tab Selector
        clearLineAt(surf, 2, colors.gray)
        if isWallMonitor then
            writeAt(surf, 2, 2, string.format(
                "PIST:%s (%d,%d,%d) | DIREK:(%d,%d,%d) | MENZIL:%dm",
                tostring(cfg.runwayId),
                cfg.thrX, cfg.thrY, cfg.thrZ,
                cfg.mastX, cfg.mastY, cfg.mastZ,
                ZOOM_RANGES[zoomIdx]
            ), colors.yellow, colors.gray)
        else
            local t1Fg = (activeTab == "RADAR") and colors.black or colors.lightGray
            local t1Bg = (activeTab == "RADAR") and colors.cyan or colors.gray
            local t2Fg = (activeTab == "CONFIG") and colors.black or colors.lightGray
            local t2Bg = (activeTab == "CONFIG") and colors.cyan or colors.gray
            writeAt(surf, 2, 2, " [1] RADAR & KOMUTA ", t1Fg, t1Bg)
            writeAt(surf, 23, 2, " [2] ILS & DIREK AYARI ", t2Fg, t2Bg)
            writeAt(surf, 47, 2, "[Q]Cik", colors.white, colors.gray)
        end

        if activeTab == "CONFIG" and not isWallMonitor then
            writeAt(surf, 2, 4, "KULE & ILS KONFIGURASYONU ([Up/Dn]:Sec [Lt/Rt]:Degistir [Enter]:Yaz)", colors.yellow, colors.black)
            local startIdx = math.max(1, math.min(configCursor - 4, math.max(1, #CONFIG_FIELDS - 7)))
            local row = 5
            for i = startIdx, math.min(#CONFIG_FIELDS, startIdx + 7) do
                local f = CONFIG_FIELDS[i]
                local isSel = (i == configCursor)
                local valStr = tostring(cfg[f.key] or "")
                if isSel and editingString then
                    valStr = editBuffer .. "_"
                end
                local line = string.format("%s %-26s : %s", isSel and ">" or " ", f.label, valStr)
                writeAt(surf, 2, row, line, isSel and colors.black or colors.white, isSel and colors.cyan or colors.black)
                row = row + 1
            end

            writeAt(surf, 2, h - 4, string.rep("-", w - 2), colors.gray, colors.black)
            writeAt(surf, 2, h - 3, "[K] Secili Geminin Konumunu Direk & Pist Olarak Kaydet!", colors.lime, colors.black)
            writeAt(surf, 2, h - 2, "[P] GPS / Sensorden Kule Konumunu Otomatik Al", colors.cyan, colors.black)
            writeAt(surf, 2, h - 1, statusToast:sub(1, w - 2), colors.yellow, colors.black)
            writeAt(surf, 2, h, "[Tab/1]:Radara Don | [Enter]:Deger Gir | [S]:Kaydet", colors.lightGray, colors.black)
            return
        end

        -- RADAR & TRAFFIC VIEW (Both Terminal Tab 1 & External Wall Monitors)
        rebuildContactList()
        local mapW = math.min(21, math.max(15, math.floor(w * 0.40)))
        local mapH = math.max(7, h - 7)
        local mapLeft = 2
        local mapTop = 3
        local cx = mapLeft + math.floor(mapW / 2)
        local cy = mapTop + math.floor(mapH / 2)
        local range = ZOOM_RANGES[zoomIdx]

        -- Draw Radar Scope Border
        local borderTop = "+" .. string.format("-%dm-", range) .. string.rep("-", math.max(0, mapW - 7)) .. "+"
        writeAt(surf, mapLeft, mapTop, borderTop:sub(1, mapW), colors.cyan, colors.black)
        for ry = 1, mapH - 2 do
            writeAt(surf, mapLeft, mapTop + ry, "|" .. string.rep(".", mapW - 2) .. "|", colors.gray, colors.black)
        end
        writeAt(surf, mapLeft, mapTop + mapH - 1, "+" .. string.rep("-", mapW - 2) .. "+", colors.cyan, colors.black)

        -- Draw Tower Center (+) & Runway Threshold (T)
        local towerX = tonumber(cfg.mastX) or tonumber(cfg.thrX) or 0
        local towerZ = tonumber(cfg.mastZ) or tonumber(cfg.thrZ) or 0
        writeAt(surf, cx, cy, "+", colors.yellow, colors.black)

        -- Plot Contacts on PPI Scope
        for idx, call in ipairs(sortedCallsigns) do
            local c = contacts[call]
            if c and c.pos then
                local dx = (tonumber(c.pos.x) or 0) - towerX
                local dz = (tonumber(c.pos.z) or 0) - towerZ
                local normX = dx / range
                local normZ = dz / range
                local px = cx + math.floor(normX * math.floor((mapW - 3) / 2) + 0.5)
                local py = cy + math.floor(normZ * math.floor((mapH - 3) / 2) + 0.5)
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

        -- Right Pane: Active Traffic Table & Selected Telemetry
        local rightX = mapLeft + mapW + 2
        local rightW = math.max(10, w - rightX)
        local targetModeLabel = targetAll and "[HEDEF: TUM FILO]" or "[HEDEF: SECILI]"
        writeAt(surf, rightX, 3, "HAVA TRAFIGI " .. targetModeLabel, colors.cyan, colors.black)

        if #sortedCallsigns == 0 then
            writeAt(surf, rightX, 5, "Radarda aktif arac yok.", colors.lightGray, colors.black)
            writeAt(surf, rightX, 6, "Gemide Flight Control", colors.gray, colors.black)
            writeAt(surf, rightX, 7, "acik oldugundan emin olun.", colors.gray, colors.black)
        else
            local maxRows = math.max(2, math.min(5, mapH - 5))
            local startRow = math.max(1, math.min(selectedIdx - maxRows + 1, #sortedCallsigns - maxRows + 1))
            for i = startRow, math.min(#sortedCallsigns, startRow + maxRows - 1) do
                local call = sortedCallsigns[i]
                local c = contacts[call]
                local isSel = (i == selectedIdx)
                local dx = (tonumber(c.pos and c.pos.x) or 0) - towerX
                local dz = (tonumber(c.pos and c.pos.z) or 0) - towerZ
                local dist = math.sqrt(dx * dx + dz * dz)
                local rowY = 4 + (i - startRow)
                local vTag = (c.vehicleType == "MOTHERSHIP" and "MSH") or (c.vehicleType == "AIRCRAFT" and "AIR") or "ZEP"
                local line = string.format(
                    "%s%-8s %s %4.0fm %-6s",
                    isSel and ">" or " ",
                    tostring(call):sub(1, 8),
                    vTag,
                    dist,
                    tostring(c.mode or "MAN"):sub(1, 6)
                )
                writeAt(
                    surf,
                    rightX,
                    rowY,
                    line:sub(1, rightW),
                    isSel and colors.black or colors.white,
                    isSel and colors.lime or colors.black
                )
            end

            -- Selected Aircraft Detailed Telemetry Box
            local sel = getSelectedContact()
            if sel and sel.pos then
                local detailY = 4 + maxRows + 1
                local dx = (tonumber(sel.pos.x) or 0) - towerX
                local dz = (tonumber(sel.pos.z) or 0) - towerZ
                local dist = math.sqrt(dx * dx + dz * dz)
                writeAt(surf, rightX, detailY, string.format(
                    "KONUM: (%d, %d, %d)",
                    math.floor(sel.pos.x), math.floor(sel.pos.y), math.floor(sel.pos.z)
                ), colors.yellow, colors.black)
                writeAt(surf, rightX, detailY + 1, string.format(
                    "ALT:%.0fm (TGT:%.0fm) VSI:%+.1f",
                    tonumber(sel.altitude) or 0,
                    tonumber(sel.targetAlt or sel.altitude) or 0,
                    tonumber(sel.vSpeed) or 0
                ), colors.white, colors.black)
                writeAt(surf, rightX, detailY + 2, string.format(
                    "SPD:%.1fm/s HDG:%03.0fd DST:%.0fm",
                    tonumber(sel.speed) or 0,
                    tonumber(sel.heading) or 0,
                    dist
                ), colors.lightGray, colors.black)
            end
        end

        -- Bottom Status & ATC Remote Command Dock
        local dockTop = h - 4
        writeAt(surf, 2, dockTop, string.format(
            "DIREK:(%d,%d,%d) | PIST:%s(%d,%d,%d) | YAYIN:#%d",
            cfg.mastX, cfg.mastY, cfg.mastZ,
            tostring(cfg.runwayId), cfg.thrX, cfg.thrY, cfg.thrZ,
            beaconCount
        ):sub(1, w - 2), colors.lightGray, colors.black)

        writeAt(surf, 2, dockTop + 1, statusToast:sub(1, w - 2), colors.yellow, colors.black)
        writeAt(surf, 2, dockTop + 2, "[R]RTB Cagir [G]Kuleye Cek [H]Hover [L]Indir [B]Acil Park", colors.lime, colors.black)
        writeAt(surf, 2, dockTop + 3, "[+/-]Irtifa+-10 [Z]Zoom [A]Hedef(Tek/Tum) [K]KonumKaydet [2]Ayar", colors.cyan, colors.black)
    end

    local function renderAll()
        drawSurface(parentTerm, false)
        for _, mon in ipairs(monitors) do
            pcall(drawSurface, mon, true)
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
        setToast(string.format("KAYDEDILDI: %s konumu (%d,%d,%d) Kule Diregi yapildi!", tostring(sel.callsign), cfg.mastX, cfg.mastY, cfg.mastZ))
    end

    -- 1Hz ILS Beacon Broadcast & 4Hz UI Refresh Loop
    local function beaconAndRenderLoop()
        local subTick = 0
        while running do
            subTick = subTick + 1
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

    -- Rednet Receiver (DRUNKEN_RADAR ADS-B) & Operator Keyboard/Monitor Input Loop
    local function eventLoop()
        while running do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "rednet_message" then
                local senderId, msg, protocol = p1, p2, p3
                if protocol == "DRUNKEN_RADAR" and type(msg) == "table" and msg.type == "AVIONICS_ADSB" then
                    local call = tostring(msg.callsign or ("SHIP-" .. tostring(senderId)))
                    msg.callsign = call
                    msg.senderId = senderId
                    msg.lastSeenClock = os.clock()
                    contacts[call] = msg
                end
            elseif ev == "peripheral" or ev == "peripheral_detach" then
                modem = findWirelessModem()
                modemName = modem and peripheral.getName(modem) or nil
                if modemName and rednet then
                    pcall(rednet.open, modemName)
                end
                monitors = findExternalMonitors()
            elseif ev == "monitor_touch" then
                -- Touching external monitor cycles radar zoom range
                zoomIdx = (zoomIdx % #ZOOM_RANGES) + 1
                setToast("RADAR MENZILI: " .. tostring(ZOOM_RANGES[zoomIdx]) .. "m")
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
                        activeTab = "CONFIG"
                    elseif key == keys.tab then
                        activeTab = (activeTab == "RADAR") and "CONFIG" or "RADAR"
                    elseif key == keys.k then
                        captureSelectedShipAsTowerPos()
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
                    elseif activeTab == "RADAR" then
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
