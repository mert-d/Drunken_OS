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

    -- Restore globals
    _G.peripheral = origPeripheral
    _G.parallel   = origParallel
    print(">>> All Avionics Tests Passed Successfully!\n")
    return true
end

runTests()
return { run = runTests }
