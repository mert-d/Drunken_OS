-- apps/flight_control.lua
-- Drunken OS Primary Flight Display (PFD) & Autopilot Cockpit App

local Avionics = require("lib.avionics")
local okSound, Sound = pcall(require, "lib.sound")

local function run(context)
    context = context or {}
    local parentTerm = context.parent or term.current()
    local theme = context.theme or {
        bg      = colors.black,
        fg      = colors.white,
        accent  = colors.cyan,
        header  = colors.blue,
        ok      = colors.lime,
        warn    = colors.orange,
        err     = colors.red,
        muted   = colors.gray
    }

    local fc = Avionics.new({
        callsign = context.username and ("DOS-" .. string.upper(string.sub(context.username, 1, 4))) or nil
    })

    local running = true
    local lastTel = fc:readTelemetry(0.05)
    local tickCount = 0

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

    local function drawArtificialHorizon(cx, cy, width, height, pitchRad, rollRad)
        local pitchDeg = math.deg(pitchRad)
        local rollSlope = math.tan(rollRad)
        local pitchOffset = math.floor((pitchDeg / 10) + 0.5)

        for dy = -math.floor(height / 2), math.floor(height / 2) do
            local y = cy + dy
            if y >= 2 and y <= 18 then
                parentTerm.setCursorPos(cx - math.floor(width / 2), y)
                for dx = -math.floor(width / 2), math.floor(width / 2) do
                    local horizonY = pitchOffset + math.floor(dx * rollSlope + 0.5)
                    if dy == 0 and math.abs(dx) <= 2 then
                        -- Center Aircraft Reticle
                        parentTerm.setBackgroundColor(colors.black)
                        parentTerm.setTextColor(colors.yellow)
                        parentTerm.write(dx == 0 and "+" or "-")
                    elseif dy < horizonY then
                        -- Sky
                        parentTerm.setBackgroundColor(colors.blue)
                        parentTerm.setTextColor(colors.white)
                        parentTerm.write(" ")
                    elseif dy == horizonY then
                        -- Horizon Line
                        parentTerm.setBackgroundColor(colors.cyan)
                        parentTerm.setTextColor(colors.white)
                        parentTerm.write("-")
                    else
                        -- Ground
                        parentTerm.setBackgroundColor(colors.brown)
                        parentTerm.setTextColor(colors.lightGray)
                        parentTerm.write(" ")
                    end
                end
            end
        end
    end

    local function renderPFD()
        local w, h = parentTerm.getSize()
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.clear()

        -- Top Status Bar
        parentTerm.setCursorPos(1, 1)
        parentTerm.setBackgroundColor(theme.header or colors.blue)
        parentTerm.setTextColor(colors.white)
        local headerText = string.format(
            " DRUNKEN AVIONICS | %s [%s] | AP: %s ",
            lastTel.callsign,
            lastTel.vehicleType,
            fc.ap.mode
        )
        parentTerm.write(headerText .. string.rep(" ", math.max(0, w - #headerText)))

        -- Artificial Horizon (Center)
        if w >= 45 and h >= 16 then
            drawArtificialHorizon(math.floor(w / 2), 7, 16, 7, lastTel.pitch, lastTel.roll)
        end

        -- Left Tape: Speed, Pitch/Roll, Engine Stress
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.setTextColor(theme.fg)
        parentTerm.setCursorPos(2, 3)
        parentTerm.write(string.format("SPD : %5.1f m/s", lastTel.speed))
        parentTerm.setCursorPos(2, 4)
        parentTerm.write(string.format("THR : %2d / 15", fc.ap.baseThrottle))
        parentTerm.setCursorPos(2, 5)
        parentTerm.write(string.format("PTCH: %+5.1f deg", math.deg(lastTel.pitch)))
        parentTerm.setCursorPos(2, 6)
        parentTerm.write(string.format("ROLL: %+5.1f deg", math.deg(lastTel.roll)))
        parentTerm.setCursorPos(2, 7)
        parentTerm.write(string.format("RPM : %5.0f", lastTel.rpm))

        parentTerm.setCursorPos(2, 8)
        if lastTel.overstressed then
            parentTerm.setTextColor(theme.err or colors.red)
            parentTerm.write("STRS: OVERSTRESS!")
        else
            parentTerm.setTextColor(theme.ok or colors.lime)
            parentTerm.write("STRS: NOMINAL")
        end

        -- Right Tape: Altitude, VSI, Heading, Radar AGL
        local rightCol = math.max(30, w - 18)
        parentTerm.setTextColor(theme.fg)
        parentTerm.setCursorPos(rightCol, 3)
        parentTerm.write(string.format("ALT: %6.1f m", lastTel.altitude))
        parentTerm.setCursorPos(rightCol, 4)
        parentTerm.setTextColor(theme.accent or colors.cyan)
        parentTerm.write(string.format("TGT: %6.1f m", fc.ap.targetAlt))

        parentTerm.setTextColor(theme.fg)
        parentTerm.setCursorPos(rightCol, 5)
        parentTerm.write(string.format("VSI: %+5.1f m/s", lastTel.vSpeed))

        local hdgDeg = math.deg(lastTel.heading) % 360
        local tgtHdgDeg = math.deg(fc.ap.targetHdg) % 360
        parentTerm.setCursorPos(rightCol, 6)
        parentTerm.write(string.format("HDG: %05.1f deg", hdgDeg))
        parentTerm.setCursorPos(rightCol, 7)
        parentTerm.setTextColor(theme.accent or colors.cyan)
        parentTerm.write(string.format("CRS: %05.1f deg", tgtHdgDeg))

        parentTerm.setCursorPos(rightCol, 8)
        parentTerm.setTextColor(theme.fg)
        if lastTel.agl then
            parentTerm.write(string.format("AGL: %5.1f m", lastTel.agl))
        else
            parentTerm.write("AGL: ---.- m")
        end

        -- ILS / RTB Deviation Row (Row 10)
        parentTerm.setCursorPos(2, 10)
        parentTerm.setBackgroundColor(theme.bg)
        if fc.ap.mode == "RTB" and fc.ap.homeBase then
            parentTerm.setTextColor(colors.cyan)
            parentTerm.write(string.format(
                "ILS [%s/%s] LOC:%+5.1fm GS:%+5.1fm DST:%4.0fm",
                tostring(fc.ap.homeBase.runwayId or "RWY"),
                tostring(fc.ap.rtbPhase),
                fc.ap.ilsDev.loc or 0,
                fc.ap.ilsDev.gs or 0,
                fc.ap.ilsDev.dist or 0
            ))
        elseif fc.ap.homeBase then
            parentTerm.setTextColor(colors.lightGray)
            parentTerm.write(string.format(
                "ILS BEACON LOCKED: %s (%s) - Press [R] for RTB",
                tostring(fc.ap.homeBase.baseName or "BASE"),
                tostring(fc.ap.homeBase.runwayId or "RWY")
            ))
        end

        -- Warnings Banner (GPWS / Stall / Gear)
        parentTerm.setCursorPos(2, 11)
        if lastTel.gpwsWarning then
            parentTerm.setBackgroundColor(colors.red)
            parentTerm.setTextColor(colors.white)
            parentTerm.write(" !! PULL UP - TERRAIN AHEAD !! ")
        elseif lastTel.stallWarning then
            parentTerm.setBackgroundColor(colors.orange)
            parentTerm.setTextColor(colors.black)
            parentTerm.write(" !! STALL WARNING - LOWER NOSE !! ")
        else
            parentTerm.setBackgroundColor(theme.bg)
            parentTerm.setTextColor(lastTel.weightOnWheels and colors.lime or colors.lightGray)
            parentTerm.write(string.format(
                "GEAR: %s | BRAKE: %s | POS: (%d, %d, %d)",
                lastTel.weightOnWheels and "DOWN/LOCKED" or "AIRBORNE",
                fc.ap.parkingBrake and "ON " or "OFF",
                math.floor(lastTel.pos.x),
                math.floor(lastTel.pos.y),
                math.floor(lastTel.pos.z)
            ))
        end

        -- Mode Annunciator Row
        parentTerm.setBackgroundColor(theme.bg)
        parentTerm.setCursorPos(2, h - 3)
        parentTerm.setTextColor(fc.ap.enabled and colors.lime or colors.orange)
        parentTerm.write(string.format(
            "[A]AP:%s [H]HVR [C]CRS [R]RTB [L]LND [B]BRK:%s",
            fc.ap.enabled and "ON " or "OFF",
            fc.ap.parkingBrake and "ON" or "OFF"
        ))

        parentTerm.setCursorPos(2, h - 2)
        parentTerm.setTextColor(colors.lightGray)
        parentTerm.write("[Up/Dn]:Alt +-5m | [Lt/Rt]:Hdg +-5d | [W/S]:Thr | [Q]:Exit")
    end

    -- Background 20Hz Flight Control & Telemetry Loop
    local function flightControlLoop()
        while running do
            lastTel = fc:step(0.05)
            tickCount = tickCount + 1

            if lastTel.gpwsWarning and (tickCount % 10 == 0) then
                playAlert("GPWS")
            end

            -- Broadcast ADS-B Telemetry once per second (every 20 ticks)
            if modem and rednet and (tickCount % 20 == 0) then
                pcall(rednet.broadcast, {
                    type        = "AVIONICS_ADSB",
                    callsign    = lastTel.callsign,
                    vehicleType = lastTel.vehicleType,
                    pos         = lastTel.pos,
                    altitude    = lastTel.altitude,
                    speed       = lastTel.speed,
                    heading     = math.deg(lastTel.heading) % 360,
                    vSpeed      = lastTel.vSpeed,
                    mode        = fc.ap.mode,
                    timestamp   = os.epoch and os.epoch("utc") or os.time()
                }, "DRUNKEN_RADAR")
            end

            renderPFD()
            sleep(0.05)
        end
    end

    -- Pilot Input & Network Event Loop (Keyboard & Rednet ILS Beacon)
    local function pilotInputLoop()
        while running do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "rednet_message" then
                local msg, protocol = p2, p3
                if protocol == "DRUNKEN_ILS" and type(msg) == "table" and msg.type == "AVIONICS_ILS_BEACON" then
                    fc:setHomeBase(msg)
                end
            elseif ev == "key" then
                local key = p1
                playAlert("CLICK")
                if key == keys.q then
                    -- Safe disarm & flush manual state to actuators on exit
                    fc.ap.baseThrottle = 0
                    fc:setMode("MANUAL", lastTel)
                    fc:step(0.05)
                    running = false
                elseif key == keys.a then
                    if fc.ap.enabled then
                        fc:setMode("MANUAL", lastTel)
                    else
                        fc:setMode("CRUISE", lastTel)
                    end
                elseif key == keys.c then
                    fc:setMode("CRUISE", lastTel)
                elseif key == keys.h then
                    fc:setMode("HOVER", lastTel)
                elseif key == keys.r then
                    fc:engageRTB(lastTel)
                elseif key == keys.l then
                    fc:setMode("AUTOLAND", lastTel)
                elseif key == keys.b then
                    fc.ap.parkingBrake = not fc.ap.parkingBrake
                elseif key == keys.up then
                    fc.ap.targetAlt = fc.ap.targetAlt + 5
                elseif key == keys.down then
                    fc.ap.targetAlt = math.max(0, fc.ap.targetAlt - 5)
                elseif key == keys.left then
                    fc.ap.targetHdg = (fc.ap.targetHdg - math.rad(5)) % (2 * math.pi)
                elseif key == keys.right then
                    fc.ap.targetHdg = (fc.ap.targetHdg + math.rad(5)) % (2 * math.pi)
                elseif key == keys.w then
                    fc.ap.baseThrottle = math.min(15, fc.ap.baseThrottle + 1)
                elseif key == keys.s then
                    fc.ap.baseThrottle = math.max(0, fc.ap.baseThrottle - 1)
                end
            end
        end
    end

    parallel.waitForAny(flightControlLoop, pilotInputLoop)
end

-- Allow direct execution when invoked from shell, CLI, or startup
if shell and shell.getRunningProgram and shell.getRunningProgram():match("flight_control") then
    run()
end

return { run = run }

