-- apps/flight_control.lua
-- Drunken OS Primary Flight Display (PFD) & Autopilot Cockpit App

-- Ensure standard Drunken OS library paths are resolvable across standalone and sub-shell execution
if package and package.path then
    package.path = "/?.lua;/lib/?.lua;?.lua;lib/?.lua;" .. package.path
end

local colors = _G.colors or {
    white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32,
    pink = 64, gray = 128, lightGray = 256, cyan = 512, purple = 1024,
    blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768
}

local Avionics
local okAvionics, modAvionics = pcall(require, "lib.avionics")
if okAvionics and type(modAvionics) == "table" then
    Avionics = modAvionics
else
    local ok2, mod2 = pcall(require, "avionics")
    if ok2 and type(mod2) == "table" then
        Avionics = mod2
    elseif fs and fs.exists and (fs.exists("/lib/avionics.lua") or fs.exists("lib/avionics.lua") or fs.exists("avionics.lua") or fs.exists("/avionics.lua")) then
        local candidate = fs.exists("/lib/avionics.lua") and "/lib/avionics.lua"
            or (fs.exists("lib/avionics.lua") and "lib/avionics.lua"
            or (fs.exists("/avionics.lua") and "/avionics.lua" or "avionics.lua"))
        Avionics = dofile(candidate)
    else
        error("Drunken Avionics HAL missing! Could not load lib.avionics: " .. tostring(modAvionics))
    end
end

local okSound, Sound = pcall(require, "lib.sound")
if not okSound or type(Sound) ~= "table" then
    local ok2, mod2 = pcall(require, "sound")
    if ok2 and type(mod2) == "table" then
        Sound = mod2
        okSound = true
    elseif fs and fs.exists and (fs.exists("/lib/sound.lua") or fs.exists("lib/sound.lua")) then
        local p = fs.exists("/lib/sound.lua") and "/lib/sound.lua" or "lib/sound.lua"
        local okLoad, modLoad = pcall(dofile, p)
        if okLoad and type(modLoad) == "table" then
            Sound = modLoad
            okSound = true
        end
    end
end

local function renderTacticalDisplay(mon, tel, ap)
    if not mon or not mon.getSize then return end
    local w, h = mon.getSize()
    if w < 20 or h < 7 then return end
    local isCol = mon.isColor and mon.isColor()

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Header
    mon.setCursorPos(1, 1)
    mon.setBackgroundColor(isCol and colors.blue or colors.black)
    mon.setTextColor(colors.white)
    local hdr = " TAKTIK & NAVIGASYON (AMIRAL KAMARASI) "
    if #hdr > w then hdr = hdr:sub(1, w) end
    mon.write(hdr .. string.rep(" ", math.max(0, w - #hdr)))

    -- Callsign & Mode
    mon.setBackgroundColor(colors.black)
    mon.setCursorPos(2, 2)
    mon.setTextColor(isCol and colors.cyan or colors.white)
    local vType = tel.vehicleType or "UNKNOWN"
    mon.write(string.format("GEMI: %-10s [%s]", tostring(tel.callsign or "DOS"), vType))

    mon.setCursorPos(2, 3)
    local apMode = ap.mode or "MANUAL"
    mon.setTextColor(ap.enabled and (isCol and colors.lime or colors.white) or (isCol and colors.orange or colors.white))
    mon.write(string.format("MOD : %s (PARK:%s)", apMode, ap.parkingBrake and "ON" or "OFF"))

    -- Coordinates & GPS
    mon.setCursorPos(2, 4)
    mon.setTextColor(colors.white)
    local px = tel.pos and math.floor(tel.pos.x + 0.5) or 0
    local py = tel.pos and math.floor(tel.pos.y + 0.5) or 0
    local pz = tel.pos and math.floor(tel.pos.z + 0.5) or 0
    mon.write(string.format("POS : X:%d Y:%d Z:%d", px, py, pz))

    -- Flight Dynamics
    mon.setCursorPos(2, 5)
    mon.setTextColor(isCol and colors.yellow or colors.white)
    local alt = tel.altitude or 0
    local tgtAlt = ap.targetAlt or 0
    local agl = tel.agl and string.format("%.1fm", tel.agl) or "N/A"
    mon.write(string.format("ALT : %5.1fm (TGT:%5.1fm) AGL:%s", alt, tgtAlt, agl))

    -- Speed & Heading
    mon.setCursorPos(2, 6)
    mon.setTextColor(colors.white)
    local spd = tel.speed or 0
    local vsi = tel.vSpeed or 0
    local hdg = math.deg(tel.heading or 0) % 360
    mon.write(string.format("SPD : %4.1fm/s | VSI:%+4.1fm/s | HDG:%03.0f", spd, vsi, hdg))

    -- ILS & Approach
    if h >= 7 then
        mon.setCursorPos(2, 7)
        if ap.homeBase then
            mon.setTextColor(isCol and colors.cyan or colors.white)
            local rwy = ap.homeBase.runwayId or "RWY"
            mon.write(string.format("ILS : %s - RTB HAZIR", tostring(rwy)))
        else
            mon.setTextColor(isCol and colors.gray or colors.white)
            mon.write("ILS : BEACON ARANIYOR...")
        end
    end

    -- Radar & Terrain Alert
    if h >= 8 then
        mon.setCursorPos(2, 8)
        if tel.gpwsWarning then
            mon.setBackgroundColor(colors.red)
            mon.setTextColor(colors.white)
            mon.write(" ! DIKKAT: ARAZI CARPISMA RISKI ! ")
        else
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(isCol and colors.lime or colors.white)
            mon.write("RADAR: ADS-B 1Hz YAYINDA")
        end
    end
end

local function renderScadaDisplay(mon, tel, ap)
    if not mon or not mon.getSize then return end
    local w, h = mon.getSize()
    if w < 20 or h < 7 then return end
    local isCol = mon.isColor and mon.isColor()

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Header
    mon.setCursorPos(1, 1)
    mon.setBackgroundColor(isCol and colors.orange or colors.black)
    mon.setTextColor(colors.black)
    local hdr = " MAKINE DAIRESI - SCADA & MOTORLAR "
    if #hdr > w then hdr = hdr:sub(1, w) end
    mon.write(hdr .. string.rep(" ", math.max(0, w - #hdr)))

    -- Powertrain
    mon.setBackgroundColor(colors.black)
    mon.setCursorPos(2, 2)
    mon.setTextColor(colors.white)
    local rpm = tel.rpm or 0
    mon.write(string.format("DEVIR (RPM): %5.0f | GAZ: %2d/15", rpm, ap.baseThrottle or 0))

    -- Stress & Transmission
    mon.setCursorPos(2, 3)
    if tel.overstressed then
        mon.setTextColor(isCol and colors.red or colors.white)
        mon.write("STRES : ! ASIRI YUK (OVERSTRESS) !")
    else
        mon.setTextColor(isCol and colors.lime or colors.white)
        mon.write("STRES : NOMINAL (SAFT GUVENDE)")
    end

    -- Gear & Clutch
    mon.setCursorPos(2, 4)
    mon.setTextColor(colors.white)
    local gearStr = ap.reverseGear and "GERI" or "ILERI"
    local clutchCut = (ap.mode == "HOVER") or ap.parkingBrake or ((ap.baseThrottle or 0) <= 0)
    mon.write(string.format("VITES : %s | DEBRIYAJ: %s", gearStr, clutchCut and "KESIK" or "AKTIF"))

    -- Quad-Rotor Vertical Lift Units or Burner
    local vType = tel.vehicleType or "MOTHERSHIP"
    if vType == "MOTHERSHIP" or vType == "GUNSHIP" then
        local ms = tel.mothership or { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 }
        mon.setCursorPos(2, 5)
        mon.setTextColor(isCol and colors.cyan or colors.white)
        local w = tel.wingAlt
        mon.write(string.format("LIFT ON  : FL:%2d FR:%2d ", ms.fl, ms.fr) .. (w and string.format("KNT dR%+.1f dP%+.1f", w.dR, w.dP) or "(BALANS)"))

        if h >= 6 then
            mon.setCursorPos(2, 6)
            mon.write(string.format("LIFT ARKA: RL:%2d RR:%2d (BALANS)", ms.rl, ms.rr))
        end

        if h >= 7 then
            mon.setCursorPos(2, 7)
            mon.setTextColor(isCol and colors.lime or colors.white)
            mon.write(string.format("ARKA ITKI: L:%+2d  C:%+2d  R:%+2d", ms.rearL, ms.rearC, ms.rearR))
        end
    elseif vType == "ZEPPELIN" then
        mon.setCursorPos(2, 5)
        mon.setTextColor(isCol and colors.orange or colors.white)
        mon.write(string.format("KAZAN / BURNER: %2d/15 (%s)", tel.burnerCmd or 0, tel.burnerActive and "YANIYOR" or "KAPALI"))
        if h >= 6 then
            mon.setCursorPos(2, 6)
            mon.setTextColor(colors.white)
            mon.write(string.format("ARKA PERVANE  : %2d/15", ap.baseThrottle or 0))
        end
    else
        mon.setCursorPos(2, 5)
        mon.setTextColor(isCol and colors.cyan or colors.white)
        mon.write(string.format("TRIM: P:%+4.1f deg | R:%+4.1f deg", math.deg(tel.pitch or 0), math.deg(tel.roll or 0)))
    end

    if h >= 8 then
        mon.setCursorPos(2, h)
        mon.setTextColor(isCol and colors.gray or colors.white)
        mon.write("CAN BUS: 20Hz SENKRON TELEMETRI")
    end
end


local function run(context)
    context = context or {}
    local parentTerm = context.parent or term.current()
    local isColor = parentTerm.isColor and parentTerm.isColor()
    if isColor == nil and term.isColor then isColor = term.isColor() end

    local theme = context.theme or {
        bg      = colors.black,
        fg      = colors.white,
        accent  = isColor and colors.cyan or colors.white,
        header  = isColor and colors.blue or colors.white,
        ok      = isColor and colors.lime or colors.white,
        warn    = isColor and colors.orange or colors.white,
        err     = isColor and colors.red or colors.white,
        muted   = isColor and colors.gray or colors.white
    }

    local fc = Avionics.new({
        callsign    = context.username and ("DOS-" .. string.upper(string.sub(context.username, 1, 4))) or nil,
        startParked = true
    })

    local running = true
    local activeTab = fc.hasSavedProfile and "PFD" or "PROFILE" -- "PROFILE", "PFD", or "IO"
    local selectedProfileIdx = (fc.vehicleType == "MOTHERSHIP" and 3) or (fc.vehicleType == "AIRCRAFT" and 2) or 1
    local selectedIOIdx = 1
    local ioScrollOffset = 0
    -- Show loaded GitHub AVX extension modules (or load error) at boot
    local hotplugNotice = fc.modErr and ("AVX HATA: " .. fc.modErr) or (#(fc.mods or {}) > 0 and ("AVX MODUL: " .. #fc.mods .. " yuklendi") or nil)
    local hotplugTimer = hotplugNotice and 100 or 0

    local lastTel = fc:readTelemetry(0.05)
    if lastTel.altitude and lastTel.altitude ~= 0 then
        fc.ap.targetAlt = math.floor(lastTel.altitude + 0.5)
    end
    local tickCount = 0

    local PROFILE_LIST = {
        {
            id    = "ZEPPELIN",
            title = "[1] ZEPPELIN (Hava Gemisi / Balon)",
            desc1 = "3x Hot Air Burner (Irtifa PID) + Arka Pervane",
            desc2 = "Inverted Clutch Fren + Dumen / Yatay Gyro Donus"
        },
        {
            id    = "AIRCRAFT",
            title = "[2] AIRCRAFT (Sabit Kanat / VTOL Ucak)",
            desc1 = "Cift/Tek Motor Diferansiyel Itki + Inis Takimi",
            desc2 = "3D Gyroscopic Propeller Vektorleme (12 deg Koni)"
        },
        {
            id    = "MOTHERSHIP",
            title = "[3] MOTHERSHIP (4x Dikey Lift + 3x Arka Itki)",
            desc1 = "4 Buyuk Dikey Motor: Gimbal (Pitch/Roll) + Irtifa Denge",
            desc2 = "3 Arka Manevra Motoru: Sol/Orta/Sag Diferansiyel Donus"
        }
    }

    local ROLE_DESC = {
        AUTO         = "Otomatik: Blok tipine gore varsayilan gorev",
        LIFT_FL      = "[1] Mothership ON-SOL Dikey Lift & Gimbal Denge",
        LIFT_FR      = "[2] Mothership ON-SAG Dikey Lift & Gimbal Denge",
        LIFT_RL      = "[3] Mothership ARKA-SOL Dikey Lift & Gimbal Denge",
        LIFT_RR      = "[4] Mothership ARKA-SAG Dikey Lift & Gimbal Denge",
        REAR_LEFT    = "[5] Mothership ARKA-SOL Manevra & Ileri/Geri Itki",
        REAR_CENTER  = "[6] Mothership ARKA-ORTA Ana Ileri/Geri Itki",
        REAR_RIGHT   = "[7] Mothership ARKA-SAG Manevra & Ileri/Geri Itki",
        LIFT_BURNER  = "Irtifa / Kazan: PID yukseklik sinyali (0-15)",
        THRUST_MAIN  = "Ana Itki: Ileri/Geri ana gaz sinyali (0-15)",
        THRUST_PORT  = "Sol Itki (Port): Diferansiyel sol motor gucu",
        THRUST_STBD  = "Sag Itki (Stbd): Diferansiyel sag motor gucu",
        AUX_BOOST    = "Boost Thruster: Gaz >= 12 oldugunda tam guc",
        CLUTCH_BRAKE = "Debriyaj / Fren: [B] Fren veya Gaz=0'da keser",
        GEAR_REVERSE = "Geri Vites (Gearshift): [G] ile yonu tersler",
        RUDDER_YAW   = "Dumen (Rudder): Yonlendirme acisi / sinyali",
        IGNORE       = "Devre Disi: Ucus bilgisayari bu bloga dokunmaz"
    }

    -- Open all available modems (wired & wireless) for Fly-by-Wire Bus & ADS-B Telemetry
    local modem = peripheral.find("modem", function(_, m) return m.isWireless and m.isWireless() end)
    if rednet then
        for _, side in ipairs(peripheral.getNames()) do
            if peripheral.getType(side) == "modem" and not rednet.isOpen(side) then
                pcall(rednet.open, side)
            end
        end
    end

    local hasLocalSensors = (fc.altSensor ~= nil or fc.gimbal ~= nil or fc.nav ~= nil or fc.velSensor ~= nil)
    local isRemoteFCC = not hasLocalSensors
    local cachedMonitors = { peripheral.find("monitor") }

    -- Probe Avionics Core Daemon on bus if available
    if rednet and rednet.isOpen and rednet.isOpen() then
        pcall(rednet.broadcast, { type = "AVIONICS_DISCOVER" }, "DRUNKEN_AVIONICS_BUS")
    end

    local function sendAvionicsCmd(cmd, payload)
        if rednet and rednet.isOpen and rednet.isOpen() then
            local pkt = { type = "AVIONICS_CMD", cmd = cmd }
            if payload then
                for k, v in pairs(payload) do pkt[k] = v end
            end
            pcall(rednet.broadcast, pkt, "DRUNKEN_AVIONICS_BUS")
        end
    end

    local drawTerm = parentTerm

    local function playAlert(alertType)
        if not okSound or not Sound then return end
        if alertType == "GPWS" and Sound.playError then
            pcall(Sound.playError)
        elseif alertType == "CLICK" and Sound.playClick then
            pcall(Sound.playClick)
        end
    end

    local function makeBar(val, maxVal, width)
        local filled = math.floor( math.max(0, math.min(1, val / math.max(1, maxVal))) * width + 0.5 )
        return "[" .. string.rep("|", filled) .. string.rep(".", width - filled) .. "]"
    end

    local function formatCompassTape(hdgDeg, width)
        local tape = "N...NE...E...SE...S...SW...W...NW..."
        local totalChars = #tape
        local centerIdx = math.floor(((hdgDeg % 360) / 360) * totalChars) + 1
        local half = math.floor(width / 2)
        local out = {}
        for i = -half, half do
            local idx = ((centerIdx + i - 1) % totalChars) + 1
            table.insert(out, tape:sub(idx, idx))
        end
        return table.concat(out)
    end

    local function drawArtificialHorizon(cx, cy, width, height, pitchRad, rollRad)
        local pitchDeg = math.deg(pitchRad)
        local rollSlope = math.tan(rollRad)
        local pitchOffset = math.floor((pitchDeg / 10) + 0.5)
        local halfW = math.floor(width / 2)
        local halfH = math.floor(height / 2)

        for dy = -halfH, halfH do
            local y = cy + dy
            if y >= 3 and y <= 14 then
                drawTerm.setCursorPos(cx - halfW, y)
                for dx = -halfW, halfW do
                    local horizonY = pitchOffset + math.floor(dx * rollSlope + 0.5)
                    if dy == 0 and math.abs(dx) <= 2 then
                        -- Center Aircraft Reticle
                        drawTerm.setBackgroundColor(colors.black)
                        drawTerm.setTextColor(isColor and colors.yellow or colors.white)
                        drawTerm.write(dx == 0 and "+" or "-")
                    elseif dy < horizonY then
                        -- Sky
                        drawTerm.setBackgroundColor(isColor and colors.blue or colors.black)
                        drawTerm.setTextColor(colors.white)
                        drawTerm.write(" ")
                    elseif dy == horizonY then
                        -- Horizon Line
                        drawTerm.setBackgroundColor(isColor and colors.cyan or colors.black)
                        drawTerm.setTextColor(colors.white)
                        drawTerm.write("-")
                    else
                        -- Ground
                        drawTerm.setBackgroundColor(isColor and colors.brown or colors.black)
                        drawTerm.setTextColor(isColor and colors.lightGray or colors.white)
                        drawTerm.write(isColor and " " or "#")
                    end
                end
            end
        end
    end

    local function renderHeader(w)
        drawTerm.setCursorPos(1, 1)
        drawTerm.setBackgroundColor(theme.header or colors.blue)
        drawTerm.setTextColor(colors.white)
        local vShort = (lastTel.vehicleType == "MOTHERSHIP" and "MSHIP")
            or (lastTel.vehicleType == "GUNSHIP" and "GSHIP")
            or (lastTel.vehicleType == "ZEPPELIN" and "ZEP")
            or "AIR"
        local tabLabel = (activeTab == "PFD") and "[PFD] [P:I/O] [V:ARAC]"
            or ((activeTab == "IO") and "[P:PFD] [I/O] [V:ARAC]" or "[ARAC SECIMI]")
        local modeStr = fc.ap.mode
        if isRemoteFCC then
            modeStr = modeStr .. " [REMOTE FCC]"
        end
        local headerText = string.format(
            " DOS | %s [%s] | %s | %s",
            lastTel.callsign or "DOS",
            vShort,
            modeStr,
            tabLabel
        )
        if #headerText > w then headerText = headerText:sub(1, w) end
        drawTerm.write(headerText .. string.rep(" ", math.max(0, w - #headerText)))
    end

    local function renderProfileSelector(w, h)
        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.clear()
        renderHeader(w)

        drawTerm.setCursorPos(2, 3)
        drawTerm.setTextColor(theme.accent or colors.cyan)
        drawTerm.write("=== ARAC KONTROL PROFILINI SECIN ===")

        for i, p in ipairs(PROFILE_LIST) do
            local baseY = 4 + (i - 1) * 4
            local isSel = (i == selectedProfileIdx)
            drawTerm.setCursorPos(2, baseY)
            drawTerm.setBackgroundColor(isSel and (isColor and colors.cyan or colors.white) or theme.bg)
            drawTerm.setTextColor(isSel and colors.black or (theme.ok or colors.lime))
            local lineTitle = (isSel and " > " or "   ") .. p.title
            drawTerm.write(lineTitle .. string.rep(" ", math.max(0, w - 3 - #lineTitle)))

            drawTerm.setBackgroundColor(theme.bg)
            drawTerm.setTextColor(theme.fg)
            drawTerm.setCursorPos(5, baseY + 1)
            drawTerm.write(p.desc1:sub(1, w - 6))
            drawTerm.setTextColor(theme.muted)
            drawTerm.setCursorPos(5, baseY + 2)
            drawTerm.write(p.desc2:sub(1, w - 6))
        end

        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.setCursorPos(2, h - 1)
        drawTerm.setTextColor(theme.ok or colors.lime)
        drawTerm.write("[1/2/3] veya [Up/Dn + Enter]: Profili Kur & Baslat")
        drawTerm.setCursorPos(2, h)
        drawTerm.setTextColor(colors.lightGray)
        drawTerm.write("[P]: I/O Motor Siralamasi | [V/Tab]: Kokpite Don")
    end

    local function renderIOConfigurator(w, h)
        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.clear()
        renderHeader(w)

        drawTerm.setBackgroundColor(isColor and colors.gray or colors.black)
        drawTerm.setTextColor(isColor and colors.yellow or colors.white)
        drawTerm.setCursorPos(1, 2)
        local colHdr = string.format(" %-18s %-12s %-12s %-4s", "CIHAZ / KANAL", "TIP", "GOREV (ROLE)", "INV")
        drawTerm.write(colHdr .. string.rep(" ", math.max(0, w - #colHdr)))

        local devs = fc.ioDevices or {}
        local maxRows = math.max(3, h - 6)
        if selectedIOIdx > #devs then selectedIOIdx = math.max(1, #devs) end
        if selectedIOIdx < ioScrollOffset + 1 then
            ioScrollOffset = math.max(0, selectedIOIdx - 1)
        elseif selectedIOIdx > ioScrollOffset + maxRows then
            ioScrollOffset = selectedIOIdx - maxRows
        end

        for row = 1, maxRows do
            local idx = ioScrollOffset + row
            local y = 2 + row
            drawTerm.setCursorPos(1, y)
            if idx <= #devs then
                local item = devs[idx]
                local cfg = fc:getDeviceConfig(item.name)
                local isSel = (idx == selectedIOIdx)
                local isTesting = (fc.spinTest and fc.spinTest.name == item.name)
                drawTerm.setBackgroundColor(
                    isTesting and (isColor and colors.orange or colors.white)
                    or (isSel and (isColor and colors.cyan or colors.white) or theme.bg)
                )
                drawTerm.setTextColor((isSel or isTesting) and colors.black or theme.fg)

                local shortName = item.name
                if #shortName > 17 then shortName = shortName:sub(1, 15) .. ".." end
                local shortKind = item.kind:gsub("create_connected_", ""):gsub("create:", ""):gsub("create_", ""):gsub("rotation_", "")
                if #shortKind > 11 then shortKind = shortKind:sub(1, 11) end

                local invStr = cfg.invert and "TERS" or "NRM "
                local lineStr = string.format(
                    "%s%-17s %-12s %-12s %-4s",
                    isSel and ">" or " ",
                    shortName,
                    shortKind,
                    cfg.role,
                    invStr
                )
                if #lineStr > w then lineStr = lineStr:sub(1, w) end
                drawTerm.write(lineStr .. string.rep(" ", math.max(0, w - #lineStr)))
            else
                drawTerm.setBackgroundColor(theme.bg)
                drawTerm.write(string.rep(" ", w))
            end
        end

        -- Role Description Row
        local selItem = devs[selectedIOIdx]
        local selCfg = selItem and fc:getDeviceConfig(selItem.name) or { role = "AUTO" }
        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.setCursorPos(2, h - 2)
        local desc = ROLE_DESC[selCfg.role] or ""
        if selItem and selItem.cap == "PASSIVE" then
            drawTerm.setTextColor(theme.warn or colors.orange)
            desc = "[PASIF BLOK] Motor donmuyor ise modemi Speed Controller'a takin!"
        else
            drawTerm.setTextColor(theme.accent or colors.cyan)
        end
        drawTerm.write(desc:sub(1, w - 2))

        drawTerm.setCursorPos(2, h - 1)
        drawTerm.setTextColor(theme.ok or colors.lime)
        drawTerm.write("[Sol/Sag]:Gorev [1-7]:MothershipMotor [T]:SpinTest")

        drawTerm.setCursorPos(2, h)
        drawTerm.setTextColor(colors.lightGray)
        drawTerm.write("[I]:Invert [X]:AUTO [V]:AracProfil [P/Tab]:Kokpit")
    end

    local function renderPFD(targetTerm)
        local prevTerm = drawTerm
        drawTerm = targetTerm or parentTerm
        local w, h = drawTerm.getSize()
        if targetTerm and targetTerm ~= parentTerm then
            -- External mirror monitor directly renders PFD flight instruments
        else
            if activeTab == "PROFILE" then
                renderProfileSelector(w, h)
                drawTerm = prevTerm
                return
            elseif activeTab == "IO" then
                renderIOConfigurator(w, h)
                drawTerm = prevTerm
                return
            end
        end
        if activeTab == "PROFILE" then
            renderProfileSelector(w, h)
            return
        elseif activeTab == "IO" then
            renderIOConfigurator(w, h)
            return
        end

        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.clear()
        renderHeader(w)

        local hdgDeg = math.deg(lastTel.heading) % 360
        local tgtHdgDeg = math.deg(fc.ap.targetHdg) % 360

        -- Sub-header & Compass Tape (Row 2)
        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.setTextColor(theme.muted)
        drawTerm.setCursorPos(2, 2)
        drawTerm.write("-- ITKI & MOTOR --")

        if w >= 45 then
            local cx = math.floor(w / 2)
            local tape = formatCompassTape(hdgDeg, 13)
            drawTerm.setCursorPos(cx - 7, 2)
            drawTerm.setTextColor(theme.accent or colors.cyan)
            drawTerm.write("[" .. tape .. "]")
        end

        local rightCol = math.max(33, w - 17)
        drawTerm.setCursorPos(rightCol, 2)
        drawTerm.setTextColor(theme.muted)
        drawTerm.write("-- IRTIFA & NAV --")

        -- Artificial Horizon (Center)
        if w >= 45 and h >= 16 then
            drawArtificialHorizon(math.floor(w / 2), 6, 13, 7, lastTel.pitch, lastTel.roll)
        end

        -- Left Tape: Speed, Throttle Bar, Reverse Gear, Vehicle-Specific Propulsion, RPM, Stress
        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.setTextColor(theme.fg)
        drawTerm.setCursorPos(2, 3)
        drawTerm.write(string.format("SPD : %5.1f m/s", lastTel.speed))

        drawTerm.setCursorPos(2, 4)
        drawTerm.setTextColor(fc.ap.baseThrottle > 0 and (theme.ok or colors.lime) or theme.fg)
        drawTerm.write(string.format("THR : %s %2d", makeBar(fc.ap.baseThrottle, 15, 5), fc.ap.baseThrottle))

        drawTerm.setCursorPos(2, 5)
        local isClutchCut = (fc.ap.mode == "HOVER") or fc.ap.parkingBrake or (fc.ap.baseThrottle <= 0)
        if fc.ap.reverseGear then
            drawTerm.setTextColor(isClutchCut and theme.muted or (theme.warn or colors.orange))
            drawTerm.write(isClutchCut and "VTS : GERI [CUT]" or "VTS : GERI  [ON]")
        else
            drawTerm.setTextColor(isClutchCut and theme.muted or (theme.ok or colors.lime))
            drawTerm.write(isClutchCut and "VTS : ILERI[CUT]" or "VTS : ILERI [ON]")
        end

        if lastTel.vehicleType == "MOTHERSHIP" then
            local ms = lastTel.mothership or { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 }
            drawTerm.setCursorPos(2, 6)
            drawTerm.setTextColor(theme.accent or colors.cyan)
            drawTerm.write(string.format("L-ON: FL%2d FR%2d", ms.fl, ms.fr))
            drawTerm.setCursorPos(2, 7)
            drawTerm.write(string.format("L-AR: RL%2d RR%2d", ms.rl, ms.rr))
            drawTerm.setCursorPos(2, 8)
            drawTerm.setTextColor(theme.ok or colors.lime)
            drawTerm.write(string.format("ARKA: %+3d %+3d %+3d", ms.rearL, ms.rearC, ms.rearR))
        elseif lastTel.vehicleType == "ZEPPELIN" then
            local bCmd = lastTel.burnerCmd or 0
            local bIn  = lastTel.burnerActual or 0
            drawTerm.setCursorPos(2, 6)
            drawTerm.setTextColor(bCmd > 0 and (theme.warn or colors.orange) or theme.muted)
            drawTerm.write(string.format("BRNR: %s %2d", makeBar(bCmd, 15, 5), bCmd))

            drawTerm.setCursorPos(2, 7)
            drawTerm.setTextColor(bIn > 0 and (theme.ok or colors.lime) or theme.muted)
            drawTerm.write(string.format("KAZN: IN:%2d/15 %s", bIn, lastTel.burnerActive and "ON" or "--"))

            drawTerm.setCursorPos(2, 8)
            drawTerm.setTextColor(theme.fg)
            drawTerm.write(string.format("RPM : %5.0f RPM", lastTel.rpm))
        else
            drawTerm.setCursorPos(2, 6)
            drawTerm.setTextColor(theme.fg)
            drawTerm.write(string.format("PTCH: %+5.1f deg", math.deg(lastTel.pitch)))
            drawTerm.setCursorPos(2, 7)
            drawTerm.write(string.format("ROLL: %+5.1f deg", math.deg(lastTel.roll)))
            drawTerm.setCursorPos(2, 8)
            drawTerm.write(string.format("RPM : %5.0f RPM", lastTel.rpm))
        end

        drawTerm.setCursorPos(2, 9)
        if lastTel.overstressed then
            drawTerm.setTextColor(theme.err or colors.red)
            drawTerm.write("STRS: OVERSTRESS!")
        else
            drawTerm.setTextColor(theme.ok or colors.lime)
            drawTerm.write("STRS: NOMINAL")
        end

        -- Right Tape: Altitude, Target, VSI, Heading, Course, Radar AGL
        drawTerm.setTextColor(theme.fg)
        drawTerm.setCursorPos(rightCol, 3)
        drawTerm.write(string.format("ALT : %6.1f m", lastTel.altitude))

        local altDiff = fc.ap.targetAlt - lastTel.altitude
        local trendChar = math.abs(altDiff) < 0.5 and "=" or (altDiff > 0 and "^" or "v")
        drawTerm.setCursorPos(rightCol, 4)
        drawTerm.setTextColor(theme.accent or colors.cyan)
        drawTerm.write(string.format("TGT : %6.1f m%s", fc.ap.targetAlt, trendChar))

        drawTerm.setCursorPos(rightCol, 5)
        if lastTel.vSpeed > 0.2 then
            drawTerm.setTextColor(theme.ok or colors.lime)
        elseif lastTel.vSpeed < -0.2 then
            drawTerm.setTextColor(theme.warn or colors.orange)
        else
            drawTerm.setTextColor(theme.fg)
        end
        drawTerm.write(string.format("VSI : %+5.1f m/s", lastTel.vSpeed))

        drawTerm.setTextColor(theme.fg)
        drawTerm.setCursorPos(rightCol, 6)
        drawTerm.write(string.format("HDG : %05.1f deg", hdgDeg))
        drawTerm.setCursorPos(rightCol, 7)
        drawTerm.setTextColor(theme.accent or colors.cyan)
        drawTerm.write(string.format("CRS : %05.1f deg", tgtHdgDeg))

        drawTerm.setCursorPos(rightCol, 8)
        drawTerm.setTextColor(theme.fg)
        if lastTel.agl then
            drawTerm.write(string.format("AGL : %6.1f m", lastTel.agl))
        else
            drawTerm.write("AGL :  ---.- m")
        end

        drawTerm.setCursorPos(rightCol, 9)
        drawTerm.setTextColor(theme.muted)
        drawTerm.write(string.format("P:%+4.0f R:%+4.0f", math.deg(lastTel.pitch), math.deg(lastTel.roll)))

        -- Row 11: Hot-Plug Toast Notification OR ILS Status
        drawTerm.setCursorPos(2, 11)
        if hotplugNotice and hotplugTimer > 0 then
            drawTerm.setBackgroundColor(isColor and colors.cyan or colors.white)
            drawTerm.setTextColor(colors.black)
            local msg = " " .. hotplugNotice .. " "
            drawTerm.write(msg:sub(1, w - 2))
        elseif fc.ap.mode == "ANCHOR" and lastTel.anchor and lastTel.anchor.active then
            drawTerm.setBackgroundColor(isColor and colors.yellow or colors.white)
            drawTerm.setTextColor(colors.black)
            local a = lastTel.anchor
            drawTerm.write(string.format(" CAPA [3D-LOCK] dH:%4.1fm SURGE:%+5.1fm SWAY:%+5.1fm dY:%+4.1fm ", a.dist, a.surge, a.sway, a.dy):sub(1, w - 2))
        elseif fc.ap.mode == "RTB" and fc.ap.homeBase then
            drawTerm.setBackgroundColor(theme.bg)
            drawTerm.setTextColor(theme.accent or colors.cyan)
            drawTerm.write(string.format(
                "ILS [%s/%s] LOC:%+5.1fm GS:%+5.1fm DST:%4.0fm",
                tostring(fc.ap.homeBase.runwayId or "RWY"),
                tostring(fc.ap.rtbPhase),
                fc.ap.ilsDev.loc or 0,
                fc.ap.ilsDev.gs or 0,
                fc.ap.ilsDev.dist or 0
            ))
        elseif fc.ap.homeBase then
            drawTerm.setBackgroundColor(theme.bg)
            drawTerm.setTextColor(colors.lightGray)
            drawTerm.write(string.format(
                "ILS LOCKED: %s (%s) - [R] RTB",
                tostring(fc.ap.homeBase.baseName or "BASE"),
                tostring(fc.ap.homeBase.runwayId or "RWY")
            ))
        else
            drawTerm.setBackgroundColor(theme.bg)
            drawTerm.setTextColor(theme.muted)
            local periphCount = math.max(0, #(fc.ioDevices or {}) - 6)
            drawTerm.write(string.format(
                "PROFIL: %s | %d Cihaz ([V] Profil Sec | [P] I/O Ayarla)",
                lastTel.vehicleType,
                periphCount
            ):sub(1, w - 2))
        end

        -- Row 12: Warnings Banner (GPWS / Stall / Gear & Clutch)
        drawTerm.setCursorPos(2, 12)
        if lastTel.gpwsWarning then
            drawTerm.setBackgroundColor(colors.red)
            drawTerm.setTextColor(colors.white)
            drawTerm.write(" !! PULL UP - TERRAIN AHEAD !! ")
        elseif lastTel.stallWarning then
            drawTerm.setBackgroundColor(colors.orange)
            drawTerm.setTextColor(colors.black)
            drawTerm.write(" !! STALL WARNING - LOWER NOSE !! ")
        else
            local clutchCut = (fc.ap.mode == "HOVER") or fc.ap.parkingBrake or (fc.ap.baseThrottle <= 0)
            drawTerm.setBackgroundColor(theme.bg)
            drawTerm.setTextColor(lastTel.weightOnWheels and (theme.ok or colors.lime) or colors.lightGray)
            drawTerm.write(string.format(
                "DMN:%+3.0fdg STR:%+4.2f | BRK:%s | WOW:%s | POS:(%d,%d)",
                lastTel.rudderDeflectionDeg or 0,
                lastTel.steerCmd or 0,
                fc.ap.parkingBrake and "PARK" or "OFF ",
                lastTel.weightOnWheels and "EVET" or "HAYIR",
                math.floor(lastTel.pos.x),
                math.floor(lastTel.pos.z)
            ):sub(1, w - 2))
        end

        -- Bottom Dock Separator & Keybind Controls
        drawTerm.setBackgroundColor(theme.bg)
        drawTerm.setCursorPos(1, h - 3)
        drawTerm.setTextColor(theme.muted)
        drawTerm.write(string.rep("-", w))

        drawTerm.setCursorPos(2, h - 2)
        drawTerm.setTextColor(fc.ap.enabled and (theme.ok or colors.lime) or (theme.warn or colors.orange))
        drawTerm.write(string.format(
            "[A]AP:%s [H]HVR [C]CRS [Z]CAPA:%s [B]PARK:%s [G]VTS",
            fc.ap.enabled and "ON " or "OFF",
            (fc.ap.mode == "ANCHOR") and "LOK" or "OFF",
            fc.ap.parkingBrake and "ON " or "OFF"
        ):sub(1, w - 2))

        drawTerm.setCursorPos(2, h - 1)
        drawTerm.setTextColor(theme.accent or colors.cyan)
        drawTerm.write("[V]:Profil Sec | [P]:I/O Matrix | [U]:GitHub OTA Guncelle")

        drawTerm.setCursorPos(2, h)
        drawTerm.setTextColor(colors.lightGray)
        drawTerm.write("[Up/Dn]:Alt+-5 [Lt/Rt]:Hdg+-5 [W/S]:Thr [Z]:Capa [Q]:Cik")
        drawTerm = prevTerm
    end

    local function renderSecondaryMonitors()
        local n = #cachedMonitors
        if n == 0 then return end

        if n == 1 then
            pcall(renderTacticalDisplay, cachedMonitors[1], lastTel, fc.ap)
        elseif n == 2 then
            pcall(renderTacticalDisplay, cachedMonitors[1], lastTel, fc.ap)
            pcall(renderScadaDisplay, cachedMonitors[2], lastTel, fc.ap)
        else
            pcall(renderPFD, cachedMonitors[1])
            pcall(renderTacticalDisplay, cachedMonitors[2], lastTel, fc.ap)
            pcall(renderScadaDisplay, cachedMonitors[3], lastTel, fc.ap)
            for i = 4, n do
                if i % 2 == 0 then
                    pcall(renderTacticalDisplay, cachedMonitors[i], lastTel, fc.ap)
                else
                    pcall(renderScadaDisplay, cachedMonitors[i], lastTel, fc.ap)
                end
            end
        end
    end

    -- Background 20Hz Flight Control & Telemetry Loop
    local function flightControlLoop()
        while running do
            if isRemoteFCC then
                tickCount = tickCount + 1
                if hotplugTimer > 0 then
                    hotplugTimer = hotplugTimer - 1
                end

                if lastTel.gpwsWarning and (tickCount % 10 == 0) then
                    playAlert("GPWS")
                end

                renderPFD()
                renderSecondaryMonitors()
                sleep(0.05)
            else
                lastTel = fc:step(0.05)
                tickCount = tickCount + 1
                if hotplugTimer > 0 then
                    hotplugTimer = hotplugTimer - 1
                end

                if lastTel.gpwsWarning and (tickCount % 10 == 0) then
                    playAlert("GPWS")
                end

                -- Broadcast Internal Bus State (10 Hz) so Lower Deck Engineering Deck receives live telemetry!
                if (tickCount % 2 == 0) and rednet and rednet.isOpen and rednet.isOpen() then
                    pcall(rednet.broadcast, {
                        type   = "AVIONICS_STATE",
                        sender = (os.getComputerID and os.getComputerID()) or 0,
                        tel    = lastTel,
                        ap     = fc.ap
                    }, "DRUNKEN_AVIONICS_BUS")
                end

                -- Broadcast ADS-B Telemetry once per second (every 20 ticks)
                if modem and rednet and (tickCount % 20 == 0) then
                    pcall(rednet.broadcast, {
                        type         = "AVIONICS_ADSB",
                        callsign     = lastTel.callsign,
                        vehicleType  = lastTel.vehicleType,
                        pos          = lastTel.pos,
                        altitude     = lastTel.altitude,
                        targetAlt    = fc.ap.targetAlt,
                        speed        = lastTel.speed,
                        heading      = math.deg(lastTel.heading) % 360,
                        vSpeed       = lastTel.vSpeed,
                        agl          = lastTel.agl,
                        fuelPct      = lastTel.fuelPct,
                        mode         = fc.ap.mode,
                        parkingBrake = fc.ap.parkingBrake,
                        timestamp    = os.epoch and os.epoch("utc") or os.time()
                    }, "DRUNKEN_RADAR")
                end

                renderPFD()
                renderSecondaryMonitors()
                sleep(0.05)
            end
        end
    end

    -- Pilot Input, Hot-Plug & Network Event Loop (Keyboard, Peripherals & Rednet ILS/ATC Tower)
    local function pilotInputLoop()
        while running do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "rednet_message" then
                local msg, protocol = p2, p3
                if protocol == "DRUNKEN_AVIONICS_BUS" and type(msg) == "table" then
                    if msg.type == "AVIONICS_STATE" then
                        isRemoteFCC = true
                        if msg.tel then lastTel = msg.tel end
                        if msg.ap then
                            for k, v in pairs(msg.ap) do
                                fc.ap[k] = v
                            end
                        end
                        if msg.ioMap then
                            fc.ioMap = msg.ioMap
                        end
                        if msg.ioDevices then
                            fc.ioDevices = msg.ioDevices
                        end
                    elseif msg.type == "AVIONICS_CMD" and not isRemoteFCC then
                        if msg.cmd == "SAFE_DISARM" then
                            fc.ap.baseThrottle = 0; fc.ap.parkingBrake = true; fc:setMode("MANUAL", lastTel); fc:step(0.05)
                        elseif msg.cmd == "SET_MODE" and msg.mode then
                            fc:setMode(msg.mode, lastTel)
                        elseif msg.cmd == "SPIN_TEST" then
                            fc:triggerSpinTest(msg.name)
                        elseif msg.cmd == "SET_IO_ROLE" and msg.name and msg.role then
                            fc:setDeviceRole(msg.name, msg.role)
                        elseif msg.cmd == "TOGGLE_IO_INVERT" and msg.name then
                            fc:toggleInvert(msg.name)
                        elseif msg.cmd == "RESET_IO_ROLE" and msg.name then
                            fc:resetDeviceRole(msg.name)
                        elseif msg.cmd == "SCAN_PERIPHERALS" then
                            fc:scanPeripherals()
                        elseif msg.cmd == "SET_PROFILE" and msg.profile then
                            fc:setVehicleProfile(msg.profile, msg.autoAssign == true)
                        end
                    end
                elseif protocol == "DRUNKEN_ILS" and type(msg) == "table" and msg.type == "AVIONICS_ILS_BEACON" then
                    fc:setHomeBase(msg)
                elseif protocol == "DRUNKEN_ATC" and type(msg) == "table" and msg.type == "AVIONICS_ATC_CMD" then
                    local okCmd, notice = fc:executeAtcCommand(msg, lastTel)
                    if okCmd and notice then
                        hotplugNotice = notice
                        hotplugTimer = 100
                        playAlert("CLICK")
                    end
                end
            elseif ev == "peripheral" then
                if peripheral.getType(p1) == "modem" and rednet and not rednet.isOpen(p1) then
                    pcall(rednet.open, p1)
                end
                cachedMonitors = { peripheral.find("monitor") }
                fc:scanPeripherals()
                hotplugNotice = "HOTPLUG + " .. tostring(p1) .. " baglandi!"
                hotplugTimer = 80
                playAlert("CLICK")
            elseif ev == "peripheral_detach" then
                cachedMonitors = { peripheral.find("monitor") }
                fc:scanPeripherals()
                hotplugNotice = "HOTPLUG - " .. tostring(p1) .. " ayrildi!"
                hotplugTimer = 80
            elseif ev == "key" then
                local key = p1
                playAlert("CLICK")
                if key == keys.q then
                    -- Safe disarm, engage full parking brake, and flush zero state to all actuators & burners on exit
                    fc.ap.baseThrottle = 0
                    fc.ap.parkingBrake = true
                    fc:setMode("MANUAL", lastTel)
                    fc:step(0.05)
                    running = false
                elseif key == keys.u then
                    -- GitHub OTA via lib/netpkg: all package files + AVX modules, all-or-nothing
                    hotplugNotice = "GitHub OTA: Guncelleniyor..."
                    hotplugTimer = 80
                    renderPFD()
                    local okN, Net = pcall(require, "lib.netpkg")
                    if not okN then okN, Net = pcall(require, "netpkg") end
                    local okU, info = false, "netpkg yok"
                    if okN then okU, info = Net.update("avionics_fcs") end
                    if okU then
                        hotplugNotice = "OTA TAMAM! Yeniden baslatiliyor..."
                        renderPFD(); sleep(0.8); os.reboot()
                    else
                        hotplugNotice = "OTA HATA: " .. tostring(info)
                        hotplugTimer = 80
                    end
                elseif key == keys.v then
                    if activeTab == "PROFILE" then
                        activeTab = "PFD"
                    else
                        activeTab = "PROFILE"
                    end
                elseif key == keys.p or key == keys.tab then
                    if activeTab == "IO" then
                        activeTab = "PFD"
                    else
                        fc:scanPeripherals()
                        activeTab = "IO"
                    end
                elseif activeTab == "PROFILE" then
                    if key == keys.up then
                        selectedProfileIdx = math.max(1, selectedProfileIdx - 1)
                    elseif key == keys.down then
                        selectedProfileIdx = math.min(#PROFILE_LIST, selectedProfileIdx + 1)
                    elseif (key >= keys.one and key <= keys.three) or (keys.numPad1 and key >= keys.numPad1 and key <= keys.numPad3) then
                        selectedProfileIdx = (key >= keys.one and key <= keys.three) and (key - keys.one + 1) or (key - keys.numPad1 + 1)
                        local chosen = PROFILE_LIST[selectedProfileIdx]
                        if chosen then
                            fc:setVehicleProfile(chosen.id, chosen.id == "MOTHERSHIP")
                            if isRemoteFCC then sendAvionicsCmd("SET_PROFILE", { profile = chosen.id, autoAssign = (chosen.id == "MOTHERSHIP") }) end
                            activeTab = "PFD"
                        end
                    elseif key == keys.enter then
                        local chosen = PROFILE_LIST[selectedProfileIdx]
                        if chosen then
                            fc:setVehicleProfile(chosen.id, chosen.id == "MOTHERSHIP")
                            if isRemoteFCC then sendAvionicsCmd("SET_PROFILE", { profile = chosen.id, autoAssign = (chosen.id == "MOTHERSHIP") }) end
                            activeTab = "PFD"
                        end
                    end
                elseif activeTab == "IO" then
                    local devs = fc.ioDevices or {}
                    local selItem = devs[selectedIOIdx]
                    local quickRoles = {
                        [keys.one]   = "LIFT_FL",
                        [keys.two]   = "LIFT_FR",
                        [keys.three] = "LIFT_RL",
                        [keys.four]  = "LIFT_RR",
                        [keys.five]  = "REAR_LEFT",
                        [keys.six]   = "REAR_CENTER",
                        [keys.seven] = "REAR_RIGHT",
                        [keys.eight] = "RUDDER_YAW",
                        [keys.nine]  = "CLUTCH_BRAKE",
                        [keys.zero]  = "GEAR_REVERSE"
                    }
                    if key == keys.up then
                        selectedIOIdx = math.max(1, selectedIOIdx - 1)
                    elseif key == keys.down then
                        selectedIOIdx = math.min(math.max(1, #devs), selectedIOIdx + 1)
                    elseif (key == keys.right or key == keys.enter) and selItem then
                        local newR = fc:cycleRole(selItem.name, 1)
                        if isRemoteFCC then sendAvionicsCmd("SET_IO_ROLE", { name = selItem.name, role = newR }) end
                    elseif key == keys.left and selItem then
                        local newR = fc:cycleRole(selItem.name, -1)
                        if isRemoteFCC then sendAvionicsCmd("SET_IO_ROLE", { name = selItem.name, role = newR }) end
                    elseif quickRoles[key] and selItem then
                        fc:setDeviceRole(selItem.name, quickRoles[key])
                        if isRemoteFCC then sendAvionicsCmd("SET_IO_ROLE", { name = selItem.name, role = quickRoles[key] }) end
                    elseif key == keys.t and selItem then
                        fc:triggerSpinTest(selItem.name)
                        if isRemoteFCC then sendAvionicsCmd("SPIN_TEST", { name = selItem.name }) end
                    elseif key == keys.i and selItem then
                        local inv = fc:toggleInvert(selItem.name)
                        if isRemoteFCC then sendAvionicsCmd("TOGGLE_IO_INVERT", { name = selItem.name }) end
                    elseif key == keys.x and selItem then
                        local cfg = fc:getDeviceConfig(selItem.name)
                        cfg.role = "AUTO"
                        cfg.invert = false
                        fc:saveIOMap()
                        if isRemoteFCC then sendAvionicsCmd("RESET_IO_ROLE", { name = selItem.name }) end
                    elseif key == keys.r then
                        fc:scanPeripherals()
                        if isRemoteFCC then sendAvionicsCmd("SCAN_PERIPHERALS") end
                    end
                else
                    -- PFD Flight Controls
                    local isAirshipOrMothership = (lastTel.vehicleType == "ZEPPELIN" or lastTel.vehicleType == "MOTHERSHIP" or lastTel.vehicleType == "GUNSHIP")
                    if key == keys.q then
                        if isRemoteFCC then sendAvionicsCmd("SAFE_DISARM")
                        else fc.ap.baseThrottle = 0; fc.ap.parkingBrake = true; fc:setMode("MANUAL", lastTel); fc:step(0.05) end
                        running = false
                    elseif key == keys.a then
                        if isRemoteFCC then sendAvionicsCmd("TOGGLE_AP")
                        elseif fc.ap.enabled then fc:setMode("MANUAL", lastTel)
                        else fc:setMode(isAirshipOrMothership and "HOVER" or "CRUISE", lastTel) end
                    elseif key == keys.c then
                        if isRemoteFCC then sendAvionicsCmd("SET_MODE", { mode = "CRUISE" }) else fc:setMode("CRUISE", lastTel) end
                        hotplugNotice = "CRUISE MODU"; hotplugTimer = 40
                    elseif key == keys.h then
                        if isRemoteFCC then sendAvionicsCmd("SET_MODE", { mode = "HOVER" }) else fc:setMode("HOVER", lastTel) end
                        hotplugNotice = "HOVER AKTIF: Irtifa Kilitli"; hotplugTimer = 50
                    elseif key == keys.r then
                        if isRemoteFCC then sendAvionicsCmd("ENGAGE_RTB") else fc:engageRTB(lastTel) end
                        hotplugNotice = "RTB: Eve Donus"; hotplugTimer = 50
                    elseif key == keys.l then
                        if isRemoteFCC then sendAvionicsCmd("SET_MODE", { mode = "AUTOLAND" }) else fc:setMode("AUTOLAND", lastTel) end
                        hotplugNotice = "AUTOLAND: Inis"; hotplugTimer = 50
                    elseif key == keys.b then
                        if isRemoteFCC then sendAvionicsCmd("TOGGLE_BRAKE")
                        elseif fc.ap.enabled then
                            fc:setMode("MANUAL", lastTel); fc.ap.parkingBrake = true; fc.ap.baseThrottle = 0; fc.ap.manualYaw = 0
                            hotplugNotice = "TAM PARK AKTIF!"; hotplugTimer = 70
                        else
                            fc.ap.parkingBrake = not fc.ap.parkingBrake
                            if fc.ap.parkingBrake then fc.ap.baseThrottle = 0; fc.ap.manualYaw = 0; hotplugNotice = "PARK FRENI AKTIF"
                            else hotplugNotice = "PARK FRENI COZULDU" end
                            hotplugTimer = 60
                        end
                    elseif key == keys.k then
                        if isRemoteFCC then sendAvionicsCmd("TOGGLE_CLUTCH")
                        else
                            local inv = fc:toggleClutchPolarity()
                            hotplugNotice = "DEBRIYAJ YONU: " .. (inv and "TERS" or "DUZ")
                            hotplugTimer = 60
                        end
                    elseif key == keys.g then
                        if isRemoteFCC then sendAvionicsCmd("TOGGLE_GEAR")
                        else
                            fc.ap.reverseGear = not fc.ap.reverseGear
                            hotplugNotice = "VITES: " .. (fc.ap.reverseGear and "GERI [REDSTONE 15]" or "ILERI [REDSTONE 0]")
                            hotplugTimer = 60
                        end
                    elseif key == keys.z then
                        if isRemoteFCC then
                            local newM = (fc.ap.mode == "ANCHOR") and "MANUAL" or "ANCHOR"
                            sendAvionicsCmd("SET_MODE", { mode = newM })
                        else
                            if fc.ap.mode == "ANCHOR" then
                                fc:setMode("MANUAL", lastTel)
                                hotplugNotice = "CAPA SERBEST (MANUEL)"
                            else
                                fc:setMode("ANCHOR", lastTel)
                                hotplugNotice = "GOKYUZU CAPASI KILITLENDI [3D-LOCK]"
                            end
                            hotplugTimer = 70
                        end
                    elseif key == keys.up or key == keys.down then
                        local d = (key == keys.up) and 5 or -5
                        if isRemoteFCC then sendAvionicsCmd("ALT_DELTA", { delta = d })
                        else
                            if not fc.ap.enabled then fc:setMode(isAirshipOrMothership and "HOVER" or "CRUISE", lastTel) end
                            fc.ap.targetAlt = math.max(0, fc.ap.targetAlt + d)
                        end
                        hotplugNotice = "IRTIFA " .. (d > 0 and "+5m" or "-5m"); hotplugTimer = 30
                    elseif key == keys.left or key == keys.right then
                        local d = (key == keys.right) and 2 or -2
                        if not fc.ap.enabled then
                            if isRemoteFCC then sendAvionicsCmd("MANUAL_YAW_DELTA", { delta = d }) else fc.ap.manualYaw = math.max(-6, math.min(6, (fc.ap.manualYaw or 0) + d)) end
                            hotplugNotice = "DUMEN: " .. (d > 0 and "SAG " or "SOL ") .. tostring(fc.ap.manualYaw); hotplugTimer = 30
                        else
                            local hdgDelta = (key == keys.right) and 5 or -5
                            if isRemoteFCC then sendAvionicsCmd("HDG_DELTA", { deltaDeg = hdgDelta }) else fc.ap.targetHdg = (fc.ap.targetHdg + math.rad(hdgDelta)) % (2 * math.pi) end
                        end
                    elseif key == keys.x then
                        if not fc.ap.enabled then
                            if isRemoteFCC then sendAvionicsCmd("MANUAL_YAW_DELTA", { delta = -(fc.ap.manualYaw or 0) }) else fc.ap.manualYaw = 0 end
                            hotplugNotice = "DUMEN SIFIRLANDI"; hotplugTimer = 30
                        end
                    elseif key == keys.w or key == keys.s then
                        local wantRev = (key == keys.s)
                        if isRemoteFCC then sendAvionicsCmd("THR_DELTA", { delta = wantRev and -1 or 1 })
                        else
                            if fc.ap.reverseGear ~= wantRev and fc.ap.baseThrottle > 0 and fc.ap.mode ~= "HOVER" then
                                fc.ap.baseThrottle = math.max(0, fc.ap.baseThrottle - 1)
                                if fc.ap.baseThrottle == 0 then fc.ap.reverseGear = wantRev; hotplugNotice = "DURDU"; hotplugTimer = 40 end
                            else
                                fc.ap.reverseGear = wantRev
                                if fc.ap.mode == "HOVER" then fc:setMode("CRUISE", lastTel) end
                                fc.ap.parkingBrake = false
                                fc.ap.baseThrottle = math.min(15, fc.ap.baseThrottle + 1)
                                hotplugNotice = wantRev and "GERI ITKI (REV)" or "ILERI ITKI"; hotplugTimer = 40
                            end
                        end
                    end
                end
            end
        end
    end

    -- Non-blocking background GPS Constellation Sync (runs in parallel so 20Hz flight loop never stalls)
    local function gpsSyncLoop()
        while running do
            if not isRemoteFCC and modem and gps and gps.locate then
                local okGps, gx, gy, gz = pcall(gps.locate, 1.5)
                if okGps and gx and gz then
                    fc.pos.x = gx
                    fc.pos.z = gz
                    if not fc.altSensor and gy then
                        fc.pos.y = gy
                    end
                    fc.gpsLocked = true
                else
                    fc.gpsLocked = false
                end
            end
            sleep(2.5)
        end
    end

    parallel.waitForAny(flightControlLoop, pilotInputLoop, gpsSyncLoop)
end

-- Allow direct execution when invoked from shell, CLI, or startup
if shell and shell.getRunningProgram and shell.getRunningProgram():match("flight_control") then
    run()
end

return {
    run = run,
    renderTacticalDisplay = renderTacticalDisplay,
    renderScadaDisplay = renderScadaDisplay
}

