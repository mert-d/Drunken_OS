-- tests/test_avionics.lua
-- Unit tests for Drunken OS Create: Avionics Flight Computer

local function runTests()
    print("=== Running Drunken OS Avionics Tests ===")

    -- Backup globals
    local origPeripheral = _G.peripheral
    local origParallel   = _G.parallel

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
                    getAltitude = function() return mockState.altitude end,
                    getVerticalSpeed = function() return -1.5 end,
                    getAirPressure = function() return 0.92 end
                }
            elseif pType == "gimbal_sensor" then
                return {
                    getPitch = function() return mockState.pitch end,
                    getRoll = function() return mockState.roll end,
                    getLinearAcceleration = function() return { x = 0, y = 0, z = 0.2 } end
                }
            elseif pType == "navigation_table" then
                return {
                    getHeadingRad = function() return mockState.heading end
                }
            elseif pType == "laser_sensor" then
                return {
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

    -- Restore globals
    _G.peripheral = origPeripheral
    _G.parallel   = origParallel
    print(">>> All Avionics Tests Passed Successfully!\n")
    return true
end

runTests()
return { run = runTests }
