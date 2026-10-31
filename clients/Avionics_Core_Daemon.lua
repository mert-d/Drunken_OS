-- clients/Avionics_Core_Daemon.lua
-- Drunken OS - Dedicated Flight Control Core (FCC) & Sensor Fusion Daemon
-- Runs headless 20Hz PID loop for The Skyfire Gunship / Zeppelins and serves bridge displays

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

local BUS_PROTOCOL   = "DRUNKEN_AVIONICS_BUS"
local ILS_PROTOCOL   = "DRUNKEN_ILS"
local RADAR_PROTOCOL = "DRUNKEN_RADAR"
local ATC_PROTOCOL   = "DRUNKEN_ATC"

local function run(context)
    context = context or {}
    local parentTerm = context.parent or term.current()
    local isColor = parentTerm.isColor and parentTerm.isColor()
    if isColor == nil and term.isColor then isColor = term.isColor() end

    local fc = Avionics.new({
        callsign    = context.callsign or "SKYFIRE-01",
        profile     = context.profile or "MOTHERSHIP",
        useGPS      = true,
        startParked = true
    })

    -- Open all available modems (Wired Networking Cable + Wireless Ender Modem)
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "modem" and rednet then
                if not rednet.isOpen(name) then
                    pcall(rednet.open, name)
                end
            end
        end
    end

    local running = true
    local lastTel = fc:readTelemetry(0.05)
    local tick = 0
    local lastCmdSender = nil
    local lastCmdName = "NONE"
    local viewMode = "STATUS" -- "STATUS" or "IO"
    local selectedIOIdx = 1
    local ioScrollOffset = 0

    local quickRoles = {
        [keys.one]   = "LIFT_FL",
        [keys.two]   = "LIFT_FR",
        [keys.three] = "LIFT_RL",
        [keys.four]  = "LIFT_RR",
        [keys.five]  = "REAR_LEFT",
        [keys.six]   = "REAR_CENTER",
        [keys.seven] = "REAR_RIGHT"
    }

    local function drawIOConfig()
        local w, h = parentTerm.getSize()
        parentTerm.setBackgroundColor(colors.black)
        parentTerm.clear()

        parentTerm.setCursorPos(1, 1)
        parentTerm.setBackgroundColor(isColor and colors.blue or colors.white)
        parentTerm.setTextColor(isColor and colors.white or colors.black)
        local header = string.format(" FCC DOGRUDAN DONANIM & ROL ATAMA [%s] ", fc.vehicleType or "MOTHERSHIP")
        parentTerm.write(header .. string.rep(" ", math.max(0, w - #header)))

        parentTerm.setBackgroundColor(isColor and colors.gray or colors.black)
        parentTerm.setTextColor(isColor and colors.yellow or colors.white)
        parentTerm.setCursorPos(1, 2)
        local colHdr = string.format(" %-18s %-12s %-12s %-4s", "CIHAZ / KANAL", "TIP", "GOREV (ROLE)", "INV")
        parentTerm.write(colHdr .. string.rep(" ", math.max(0, w - #colHdr)))

        local devs = fc.ioDevices or {}
        local maxRows = math.max(3, h - 5)
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
                local isTesting = (fc.spinTest and (fc.spinTest.name == item.name or fc.spinTest.name == "ALL"))
                parentTerm.setBackgroundColor(
                    isTesting and (isColor and colors.orange or colors.white)
                    or (isSel and (isColor and colors.cyan or colors.white) or colors.black)
                )
                parentTerm.setTextColor((isSel or isTesting) and colors.black or colors.white)

                local shortName = item.name
                if #shortName > 17 then shortName = shortName:sub(1, 15) .. ".." end
                local shortKind = (item.kind or ""):gsub("create_connected_", ""):gsub("create:", ""):gsub("create_", ""):gsub("rotation_", "")
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
                parentTerm.setBackgroundColor(colors.black)
                parentTerm.write(string.rep(" ", w))
            end
        end

        parentTerm.setBackgroundColor(colors.black)
        parentTerm.setCursorPos(2, h - 1)
        parentTerm.setTextColor(isColor and colors.lime or colors.white)
        parentTerm.write("[Sol/Sag]:Rol [1-7]:Mothership [T]:SpinTest [A]:OtoDiz")
        parentTerm.setCursorPos(2, h)
        parentTerm.setTextColor(isColor and colors.lightGray or colors.white)
        parentTerm.write("[I]:Ters [X]:AUTO [R]:Yenile [V]:Profil [P/Tab]:Durum")
    end

    local function drawCoreStatus()
        if viewMode == "IO" then
            drawIOConfig()
            return
        end
        local w, h = parentTerm.getSize()
        parentTerm.setBackgroundColor(colors.black)
        parentTerm.clear()

        -- Top Header Banner
        parentTerm.setCursorPos(1, 1)
        parentTerm.setBackgroundColor(isColor and colors.blue or colors.white)
        parentTerm.setTextColor(isColor and colors.white or colors.black)
        local header = " DRUNKEN OS - FLIGHT CONTROL CORE (FCC DAEMON) "
        parentTerm.write(header .. string.rep(" ", math.max(0, w - #header)))

        parentTerm.setBackgroundColor(colors.black)

        -- Telemetry & Mode
        parentTerm.setTextColor(isColor and colors.cyan or colors.white)
        parentTerm.setCursorPos(2, 3)
        parentTerm.write(string.format("VEHICLE : %s [%s]", lastTel.callsign or fc.callsign, lastTel.vehicleType or fc.vehicleType))

        parentTerm.setCursorPos(2, 4)
        parentTerm.setTextColor(fc.ap.enabled and (isColor and colors.lime or colors.white) or (isColor and colors.orange or colors.white))
        parentTerm.write(string.format("AP MODE : %s (ALT:%.1fm TGT:%.1fm)", fc.ap.mode, lastTel.altitude, fc.ap.targetAlt))

        -- Sensors Health
        parentTerm.setTextColor(colors.white)
        parentTerm.setCursorPos(2, 6)
        parentTerm.write(string.format("SENSORS : ALT=%s GIMBAL=%s NAV=%s VEL=%s",
            fc.altSensor and "OK" or "--",
            fc.gimbal and "OK" or "--",
            fc.nav and "OK" or "--",
            fc.velSensor and "OK" or "--"
        ))

        -- Actuator Overview
        parentTerm.setCursorPos(2, 7)
        parentTerm.write(string.format("ROTORS  : %d Gearboxes | %d Gyros | %d Engines | %d SC",
            #(fc.gearboxes or {}), #(fc.gyros or {}), #(fc.engines or {}), #(fc.speedControllers or {})
        ))

        -- Attitude
        parentTerm.setCursorPos(2, 8)
        parentTerm.write(string.format("ATTITUDE: Pitch %+5.1f deg | Roll %+5.1f deg | Yaw %+5.1f deg",
            math.deg(lastTel.pitch), math.deg(lastTel.roll), math.deg(lastTel.heading) % 360
        ))

        -- Last Bus Command
        parentTerm.setCursorPos(2, 9)
        parentTerm.setTextColor(isColor and colors.yellow or colors.white)
        parentTerm.write(string.format("LAST CMD: %s (from ID:%s)",
            tostring(lastCmdName), tostring(lastCmdSender or "-")
        ))

        -- Keybind hints
        parentTerm.setCursorPos(2, math.min(h - 1, 11))
        parentTerm.setTextColor(isColor and colors.lime or colors.white)
        parentTerm.write("[P / Tab]: FCC Donanim & Motor Rol Atama Ekrani")
        parentTerm.setCursorPos(2, math.min(h, 12))
        parentTerm.setTextColor(isColor and colors.lightGray or colors.white)
        parentTerm.write("[H]:Hover [M]:Manual [C]:Cruise [Z]:Anchor [B]:Brake [U]:OTA [Q]:Stop")
    end

    local function broadcastState()
        if not (rednet and rednet.isOpen and rednet.isOpen()) then return end
        local ioDevs = {}
        for _, d in ipairs(fc.ioDevices or {}) do
            ioDevs[#ioDevs + 1] = {
                name       = d.name,
                kind       = d.kind,
                cap        = d.cap,
                isRedstone = d.isRedstone
            }
        end
        pcall(rednet.broadcast, {
            type      = "AVIONICS_STATE",
            sender    = (os.getComputerID and os.getComputerID()) or 0,
            tel       = lastTel,
            ioMap     = fc.ioMap,
            ioDevices = ioDevs,
            ap        = {
                enabled      = fc.ap.enabled,
                mode         = fc.ap.mode,
                altHold      = fc.ap.altHold,
                hdgHold      = fc.ap.hdgHold,
                targetAlt    = fc.ap.targetAlt,
                targetHdg    = fc.ap.targetHdg,
                baseThrottle = fc.ap.baseThrottle,
                parkingBrake = fc.ap.parkingBrake,
                reverseGear  = fc.ap.reverseGear,
                manualYaw    = fc.ap.manualYaw,
                rtbPhase     = fc.ap.rtbPhase,
                ilsDev       = fc.ap.ilsDev,
                waypoint     = fc.ap.waypoint,
                vehicleType  = fc.vehicleType,
                homeBase     = fc.ap.homeBase and {
                    baseName = fc.ap.homeBase.baseName,
                    runwayId = fc.ap.homeBase.runwayId
                } or nil
            }
        }, BUS_PROTOCOL)
    end

    -- 1. Real-Time 20Hz Sensor Fusion & Actuator PID Loop
    local function controlLoop()
        while running do
            lastTel = fc:step(0.05)
            tick = tick + 1

            -- Broadcast High-Rate Internal Avionics Bus State (10 Hz) to Bridge/Cabin Computers
            if tick % 2 == 0 then
                broadcastState()
            end

            -- Broadcast External ADS-B Telemetry (1 Hz) to Ground Radar Stations
            if tick % 20 == 0 and rednet and rednet.isOpen and rednet.isOpen() then
                pcall(rednet.broadcast, {
                    type         = "AVIONICS_ADSB",
                    callsign     = lastTel.callsign or fc.callsign,
                    vehicleType  = lastTel.vehicleType or fc.vehicleType,
                    pos          = lastTel.pos,
                    altitude     = lastTel.altitude,
                    targetAlt    = fc.ap.targetAlt,
                    speed        = lastTel.speed,
                    heading      = math.deg(lastTel.heading) % 360,
                    vSpeed       = lastTel.vSpeed,
                    mode         = fc.ap.mode,
                    parkingBrake = fc.ap.parkingBrake,
                    timestamp    = (os.epoch and os.epoch("utc")) or os.time()
                }, RADAR_PROTOCOL)
            end

            if tick % 5 == 0 then
                drawCoreStatus()
            end

            sleep(0.05)
        end
    end

    -- 2. Command Receiver (From Cockpit Computer, Cabin Computer, or ILS Tower)
    local function commandLoop()
        while running do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "rednet_message" then
                local senderId, msg, protocol = p1, p2, p3
                if protocol == ILS_PROTOCOL and type(msg) == "table" and msg.type == "AVIONICS_ILS_BEACON" then
                    fc:setHomeBase(msg)
                elseif protocol == ATC_PROTOCOL and type(msg) == "table" and msg.type == "AVIONICS_ATC_CMD" then
                    lastCmdSender = senderId
                    lastCmdName = "ATC:" .. tostring(msg.cmd or "")
                    fc:executeAtcCommand(msg, lastTel)
                elseif protocol == BUS_PROTOCOL and type(msg) == "table" then
                    if msg.type == "AVIONICS_DISCOVER" then
                        broadcastState()
                    elseif msg.type == "AVIONICS_CMD" then
                        lastCmdSender = senderId
                        lastCmdName = tostring(msg.cmd or "")

                        if msg.cmd == "SET_MODE" then
                            fc:setMode(msg.mode or "MANUAL", lastTel)
                            if tonumber(msg.targetAlt) then
                                fc.ap.targetAlt = tonumber(msg.targetAlt)
                            end
                        elseif msg.cmd == "TOGGLE_AP" then
                            if fc.ap.enabled then
                                fc:setMode("MANUAL", lastTel)
                            else
                                local isHoverable = (fc.vehicleType == "ZEPPELIN" or fc.vehicleType == "MOTHERSHIP" or fc.vehicleType == "GUNSHIP")
                                fc:setMode(isHoverable and "HOVER" or "CRUISE", lastTel)
                            end
                        elseif msg.cmd == "ENGAGE_RTB" then
                            fc:engageRTB(lastTel)
                        elseif msg.cmd == "ALT_DELTA" then
                            fc.ap.targetAlt = math.max(0, fc.ap.targetAlt + (tonumber(msg.delta) or 0))
                        elseif msg.cmd == "SET_ALT" then
                            fc.ap.targetAlt = math.max(0, tonumber(msg.alt) or fc.ap.targetAlt)
                        elseif msg.cmd == "HDG_DELTA" then
                            fc.ap.targetHdg = (fc.ap.targetHdg + math.rad(tonumber(msg.deltaDeg) or 0)) % (2 * math.pi)
                        elseif msg.cmd == "SET_HDG" then
                            fc.ap.targetHdg = tonumber(msg.hdg) or fc.ap.targetHdg
                        elseif msg.cmd == "THR_DELTA" then
                            fc.ap.baseThrottle = math.max(0, math.min(15, fc.ap.baseThrottle + (tonumber(msg.delta) or 0)))
                        elseif msg.cmd == "SET_THROTTLE" then
                            fc.ap.baseThrottle = math.max(0, math.min(15, tonumber(msg.throttle) or 0))
                        elseif msg.cmd == "TOGGLE_BRAKE" then
                            fc.ap.parkingBrake = not fc.ap.parkingBrake
                        elseif msg.cmd == "SET_BRAKE" then
                            fc.ap.parkingBrake = (msg.brake == true)
                        elseif msg.cmd == "TOGGLE_GEAR" then
                            fc.ap.reverseGear = not fc.ap.reverseGear
                        elseif msg.cmd == "SET_GEAR" then
                            fc.ap.reverseGear = (msg.reverse == true)
                        elseif msg.cmd == "TOGGLE_CLUTCH" then
                            fc:toggleClutchPolarity()
                        elseif msg.cmd == "MANUAL_YAW_DELTA" then
                            fc.ap.manualYaw = math.max(-6, math.min(6, (fc.ap.manualYaw or 0) + (tonumber(msg.delta) or 0)))
                        elseif msg.cmd == "SET_WAYPOINT" and type(msg.waypoint) == "table" then
                            fc.ap.waypoint = msg.waypoint
                            fc:setMode("LNAV", lastTel)
                        elseif msg.cmd == "SET_PROFILE" and msg.profile then
                            fc:setVehicleProfile(msg.profile, msg.autoAssign == true)
                        elseif msg.cmd == "SCAN_PERIPHERALS" then
                            fc:scanPeripherals()
                        elseif msg.cmd == "SET_IO_ROLE" and msg.name and msg.role then
                            fc:setDeviceRole(msg.name, msg.role)
                        elseif msg.cmd == "TOGGLE_IO_INVERT" and msg.name then
                            fc:toggleInvert(msg.name)
                        elseif msg.cmd == "RESET_IO_ROLE" and msg.name then
                            fc:resetDeviceRole(msg.name)
                        elseif msg.cmd == "SPIN_TEST" then
                            fc:triggerSpinTest(msg.name)
                        elseif msg.cmd == "SAFE_DISARM" or msg.cmd == "DISARM" then
                            fc.ap.baseThrottle = 0
                            fc.ap.parkingBrake = true
                            fc:setMode("MANUAL", lastTel)
                            fc:step(0.05)
                        end
                        broadcastState()
                    end
                end
            elseif ev == "peripheral" or ev == "peripheral_detach" then
                if ev == "peripheral" and peripheral.getType(p1) == "modem" and rednet and not rednet.isOpen(p1) then
                    pcall(rednet.open, p1)
                end
                fc:scanPeripherals()
                broadcastState()
                drawCoreStatus()
            elseif ev == "key" then
                if p1 == keys.q then
                    fc.ap.baseThrottle = 0
                    fc.ap.parkingBrake = true
                    fc:setMode("MANUAL", lastTel)
                    fc:step(0.05)
                    running = false
                elseif p1 == keys.p or p1 == keys.tab then
                    viewMode = (viewMode == "IO") and "STATUS" or "IO"
                    drawCoreStatus()
                elseif viewMode == "IO" then
                    local devs = fc.ioDevices or {}
                    local selItem = devs[selectedIOIdx]
                    if p1 == keys.up then
                        selectedIOIdx = math.max(1, selectedIOIdx - 1)
                    elseif p1 == keys.down then
                        selectedIOIdx = math.min(math.max(1, #devs), selectedIOIdx + 1)
                    elseif p1 == keys.left and selItem then
                        fc:cycleRole(selItem.name, -1)
                        broadcastState()
                    elseif p1 == keys.right and selItem then
                        fc:cycleRole(selItem.name, 1)
                        broadcastState()
                    elseif quickRoles[p1] and selItem then
                        fc:setDeviceRole(selItem.name, quickRoles[p1])
                        broadcastState()
                    elseif p1 == keys.t and selItem then
                        fc:triggerSpinTest(selItem.name)
                    elseif p1 == keys.i and selItem then
                        fc:toggleInvert(selItem.name)
                        broadcastState()
                    elseif p1 == keys.x and selItem then
                        fc:resetDeviceRole(selItem.name)
                        broadcastState()
                    elseif p1 == keys.a then
                        fc:autoAssignMothershipRoles(true)
                        broadcastState()
                    elseif p1 == keys.r then
                        fc:scanPeripherals()
                        broadcastState()
                    elseif p1 == keys.v then
                        local nextProf = (fc.vehicleType == "MOTHERSHIP") and "ZEPPELIN"
                            or ((fc.vehicleType == "ZEPPELIN") and "AIRCRAFT" or "MOTHERSHIP")
                        fc:setVehicleProfile(nextProf, nextProf == "MOTHERSHIP")
                        broadcastState()
                    end
                    drawCoreStatus()
                elseif p1 == keys.h then
                    fc:setMode("HOVER", lastTel)
                    broadcastState()
                elseif p1 == keys.m then
                    fc:setMode("MANUAL", lastTel)
                    broadcastState()
                elseif p1 == keys.c then
                    fc:setMode("CRUISE", lastTel)
                    broadcastState()
                elseif p1 == keys.z then
                    local newM = (fc.ap.mode == "ANCHOR") and "MANUAL" or "ANCHOR"
                    fc:setMode(newM, lastTel)
                    broadcastState()
                elseif p1 == keys.b then
                    fc.ap.parkingBrake = not fc.ap.parkingBrake
                    broadcastState()
                elseif p1 == keys.u then
                    local okNet, netpkg = pcall(require, "lib.netpkg")
                    if not okNet then okNet, netpkg = pcall(require, "netpkg") end
                    if okNet and netpkg and netpkg.update then
                        lastCmdName = "OTA_UPDATE"
                        drawCoreStatus()
                        local okUpd, countOrErr = netpkg.update("avionics_core")
                        lastCmdName = okUpd and ("OTA_OK (" .. tostring(countOrErr) .. "f)") or ("OTA_ERR:" .. tostring(countOrErr):sub(1, 10))
                        drawCoreStatus()
                    end
                end
            end
        end
    end

    parallel.waitForAny(controlLoop, commandLoop)
end

-- Allow direct execution when invoked from shell or startup
if shell and shell.getRunningProgram and shell.getRunningProgram():match("Avionics_Core_Daemon") then
    run()
end

return { run = run }
