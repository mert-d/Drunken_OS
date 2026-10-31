--[[
    Drunken OS - Engineering Deck & Powertrain Monitor v1.1
    by MuhendizBey

    Purpose:
    Dedicated diagnostic dashboard and touch control console for the
    Mothership Lower Deck (Makine Dairesi). Displays live RPM, stress,
    clutch states, rear thruster matrix, wing altimeter balance, and provides
    emergency SCRAM & pre-flight spin test controls.
]]

local mon = peripheral.find("monitor")
local termObj = mon or term
if mon and mon.setTextScale then pcall(mon.setTextScale, 0.5) end

local isColor = termObj.isColor and termObj.isColor()
local BUS_PROTOCOL = "DRUNKEN_AVIONICS_BUS"

-- Open modem for FCC bus telemetry if available
local modem = peripheral.find("modem")
local hasModem = false
if modem then
    local mName = peripheral.getName(modem)
    if rednet and rednet.open then pcall(rednet.open, mName); hasModem = true end
end

-- Discover local kinetic devices if directly wired
local function findLocal(types)
    local res = {}
    if not (peripheral and peripheral.find) then return res end
    for _, t in ipairs(types) do
        local found = { peripheral.find(t) }
        for _, p in ipairs(found) do table.insert(res, p) end
    end
    return res
end

local localSpeedControllers = findLocal({ "Create_RotationSpeedController", "rotation_speed_controller", "speed_controller" })
local localClutches         = findLocal({ "create_connected_inverted_clutch", "inverted_clutch", "create_clutch", "clutch" })
local localGearshifts       = findLocal({ "create_gearshift", "gearshift" })
local localAltSensors       = findLocal({ "altitude_sensor" })

local lastTel = {
    vehicleType = "MOTHERSHIP",
    speed = 0,
    altitude = 0,
    heading = 0,
    pitch = 0,
    roll = 0,
    mothership = { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 },
    wingAlt = { dR = 0, dP = 0 }
}

local lastAp = {
    mode = "MANUAL",
    reverseGear = false,
    parkingBrake = false,
    baseThrottle = 0
}

local toastMsg = "MAKINE DAIRESI HAZIR"
local toastTimer = 60
local spinTestActive = 0
local running = true

-- Touch button boundaries (Rows 16..17)
local btnScram = { x1 = 2,  y1 = 16, x2 = 16, y2 = 17 }
local btnSpin  = { x1 = 18, y1 = 16, x2 = 33, y2 = 17 }
local btnAnc   = { x1 = 35, y1 = 16, x2 = 49, y2 = 17 }

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
    rednet.broadcast(pkt, BUS_PROTOCOL)
    return true
end

local function executeScram()
    toastMsg = "!! ACIL SCRAM AKTIF !!"
    toastTimer = 80
    sendCmd("SAFE_DISARM")
    -- Local emergency cut
    for _, cl in ipairs(localClutches) do
        if cl.setPowered then pcall(cl.setPowered, true) end
        if cl.setSignal then pcall(cl.setSignal, 15) end
    end
    for _, sc in ipairs(localSpeedControllers) do
        if sc.setTargetSpeed then pcall(sc.setTargetSpeed, 0) end
    end
    if redstone and redstone.setOutput then
        pcall(redstone.setOutput, "back", false)
        pcall(redstone.setOutput, "top", false)
    end
end

local function executeSpinTest()
    toastMsg = "MOTOR TESTI BASLATILDI..."
    toastTimer = 70
    sendCmd("SPIN_TEST", { name = "ALL" })
    spinTestActive = 30 -- ~1.5 sec at 20Hz non-blocking
    for _, sc in ipairs(localSpeedControllers) do
        if sc.setTargetSpeed then pcall(sc.setTargetSpeed, 64) end
    end
end

local function drawBox(x, y, w, h, title, col)
    termObj.setTextColor(col or colors.cyan)
    termObj.setCursorPos(x, y)
    termObj.write("+" .. string.rep("-", math.max(0, w - 2)) .. "+")
    for row = 1, h - 2 do
        termObj.setCursorPos(x, y + row)
        termObj.write("|" .. string.rep(" ", math.max(0, w - 2)) .. "|")
    end
    termObj.setCursorPos(x, y + h - 1)
    termObj.write("+" .. string.rep("-", math.max(0, w - 2)) .. "+")
    if title then
        termObj.setCursorPos(x + 2, y)
        termObj.setTextColor(colors.white)
        termObj.write(" " .. title .. " ")
    end
end

local function renderDashboard()
    local w, h = termObj.getSize()
    termObj.setBackgroundColor(colors.black)
    termObj.clear()

    -- Title Bar
    termObj.setCursorPos(1, 1)
    termObj.setBackgroundColor(isColor and colors.gray or colors.white)
    termObj.setTextColor(isColor and colors.yellow or colors.black)
    termObj.clearLine()
    termObj.write(" DRUNKEN OS // MAKINE DAIRESI & GUC DAGITIM KONSOLU ")

    local ms = lastTel.mothership or { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 }
    local wA = lastTel.wingAlt or { dR = 0, dP = 0 }

    termObj.setBackgroundColor(colors.black)

    -- 1. Lift Rotors FL & FR (Rows 3..5)
    drawBox(2, 3, 24, 3, "ON-SOL (FL)", colors.cyan)
    termObj.setCursorPos(4, 4); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC:%2d/15", ms.fl))
    termObj.setCursorPos(14, 4); termObj.setTextColor(colors.lime)
    local rpmFL = math.floor((ms.fl / 15) * 256 + 0.5)
    termObj.write(string.format("%3d RPM", rpmFL))

    drawBox(27, 3, 24, 3, "ON-SAG (FR)", colors.cyan)
    termObj.setCursorPos(29, 4); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC:%2d/15", ms.fr))
    termObj.setCursorPos(39, 4); termObj.setTextColor(colors.lime)
    local rpmFR = math.floor((ms.fr / 15) * 256 + 0.5)
    termObj.write(string.format("%3d RPM", rpmFR))

    -- 2. Lift Rotors RL & RR (Rows 6..8)
    drawBox(2, 6, 24, 3, "ARKA-SOL (RL)", colors.cyan)
    termObj.setCursorPos(4, 7); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC:%2d/15", ms.rl))
    termObj.setCursorPos(14, 7); termObj.setTextColor(colors.lime)
    local rpmRL = math.floor((ms.rl / 15) * 256 + 0.5)
    termObj.write(string.format("%3d RPM", rpmRL))

    drawBox(27, 6, 24, 3, "ARKA-SAG (RR)", colors.cyan)
    termObj.setCursorPos(29, 7); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC:%2d/15", ms.rr))
    termObj.setCursorPos(39, 7); termObj.setTextColor(colors.lime)
    local rpmRR = math.floor((ms.rr / 15) * 256 + 0.5)
    termObj.write(string.format("%3d RPM", rpmRR))

    -- 3. Rear Propulsion & Drivetrain (Rows 9..11)
    drawBox(2, 9, 49, 3, "ARKA ITKI & SAFT SISTEMI", colors.purple or colors.magenta)
    termObj.setCursorPos(4, 10); termObj.setTextColor(colors.white)
    termObj.write(string.format("SOL:%2d  MRK:%2d  SAG:%2d", ms.rearL or 0, ms.rearC or 0, ms.rearR or 0))

    termObj.setCursorPos(28, 10)
    termObj.setTextColor(colors.lightGray)
    termObj.write("| VTS:")
    if lastAp.reverseGear then
        termObj.setTextColor(isColor and colors.yellow or colors.white)
        termObj.write("GERI ")
    else
        termObj.setTextColor(isColor and colors.lime or colors.white)
        termObj.write("ILR  ")
    end

    termObj.setTextColor(colors.lightGray)
    termObj.write("DEB:")
    local clutchCut = (lastAp.parkingBrake or lastAp.mode == "HOVER")
    if clutchCut then
        termObj.setTextColor(isColor and colors.orange or colors.white)
        termObj.write("AYRIK")
    else
        termObj.setTextColor(isColor and colors.lime or colors.white)
        termObj.write("BAGLI")
    end

    -- 4. Wing Matrix & Sky Anchor Status (Rows 12..14)
    drawBox(2, 12, 49, 3, "KANAT TERAZISI & CAPA KILIDI", colors.orange)
    termObj.setCursorPos(4, 13); termObj.setTextColor(colors.white)
    termObj.write(string.format("dR:%+4.1fm  dP:%+4.1fm", wA.dR or 0, wA.dP or 0))

    termObj.setCursorPos(28, 13)
    if (lastTel.anchor and lastTel.anchor.active) or lastAp.mode == "ANCHOR" then
        termObj.setTextColor(isColor and colors.yellow or colors.white)
        termObj.write("[CAPA: LOK-SABIT]")
    elseif lastAp.parkingBrake then
        termObj.setTextColor(isColor and colors.red or colors.white)
        termObj.write("[PARK FRENI AKTIF]")
    else
        termObj.setTextColor(isColor and colors.lime or colors.white)
        termObj.write("[DENGELEME: OK]  ")
    end

    -- 5. Interactive Touch Buttons Bar (Rows 16..17)
    termObj.setCursorPos(btnScram.x1, btnScram.y1)
    termObj.setBackgroundColor(colors.red); termObj.setTextColor(colors.white)
    termObj.write(" [S] ACIL SCRAM ")
    termObj.setCursorPos(btnScram.x1, btnScram.y2)
    termObj.write("                ")

    termObj.setCursorPos(btnSpin.x1, btnSpin.y1)
    termObj.setBackgroundColor(colors.blue); termObj.setTextColor(colors.white)
    termObj.write(" [T] TEST DONDUR")
    termObj.setCursorPos(btnSpin.x1, btnSpin.y2)
    termObj.write("                ")

    termObj.setCursorPos(btnAnc.x1, btnAnc.y1)
    termObj.setBackgroundColor(colors.yellow); termObj.setTextColor(colors.black)
    termObj.write(" [C] CAPA KILIT ")
    termObj.setCursorPos(btnAnc.x1, btnAnc.y2)
    termObj.write("                ")

    -- 6. Toast & Connection Status (Rows 18..19)
    termObj.setBackgroundColor(colors.black)
    termObj.setCursorPos(2, 18)
    if toastTimer > 0 then
        termObj.setTextColor(isColor and colors.yellow or colors.white)
        termObj.write(">> " .. tostring(toastMsg) .. " <<")
    else
        termObj.write(string.rep(" ", 48))
    end

    termObj.setCursorPos(2, 19)
    termObj.setTextColor(isColor and colors.gray or colors.white)
    local connStatus = hasModem and "FCC BUS [BAGLI]" or "YEREL SENSOR"
    termObj.write(string.format("BAGLANTI: %-15s | [Q]: Cikis", connStatus))
end

-- Telemetry listener thread
local function telemetryListener()
    while running do
        if hasModem and rednet then
            local sender, msg, proto = rednet.receive(BUS_PROTOCOL, 0.05)
            if msg and type(msg) == "table" then
                if msg.type == "AVIONICS_STATE" then
                    if msg.tel then lastTel = msg.tel end
                    if msg.ap then
                        for k, v in pairs(msg.ap) do
                            lastAp[k] = v
                        end
                    end
                elseif msg.type == "AVIONICS_TELEMETRY" and msg.telemetry then
                    lastTel = msg.telemetry
                end
            end
        else
            sleep(0.05)
        end
    end
end

-- Input & Interaction loop
local function interactionLoop()
    local timerId = os.startTimer(0.1)
    while running do
        renderDashboard()
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "timer" and p1 == timerId then
            if spinTestActive > 0 then
                spinTestActive = spinTestActive - 1
                if spinTestActive <= 0 then
                    for _, sc in ipairs(localSpeedControllers) do
                        if sc.setTargetSpeed then pcall(sc.setTargetSpeed, 0) end
                    end
                    toastMsg = "MOTOR TESTI TAMAMLANDI"
                    toastTimer = 50
                end
            end
            if toastTimer > 0 then
                toastTimer = toastTimer - 1
            end
            timerId = os.startTimer(0.1)
        elseif ev == "key" then
            local k = p1
            if k == keys.q then
                running = false
            elseif k == keys.s then
                executeScram()
            elseif k == keys.t then
                executeSpinTest()
            elseif k == keys.c then
                local nextM = (lastAp.mode == "ANCHOR") and "MANUAL" or "ANCHOR"
                sendCmd("SET_MODE", { mode = nextM })
                toastMsg = (nextM == "ANCHOR") and "CAPA KILITLENDI" or "CAPA COZULDU"
                toastTimer = 60
            end
        elseif ev == "monitor_touch" or ev == "mouse_click" then
            local tx, ty = p2, p3
            if ty >= btnScram.y1 and ty <= btnScram.y2 and tx >= btnScram.x1 and tx <= btnScram.x2 then
                executeScram()
            elseif ty >= btnSpin.y1 and ty <= btnSpin.y2 and tx >= btnSpin.x1 and tx <= btnSpin.x2 then
                executeSpinTest()
            elseif ty >= btnAnc.y1 and ty <= btnAnc.y2 and tx >= btnAnc.x1 and tx <= btnAnc.x2 then
                local nextM = (lastAp.mode == "ANCHOR") and "MANUAL" or "ANCHOR"
                sendCmd("SET_MODE", { mode = nextM })
                toastMsg = (nextM == "ANCHOR") and "CAPA KILITLENDI" or "CAPA COZULDU"
                toastTimer = 60
            end
        end
    end
end

if parallel and parallel.waitForAny then
    parallel.waitForAny(telemetryListener, interactionLoop)
else
    interactionLoop()
end

termObj.setBackgroundColor(colors.black)
termObj.clear()
termObj.setCursorPos(1, 1)
print("Drunken OS Engineering Deck sonlandirildi.")
