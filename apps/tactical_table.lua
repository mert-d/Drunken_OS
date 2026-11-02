--[[
    Drunken OS - Captain's War Room & Tactical Holo-Table v1.0
    by MuhendizBey

    Purpose:
    Dedicated multi-block tactical table dashboard for the Captain's Bridge
    (Amiral Kamarasi). Renders a high-resolution 360 polar radar, flight trail,
    quad-lift & thruster power matrix, ship-wide alert annunciator, and touch-first
    naval controls (Red Alert, Sky Anchor, Hover, Zoom).
]]

local mon = peripheral.find("monitor")
local termObj = mon or term
if mon and mon.setTextScale then pcall(mon.setTextScale, 0.5) end

local isColor = termObj.isColor and termObj.isColor()
local BUS_PROTOCOL = "DRUNKEN_AVIONICS_BUS"

-- Audio Engine Probe
local okSound, Sound = pcall(require, "lib.sound")
if not okSound or type(Sound) ~= "table" then
    local ok2, mod2 = pcall(require, "sound")
    if ok2 and type(mod2) == "table" then Sound = mod2; okSound = true end
end

-- Open modem on rednet for avionics bus
local modem = peripheral.find("modem")
local hasModem = false
if modem then
    local mName = peripheral.getName(modem)
    if rednet and rednet.open then pcall(rednet.open, mName); hasModem = true end
end

-- Telemetry & Autopilot State Cache
local lastTel = {
    callsign = "SKYFIRE",
    vehicleType = "MOTHERSHIP",
    speed = 0,
    altitude = 185,
    heading = 0,
    pitch = 0,
    roll = 0,
    pos = { x = 0, y = 0, z = 0 },
    mothership = { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0, flRpm = 0, frRpm = 0, rlRpm = 0, rrRpm = 0 },
    alertLevel = "NORMAL",
    gpwsWarning = false
}

local lastAp = {
    mode = "MANUAL",
    targetAlt = 185,
    targetHdg = 0,
    reverseGear = false,
    parkingBrake = false,
    homeBase = nil
}

local radarRanges = { 50, 100, 250, 500 }
local currentRangeIdx = 2 -- Default 100m
local trailHistory = {}   -- Breadcrumb trail
local running = true
local flashTick = 0
local toastNotice = "TAKTIK MASA HAZIR"
local toastTimer = 60

-- Touch Button Zones (re-calculated dynamically based on w, h)
local btnAlarm  = { x1 = 2,  y1 = 1, x2 = 14, y2 = 1 }
local btnAnchor = { x1 = 16, y1 = 1, x2 = 27, y2 = 1 }
local btnHover  = { x1 = 29, y1 = 1, x2 = 39, y2 = 1 }
local btnZoom   = { x1 = 41, y1 = 1, x2 = 52, y2 = 1 }

local function sendCmd(cmd, payload)
    if not hasModem or not rednet then return false end
    local pkt = {
        type = "AVIONICS_CMD",
        cmd  = cmd,
        time = (os.epoch and os.epoch("utc")) or os.time()
    }
    if payload then
        for k, v in pairs(payload) do pkt[k] = v end
    end
    pcall(rednet.broadcast, pkt, BUS_PROTOCOL)
    return true
end

local function toggleRedAlert()
    local nextLvl = (lastTel.alertLevel == "RED") and "NORMAL" or "RED"
    lastTel.alertLevel = nextLvl
    sendCmd("SET_ALERT", { level = nextLvl })
    if okSound and Sound and Sound.playAlarm then
        pcall(Sound.playAlarm, nextLvl)
    end
    toastNotice = (nextLvl == "RED") and "🚨 KIRMIZI ALARM DEVREDE! 🚨" or "ALARM IPTAL: NORMAL SEYIR"
    toastTimer = 70
end

local function toggleAnchor()
    local nextMode = (lastAp.mode == "ANCHOR") and "MANUAL" or "ANCHOR"
    lastAp.mode = nextMode
    sendCmd("SET_MODE", { mode = nextMode })
    toastNotice = (nextMode == "ANCHOR") and "GOK CIPASI KILITLENDI" or "CIPA COZULDU: MANUAL"
    toastTimer = 60
end

local function toggleHover()
    local nextMode = (lastAp.mode == "HOVER") and "MANUAL" or "HOVER"
    lastAp.mode = nextMode
    sendCmd("SET_MODE", { mode = nextMode })
    toastNotice = (nextMode == "HOVER") and "HOVER OTOPILOT DEVREDE" or "MANUAL KONTROL"
    toastTimer = 60
end

local function cycleZoom()
    currentRangeIdx = (currentRangeIdx % #radarRanges) + 1
    toastNotice = string.format("RADAR MENZIL: %dm", radarRanges[currentRangeIdx])
    toastTimer = 50
end

local function drawRadar(cx, cy, radiusX, radiusY, maxDist)
    -- Concentric Range Rings
    local r1X, r1Y = math.floor(radiusX * 0.5 + 0.5), math.floor(radiusY * 0.5 + 0.5)
    local r2X, r2Y = radiusX, radiusY

    termObj.setTextColor(isColor and colors.gray or colors.white)
    -- Outer Ring Points (approximation)
    for aDeg = 0, 345, 15 do
        local rad = math.rad(aDeg)
        local ox = math.floor(cx + math.sin(rad) * r2X + 0.5)
        local oy = math.floor(cy - math.cos(rad) * r2Y + 0.5)
        if ox >= 1 and oy >= 2 then
            termObj.setCursorPos(ox, oy)
            termObj.write(".")
        end
    end

    -- Inner Ring Points
    for aDeg = 0, 330, 30 do
        local rad = math.rad(aDeg)
        local ox = math.floor(cx + math.sin(rad) * r1X + 0.5)
        local oy = math.floor(cy - math.cos(rad) * r1Y + 0.5)
        if ox >= 1 and oy >= 2 then
            termObj.setCursorPos(ox, oy)
            termObj.write(":")
        end
    end

    -- Crosshair Axis
    termObj.setTextColor(isColor and colors.cyan or colors.white)
    termObj.setCursorPos(cx, math.max(2, cy - r2Y))
    termObj.write("N")
    termObj.setCursorPos(cx, cy + r2Y)
    termObj.write("S")
    termObj.setCursorPos(math.max(1, cx - r2X), cy)
    termObj.write("W")
    termObj.setCursorPos(cx + r2X, cy)
    termObj.write("E")

    -- Flight Trail Breadcrumbs
    termObj.setTextColor(isColor and colors.blue or colors.lightGray)
    local curX = lastTel.pos and lastTel.pos.x or 0
    local curZ = lastTel.pos and lastTel.pos.z or 0
    for _, pt in ipairs(trailHistory) do
        local dx = pt.x - curX
        local dz = pt.z - curZ
        local px = math.floor(cx + (dx / maxDist) * radiusX + 0.5)
        local py = math.floor(cy + (dz / maxDist) * radiusY + 0.5)
        if px >= cx - radiusX and px <= cx + radiusX and py >= cy - radiusY and py <= cy + radiusY then
            termObj.setCursorPos(px, py)
            termObj.write("·")
        end
    end

    -- Home Base / Dock Beacon
    if lastAp.homeBase and lastAp.homeBase.pos then
        local bx = lastAp.homeBase.pos.x - curX
        local bz = lastAp.homeBase.pos.z - curZ
        local dist = math.sqrt(bx * bx + bz * bz)
        local scale = math.min(1.0, dist / maxDist)
        local angle = math.atan2(bx, -bz)
        local bpx = math.floor(cx + math.sin(angle) * (scale * radiusX) + 0.5)
        local bpy = math.floor(cy - math.cos(angle) * (scale * radiusY) + 0.5)
        termObj.setTextColor(isColor and colors.yellow or colors.white)
        termObj.setCursorPos(bpx, bpy)
        termObj.write("⚓")
    end

    -- Route Waypoints & Flight Legs on Radar
    if lastTel.navRoute and lastTel.navRoute.waypoints then
        local wps = lastTel.navRoute.waypoints
        for idx, wp in ipairs(wps) do
            local wx = wp.x - curX
            local wz = wp.z - curZ
            local dist = math.sqrt(wx * wx + wz * wz)
            if dist < maxDist * 1.5 then
                local scale = math.min(1.0, dist / maxDist)
                local angle = math.atan2(wx, -wz)
                local rpx = math.floor(cx + math.sin(angle) * (scale * radiusX) + 0.5)
                local rpy = math.floor(cy - math.cos(angle) * (scale * radiusY) + 0.5)
                if rpx >= 1 and rpx <= w and rpy >= 2 and rpy <= h - 1 then
                    termObj.setCursorPos(rpx, rpy)
                    if idx == lastTel.navRoute.activeIdx then
                        termObj.setTextColor(isColor and colors.lime or colors.white)
                        termObj.write(tostring(idx))
                    else
                        termObj.setTextColor(isColor and colors.lightGray or colors.white)
                        termObj.write("o")
                    end
                end
            end
        end
    end

    -- Ship Symbol in Center with Heading Needle
    local hdgDeg = math.deg(lastTel.heading or 0) % 360
    local sym = "^"
    if hdgDeg >= 337.5 or hdgDeg < 22.5 then sym = "^"
    elseif hdgDeg >= 22.5 and hdgDeg < 67.5 then sym = "/"
    elseif hdgDeg >= 67.5 and hdgDeg < 112.5 then sym = ">"
    elseif hdgDeg >= 112.5 and hdgDeg < 157.5 then sym = "\\"
    elseif hdgDeg >= 157.5 and hdgDeg < 202.5 then sym = "v"
    elseif hdgDeg >= 202.5 and hdgDeg < 247.5 then sym = "/"
    elseif hdgDeg >= 247.5 and hdgDeg < 292.5 then sym = "<"
    else sym = "\\" end

    termObj.setCursorPos(cx, cy)
    termObj.setBackgroundColor(isColor and colors.blue or colors.white)
    termObj.setTextColor(isColor and colors.yellow or colors.black)
    termObj.write(sym)
    termObj.setBackgroundColor(colors.black)
end

local function renderTable()
    local w, h = termObj.getSize()
    termObj.setBackgroundColor(colors.black)
    termObj.clear()

    flashTick = (flashTick + 1) % 40
    local isRedAlert = (lastTel.alertLevel == "RED")

    -- 1. Top Header Banner
    termObj.setCursorPos(1, 1)
    if isRedAlert then
        local flashCol = (flashTick < 20) and colors.red or colors.orange
        termObj.setBackgroundColor(flashCol)
        termObj.setTextColor(colors.white)
        local hdr = " 🚨 DRUNKEN OS // KIRMIZI ALARM - SAVAS POZISYONU 🚨 "
        termObj.write(hdr .. string.rep(" ", math.max(0, w - #hdr)))
    else
        termObj.setBackgroundColor(isColor and colors.blue or colors.white)
        termObj.setTextColor(isColor and colors.white or colors.black)
        local hdr = string.format(" DRUNKEN OS // KAPTAN KOSKU TAKTIK MASASI [%s] ", tostring(lastTel.callsign or "SKYFIRE"))
        termObj.write(hdr .. string.rep(" ", math.max(0, w - #hdr)))
    end

    termObj.setBackgroundColor(colors.black)

    -- 2. Left Telemetry & Propulsion Column (w <= 20)
    local ms = lastTel.mothership or { flRpm = 0, frRpm = 0, rlRpm = 0, rrRpm = 0, rearL = 0, rearC = 0, rearR = 0 }
    termObj.setTextColor(isColor and colors.cyan or colors.white)
    termObj.setCursorPos(2, 3)
    termObj.write("--- GUC DAGILIMI ---")
    termObj.setCursorPos(2, 4)
    termObj.setTextColor(colors.white)
    termObj.write(string.format("FL:%3d | FR:%3d RPM", ms.flRpm or 0, ms.frRpm or 0))
    termObj.setCursorPos(2, 5)
    termObj.write(string.format("RL:%3d | RR:%3d RPM", ms.rlRpm or 0, ms.rrRpm or 0))
    termObj.setCursorPos(2, 6)
    termObj.setTextColor(isColor and colors.lightGray or colors.white)
    termObj.write(string.format("ARKA: L:%d C:%d R:%d", ms.rearL or 0, ms.rearC or 0, ms.rearR or 0))

    termObj.setCursorPos(2, 8)
    termObj.setTextColor(isColor and colors.cyan or colors.white)
    termObj.write("--- UCUS VE TUTUM ---")
    termObj.setCursorPos(2, 9)
    termObj.setTextColor(colors.white)
    termObj.write(string.format("IRT : %5.1fm (T:%.0f)", lastTel.altitude or 0, lastAp.targetAlt or 0))
    termObj.setCursorPos(2, 10)
    termObj.write(string.format("HIZ : %4.1fm/s | VSI:%+4.1f", lastTel.speed or 0, lastTel.vSpeed or 0))
    termObj.setCursorPos(2, 11)
    termObj.write(string.format("PCH : %+4.1f° | ROL:%+4.1f°", math.deg(lastTel.pitch or 0), math.deg(lastTel.roll or 0)))
    termObj.setCursorPos(2, 12)
    local hdgDeg = math.deg(lastTel.heading or 0) % 360
    termObj.write(string.format("PUS : %03.0f° | PARK:%s", hdgDeg, lastAp.parkingBrake and "EVET" or "HAYIR"))
    if h >= 14 then
        termObj.setCursorPos(2, 13)
        local pAtm = lastTel.pressure or 1.0
        local pHpa = lastTel.pressureHPa or (pAtm * 1013.25)
        termObj.setTextColor(pAtm < 0.45 and (isColor and colors.orange or colors.white) or (isColor and colors.cyan or colors.white))
        termObj.write(string.format("BAR : %4.0fhPa (%4.2fa)", pHpa, pAtm))
    end

    -- 3. Center 360 Polar Tactical Radar
    local hasRightCol = (w >= 48)
    local maxDist = radarRanges[currentRangeIdx] or 100
    local radarCx = hasRightCol and math.floor(w * 0.5) or math.floor(w * 0.58)
    local radarCy = math.floor((h - 3) * 0.5) + 2
    local radX = hasRightCol and math.min(12, math.floor((w - 36) * 0.5)) or math.min(18, math.floor(w * 0.22))
    local radY = math.min(8, math.floor((h - 6) * 0.45))

    drawRadar(radarCx, radarCy, radX, radY, maxDist)

    -- Radar Legend
    termObj.setCursorPos(radarCx - 6, math.max(2, radarCy - radY - 1))
    termObj.setTextColor(isColor and colors.yellow or colors.white)
    termObj.write(string.format("[ RADAR: %dm ]", maxDist))

    -- 4. Right Status Column (If screen is wide enough)
    if w >= 48 then
        local rx = w - 18
        termObj.setCursorPos(rx, 3)
        termObj.setTextColor(isColor and colors.cyan or colors.white)
        termObj.write("--- ISTASYONLAR ---")
        termObj.setCursorPos(rx, 4)
        termObj.setTextColor(isColor and colors.lime or colors.white)
        termObj.write("FCS KOKPIT : OK")
        termObj.setCursorPos(rx, 5)
        termObj.write("FCC MOTOR  : OK")
        termObj.setCursorPos(rx, 6)
        termObj.setTextColor(isColor and colors.lightGray or colors.white)
        termObj.write("ENG GUVRT  : HAZIR")
        termObj.setCursorPos(rx, 7)
        local baseStr = lastAp.homeBase and tostring(lastAp.homeBase.runwayId or "RWY") or "YOK"
        termObj.write("ILS KULE   : " .. baseStr)

        termObj.setCursorPos(rx, 9)
        termObj.setTextColor(isColor and colors.yellow or colors.white)
        termObj.write("--- GUVENLIK ---")
        termObj.setCursorPos(rx, 10)
        local alertStr = (lastTel.alertLevel == "RED") and "KIRMIZI ALARM" or "GUVENLI SEYIR"
        termObj.setTextColor((lastTel.alertLevel == "RED") and colors.red or (isColor and colors.lime or colors.white))
        termObj.write(alertStr)
        termObj.setCursorPos(rx, 11)
        termObj.setTextColor(colors.white)
        termObj.write("MOD: " .. tostring(lastAp.mode or "MANUAL"))

        if lastTel.navRoute and lastTel.navRoute.wpName then
            termObj.setCursorPos(rx, 13)
            termObj.setTextColor(isColor and colors.cyan or colors.white)
            termObj.write("--- OTONOM NAV ---")
            termObj.setCursorPos(rx, 14)
            termObj.setTextColor(isColor and colors.lime or colors.white)
            termObj.write(string.format("WP: %s", lastTel.navRoute.wpName:sub(1, 13)))
            termObj.setCursorPos(rx, 15)
            termObj.setTextColor(colors.white)
            termObj.write(string.format("D:%4.0fm T:%3.0fs", lastTel.navRoute.dist or 0, lastTel.navRoute.ete or 0))
            termObj.setCursorPos(rx, 16)
            termObj.setTextColor(colors.lightGray)
            termObj.write(string.format("XTK: %+5.1fm", lastTel.navRoute.xtk or 0))
        end
    end

    -- 5. Toast / Status Line (Row h - 2)
    termObj.setCursorPos(2, h - 2)
    if toastTimer > 0 then
        termObj.setTextColor(isColor and colors.yellow or colors.white)
        termObj.write(">> " .. tostring(toastNotice) .. " <<")
    else
        termObj.setTextColor(isColor and colors.gray or colors.white)
        termObj.write(string.format("KONUM: X:%d Y:%d Z:%d | PUSULA: %03.0f°",
            math.floor(lastTel.pos.x or 0), math.floor(lastTel.pos.y or 0), math.floor(lastTel.pos.z or 0), hdgDeg
        ))
    end

    -- 6. Interactive Touch Controls Bar (Row h - 1 to h)
    btnAlarm  = { x1 = 2,  y1 = h - 1, x2 = 14, y2 = h }
    btnAnchor = { x1 = 16, y1 = h - 1, x2 = 27, y2 = h }
    btnHover  = { x1 = 29, y1 = h - 1, x2 = 39, y2 = h }
    btnZoom   = { x1 = 41, y1 = h - 1, x2 = 52, y2 = h }

    -- [ALARM] Button
    termObj.setCursorPos(btnAlarm.x1, btnAlarm.y1)
    termObj.setBackgroundColor(isRedAlert and colors.red or colors.gray)
    termObj.setTextColor(colors.white)
    termObj.write(isRedAlert and "[!] ALARM: ON " or "[!] ALARM: OFF")
    termObj.setCursorPos(btnAlarm.x1, btnAlarm.y2)
    termObj.write("              ")

    -- [ANCHOR] Button
    local isAnc = (lastAp.mode == "ANCHOR")
    termObj.setCursorPos(btnAnchor.x1, btnAnchor.y1)
    termObj.setBackgroundColor(isAnc and colors.yellow or colors.gray)
    termObj.setTextColor(isAnc and colors.black or colors.white)
    termObj.write(" [⚓] CIPA     ")
    termObj.setCursorPos(btnAnchor.x1, btnAnchor.y2)
    termObj.write("              ")

    -- [HOVER] Button
    local isHvr = (lastAp.mode == "HOVER")
    termObj.setCursorPos(btnHover.x1, btnHover.y1)
    termObj.setBackgroundColor(isHvr and colors.lime or colors.gray)
    termObj.setTextColor(isHvr and colors.black or colors.white)
    termObj.write(" [⚡] HOVER   ")
    termObj.setCursorPos(btnHover.x1, btnHover.y2)
    termObj.write("           ")

    -- [ZOOM] Button
    termObj.setCursorPos(btnZoom.x1, btnZoom.y1)
    termObj.setBackgroundColor(colors.blue)
    termObj.setTextColor(colors.white)
    termObj.write(string.format(" [🔍] %-4dm   ", maxDist))
    termObj.setCursorPos(btnZoom.x1, btnZoom.y2)
    termObj.write("              ")

    termObj.setBackgroundColor(colors.black)
end

-- Telemetry & Network Listener Thread
local function networkLoop()
    -- Request state on bus
    sendCmd("SCAN_PERIPHERALS")
    if rednet and rednet.broadcast then
        pcall(rednet.broadcast, { type = "AVIONICS_DISCOVER" }, BUS_PROTOCOL)
    end

    while running do
        local sender, msg, proto = rednet.receive(BUS_PROTOCOL, 0.05)
        if msg and type(msg) == "table" then
            if msg.type == "AVIONICS_STATE" then
                if msg.tel then
                    lastTel = msg.tel
                    -- Record flight breadcrumb
                    if lastTel.pos then
                        table.insert(trailHistory, { x = lastTel.pos.x, z = lastTel.pos.z })
                        if #trailHistory > 20 then table.remove(trailHistory, 1) end
                    end
                end
                if msg.alertLevel then lastTel.alertLevel = msg.alertLevel end
                if msg.ap then
                    for k, v in pairs(msg.ap) do lastAp[k] = v end
                end
            elseif msg.type == "AVIONICS_TELEMETRY" and msg.telemetry then
                lastTel = msg.telemetry
                if lastTel.pos then
                    table.insert(trailHistory, { x = lastTel.pos.x, z = lastTel.pos.z })
                    if #trailHistory > 20 then table.remove(trailHistory, 1) end
                end
            elseif msg.type == "AVIONICS_ALERT" and msg.level then
                lastTel.alertLevel = msg.level
            end
        else
            sleep(0.05)
        end
    end
end

-- Render & User Interaction Thread
local function interactionLoop()
    local renderTimer = os.startTimer(0.1)
    while running do
        renderTable()
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "timer" and p1 == renderTimer then
            if toastTimer > 0 then toastTimer = toastTimer - 1 end
            renderTimer = os.startTimer(0.1)
        elseif ev == "key" then
            local k = p1
            if k == keys.q then
                running = false
            elseif k == keys.k then
                toggleRedAlert()
            elseif k == keys.z or k == keys.c then
                toggleAnchor()
            elseif k == keys.h then
                toggleHover()
            elseif k == keys.r or k == keys.tab then
                cycleZoom()
            end
        elseif ev == "monitor_touch" or ev == "mouse_click" then
            local tx, ty = p2, p3
            if ty >= btnAlarm.y1 and ty <= btnAlarm.y2 and tx >= btnAlarm.x1 and tx <= btnAlarm.x2 then
                toggleRedAlert()
            elseif ty >= btnAnchor.y1 and ty <= btnAnchor.y2 and tx >= btnAnchor.x1 and tx <= btnAnchor.x2 then
                toggleAnchor()
            elseif ty >= btnHover.y1 and ty <= btnHover.y2 and tx >= btnHover.x1 and tx <= btnHover.x2 then
                toggleHover()
            elseif ty >= btnZoom.y1 and ty <= btnZoom.y2 and tx >= btnZoom.x1 and tx <= btnZoom.x2 then
                cycleZoom()
            end
        end
    end
end

if parallel and parallel.waitForAny then
    parallel.waitForAny(networkLoop, interactionLoop)
else
    interactionLoop()
end

termObj.setBackgroundColor(colors.black)
termObj.clear()
termObj.setCursorPos(1, 1)
print("Kaptan Kosku Taktik Masasi sonlandirildi.")
