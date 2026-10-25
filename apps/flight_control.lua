-- apps/flight_control.lua
-- Drunken OS Primary Flight Display (PFD) & Autopilot Cockpit App

-- Ensure standard Drunken OS library paths are resolvable across standalone and sub-shell execution
if package and package.path then
    package.path = "/?.lua;/lib/?.lua;?.lua;lib/?.lua;" .. package.path
end

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
    local hotplugNotice = nil
    local hotplugTimer = 0

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

    -- Open wireless modem for ADS-B Radar Telemetry & ILS Beacon Reception
    local modem = peripheral.find("modem", function(_, m) return m.isWireless and m.isWireless() end)
    if modem and rednet and not rednet.isOpen(peripheral.getName(modem)) then
        pcall(rednet.open, peripheral.getName(modem))
    end

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
                parentTerm.setCursorPos(cx - halfW, y)
                for dx = -halfW, halfW do
                    local horizonY = pitchOffset + math.floor(dx * rollSlope + 0.5)
                    if dy == 0 and math.abs(dx) <= 2 then
                        -- Center Aircraft Reticle
                        parentTerm.setBackgroundColor(colors.black)
                        parentTerm.setTextColor(isColor and colors.yellow or colors.white)
                        parentTerm.write(dx == 0 and "+" or "-")
                    elseif dy < horizonY then
                        -- Sky
                        parentTerm.setBackgroundColor(isColor and colors.blue or colors.black)
                        parentTerm.setTextColor(colors.white)
                        parentTerm.write(" ")
                    elseif dy == horizonY then
                        -- Horizon Line
                        parentTerm.setBackgroundColor(isColor and colors.cyan or colors.black)
                        parentTerm.setTextColor(colors.white)
                        parentTerm.write("-")
                    else
                        -- Ground
                        parentTerm.setBackgroundColor(isColor and colors.brown or colors.black)
                        parentTerm.setTextColor(isColor and colors.lightGray or colors.white)
                        parentTerm.write(isColor and " " or "#")
                    end
                end
            end
        end
    end

    local function renderHeader(w)
        parentTerm.setCursorPos(1, 1)
        parentTerm.setBackgroundColor(theme.header or colors.blue)
        parentTerm.setTextColor(colors.white)
        local vShort = (lastTel.vehicleType == "MOTHERSHIP" and "MSHIP")
            or (lastTel.vehicleType == "ZEPPELIN" and "ZEP")
            or "AIR"
        local tabLabel = (activeTab == "PFD") and "[PFD] [P:I/O] [V:ARAC]"
            or ((activeTab == "IO") and "[P:PFD] [I/O] [V:ARAC]" or "[ARAC SECIMI]")
        local headerText = string.format(
            " DOS | %s [%s] | %s | %s",
            lastTel.callsign,
            vShort,
            fc.ap.mode,
            tabLabel
        )
        if #headerText > w then headerText = headerText:sub(1, w) end
        parentTerm.write(headerText .. string.rep(" ", math.max(0, w - #headerText)))
    end

    local function renderProfileSelector(w, h)
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.clear()
        renderHeader(w)

        parentTerm.setCursorPos(2, 3)
        parentTerm.setTextColor(theme.accent or colors.cyan)
        parentTerm.write("=== ARAC KONTROL PROFILINI SECIN ===")

        for i, p in ipairs(PROFILE_LIST) do
            local baseY = 4 + (i - 1) * 4
            local isSel = (i == selectedProfileIdx)
            parentTerm.setCursorPos(2, baseY)
            parentTerm.setBackgroundColor(isSel and (isColor and colors.cyan or colors.white) or theme.bg)
            parentTerm.setTextColor(isSel and colors.black or (theme.ok or colors.lime))
            local lineTitle = (isSel and " > " or "   ") .. p.title
            parentTerm.write(lineTitle .. string.rep(" ", math.max(0, w - 3 - #lineTitle)))

            parentTerm.setBackgroundColor(theme.bg)
            parentTerm.setTextColor(theme.fg)
            parentTerm.setCursorPos(5, baseY + 1)
            parentTerm.write(p.desc1:sub(1, w - 6))
            parentTerm.setTextColor(theme.muted)
            parentTerm.setCursorPos(5, baseY + 2)
            parentTerm.write(p.desc2:sub(1, w - 6))
        end

        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.setCursorPos(2, h - 1)
        parentTerm.setTextColor(theme.ok or colors.lime)
        parentTerm.write("[1/2/3] veya [Up/Dn + Enter]: Profili Kur & Baslat")
        parentTerm.setCursorPos(2, h)
        parentTerm.setTextColor(colors.lightGray)
        parentTerm.write("[P]: I/O Motor Siralamasi | [V/Tab]: Kokpite Don")
    end

    local function renderIOConfigurator(w, h)
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.clear()
        renderHeader(w)

        parentTerm.setBackgroundColor(isColor and colors.gray or colors.black)
        parentTerm.setTextColor(isColor and colors.yellow or colors.white)
        parentTerm.setCursorPos(1, 2)
        local colHdr = string.format(" %-18s %-12s %-12s %-4s", "CIHAZ / KANAL", "TIP", "GOREV (ROLE)", "INV")
        parentTerm.write(colHdr .. string.rep(" ", math.max(0, w - #colHdr)))

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
            parentTerm.setCursorPos(1, y)
            if idx <= #devs then
                local item = devs[idx]
                local cfg = fc:getDeviceConfig(item.name)
                local isSel = (idx == selectedIOIdx)
                local isTesting = (fc.spinTest and fc.spinTest.name == item.name)
                parentTerm.setBackgroundColor(
                    isTesting and (isColor and colors.orange or colors.white)
                    or (isSel and (isColor and colors.cyan or colors.white) or theme.bg)
                )
                parentTerm.setTextColor((isSel or isTesting) and colors.black or theme.fg)

                local shortName = item.name
                if #shortName > 17 then shortName = shortName:sub(1, 15) .. ".." end
                local shortKind = item.kind:gsub("create_connected_", ""):gsub("create_", ""):gsub("rotation_", "")
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
                parentTerm.write(lineStr .. string.rep(" ", math.max(0, w - #lineStr)))
            else
                parentTerm.setBackgroundColor(theme.bg)
                parentTerm.write(string.rep(" ", w))
            end
        end

        -- Role Description Row
        local selItem = devs[selectedIOIdx]
        local selCfg = selItem and fc:getDeviceConfig(selItem.name) or { role = "AUTO" }
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.setCursorPos(2, h - 2)
        parentTerm.setTextColor(theme.accent or colors.cyan)
        local desc = ROLE_DESC[selCfg.role] or ""
        parentTerm.write(desc:sub(1, w - 2))

        parentTerm.setCursorPos(2, h - 1)
        parentTerm.setTextColor(theme.ok or colors.lime)
        parentTerm.write("[Sol/Sag]:Gorev [1-7]:MothershipMotor [T]:SpinTest")

        parentTerm.setCursorPos(2, h)
        parentTerm.setTextColor(colors.lightGray)
        parentTerm.write("[I]:Invert [X]:AUTO [V]:AracProfil [P/Tab]:Kokpit")
    end

    local function renderPFD()
        local w, h = parentTerm.getSize()
        if activeTab == "PROFILE" then
            renderProfileSelector(w, h)
            return
        elseif activeTab == "IO" then
            renderIOConfigurator(w, h)
            return
        end

        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.clear()
        renderHeader(w)

        local hdgDeg = math.deg(lastTel.heading) % 360
        local tgtHdgDeg = math.deg(fc.ap.targetHdg) % 360

        -- Sub-header & Compass Tape (Row 2)
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.setTextColor(theme.muted)
        parentTerm.setCursorPos(2, 2)
        parentTerm.write("-- ITKI & MOTOR --")

        if w >= 45 then
            local cx = math.floor(w / 2)
            local tape = formatCompassTape(hdgDeg, 13)
            parentTerm.setCursorPos(cx - 7, 2)
            parentTerm.setTextColor(theme.accent or colors.cyan)
            parentTerm.write("[" .. tape .. "]")
        end

        local rightCol = math.max(33, w - 17)
        parentTerm.setCursorPos(rightCol, 2)
        parentTerm.setTextColor(theme.muted)
        parentTerm.write("-- IRTIFA & NAV --")

        -- Artificial Horizon (Center)
        if w >= 45 and h >= 16 then
            drawArtificialHorizon(math.floor(w / 2), 6, 13, 7, lastTel.pitch, lastTel.roll)
        end

        -- Left Tape: Speed, Throttle Bar, Reverse Gear, Vehicle-Specific Propulsion, RPM, Stress
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.setTextColor(theme.fg)
        parentTerm.setCursorPos(2, 3)
        parentTerm.write(string.format("SPD : %5.1f m/s", lastTel.speed))

        parentTerm.setCursorPos(2, 4)
        parentTerm.setTextColor(fc.ap.baseThrottle > 0 and (theme.ok or colors.lime) or theme.fg)
        parentTerm.write(string.format("THR : %s %2d", makeBar(fc.ap.baseThrottle, 15, 5), fc.ap.baseThrottle))

        parentTerm.setCursorPos(2, 5)
        local isClutchCut = (fc.ap.mode == "HOVER") or fc.ap.parkingBrake or (fc.ap.baseThrottle <= 0)
        if fc.ap.reverseGear then
            parentTerm.setTextColor(isClutchCut and theme.muted or (theme.warn or colors.orange))
            parentTerm.write(isClutchCut and "VTS : GERI [CUT]" or "VTS : GERI  [ON]")
        else
            parentTerm.setTextColor(isClutchCut and theme.muted or (theme.ok or colors.lime))
            parentTerm.write(isClutchCut and "VTS : ILERI[CUT]" or "VTS : ILERI [ON]")
        end

        if lastTel.vehicleType == "MOTHERSHIP" then
            local ms = lastTel.mothership or { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 }
            parentTerm.setCursorPos(2, 6)
            parentTerm.setTextColor(theme.accent or colors.cyan)
            parentTerm.write(string.format("L-ON: FL%2d FR%2d", ms.fl, ms.fr))
            parentTerm.setCursorPos(2, 7)
            parentTerm.write(string.format("L-AR: RL%2d RR%2d", ms.rl, ms.rr))
            parentTerm.setCursorPos(2, 8)
            parentTerm.setTextColor(theme.ok or colors.lime)
            parentTerm.write(string.format("ARKA: %+3d %+3d %+3d", ms.rearL, ms.rearC, ms.rearR))
        elseif lastTel.vehicleType == "ZEPPELIN" then
            local bCmd = lastTel.burnerCmd or 0
            local bIn  = lastTel.burnerActual or 0
            parentTerm.setCursorPos(2, 6)
            parentTerm.setTextColor(bCmd > 0 and (theme.warn or colors.orange) or theme.muted)
            parentTerm.write(string.format("BRNR: %s %2d", makeBar(bCmd, 15, 5), bCmd))

            parentTerm.setCursorPos(2, 7)
            parentTerm.setTextColor(bIn > 0 and (theme.ok or colors.lime) or theme.muted)
            parentTerm.write(string.format("KAZN: IN:%2d/15 %s", bIn, lastTel.burnerActive and "ON" or "--"))

            parentTerm.setCursorPos(2, 8)
            parentTerm.setTextColor(theme.fg)
            parentTerm.write(string.format("RPM : %5.0f RPM", lastTel.rpm))
        else
            parentTerm.setCursorPos(2, 6)
            parentTerm.setTextColor(theme.fg)
            parentTerm.write(string.format("PTCH: %+5.1f deg", math.deg(lastTel.pitch)))
            parentTerm.setCursorPos(2, 7)
            parentTerm.write(string.format("ROLL: %+5.1f deg", math.deg(lastTel.roll)))
            parentTerm.setCursorPos(2, 8)
            parentTerm.write(string.format("RPM : %5.0f RPM", lastTel.rpm))
        end

        parentTerm.setCursorPos(2, 9)
        if lastTel.overstressed then
            parentTerm.setTextColor(theme.err or colors.red)
            parentTerm.write("STRS: OVERSTRESS!")
        else
            parentTerm.setTextColor(theme.ok or colors.lime)
            parentTerm.write("STRS: NOMINAL")
        end

        -- Right Tape: Altitude, Target, VSI, Heading, Course, Radar AGL
        parentTerm.setTextColor(theme.fg)
        parentTerm.setCursorPos(rightCol, 3)
        parentTerm.write(string.format("ALT : %6.1f m", lastTel.altitude))

        local altDiff = fc.ap.targetAlt - lastTel.altitude
        local trendChar = math.abs(altDiff) < 0.5 and "=" or (altDiff > 0 and "^" or "v")
        parentTerm.setCursorPos(rightCol, 4)
        parentTerm.setTextColor(theme.accent or colors.cyan)
        parentTerm.write(string.format("TGT : %6.1f m%s", fc.ap.targetAlt, trendChar))

        parentTerm.setCursorPos(rightCol, 5)
        if lastTel.vSpeed > 0.2 then
            parentTerm.setTextColor(theme.ok or colors.lime)
        elseif lastTel.vSpeed < -0.2 then
            parentTerm.setTextColor(theme.warn or colors.orange)
        else
            parentTerm.setTextColor(theme.fg)
        end
        parentTerm.write(string.format("VSI : %+5.1f m/s", lastTel.vSpeed))

        parentTerm.setTextColor(theme.fg)
        parentTerm.setCursorPos(rightCol, 6)
        parentTerm.write(string.format("HDG : %05.1f deg", hdgDeg))
        parentTerm.setCursorPos(rightCol, 7)
        parentTerm.setTextColor(theme.accent or colors.cyan)
        parentTerm.write(string.format("CRS : %05.1f deg", tgtHdgDeg))

        parentTerm.setCursorPos(rightCol, 8)
        parentTerm.setTextColor(theme.fg)
        if lastTel.agl then
            parentTerm.write(string.format("AGL : %6.1f m", lastTel.agl))
        else
            parentTerm.write("AGL :  ---.- m")
        end

        parentTerm.setCursorPos(rightCol, 9)
        parentTerm.setTextColor(theme.muted)
        parentTerm.write(string.format("P:%+4.0f R:%+4.0f", math.deg(lastTel.pitch), math.deg(lastTel.roll)))

        -- Row 11: Hot-Plug Toast Notification OR ILS Status
        parentTerm.setCursorPos(2, 11)
        if hotplugNotice and hotplugTimer > 0 then
            parentTerm.setBackgroundColor(isColor and colors.cyan or colors.white)
            parentTerm.setTextColor(colors.black)
            local msg = " " .. hotplugNotice .. " "
            parentTerm.write(msg:sub(1, w - 2))
        elseif fc.ap.mode == "RTB" and fc.ap.homeBase then
            parentTerm.setBackgroundColor(theme.bg)
            parentTerm.setTextColor(theme.accent or colors.cyan)
            parentTerm.write(string.format(
                "ILS [%s/%s] LOC:%+5.1fm GS:%+5.1fm DST:%4.0fm",
                tostring(fc.ap.homeBase.runwayId or "RWY"),
                tostring(fc.ap.rtbPhase),
                fc.ap.ilsDev.loc or 0,
                fc.ap.ilsDev.gs or 0,
                fc.ap.ilsDev.dist or 0
            ))
        elseif fc.ap.homeBase then
            parentTerm.setBackgroundColor(theme.bg)
            parentTerm.setTextColor(colors.lightGray)
            parentTerm.write(string.format(
                "ILS LOCKED: %s (%s) - [R] RTB",
                tostring(fc.ap.homeBase.baseName or "BASE"),
                tostring(fc.ap.homeBase.runwayId or "RWY")
            ))
        else
            parentTerm.setBackgroundColor(theme.bg)
            parentTerm.setTextColor(theme.muted)
            local periphCount = math.max(0, #(fc.ioDevices or {}) - 6)
            parentTerm.write(string.format(
                "PROFIL: %s | %d Cihaz ([V] Profil Sec | [P] I/O Ayarla)",
                lastTel.vehicleType,
                periphCount
            ):sub(1, w - 2))
        end

        -- Row 12: Warnings Banner (GPWS / Stall / Gear & Clutch)
        parentTerm.setCursorPos(2, 12)
        if lastTel.gpwsWarning then
            parentTerm.setBackgroundColor(colors.red)
            parentTerm.setTextColor(colors.white)
            parentTerm.write(" !! PULL UP - TERRAIN AHEAD !! ")
        elseif lastTel.stallWarning then
            parentTerm.setBackgroundColor(colors.orange)
            parentTerm.setTextColor(colors.black)
            parentTerm.write(" !! STALL WARNING - LOWER NOSE !! ")
        else
            local clutchCut = (fc.ap.mode == "HOVER") or fc.ap.parkingBrake or (fc.ap.baseThrottle <= 0)
            parentTerm.setBackgroundColor(theme.bg)
            parentTerm.setTextColor(lastTel.weightOnWheels and (theme.ok or colors.lime) or colors.lightGray)
            parentTerm.write(string.format(
                "CLUTCH:%s(%s) | BRK:%s | POS:(%d,%d,%d)",
                clutchCut and "KESIK" or "AKTIF",
                fc.clutchPolarInvert and "TERS" or "DUZ",
                fc.ap.parkingBrake and "PARK" or "OFF ",
                math.floor(lastTel.pos.x),
                math.floor(lastTel.pos.y),
                math.floor(lastTel.pos.z)
            ):sub(1, w - 2))
        end

        -- Bottom Dock Separator & Keybind Controls
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.setCursorPos(1, h - 3)
        parentTerm.setTextColor(theme.muted)
        parentTerm.write(string.rep("-", w))

        parentTerm.setCursorPos(2, h - 2)
        parentTerm.setTextColor(fc.ap.enabled and (theme.ok or colors.lime) or (theme.warn or colors.orange))
        parentTerm.write(string.format(
            "[A]AP:%s [H]HVR [C]CRS [B]PARK:%s [K]CLUTCH [G]VTS",
            fc.ap.enabled and "ON " or "OFF",
            fc.ap.parkingBrake and "ON " or "OFF"
        ):sub(1, w - 2))

        parentTerm.setCursorPos(2, h - 1)
        parentTerm.setTextColor(theme.accent or colors.cyan)
        parentTerm.write("[V]:Profil Sec | [P]:I/O Matrix | [U]:GitHub OTA Guncelle")

        parentTerm.setCursorPos(2, h)
        parentTerm.setTextColor(colors.lightGray)
        parentTerm.write("[Up/Dn]:Alt+-5 [Lt/Rt]:Hdg+-5 [W/S]:Thr [L]:Lnd [Q]:Cik")
    end

    -- Background 20Hz Flight Control & Telemetry Loop
    local function flightControlLoop()
        while running do
            lastTel = fc:step(0.05)
            tickCount = tickCount + 1
            if hotplugTimer > 0 then
                hotplugTimer = hotplugTimer - 1
            end

            if lastTel.gpwsWarning and (tickCount % 10 == 0) then
                playAlert("GPWS")
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
            sleep(0.05)
        end
    end

    -- Pilot Input, Hot-Plug & Network Event Loop (Keyboard, Peripherals & Rednet ILS/ATC Tower)
    local function pilotInputLoop()
        while running do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "rednet_message" then
                local msg, protocol = p2, p3
                if protocol == "DRUNKEN_ILS" and type(msg) == "table" and msg.type == "AVIONICS_ILS_BEACON" then
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
                fc:scanPeripherals()
                hotplugNotice = "HOTPLUG + " .. tostring(p1) .. " baglandi!"
                hotplugTimer = 80
                playAlert("CLICK")
            elseif ev == "peripheral_detach" then
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
                    if http and http.get then
                        hotplugNotice = "GitHub OTA: Guncel ucus yazilimi indiriliyor..."
                        hotplugTimer = 100
                        renderPFD()
                        local base = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/"
                        local ts = tostring((os.epoch and os.epoch("utc")) or os.time())
                        local okAll = true
                        local errReason = ""
                        for _, rel in ipairs({ "lib/avionics.lua", "apps/flight_control.lua" }) do
                            local okH, resp, errStr = pcall(http.get, base .. rel .. "?v=" .. ts)
                            if okH and resp then
                                local code = (not resp.getResponseCode) or (resp.getResponseCode() == 200)
                                local content = code and resp.readAll() or nil
                                if resp.close then pcall(resp.close) end
                                if content and #content > 200 then
                                    local targets = { "/" .. rel, rel }
                                    if rel == "lib/avionics.lua" and fs.exists("/avionics.lua") then
                                        table.insert(targets, "/avionics.lua")
                                    elseif rel == "apps/flight_control.lua" and shell and shell.getRunningProgram then
                                        local rp = shell.getRunningProgram()
                                        if rp and rp ~= "" then table.insert(targets, "/" .. rp) end
                                    end
                                    for _, tPath in ipairs(targets) do
                                        local dir = fs.getDir(tPath)
                                        if dir and dir ~= "" and not fs.exists(dir) then pcall(fs.makeDir, dir) end
                                        local f = fs.open(tPath, "w")
                                        if f then f.write(content); f.close() end
                                    end
                                else
                                    okAll = false
                                    errReason = "Bos icerik"
                                end
                            else
                                okAll = false
                                errReason = tostring(errStr or resp or "Baglanti yok")
                            end
                        end
                        if okAll then
                            hotplugNotice = "OTA GUNCELLEME TAMAM! Yeniden baslatiliyor..."
                            hotplugTimer = 100
                            renderPFD()
                            sleep(0.8)
                            os.reboot()
                        else
                            hotplugNotice = "OTA HATA: " .. errReason
                            hotplugTimer = 100
                        end
                    else
                        hotplugNotice = "OTA HATA: HTTP API kapali!"
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
                    elseif key == keys.one or key == keys.numPad1 then
                        selectedProfileIdx = 1
                        fc:setVehicleProfile("ZEPPELIN", false)
                        activeTab = "PFD"
                    elseif key == keys.two or key == keys.numPad2 then
                        selectedProfileIdx = 2
                        fc:setVehicleProfile("AIRCRAFT", false)
                        activeTab = "PFD"
                    elseif key == keys.three or key == keys.numPad3 then
                        selectedProfileIdx = 3
                        fc:setVehicleProfile("MOTHERSHIP", true)
                        activeTab = "PFD"
                    elseif key == keys.enter then
                        local chosen = PROFILE_LIST[selectedProfileIdx]
                        if chosen then
                            fc:setVehicleProfile(chosen.id, chosen.id == "MOTHERSHIP")
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
                        [keys.seven] = "REAR_RIGHT"
                    }
                    if key == keys.up then
                        selectedIOIdx = math.max(1, selectedIOIdx - 1)
                    elseif key == keys.down then
                        selectedIOIdx = math.min(math.max(1, #devs), selectedIOIdx + 1)
                    elseif (key == keys.right or key == keys.enter) and selItem then
                        fc:cycleRole(selItem.name, 1)
                    elseif key == keys.left and selItem then
                        fc:cycleRole(selItem.name, -1)
                    elseif quickRoles[key] and selItem then
                        fc:setDeviceRole(selItem.name, quickRoles[key])
                    elseif key == keys.t and selItem then
                        fc:triggerSpinTest(selItem.name)
                    elseif key == keys.i and selItem then
                        fc:toggleInvert(selItem.name)
                    elseif key == keys.x and selItem then
                        local cfg = fc:getDeviceConfig(selItem.name)
                        cfg.role = "AUTO"
                        cfg.invert = false
                        fc:saveIOMap()
                    elseif key == keys.r then
                        fc:scanPeripherals()
                    end
                else
                    -- PFD Flight Controls
                    local isAirshipOrMothership = (lastTel.vehicleType == "ZEPPELIN" or lastTel.vehicleType == "MOTHERSHIP")
                    if key == keys.a then
                        if fc.ap.enabled then
                            fc:setMode("MANUAL", lastTel)
                        else
                            fc:setMode(isAirshipOrMothership and "HOVER" or "CRUISE", lastTel)
                        end
                    elseif key == keys.c then
                        fc:setMode("CRUISE", lastTel)
                    elseif key == keys.h then
                        fc:setMode("HOVER", lastTel)
                        hotplugNotice = "HOVER AKTIF: Irtifa Kilitli, Arka Pervane Kesildi"
                        hotplugTimer = 60
                    elseif key == keys.r then
                        fc:engageRTB(lastTel)
                    elseif key == keys.l then
                        fc:setMode("AUTOLAND", lastTel)
                    elseif key == keys.b then
                        if fc.ap.enabled then
                            -- Engaging [B] while in HOVER/CRUISE switches to Full Park (cuts both propeller and burners)
                            fc:setMode("MANUAL", lastTel)
                            fc.ap.parkingBrake = true
                            fc.ap.baseThrottle = 0
                            fc.ap.manualYaw = 0
                            hotplugNotice = "TAM PARK AKTIF: Pervane ve Kazanlar Kapatildi!"
                            hotplugTimer = 70
                        else
                            fc.ap.parkingBrake = not fc.ap.parkingBrake
                            if fc.ap.parkingBrake then
                                fc.ap.baseThrottle = 0
                                fc.ap.manualYaw = 0
                                hotplugNotice = "PARK FRENI AKTIF: Pervane ve Kazanlar Kapatildi!"
                            else
                                hotplugNotice = "PARK FRENI COZULDU: [W] ile gaz verebilirsiniz"
                            end
                            hotplugTimer = 60
                        end
                    elseif key == keys.k then
                        local inv = fc:toggleClutchPolarity()
                        hotplugNotice = "DEBRIYAJ YONU: " .. (inv and "TERS (INVERTED)" or "DUZ (NORMAL)")
                        hotplugTimer = 70
                    elseif key == keys.g then
                        fc.ap.reverseGear = not fc.ap.reverseGear
                        hotplugNotice = "VITES (GEARSHIFT): " .. (fc.ap.reverseGear and "GERI (REVERSE AKTIF)" or "ILERI (FORWARD AKTIF)")
                        hotplugTimer = 60
                    elseif key == keys.up then
                        if not fc.ap.enabled then
                            fc:setMode(isAirshipOrMothership and "HOVER" or "CRUISE", lastTel)
                        end
                        fc.ap.targetAlt = fc.ap.targetAlt + 5
                    elseif key == keys.down then
                        if not fc.ap.enabled then
                            fc:setMode(isAirshipOrMothership and "HOVER" or "CRUISE", lastTel)
                        end
                        fc.ap.targetAlt = math.max(0, fc.ap.targetAlt - 5)
                    elseif key == keys.left then
                        if not fc.ap.enabled and lastTel.vehicleType == "MOTHERSHIP" then
                            fc.ap.manualYaw = math.max(-6, (fc.ap.manualYaw or 0) - 2)
                        else
                            fc.ap.targetHdg = (fc.ap.targetHdg - math.rad(5)) % (2 * math.pi)
                        end
                    elseif key == keys.right then
                        if not fc.ap.enabled and lastTel.vehicleType == "MOTHERSHIP" then
                            fc.ap.manualYaw = math.min(6, (fc.ap.manualYaw or 0) + 2)
                        else
                            fc.ap.targetHdg = (fc.ap.targetHdg + math.rad(5)) % (2 * math.pi)
                        end
                    elseif key == keys.w then
                        if fc.ap.reverseGear and fc.ap.baseThrottle > 0 and fc.ap.mode ~= "HOVER" then
                            -- Slow down from reverse movement toward 0
                            fc.ap.baseThrottle = math.max(0, fc.ap.baseThrottle - 1)
                            if fc.ap.baseThrottle == 0 then
                                fc.ap.reverseGear = false
                                hotplugNotice = "DURDU: Pervane kesildi ([W]:Ileri [S]:Geri)"
                                hotplugTimer = 50
                            end
                        else
                            fc.ap.reverseGear = false
                            if fc.ap.mode == "HOVER" then
                                fc:setMode("CRUISE", lastTel)
                                fc.ap.parkingBrake = false
                                fc.ap.baseThrottle = 1
                                hotplugNotice = "ILERI ITKI: Debriyaj Acik, Gearshift=ILERI"
                                hotplugTimer = 50
                            else
                                fc.ap.parkingBrake = false
                                fc.ap.baseThrottle = math.min(15, fc.ap.baseThrottle + 1)
                                if fc.ap.baseThrottle == 1 then
                                    hotplugNotice = "ILERI ITKI: Debriyaj Acik, Gearshift=ILERI"
                                    hotplugTimer = 50
                                end
                            end
                        end
                    elseif key == keys.s then
                        if not fc.ap.reverseGear and fc.ap.baseThrottle > 0 and fc.ap.mode ~= "HOVER" then
                            -- Slow down from forward movement toward 0
                            fc.ap.baseThrottle = math.max(0, fc.ap.baseThrottle - 1)
                            if fc.ap.baseThrottle == 0 then
                                hotplugNotice = "DURDU: Geri gitmek icin tekrar [S]'ye basin"
                                hotplugTimer = 50
                            end
                        else
                            -- Engage Reverse Gearshift and clutch for backward movement!
                            fc.ap.reverseGear = true
                            if fc.ap.mode == "HOVER" then
                                fc:setMode("CRUISE", lastTel)
                                fc.ap.parkingBrake = false
                                fc.ap.baseThrottle = 1
                                hotplugNotice = "GERI ITKI (REVERSE): Debriyaj Acik, Gearshift=GERI"
                                hotplugTimer = 50
                            else
                                fc.ap.parkingBrake = false
                                fc.ap.baseThrottle = math.min(15, fc.ap.baseThrottle + 1)
                                if fc.ap.baseThrottle == 1 then
                                    hotplugNotice = "GERI ITKI (REVERSE): Debriyaj Acik, Gearshift=GERI"
                                    hotplugTimer = 50
                                end
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
            if modem and gps and gps.locate then
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

return { run = run }

