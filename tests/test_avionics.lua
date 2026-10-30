-- tests/test_avionics.lua
-- Unit tests for Drunken OS Create: Avionics Flight Computer

local function runTests()
    print("=== Running Drunken OS Avionics Tests ===")

    -- Backup globals
    local origPeripheral = _G.peripheral
    local origParallel   = _G.parallel
    local origColors     = _G.colors

    _G.colors = _G.colors or {
        white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32,
        pink = 64, gray = 128, lightGray = 256, cyan = 512, purple = 1024,
        blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768
    }

    -- Mock actuator state
    local mockState = {
        portSignal  = 0,
        stbdSignal  = 0,
        burnerSig   = 0,
        gyroTarget  = nil,
        brakeVal    = 0,
        altitude    = 100.0,
        heading     = 0.0,
        pitch       = 0.0,
        roll        = 0.0,
        agl         = 25.0,
        hasBurner   = true
    }

    -- Mock CC:Tweaked parallel API
    _G.parallel = {
        waitForAll = function(...)
            local fns = { ... }
            for _, fn in ipairs(fns) do
                if type(fn) == "function" then fn() end
            end
        end,
        waitForAny = function(...)
            local fns = { ... }
            if fns[1] then fns[1]() end
        end
    }

    -- Mock CC:Tweaked peripheral.find for Create: Avionics blocks
    _G.peripheral = {
        find = function(pType)
            if pType == "altitude_sensor" then
                return {
                    getHeight = function() return mockState.altitude end,
                    getAltitude = function() return mockState.altitude end,
                    getVerticalSpeed = function() return -1.5 end,
                    getAirPressure = function() return 0.92 end
                }
            elseif pType == "gimbal_sensor" then
                return {
                    getAnglesRad = function() return { mockState.pitch, mockState.roll } end,
                    getAngles = function() return { math.deg(mockState.pitch), math.deg(mockState.roll) } end,
                    getPitch = function() return mockState.pitch end,
                    getRoll = function() return mockState.roll end,
                    getLinearAcceleration = function() return { 0, 0, 0.2, x = 0, y = 0, z = 0.2 } end
                }
            elseif pType == "navigation_table" then
                return {
                    getHeadingRad = function() return mockState.heading end,
                    hasTarget = function() return false end
                }
            elseif pType == "laser_sensor" then
                return {
                    getClosestHitDistance = function() return mockState.agl end,
                    getDistance = function() return mockState.agl end
                }
            elseif pType == "gas_provider" then
                if mockState.hasBurner then
                    return { getGasType = function() return "HOT_AIR" end }
                end
                return nil
            elseif pType == "analog_transmission" then
                return
                    { setSignal = function(s) mockState.portSignal = s end },
                    { setSignal = function(s) mockState.stbdSignal = s end }
            elseif pType == "throttle_lever" then
                return { setSignal = function(s) mockState.burnerSig = s end }
            elseif pType == "gyroscopic_propeller_bearing" then
                return {
                    setManualTarget = function(vec) mockState.gyroTarget = vec end,
                    clearManualTarget = function() mockState.gyroTarget = nil end
                }
            elseif pType == "wheel_mount" then
                return {
                    getTouchingFriction = function() return mockState.agl <= 0.5 and 1.0 or 0.0 end,
                    setBrake = function(b) mockState.brakeVal = b end,
                    setSteering = function(_) end
                }
            elseif pType == "portable_engine" then
                return {
                    getRpm = function() return 256 end,
                    isOverstressed = function() return false end
                }
            end
            return nil
        end
    }

    local Avionics = require("lib.avionics")

    -- Test 1: Zeppelin Auto-Detection & Altitude Climb
    mockState.hasBurner = true
    mockState.altitude = 100.0
    local zepFC = Avionics.new({ callsign = "ZEP-01" })
    assert(zepFC.vehicleType == "ZEPPELIN", "Expected ZEPPELIN vehicle type when gas_provider is present")

    zepFC:setMode("CRUISE", zepFC:readTelemetry(0.05))
    zepFC.ap.targetAlt = 130.0 -- Climb 30m
    zepFC.ap.targetHdg = math.rad(45) -- Turn right
    zepFC:step(0.05)

    assert(mockState.burnerSig > 8, "Expected burner throttle > 8 when climbing")
    assert(mockState.stbdSignal ~= mockState.portSignal, "Expected differential thrust during heading turn")
    print("  PASS: Test 1: Zeppelin detection, Altitude PID & Differential Yaw")

    -- Test 2: Fixed-Wing Aircraft Gyroscopic Thrust Vectoring (12-deg Cone Limit)
    mockState.hasBurner = false
    local airFC = Avionics.new({ callsign = "AIR-01" })
    assert(airFC.vehicleType == "AIRCRAFT", "Expected AIRCRAFT vehicle type when no gas_provider is present")

    airFC:setMode("CRUISE", airFC:readTelemetry(0.05))
    airFC.ap.targetAlt = 200.0
    airFC:step(0.05)

    assert(mockState.gyroTarget ~= nil, "Expected gyroscopic propeller vector target to be set")
    local coneMag = math.sqrt(mockState.gyroTarget.x^2 + mockState.gyroTarget.y^2)
    assert(coneMag <= math.sin(math.rad(12.1)) * 1.42, "Gyro vector exceeded safe cone limits")
    print("  PASS: Test 2: Aircraft Gyroscopic Propeller Bearing 3D vectoring")

    -- Test 3: Autoland Touchdown & Automatic Wheel Braking
    mockState.agl = 0.2
    airFC:setMode("AUTOLAND", airFC:readTelemetry(0.05))
    airFC:step(0.05)

    assert(airFC.ap.parkingBrake == true, "Expected parking brake to engage on touchdown")
    assert(airFC.ap.mode == "MANUAL", "Expected AP to disarm to MANUAL after landing rollout")
    print("  PASS: Test 3: Autoland flare, Weight-on-Wheels detection & Auto-Brake")

    -- Test 4: RTB & ILS Localizer Convergence (Phase 2)
    local mockILSBeacon = {
        type          = "AVIONICS_ILS_BEACON",
        baseName      = "DRUNKEN-BASE-ALPHA",
        runwayId      = "RWY-36",
        threshold     = { x = 0, y = 68, z = 0 },
        rwyHeadingRad = 0.0,
        glideSlopeRad = math.rad(8.0),
        approachDist  = 80,
        zeppelinMast  = { x = 25, y = 85, z = 0 },
        timestamp     = 1000
    }

    mockState.hasBurner = false
    mockState.altitude = 120.0
    mockState.agl = 50.0
    local rtbFC = Avionics.new({ callsign = "AIR-RTB" })
    rtbFC:setHomeBase(mockILSBeacon)

    -- Step 4a: Engage RTB away from FAF -> phase should be RTB_IAF
    rtbFC.pos.x = 20
    rtbFC.pos.z = -140
    local engaged = rtbFC:engageRTB(rtbFC:readTelemetry(0.05))
    assert(engaged == true, "Expected engageRTB to succeed")
    assert(rtbFC.ap.mode == "RTB", "Expected mode to be RTB")
    assert(rtbFC.ap.rtbPhase == "RTB_IAF", "Expected initial phase to be RTB_IAF")

    -- Step 4b: Transition near FAF (FAF is at x=0, z=-80)
    rtbFC.pos.x = 2
    rtbFC.pos.z = -82
    rtbFC:step(0.05)
    assert(rtbFC.ap.rtbPhase == "RTB_ILS", "Expected transition to RTB_ILS near FAF")

    -- Step 4c: Localizer cross-track error correction
    rtbFC.pos.x = 10 -- 10 blocks right of centerline
    rtbFC.pos.z = -50
    mockState.altitude = 75.0
    rtbFC:step(0.05)
    assert(rtbFC.ap.ilsDev.loc == 10, "Expected cross-track error of 10m")
    assert(rtbFC.ap.targetHdg < 0, "Expected target heading to steer left towards runway centerline")

    -- Step 4d: Convergence onto centerline (cross-track error -> 0)
    rtbFC.pos.x = 0
    rtbFC.pos.z = -25
    rtbFC:step(0.05)
    assert(math.abs(rtbFC.ap.ilsDev.loc) < 0.001, "Expected zero cross-track error on centerline")
    assert(math.abs(rtbFC.ap.targetHdg) < 0.001, "Expected runway alignment heading on centerline")

    -- Step 4e: Zeppelin RTB to Mooring Mast
    mockState.hasBurner = true
    local zepRTB = Avionics.new({ callsign = "ZEP-RTB" })
    zepRTB:setHomeBase(mockILSBeacon)
    zepRTB.pos.x = 50
    zepRTB.pos.z = 50
    zepRTB:engageRTB(zepRTB:readTelemetry(0.05))
    assert(zepRTB.ap.rtbPhase == "RTB_MAST", "Expected Zeppelin to engage RTB_MAST")

    -- Arrive at mast
    zepRTB.pos.x = 25
    zepRTB.pos.z = 0
    mockState.altitude = 85.0
    zepRTB:step(0.05)
    assert(zepRTB.ap.mode == "HOVER", "Expected Zeppelin to switch to HOVER at mooring mast")
    print("  PASS: Test 4: RTB & ILS Localizer Convergence (FAF -> ILS -> Flare/Mast)")

    -- Test 5: Manual Mode Throttle Transmission (Phase 3)
    airFC:setMode("MANUAL", airFC:readTelemetry(0.05))
    assert(airFC.ap.enabled == false, "Expected AP to be disabled in MANUAL")
    airFC.ap.baseThrottle = 11
    airFC:step(0.05)
    assert(mockState.portSignal == 11, "Expected manual throttle to reach port transmission")
    assert(mockState.stbdSignal == 11, "Expected manual throttle to reach stbd transmission")
    print("  PASS: Test 5: Manual Mode Throttle Transmission ([W]/[S] Passthrough)")

    -- Test 6: 1D Negative Velocity Sensor Speed Fix & Configurable I/O Roles / Gearshift
    local gearshiftState = 0
    _G.peripheral.find = function(pType)
        if pType == "velocity_sensor" then
            return { getVelocity = function() return -12.5 end }
        elseif pType == "gearshift" then
            return { setSignal = function(s) gearshiftState = s end }
        end
        return nil
    end
    local cfgFC = Avionics.new({ callsign = "CFG-01" })
    local cfgTel = cfgFC:readTelemetry(0.05)
    assert(cfgTel.speed == 12.5, "Expected negative 1D velocity sensor reading (-12.5) to yield positive speed (12.5)")
    cfgFC.ap.reverseGear = true
    cfgFC:step(0.05)
    assert(gearshiftState == 15, "Expected reverseGear=true to drive gearshift to 15")
    local newRole = cfgFC:cycleRole("RS:back", 1)
    assert(newRole == "LIFT_FL", "Expected cycleRole on RS:back to advance from AUTO to LIFT_FL")
    local inv = cfgFC:toggleInvert("RS:back")
    assert(inv == true, "Expected toggleInvert on RS:back to set invert=true")
    print("  PASS: Test 6: Positive Airspeed Fix, Reverse Gearshift & Configurable I/O Matrix")

    -- Test 7: Mothership Profile (4x Quad-Lift Gimbal Horizon Balance + 3x Rear Thruster Differential Yaw)
    local scRPMs = { 0, 0, 0, 0, 0, 0, 0 }
    local scMocks = {}
    for i = 1, 7 do
        scMocks[i] = {
            setTargetSpeed = function(rpm) scRPMs[i] = rpm end,
            getTargetSpeed = function() return scRPMs[i] end
        }
    end
    _G.peripheral.find = function(pType)
        if pType == "rotation_speed_controller" then
            return table.unpack(scMocks)
        elseif pType == "altitude_sensor" then
            return { getHeight = function() return 100.0 end, getVerticalSpeed = function() return 0 end }
        elseif pType == "gimbal_sensor" then
            -- Nose pitched down (-0.15 rad) and rolled left (-0.12 rad)
            return { getPitch = function() return -0.15 end, getRoll = function() return -0.12 end }
        elseif pType == "navigation_table" then
            return { getHeadingRad = function() return 0.0 end }
        end
        return nil
    end

    local msFC = Avionics.new({ callsign = "MS-SKYFIRE", profile = "MOTHERSHIP" })
    assert(msFC.vehicleType == "MOTHERSHIP", "Expected MOTHERSHIP vehicle type")
    msFC:setMode("CRUISE", msFC:readTelemetry(0.05))
    msFC.ap.baseThrottle = 10
    msFC.ap.targetAlt = 110.0 -- Climb 10m
    msFC.ap.targetHdg = math.rad(30) -- Turn right
    msFC:step(0.05)

    -- Since nose is pitched down and rolled left, Front-Left (scRPMs[1]) must spin faster than Rear-Right (scRPMs[4])
    assert(scRPMs[1] > scRPMs[4], "Expected Front-Left Lift Rotor RPM > Rear-Right Lift Rotor RPM when pitched down & rolled left")
    -- Rear thrusters (5:Left, 6:Center, 7:Right) should show differential yaw during turn
    assert(scRPMs[6] > 0, "Expected Rear-Center Thruster to produce forward RPM")
    assert(scRPMs[5] ~= scRPMs[7], "Expected Rear-Left and Rear-Right Thrusters to produce differential yaw RPM")
    print("  PASS: Test 7: Mothership 4x Quad-Lift Gimbal Stabilization & 3x Rear Thruster Differential Yaw")

    -- Test 8: Zeppelin HOVER Equilibrium, Steady-State Inverted Clutch (No Oscillation) & Shared Network Gearshift
    local hoverBurnerSig = 0
    local netPowered = {}
    local netSignal = {}
    local sharedControls = { "create_connected_inverted_clutch_0", "create_gearshift_0" }
    _G.peripheral.find = function(pType)
        if pType == "gas_provider" then
            return {
                getGasType = function() return "HOT_AIR" end,
                getBalloonVolumeChange = function() return -0.5 end
            }
        elseif pType == "altitude_sensor" then
            return {
                getHeight = function() return 147.0 end,
                getVerticalSpeed = function() return -0.35 end,
                getAirPressure = function() return 0.71 end
            }
        elseif pType == "throttle_lever" then
            return {
                setSignal = function(s) hoverBurnerSig = s end
            }
        elseif pType == "create_connected_inverted_clutch" then
            return {
                getBlockEntityId = function() return "create_connected_inverted_clutch_0" end,
                listControls = function() return sharedControls end,
                getOutputSpeed = function(id)
                    if type(id) ~= "string" then error("string expected") end
                    return 128
                end,
                setPowered = function(id, p)
                    if type(id) ~= "string" then error("string expected") end
                    netPowered[id] = p
                end,
                setSignal = function(id, s)
                    if type(id) ~= "string" then error("string expected") end
                    netSignal[id] = s
                end
            }
        elseif pType == "create_gearshift" then
            return {
                getBlockEntityId = function() return "create_gearshift_0" end,
                listControls = function() return sharedControls end,
                setPowered = function(id, p)
                    if type(id) ~= "string" then error("string expected") end
                    netPowered[id] = p
                end,
                setSignal = function(id, s)
                    if type(id) ~= "string" then error("string expected") end
                    netSignal[id] = s
                end
            }
        end
        return nil
    end

    local hvrFC = Avionics.new({ callsign = "ZEP-HVR", startParked = true })
    assert(hvrFC.ap.baseThrottle == 0 and hvrFC.ap.parkingBrake == true, "Expected startParked=true to initialize with 0 throttle and parkingBrake=true")

    -- Step 8a: While parked in MANUAL, burner and throttle must both be 0
    hvrFC:step(0.05)
    assert(hoverBurnerSig == 0, "Expected parked Zeppelin in MANUAL mode to keep burner signal at 0")

    -- Step 8b: Switch to HOVER at current altitude -> burner must stay in smooth proportional equilibrium (9..12, not 0 or 15!) and lock forward throttle to 0
    hvrFC:setMode("HOVER", hvrFC:readTelemetry(0.05))
    local hvrTel = hvrFC:step(0.05)
    assert(hoverBurnerSig >= 9 and hoverBurnerSig <= 12, "Expected HOVER mode at equilibrium to hold smooth proportional burner 9..12, got " .. tostring(hoverBurnerSig))
    assert(hvrFC.ap.baseThrottle == 0 and hvrFC.ap.parkingBrake == true, "Expected HOVER mode to lock baseThrottle=0 and parkingBrake=true")
    assert(hvrTel.burnerCmd >= 9 and hvrTel.burnerCmd <= 12, "Expected telemetry burnerCmd 9..12 in HOVER equilibrium")

    -- Step 8c: Verify inverted clutch stays strictly disengaged (false / 0) across 10 ticks without periodic oscillation
    for _ = 1, 10 do
        hvrFC:step(0.05)
        assert(netPowered["create_connected_inverted_clutch_0"] == false, "Expected inverted clutch to stay unpowered in HOVER without oscillating")
        assert(netSignal["create_connected_inverted_clutch_0"] == 0, "Expected inverted clutch signal to stay 0 in HOVER")
    end

    -- Step 8d: Engage CRUISE forward vs reverse and verify clutch and gearshift do not cross-talk on shared kinetic network
    hvrFC:setMode("CRUISE", hvrTel)
    hvrFC.ap.baseThrottle = 5
    hvrFC.ap.reverseGear = false
    hvrFC:step(0.05)
    assert(netPowered["create_connected_inverted_clutch_0"] == true and netSignal["create_connected_inverted_clutch_0"] == 15, "Expected inverted clutch to engage (true/15) in forward CRUISE")
    assert(netPowered["create_gearshift_0"] == false and netSignal["create_gearshift_0"] == 0, "Expected gearshift to stay OFF (false/0) in forward movement")

    hvrFC.ap.reverseGear = true
    hvrFC:step(0.05)
    assert(netPowered["create_connected_inverted_clutch_0"] == true and netSignal["create_connected_inverted_clutch_0"] == 15, "Expected inverted clutch to remain engaged (true/15) in reverse movement")
    assert(netPowered["create_gearshift_0"] == true and netSignal["create_gearshift_0"] == 15, "Expected gearshift to engage (true/15) in reverse movement")
    print("  PASS: Test 8: Zeppelin HOVER Equilibrium, Steady-State Inverted Clutch & Shared Network Gearshift")

    -- Test 9: Remote ATC Command Uplink (DRUNKEN_ATC)
    local okAtc, msgAtc = hvrFC:executeAtcCommand({
        type   = "AVIONICS_ATC_CMD",
        target = "ZEP-HVR",
        cmd    = "RTB",
        beacon = {
            type         = "AVIONICS_ILS_BEACON",
            baseName     = "TOWER-ALPHA",
            runwayId     = "RWY-09",
            threshold    = { x = 100, y = 70, z = 200 },
            zeppelinMast = { x = 120, y = 95, z = 210 }
        }
    }, hvrTel)
    assert(okAtc == true and hvrFC.ap.mode == "RTB" and hvrFC.ap.rtbPhase == "RTB_MAST", "Expected ATC RTB command to lock beacon and engage RTB_MAST")
    assert(msgAtc:find("TOWER%-ALPHA") ~= nil, "Expected ATC toast message to include tower baseName")

    local okWp, _ = hvrFC:executeAtcCommand({
        type     = "AVIONICS_ATC_CMD",
        target   = "ALL",
        cmd      = "WAYPOINT",
        waypoint = { x = -350, y = 120, z = 480 }
    }, hvrTel)
    assert(okWp == true and hvrFC.ap.mode == "LNAV" and hvrFC.ap.targetAlt == 120 and hvrFC.ap.baseThrottle > 0, "Expected ATC WAYPOINT command to engage LNAV with forward throttle")

    local okPark, _ = hvrFC:executeAtcCommand({
        type   = "AVIONICS_ATC_CMD",
        target = "ZEP-HVR",
        cmd    = "PARK"
    }, hvrTel)
    assert(okPark == true and hvrFC.ap.mode == "MANUAL" and hvrFC.ap.parkingBrake == true and hvrFC.ap.baseThrottle == 0, "Expected ATC PARK command to cut throttle and engage parkingBrake")
    print("  PASS: Test 9: Remote ATC Command Uplink (RTB, WAYPOINT, PARK)")

    -- Test 10: Dual-Computer Architecture (Avionics Core Daemon FCC + Multi-Monitor Cockpit Remote Command Bus & Telemetry)
    -- Step 10a: Initialize FCC Core Daemon simulation
    local fccFC = Avionics.new({ callsign = "DOS-FLAGSHIP", startParked = true })
    fccFC:setVehicleProfile("GUNSHIP", true)
    assert(fccFC.vehicleType == "GUNSHIP", "Expected FCC Core to support GUNSHIP vehicle profile")

    local fccTel = fccFC:readTelemetry(0.05)
    fccTel.altitude = 75.0
    fccTel.pos = { x = 250, y = 75, z = -400 }
    fccTel.speed = 12.5
    fccTel.vSpeed = 0.5
    fccTel.heading = math.rad(90)
    fccTel.rpm = 256
    fccTel.mothership = { fl = 10, fr = 10, rl = 10, rr = 10, rearL = 4, rearC = 8, rearR = 4 }

    -- Step 10b: Simulate command processor of Avionics_Core_Daemon handling AVIONICS_CMD packets
    local function simulateFCCCommand(fcc, msg, tel)
        if msg.cmd == "SET_MODE" then
            fcc:setMode(msg.mode or "MANUAL", tel)
            if tonumber(msg.targetAlt) then fcc.ap.targetAlt = tonumber(msg.targetAlt) end
        elseif msg.cmd == "TOGGLE_AP" then
            if fcc.ap.enabled then
                fcc:setMode("MANUAL", tel)
            else
                local isHvr = (fcc.vehicleType == "ZEPPELIN" or fcc.vehicleType == "MOTHERSHIP" or fcc.vehicleType == "GUNSHIP")
                fcc:setMode(isHvr and "HOVER" or "CRUISE", tel)
            end
        elseif msg.cmd == "ALT_DELTA" then
            fcc.ap.targetAlt = math.max(0, fcc.ap.targetAlt + (tonumber(msg.delta) or 0))
        elseif msg.cmd == "HDG_DELTA" then
            fcc.ap.targetHdg = (fcc.ap.targetHdg + math.rad(tonumber(msg.deltaDeg) or 0)) % (2 * math.pi)
        elseif msg.cmd == "THR_DELTA" then
            fcc.ap.baseThrottle = math.max(0, math.min(15, fcc.ap.baseThrottle + (tonumber(msg.delta) or 0)))
        elseif msg.cmd == "TOGGLE_BRAKE" then
            fcc.ap.parkingBrake = not fcc.ap.parkingBrake
        elseif msg.cmd == "TOGGLE_GEAR" then
            fcc.ap.reverseGear = not fcc.ap.reverseGear
        elseif msg.cmd == "TOGGLE_CLUTCH" then
            fcc:toggleClutchPolarity()
        elseif msg.cmd == "MANUAL_YAW_DELTA" then
            fcc.ap.manualYaw = math.max(-6, math.min(6, (fcc.ap.manualYaw or 0) + (tonumber(msg.delta) or 0)))
        elseif msg.cmd == "SAFE_DISARM" or msg.cmd == "DISARM" then
            fcc.ap.baseThrottle = 0
            fcc.ap.parkingBrake = true
            fcc:setMode("MANUAL", tel)
        end
    end

    -- Send remote cockpit commands
    simulateFCCCommand(fccFC, { type = "AVIONICS_CMD", cmd = "SET_MODE", mode = "HOVER", targetAlt = 80 }, fccTel)
    assert(fccFC.ap.mode == "HOVER" and fccFC.ap.targetAlt == 80, "Expected SET_MODE HOVER with targetAlt=80 on FCC Core")

    simulateFCCCommand(fccFC, { type = "AVIONICS_CMD", cmd = "ALT_DELTA", delta = 15 }, fccTel)
    assert(fccFC.ap.targetAlt == 95, "Expected ALT_DELTA +15 to reach targetAlt=95")

    simulateFCCCommand(fccFC, { type = "AVIONICS_CMD", cmd = "THR_DELTA", delta = 7 }, fccTel)
    assert(fccFC.ap.baseThrottle == 7, "Expected THR_DELTA +7 to set baseThrottle=7")

    simulateFCCCommand(fccFC, { type = "AVIONICS_CMD", cmd = "TOGGLE_GEAR" }, fccTel)
    assert(fccFC.ap.reverseGear == true, "Expected TOGGLE_GEAR to engage reverse gear")

    simulateFCCCommand(fccFC, { type = "AVIONICS_CMD", cmd = "MANUAL_YAW_DELTA", delta = 4 }, fccTel)
    assert(fccFC.ap.manualYaw == 4, "Expected MANUAL_YAW_DELTA +4 to set manualYaw=4")

    -- Step 10c: Verify telemetry state packet serialization for DRUNKEN_AVIONICS_BUS
    local busPacket = {
        type   = "AVIONICS_STATE",
        sender = 5,
        tel    = fccTel,
        ap     = {
            enabled      = fccFC.ap.enabled,
            mode         = fccFC.ap.mode,
            targetAlt    = fccFC.ap.targetAlt,
            baseThrottle = fccFC.ap.baseThrottle,
            parkingBrake = fccFC.ap.parkingBrake,
            reverseGear  = fccFC.ap.reverseGear,
            vehicleType  = fccFC.vehicleType
        }
    }
    assert(busPacket.type == "AVIONICS_STATE", "Expected AVIONICS_STATE packet type")
    assert(busPacket.ap.mode == "HOVER" and busPacket.ap.targetAlt == 95, "Expected telemetry AP state match")
    assert(busPacket.ap.vehicleType == "GUNSHIP", "Expected telemetry vehicleType GUNSHIP")

    -- Step 10d: Multi-Monitor Rendering Test
    local FlightApp = require("apps.flight_control")
    assert(type(FlightApp.renderTacticalDisplay) == "function", "Expected FlightApp.renderTacticalDisplay function")
    assert(type(FlightApp.renderScadaDisplay) == "function", "Expected FlightApp.renderScadaDisplay function")

    local function createMockMonitor(w, h, isCol)
        local lines = {}
        local curX, curY = 1, 1
        return {
            getSize = function() return w, h end,
            isColor = function() return isCol end,
            clear = function() lines = {} end,
            setCursorPos = function(x, y) curX, curY = x, y end,
            setBackgroundColor = function() end,
            setTextColor = function() end,
            write = function(str)
                lines[curY] = (lines[curY] or "") .. tostring(str)
            end,
            getOutput = function()
                local out = {}
                for i = 1, h do table.insert(out, lines[i] or "") end
                return table.concat(out, "\n")
            end
        }
    end

    -- Monitor 2 (Admiral Cabin Tactical & Navigation Display)
    local monTactical = createMockMonitor(45, 12, true)
    FlightApp.renderTacticalDisplay(monTactical, fccTel, fccFC.ap)
    local tacText = monTactical.getOutput()
    assert(tacText:find("TAKTIK & NAVIGASYON") ~= nil, "Expected Tactical display to contain header")
    assert(tacText:find("DOS%-FLAGSHIP") ~= nil, "Expected Tactical display to contain vessel callsign")
    assert(tacText:find("GUNSHIP") ~= nil, "Expected Tactical display to contain GUNSHIP profile")
    assert(tacText:find("HOVER") ~= nil, "Expected Tactical display to contain AP HOVER mode")
    assert(tacText:find("POS : X:250 Y:75 Z:%-400") ~= nil, "Expected Tactical display to contain position coordinates")

    -- Monitor 3 (Engine Room SCADA Display)
    local monScada = createMockMonitor(45, 12, true)
    FlightApp.renderScadaDisplay(monScada, fccTel, fccFC.ap)
    local scadaText = monScada.getOutput()
    assert(scadaText:find("MAKINE DAIRESI") ~= nil, "Expected SCADA display to contain header")
    assert(scadaText:find("DEVIR %(RPM%):   256") ~= nil, "Expected SCADA display to contain RPM")
    assert(scadaText:find("GERI") ~= nil, "Expected SCADA display to show reverse gear status")
    assert(scadaText:find("LIFT ON  : FL:10 FR:10") ~= nil, "Expected SCADA display to show front lift motors")
    assert(scadaText:find("LIFT ARKA: RL:10 RR:10") ~= nil, "Expected SCADA display to show rear lift motors")

    -- Disarm test
    simulateFCCCommand(fccFC, { type = "AVIONICS_CMD", cmd = "SAFE_DISARM" }, fccTel)
    assert(fccFC.ap.baseThrottle == 0 and fccFC.ap.parkingBrake == true and fccFC.ap.mode == "MANUAL", "Expected SAFE_DISARM to cut throttle and park")
    print("  PASS: Test 10: Dual-Computer Architecture (Avionics Core Daemon FCC + Multi-Monitor Cockpit Remote Command Bus & Telemetry)")

    -- Test 11: System 3 (Wheel Mount Steering) & System 4 (Physical Rudder Bearing & Pilot Override)
    local wheelSteer = 0
    local wheelBrake = 0
    local mockWheel = {
        setSteering = function(v) wheelSteer = v end,
        setBrake = function(b) wheelBrake = b end,
        getTouchingFriction = function() return 0.5 end
    }
    local rudderTargetAngle = 0
    local mockRudderBearing = {
        setTargetAngle = function(deg) rudderTargetAngle = deg end
    }
    local isPilotHoldingWheel = true
    local mockCockpitWheel = {
        isHeld = function() return isPilotHoldingWheel end,
        getNormalizedAngle = function() return 0.75 end
    }

    _G.peripheral.find = function(pType)
        if pType == "wheel_mount" then return mockWheel
        elseif pType == "steering_wheel" then return mockCockpitWheel
        elseif pType == "altitude_sensor" then return { getHeight = function() return 80 end, getVerticalSpeed = function() return 0 end }
        elseif pType == "navigation_table" then return { getHeadingRad = function() return 0 end }
        end
        return nil
    end
    _G.peripheral.getNames = function() return { "wheel_mount_0", "rudder_bearing" } end
    _G.peripheral.getType = function(n)
        if n == "wheel_mount_0" then return "wheel_mount"
        elseif n == "rudder_bearing" then return "create_mechanical_bearing" end
        return "peripheral"
    end
    _G.peripheral.wrap = function(n)
        if n == "wheel_mount_0" then return mockWheel
        elseif n == "rudder_bearing" then return mockRudderBearing end
        return nil
    end

    local sysFC = Avionics.new({ callsign = "SYS34-TEST" })
    local rudderCfg = sysFC:getDeviceConfig("rudder_bearing")
    assert(rudderCfg.role == "RUDDER_YAW", "Expected device named rudder_bearing to auto-assign role RUDDER_YAW")

    -- 1. Pilot physically holds steering wheel at 0.75:
    sysFC:step(0.05)
    assert(wheelSteer == 0.75, "Expected wheel_mount to receive pilot steering command (0.75)")
    assert(rudderTargetAngle == 0.75 * 45.0, "Expected rudder mechanical bearing to deflect to 0.75 * 45 deg")

    -- 2. Pilot releases wheel (isHeld = false); Autopilot Heading Hold active with 30 deg error:
    isPilotHoldingWheel = false
    mockCockpitWheel.getNormalizedAngle = function() return 0 end
    sysFC.ap.enabled = true
    sysFC.ap.hdgHold = true
    sysFC.ap.targetHdg = math.rad(30)
    sysFC:step(0.05)
    assert(wheelSteer > 0, "Expected Autopilot heading hold to command positive steering to correct heading error")
    assert(rudderTargetAngle > 0, "Expected Autopilot heading hold to deflect rudder bearing towards target heading")

    -- 3. Manual Mode with manualYaw:
    sysFC.ap.enabled = false
    sysFC.ap.manualYaw = -3
    sysFC:step(0.05)
    assert(wheelSteer == -0.5, "Expected manualYaw=-3 to command -0.5 steering")
    assert(rudderTargetAngle == -0.5 * 45.0, "Expected rudder bearing to deflect to -22.5 deg")

    -- 4. Redstone Gearshift Driving (Digital & Analog Redstone)
    local rsAnalog = {}
    local rsDigital = {}
    local origRs = _G.redstone
    _G.redstone = {
        setAnalogOutput = function(s, v) rsAnalog[s] = v end,
        setOutput = function(s, b) rsDigital[s] = b end
    }
    assert(sysFC:getDeviceConfig("RS:back").role == "GEAR_REVERSE", "Expected RS:back to auto-assign GEAR_REVERSE when no gearshift peripheral present")
    sysFC.ap.reverseGear = true
    sysFC:step(0.05)
    assert(rsAnalog["back"] == 15, "Expected RS:back analog redstone to be 15 in reverse")
    assert(rsDigital["back"] == true, "Expected RS:back digital redstone to be true in reverse")
    sysFC.ap.reverseGear = false
    sysFC:step(0.05)
    assert(rsAnalog["back"] == 0, "Expected RS:back analog redstone to be 0 in forward")
    assert(rsDigital["back"] == false, "Expected RS:back digital redstone to be false in forward")
    _G.redstone = origRs

    print("  PASS: Test 11: System 3 (Wheel Mount Steering) & System 4 (Physical Rudder Bearing & Pilot Override)")

    -- Test 12: Quad wing altimeters (wired) + 4 central speed controllers -> differential auto-leveling
    local wingH = { alt_fl = 78, alt_rl = 78, alt_fr = 82, alt_rr = 82 }
    local rpmOut = {}
    local wingDevs = {}
    for n, _ in pairs(wingH) do
        wingDevs[n] = { getHeight = function() return wingH[n] end }
    end
    for i = 0, 3 do
        local n = "rsc_" .. i
        wingDevs[n] = { setTargetSpeed = function(v) rpmOut[n] = v end, getTargetSpeed = function() return rpmOut[n] or 0 end }
    end
    _G.peripheral.find = function(pType)
        if pType == "altitude_sensor" then return wingDevs.alt_fl end
        return nil
    end
    _G.peripheral.getNames = function() return { "alt_fl", "alt_fr", "alt_rl", "alt_rr", "rsc_0", "rsc_1", "rsc_2", "rsc_3" } end
    _G.peripheral.getType = function(n) return n:find("^alt_") and "altitude_sensor" or "rotation_speed_controller" end
    _G.peripheral.wrap = function(n) return wingDevs[n] end
    _G.peripheral.getName = function(h) for n, d in pairs(wingDevs) do if d == h then return n end end end

    local wFC = Avionics.new({ callsign = "WING-ALT", profile = "MOTHERSHIP" })
    local corner = { "FL", "FR", "RL", "RR" }
    for i, c in ipairs(corner) do
        wFC:setDeviceRole("alt_" .. c:lower(), "LIFT_" .. c)
        wFC:setDeviceRole("rsc_" .. (i - 1), "LIFT_" .. c)
    end
    wFC.ap.sasEnabled = true
    wFC.ap.parkingBrake = false
    wFC.ap.baseThrottle = 8
    local wTel = wFC:step(0.05) or wFC:readTelemetry(0.05)
    assert(wFC.wingAlt and wFC.wingAlt.n == 4, "Expected 4 wing altimeters to be detected via LIFT_* roles")
    assert(wFC.wingAlt.dR == -4, "Expected left-right altitude diff of -4 (left wing low)")
    assert(wFC.wingAlt.dP == 0, "Expected zero fore-aft altitude diff")
    local ms = wFC.lastMothershipState
    assert(ms.fl > ms.fr and ms.rl > ms.rr, "Expected low left wing to receive more lift than right wing")
    assert(rpmOut.rsc_0 > rpmOut.rsc_1, "Expected FL speed controller RPM > FR speed controller RPM")
    -- Nose low: front altimeters below rear -> front lift increases
    wingH.alt_fl, wingH.alt_fr, wingH.alt_rl, wingH.alt_rr = 79, 79, 81, 81
    wFC:step(0.05)
    ms = wFC.lastMothershipState
    assert(wFC.wingAlt.dP == -2 and ms.fl > ms.rl and ms.fr > ms.rr, "Expected low nose to receive more front lift")
    print("  PASS: Test 12: Quad Wing Altimeter Differential Auto-Leveling (4x RSC)")

    -- Test 13: Sky Anchor (Station Keeping & 3D Position Lock)
    local ancFC = Avionics.new({ callsign = "SKY-ANCHOR-TEST", profile = "MOTHERSHIP" })
    ancFC.pos = { x = 100, y = 80, z = 200 }
    local initTel = { altitude = 80, pos = { x = 100, y = 80, z = 200 }, heading = 0, pitch = 0, roll = 0 }
    ancFC:setMode("ANCHOR", initTel)
    assert(ancFC.ap.mode == "ANCHOR", "Expected mode to be ANCHOR")
    assert(ancFC.anchorPos and ancFC.anchorPos.x == 100 and ancFC.anchorPos.y == 80 and ancFC.anchorPos.z == 200, "Expected anchorPos locked to initial coordinates")

    -- Simulate forward drift: vessel moved to z=205 (5 blocks ahead)
    ancFC.pos = { x = 100, y = 80, z = 205 }
    local telStep = ancFC:step(0.05) or ancFC:readTelemetry(0.05)
    assert(telStep.anchor and telStep.anchor.active == true, "Expected anchor telemetry active")
    assert(telStep.anchor.surge == -5, "Expected negative surge (-5) when vessel drifts forward")
    assert(ancFC.lastMothershipState.rearC < 0, "Expected rear propulsion to command reverse thrust to arrest forward drift")

    -- Disengage anchor
    ancFC:setMode("MANUAL", telStep)
    assert(ancFC.anchorPos == nil, "Expected anchorPos cleared when disengaging anchor")
    print("  PASS: Test 13: Sky Anchor 3D Station Keeping & Anti-Drift Counter-Thrust")

    -- Restore globals
    _G.peripheral = origPeripheral
    _G.parallel   = origParallel
    _G.colors     = origColors
    print(">>> All Avionics Tests Passed Successfully!\n")
    return true
end

runTests()
return { run = runTests }
