--[[
    Drunken OS - Engineering Deck & Powertrain Monitor v1.0
    by MuhendizBey

    Purpose:
    Dedicated diagnostic dashboard and touch control console for the
    Mothership Lower Deck (Makine Dairesi). Displays live RPM, stress,
    clutch states, wing altimeter balance (tilt matrix), and provides
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
local localClutches         = findLocal({ "create_connected_inverted_clutch", "inverted_clutch", "clutch" })
local localGearshifts       = findLocal({ "create_gearshift", "gearshift" })
local localAltSensors       = findLocal({ "altitude_sensor" })

local lastTel = {
    vehicleType = "MOTHERSHIP",
    speed = 0,
    altitude = 0,
    heading = 0,
    pitch = 0,
    roll = 0,
    mothership = { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 }
}

local toastMsg = "MAKINE DAIRESI HAZIR"
local toastTimer = 60
local running = true

-- Touch button boundaries
local btnScram = { x1 = 2, y1 = 17, x2 = 18, y2 = 18 }
local btnSpin  = { x1 = 20, y1 = 17, x2 = 36, y2 = 18 }
local btnAnc   = { x1 = 38, y1 = 17, x2 = 50, y2 = 18 }

local function sendCmd(cmd, payload)
    if not hasModem or not rednet then return false end
    rednet.broadcast({
        type    = "AVIONICS_PILOT_CMD",
        cmd     = cmd,
        payload = payload or {},
        time    = os.epoch and os.epoch("utc") or os.time()
    }, BUS_PROTOCOL)
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
    sendCmd("SPIN_TEST")
    -- Local spin test
    for _, sc in ipairs(localSpeedControllers) do
        if sc.setTargetSpeed then pcall(sc.setTargetSpeed, 64) end
    end
    sleep(1.2)
    for _, sc in ipairs(localSpeedControllers) do
        if sc.setTargetSpeed then pcall(sc.setTargetSpeed, 0) end
    end
    toastMsg = "MOTOR TESTI TAMAMLANDI"
    toastTimer = 60
end

local function drawBox(x, y, w, h, title, col)
    termObj.setTextColor(col or colors.cyan)
    termObj.setCursorPos(x, y)
    termObj.write("+" .. string.rep("-", w - 2) .. "+")
    for row = 1, h - 2 do
        termObj.setCursorPos(x, y + row)
        termObj.write("|" .. string.rep(" ", w - 2) .. "|")
    end
    termObj.setCursorPos(x, y + h - 1)
    termObj.write("+" .. string.rep("-", w - 2) .. "+")
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

    -- 4 Quadrants: FL, FR, RL, RR
    -- Row 3 to 9
    termObj.setBackgroundColor(colors.black)
    drawBox(2, 3, 24, 4, "ON-SOL (FL)", colors.cyan)
    termObj.setCursorPos(4, 4); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC : %2d/15", ms.fl))
    termObj.setCursorPos(4, 5); termObj.setTextColor(colors.lime)
    local rpmFL = math.floor((ms.fl / 15) * 256 + 0.5)
    termObj.write(string.format("DEVIR: %3d RPM", rpmFL))

    drawBox(28, 3, 24, 4, "ON-SAG (FR)", colors.cyan)
    termObj.setCursorPos(30, 4); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC : %2d/15", ms.fr))
    termObj.setCursorPos(30, 5); termObj.setTextColor(colors.lime)
    local rpmFR = math.floor((ms.fr / 15) * 256 + 0.5)
    termObj.write(string.format("DEVIR: %3d RPM", rpmFR))

    drawBox(2, 8, 24, 4, "ARKA-SOL (RL)", colors.cyan)
    termObj.setCursorPos(4, 9); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC : %2d/15", ms.rl))
    termObj.setCursorPos(4, 10); termObj.setTextColor(colors.lime)
    local rpmRL = math.floor((ms.rl / 15) * 256 + 0.5)
    termObj.write(string.format("DEVIR: %3d RPM", rpmRL))

    drawBox(28, 8, 24, 4, "ARKA-SAG (RR)", colors.cyan)
    termObj.setCursorPos(30, 9); termObj.setTextColor(colors.white)
    termObj.write(string.format("GUC : %2d/15", ms.rr))
    termObj.setCursorPos(30, 10); termObj.setTextColor(colors.lime)
    local rpmRR = math.floor((ms.rr / 15) * 256 + 0.5)
    termObj.write(string.format("DEVIR: %3d RPM", rpmRR))

    -- Powertrain Balance & Altimeter Matrix (Row 13 to 15)
    drawBox(2, 13, 50, 3, "KANAT VE TERAZI MATRISI", colors.orange)
    termObj.setCursorPos(4, 14); termObj.setTextColor(colors.white)
    termObj.write(string.format("YATIS (dR): %+5.1fm | BURUN (dP): %+5.1fm", wA.dR or 0, wA.dP or 0))

    if lastTel.anchor and lastTel.anchor.active then
        termObj.setTextColor(colors.yellow)
        termObj.write(" [CAPA: LOK]")
    else
        termObj.setTextColor(colors.lightGray)
        termObj.write(" [DENGE: AKTIF]")
    end

    -- Interactive Buttons Bar (Row 17)
    termObj.setCursorPos(btnScram.x1, btnScram.y1)
    termObj.setBackgroundColor(colors.red); termObj.setTextColor(colors.white)
    termObj.write(" [S] ACIL SCRAM ")

    termObj.setCursorPos(btnSpin.x1, btnSpin.y1)
    termObj.setBackgroundColor(colors.blue); termObj.setTextColor(colors.white)
    termObj.write(" [T] TEST DONDUR ")

    termObj.setCursorPos(btnAnc.x1, btnAnc.y1)
    termObj.setBackgroundColor(colors.yellow); termObj.setTextColor(colors.black)
    termObj.write(" [C] CAPA ")

    -- Toast / Status Banner
    termObj.setBackgroundColor(colors.black)
    termObj.setCursorPos(2, 19)
    if toastTimer > 0 then
        termObj.setTextColor(colors.yellow)
        termObj.write(">> " .. tostring(toastMsg) .. " <<")
        toastTimer = toastTimer - 1
    else
        termObj.setTextColor(colors.gray)
        termObj.write("HAT: " .. (hasModem and "FCC BUS BAGLI" or "YEREL SENSORLER") .. " | [Q] Cikis")
    end
end

-- Background telemetry listener thread
local function telemetryListener()
    while running do
        if hasModem and rednet then
            local sender, msg, proto = rednet.receive(BUS_PROTOCOL, 0.1)
            if msg and type(msg) == "table" and msg.type == "AVIONICS_TELEMETRY" and msg.telemetry then
                lastTel = msg.telemetry
            end
        else
            sleep(0.1)
        end
    end
end

-- Input & Interaction loop
local function interactionLoop()
    while running do
        renderDashboard()
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            local k = p1
            if k == keys.q then
                running = false
            elseif k == keys.s then
                executeScram()
            elseif k == keys.t then
                executeSpinTest()
            elseif k == keys.c then
                sendCmd("SET_MODE", { mode = "ANCHOR" })
                toastMsg = "CAPA MODU TETIKLENDI"
                toastTimer = 60
            end
        elseif ev == "monitor_touch" or ev == "mouse_click" then
            local tx, ty = p2, p3
            if ty >= btnScram.y1 and ty <= btnScram.y2 and tx >= btnScram.x1 and tx <= btnScram.x2 then
                executeScram()
            elseif ty >= btnSpin.y1 and ty <= btnSpin.y2 and tx >= btnSpin.x1 and tx <= btnSpin.x2 then
                executeSpinTest()
            elseif ty >= btnAnc.y1 and ty <= btnAnc.y2 and tx >= btnAnc.x1 and tx <= btnAnc.x2 then
                sendCmd("SET_MODE", { mode = "ANCHOR" })
                toastMsg = "CAPA MODU TETIKLENDI"
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
