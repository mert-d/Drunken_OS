-- lib/avionics.lua
-- Drunken OS - Create: Avionics & Aeronautics Flight Control Core
-- Supports Airships (Zeppelins) and Fixed-Wing / VTOL Aircraft

local Avionics = {}
Avionics.__index = Avionics

local MAX_GYRO_CONE_RAD = math.rad(12) -- Gyroscopic Propeller Bearing 12 deg limit

-- Derivative-on-Measurement & Anti-Windup PID Controller
local function createPID(kp, ki, kd, minOut, maxOut)
    local integral = 0
    local prevPV = nil

    return {
        compute = function(self, setpoint, pv, dt)
            if dt <= 0 then dt = 0.05 end
            local err = setpoint - pv

            -- Integral with clamping (anti-windup)
            integral = integral + (err * dt * ki)
            if integral > maxOut then integral = maxOut end
            if integral < minOut then integral = minOut end

            -- Derivative on measurement to avoid setpoint kick
            local deriv = 0
            if prevPV ~= nil then
                deriv = -(pv - prevPV) / dt
            end
            prevPV = pv

            local out = (kp * err) + integral + (kd * deriv)
            if out > maxOut then out = maxOut end
            if out < minOut then out = minOut end
            return out
        end,
        reset = function(self)
            integral = 0
            prevPV = nil
        end
    }
end

-- Normalize angle difference to [-pi, pi]
local function normalizeAngleRad(angle)
    return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function clamp(val, minVal, maxVal)
    return math.max(minVal, math.min(maxVal, val))
end

-- Safe peripheral method caller: prevents modded peripheral signature mismatches or disconnects from crashing PFD
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

-- Calls a peripheral method directly first; if it requires a Create control/entity ID string as arg #1, resolves it automatically
local function callKinetic(dev, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    if type(dev) == "table" then
        if type(dev.listControls) == "function" then
            local okC, ctrls = pcall(dev.listControls)
            if okC and type(ctrls) == "table" then
                for _, ctrl in ipairs(ctrls) do
                    local ok2, res2 = pcall(fn, ctrl, ...)
                    if ok2 then return res2 end
                end
            end
        end
        if type(dev.getBlockEntityId) == "function" then
            local okId, id = pcall(dev.getBlockEntityId)
            if okId and id ~= nil then
                local ok3, res3 = pcall(fn, id, ...)
                if ok3 then return res3 end
            end
        end
    end
    return nil
end

function Avionics.new(config)
    local self = setmetatable({}, Avionics)
    self.config = config or {}
    self.callsign = self.config.callsign or ("DOS-" .. tostring(os.getComputerID and os.getComputerID() or 0))

    self:scanPeripherals()

    -- Autopilot State & Setpoints
    self.ap = {
        enabled      = false,
        mode         = "MANUAL", -- MANUAL, CRUISE, HOVER, LNAV, AUTOLAND, RTB
        altHold      = false,
        hdgHold      = false,
        spdHold      = false,
        sasEnabled   = true,     -- Stability Augmentation System
        targetAlt    = 120.0,
        targetHdg    = 0.0,      -- Radians
        targetSpd    = 10.0,     -- m/s
        baseThrottle = 8,        -- 0..15 Redstone/Transmission scale
        parkingBrake = false,
        waypoint     = nil,      -- { x = 0, y = 120, z = 0, name = "HOME" }
        homeBase     = nil,      -- ILS Beacon packet or manual base table
        rtbPhase     = "NONE",   -- NONE, RTB_IAF, RTB_ILS, RTB_MAST
        ilsDev       = { loc = 0.0, gs = 0.0, dist = 0.0 }
    }

    -- Dead-Reckoning Position Estimate & GPS Tick Throttle
    self.pos = { x = 0, y = 0, z = 0 }
    self.gpsTick = 0

    -- PID Controllers
    self.altPID   = createPID(1.6, 0.35, 2.0, -7.0, 7.0)
    self.hdgPID   = createPID(3.8, 0.10, 1.2, -6.0, 6.0)
    self.pitchPID = createPID(0.8, 0.05, 0.4, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)
    self.rollPID  = createPID(0.8, 0.05, 0.4, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)

    return self
end

function Avionics:scanPeripherals()
    -- Sensors
    self.altSensor   = peripheral and peripheral.find and peripheral.find("altitude_sensor")
    self.gimbal      = peripheral and peripheral.find and peripheral.find("gimbal_sensor")
    self.nav         = peripheral and peripheral.find and peripheral.find("navigation_table")
    self.velSensor   = peripheral and peripheral.find and peripheral.find("velocity_sensor")
    self.laserSensor = peripheral and peripheral.find and peripheral.find("laser_sensor")
    self.steerWheel  = peripheral and peripheral.find and peripheral.find("steering_wheel")
    self.typewriter  = peripheral and peripheral.find and peripheral.find("linked_typewriter")

    -- Actuators & Engines (Multiple instances supported, sorted deterministically by peripheral name)
    if peripheral and peripheral.find then
        self.burners     = { peripheral.find("gas_provider") }
        self.gearboxes   = { peripheral.find("analog_transmission") }
        table.sort(self.gearboxes, function(a, b)
            local na = (peripheral.getName and pcall(peripheral.getName, a) and peripheral.getName(a)) or ""
            local nb = (peripheral.getName and pcall(peripheral.getName, b) and peripheral.getName(b)) or ""
            return tostring(na) < tostring(nb)
        end)

        self.throttles   = { peripheral.find("throttle_lever") }
        self.gyros       = { peripheral.find("gyroscopic_propeller_bearing") }
        self.wheels      = { peripheral.find("wheel_mount") }
        self.engines     = { peripheral.find("portable_engine") }
        self.clutches    = { peripheral.find("create_connected_inverted_clutch") }
    else
        self.burners     = {}
        self.gearboxes   = {}
        self.throttles   = {}
        self.gyros       = {}
        self.wheels      = {}
        self.engines     = {}
        self.clutches    = {}
    end

    -- Determine Vehicle Type
    if #self.burners > 0 then
        self.vehicleType = "ZEPPELIN"
    else
        self.vehicleType = "AIRCRAFT"
    end
end

function Avionics:readTelemetry(dt)
    dt = dt or 0.05

    self.gpsTick = (self.gpsTick or 0) + 1
    if (self.gpsTick % 20 == 0) or (not self.altSensor and not self.velSensor) then
        self:scanPeripherals()
    end

    -- 1. Altitude & Vertical Speed (Supports Create Simulated getHeight and legacy getAltitude)
    local alt = 0
    local vsi = 0
    local pressure = 1.0
    if self.altSensor then
        alt = tonumber(safeCall(self.altSensor.getHeight))
           or tonumber(safeCall(self.altSensor.getAltitude))
           or 0
        vsi = tonumber(safeCall(self.altSensor.getVerticalSpeed)) or 0
        pressure = tonumber(safeCall(self.altSensor.getAirPressure)) or 1.0
    end

    -- 2. Attitude (Pitch, Roll, Linear Acceleration)
    local pitch, roll = 0, 0
    local linAcc = { x = 0, y = 0, z = 0 }
    if self.gimbal then
        pitch = tonumber(safeCall(self.gimbal.getPitch)) or 0
        roll  = tonumber(safeCall(self.gimbal.getRoll)) or 0
        local acc = safeCall(self.gimbal.getLinearAcceleration)
        if type(acc) == "table" then linAcc = acc end
    end

    -- 3. Heading (Navigation Table)
    local heading = 0
    if self.nav then
        local hRad = tonumber(safeCall(self.nav.getHeadingRad))
        if hRad then
            heading = hRad
        else
            local hDeg = tonumber(safeCall(self.nav.getHeading))
            if hDeg then heading = math.rad(hDeg) end
        end
    end

    -- 4. Velocity & Airspeed
    local vel = { x = 0, y = vsi, z = 0 }
    local speed = 0
    if self.velSensor then
        local v = safeCall(self.velSensor.getVelocity)
        if type(v) == "table" then
            vel.x = tonumber(v.x) or 0
            vel.y = tonumber(v.y) or vsi
            vel.z = tonumber(v.z) or 0
            speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
        elseif type(v) == "number" then
            speed = v
        end
    end

    -- Update Position (Dead-Reckoning every tick, GPS sync once every 20 ticks to avoid os.pullEvent conflicts)
    self.pos.x = self.pos.x + vel.x * dt
    self.pos.y = alt
    self.pos.z = self.pos.z + vel.z * dt

    if self.config.useGPS and gps and gps.locate and (self.gpsTick % 20 == 0) then
        local okGps, gx, gy, gz = pcall(gps.locate, 0.02)
        if okGps and gx then
            self.pos.x, self.pos.y, self.pos.z = gx, gy, gz
        end
    end

    -- 5. Laser Radar Altimeter (AGL)
    local agl = nil
    if self.laserSensor then
        agl = tonumber(safeCall(self.laserSensor.getDistance))
           or tonumber(safeCall(self.laserSensor.getHitDistance))
    end

    -- 6. Weight-on-Wheels (Ground Contact)
    local weightOnWheels = false
    for _, w in ipairs(self.wheels) do
        local fric = tonumber(safeCall(w.getTouchingFriction)) or 0
        if fric > 0 then
            weightOnWheels = true
            break
        end
    end

    -- 7. Engine, Clutch & Burner SCADA (RPM, Overstress, Burner Signal)
    local maxRpm = 0
    local overstressed = false
    local gasType = "NONE"
    local burnerActual = 0
    local burnerActive = false

    for _, eng in ipairs(self.engines) do
        local engRpm = tonumber(safeCall(eng.getRpm)) or tonumber(safeCall(eng.getSpeed)) or 0
        maxRpm = math.max(maxRpm, math.abs(engRpm))
        if safeCall(eng.isOverstressed) == true then
            overstressed = true
        end
    end

    for _, cl in ipairs(self.clutches or {}) do
        local clRpm = tonumber(callKinetic(cl, cl.getSpeed))
                   or tonumber(callKinetic(cl, cl.getOutputSpeed))
                   or tonumber(callKinetic(cl, cl.getGeneratedSpeed))
                   or 0
        maxRpm = math.max(maxRpm, math.abs(clRpm))
        if callKinetic(cl, cl.isOverstressed) == true then
            overstressed = true
        end
    end

    for _, b in ipairs(self.burners) do
        if gasType == "NONE" then
            local gt = safeCall(b.getGasType)
            if gt then gasType = tostring(gt) end
        end
        local bSig = tonumber(safeCall(b.getSignalStrength)) or 0
        burnerActual = math.max(burnerActual, bSig)
        if safeCall(b.isActive) == true then
            burnerActive = true
        end
    end

    -- 8. Warnings (GPWS & Stall)
    local gpwsWarning = (agl ~= nil and agl < 12 and vsi < -3.5 and not weightOnWheels)
    local stallWarning = (self.vehicleType == "AIRCRAFT" and not weightOnWheels and speed < 3.0 and pitch > math.rad(15))

    return {
        callsign       = self.callsign,
        vehicleType    = self.vehicleType,
        altitude       = alt,
        agl            = agl,
        vSpeed         = vsi,
        pressure       = pressure,
        pitch          = pitch,
        roll           = roll,
        heading        = heading,
        speed          = speed,
        velocity       = vel,
        linAcc         = linAcc,
        pos            = { x = self.pos.x, y = self.pos.y, z = self.pos.z },
        weightOnWheels = weightOnWheels,
        rpm            = maxRpm,
        overstressed   = overstressed,
        gasType        = gasType,
        burnerCmd      = self.lastBurnerSignal or 0,
        burnerActual   = burnerActual,
        burnerActive   = burnerActive,
        gpwsWarning    = gpwsWarning,
        stallWarning   = stallWarning
    }
end

function Avionics:setHomeBase(ilsBeacon)
    self.ap.homeBase = ilsBeacon
end

function Avionics:engageRTB(currentTel)
    if not self.ap.homeBase then return false end
    self.ap.enabled  = true
    self.ap.altHold  = true
    self.ap.hdgHold  = true
    self.ap.mode     = "RTB"

    if self.vehicleType == "ZEPPELIN" and self.ap.homeBase.zeppelinMast then
        self.ap.rtbPhase = "RTB_MAST"
    else
        self.ap.rtbPhase = "RTB_IAF"
    end
    self.altPID:reset()
    self.hdgPID:reset()
    return true
end

function Avionics:setMode(modeName, currentTel)
    self.ap.mode = modeName
    self.altPID:reset()
    self.hdgPID:reset()
    self.pitchPID:reset()
    self.rollPID:reset()

    if modeName == "MANUAL" then
        self.ap.enabled = false
        self.ap.altHold = false
        self.ap.hdgHold = false
        self.ap.rtbPhase = "NONE"
    elseif modeName == "CRUISE" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
        if currentTel then
            self.ap.targetAlt = math.floor(currentTel.altitude + 0.5)
            self.ap.targetHdg = currentTel.heading
        end
    elseif modeName == "HOVER" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
        self.ap.baseThrottle = 0
        if currentTel then
            self.ap.targetAlt = math.floor(currentTel.altitude + 0.5)
            self.ap.targetHdg = currentTel.heading
        end
    elseif modeName == "LNAV" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
    elseif modeName == "AUTOLAND" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
    elseif modeName == "RTB" then
        self:engageRTB(currentTel)
    end
end

-- Executes 1 control step (dt = 0.05s for 20Hz)
-- Batches all mainThread yielding calls into parallel.waitForAll
function Avionics:step(dt)
    dt = dt or 0.05
    local tel = self:readTelemetry(dt)
    local tasks = {}

    -- Handle Waypoint LNAV Bearing Calculation
    if self.ap.enabled and self.ap.mode == "LNAV" and self.ap.waypoint then
        local dx = self.ap.waypoint.x - tel.pos.x
        local dz = self.ap.waypoint.z - tel.pos.z
        local distSq = dx * dx + dz * dz
        if distSq > 25 then -- > 5 blocks away
            self.ap.targetHdg = math.atan2(-dx, dz)
            if self.ap.waypoint.y then
                self.ap.targetAlt = self.ap.waypoint.y
            end
        elseif self.vehicleType == "ZEPPELIN" then
            self:setMode("HOVER", tel)
        end
    end

    -- Handle RTB & ILS Approach State Machine
    if self.ap.enabled and self.ap.mode == "RTB" and self.ap.homeBase then
        local base = self.ap.homeBase

        if self.ap.rtbPhase == "RTB_MAST" then
            local mast = base.zeppelinMast or base.threshold
            local dx = mast.x - tel.pos.x
            local dz = mast.z - tel.pos.z
            local dist = math.sqrt(dx * dx + dz * dz)
            self.ap.ilsDev.dist = dist

            if dist > 6.0 then
                self.ap.targetHdg = math.atan2(-dx, dz)
                self.ap.targetAlt = mast.y + 15.0
                self.ap.baseThrottle = math.min(10, math.max(3, math.floor(dist * 0.25)))
            else
                self.ap.targetHdg = base.rwyHeadingRad or 0.0
                self.ap.targetAlt = mast.y
                self.ap.baseThrottle = 0
                if math.abs(tel.altitude - mast.y) < 1.5 then
                    self:setMode("HOVER", tel)
                end
            end
        else
            local thr = base.threshold
            local psi = base.rwyHeadingRad or 0.0
            local gs  = base.glideSlopeRad or math.rad(8.0)
            local dApp = base.approachDist or 80.0

            local relX = tel.pos.x - thr.x
            local relZ = tel.pos.z - thr.z

            local dAlong = relX * math.sin(psi) - relZ * math.cos(psi)
            local crossTrackErr = relX * math.cos(psi) + relZ * math.sin(psi)

            self.ap.ilsDev.loc  = crossTrackErr
            self.ap.ilsDev.dist = math.max(0, dAlong)

            if self.ap.rtbPhase == "RTB_IAF" then
                local fafX = thr.x + dApp * math.sin(psi)
                local fafZ = thr.z - dApp * math.cos(psi)
                local fafY = thr.y + dApp * math.tan(gs)

                local dx = fafX - tel.pos.x
                local dz = fafZ - tel.pos.z
                local distToFAF = math.sqrt(dx * dx + dz * dz)

                self.ap.targetHdg = math.atan2(-dx, dz)
                self.ap.targetAlt = fafY

                if distToFAF < 12.0 then
                    self.ap.rtbPhase = "RTB_ILS"
                end
            elseif self.ap.rtbPhase == "RTB_ILS" then
                local interceptAngle = math.atan(0.18 * crossTrackErr)
                interceptAngle = clamp(interceptAngle, -math.rad(30), math.rad(30))
                self.ap.targetHdg = normalizeAngleRad(psi - interceptAngle)

                local gsTargetAlt = thr.y + math.max(0, dAlong) * math.tan(gs)
                self.ap.ilsDev.gs = tel.altitude - gsTargetAlt
                self.ap.targetAlt = gsTargetAlt

                self.ap.baseThrottle = math.max(4, math.min(8, self.ap.baseThrottle))

                if dAlong <= 8.0 or (tel.agl and tel.agl <= 5.0) then
                    self.ap.targetHdg = psi
                    self:setMode("AUTOLAND", tel)
                end
            end
        end
    end

    -- Handle AUTOLAND Profile
    if self.ap.enabled and self.ap.mode == "AUTOLAND" then
        local currentAGL = tel.agl or (tel.altitude - 64)
        if tel.weightOnWheels or currentAGL <= 1.5 then
            self.ap.baseThrottle = 0
            self.ap.parkingBrake = true
            self:setMode("MANUAL", tel)
        elseif currentAGL < 8.0 then
            self.ap.targetAlt = tel.altitude - 0.5
            self.ap.baseThrottle = math.max(0, self.ap.baseThrottle - 1)
        else
            self.ap.targetAlt = tel.altitude - 2.0
        end
    end

    -- Heading PID computation (used for differential thrust, vectoring gyros, and rudder steering)
    local yawDiff = 0
    if self.ap.hdgHold then
        local hdgErr = normalizeAngleRad(self.ap.targetHdg - tel.heading)
        yawDiff = self.hdgPID:compute(0, -hdgErr, dt)
    end

    local function driveSignal(dev, sig)
        if dev.setSignal then callKinetic(dev, dev.setSignal, sig)
        elseif dev.setThrottle then callKinetic(dev, dev.setThrottle, sig)
        elseif dev.setTarget then callKinetic(dev, dev.setTarget, sig)
        elseif dev.setLevel then callKinetic(dev, dev.setLevel, sig)
        elseif dev.setOutput then callKinetic(dev, dev.setOutput, sig)
        elseif dev.setSignalStrength then callKinetic(dev, dev.setSignalStrength, sig)
        elseif dev.setControl then callKinetic(dev, dev.setControl, sig)
        end
    end

    local function emitRedstoneBurner(sig)
        if redstone and redstone.setAnalogOutput then
            for _, side in ipairs({ "left", "right", "front", "back", "top", "bottom" }) do
                pcall(redstone.setAnalogOutput, side, sig)
            end
        end
    end

    -- 1. Landing Gear Brakes, Inverted Clutches & Steering / Rudder Deflection
    local brakeVal = self.ap.parkingBrake and 1.0 or 0.0
    local steerVal = 0.0
    if self.steerWheel and self.steerWheel.getSteering then
        steerVal = tonumber(safeCall(self.steerWheel.getSteering)) or 0.0
    end
    -- Autopilot rudder steering when using steering mounts with single engine or Zeppelin
    if self.ap.enabled and self.ap.hdgHold and steerVal == 0.0 and #self.gearboxes < 2 then
        steerVal = clamp(-yawDiff * 0.15, -1.0, 1.0)
    end
    for _, wheel in ipairs(self.wheels) do
        if wheel.setBrake then
            table.insert(tasks, function() safeCall(wheel.setBrake, brakeVal) end)
        end
        if wheel.setSteering then
            table.insert(tasks, function() safeCall(wheel.setSteering, steerVal) end)
        end
    end

    -- Drive Create: Connected Inverted Clutches (Propeller power cut / brake signal)
    local clutchCut = self.ap.parkingBrake or (self.ap.baseThrottle <= 0)
    for _, cl in ipairs(self.clutches or {}) do
        table.insert(tasks, function()
            -- When parkingBrake is ON or throttle is 0, cut power; otherwise engage
            if cl.setPowered then callKinetic(cl, cl.setPowered, not clutchCut) end
            if cl.setSignal then callKinetic(cl, cl.setSignal, clutchCut and 0 or math.floor(clamp(self.ap.baseThrottle, 1, 15))) end
        end)
    end

    -- If Autopilot is disabled, apply baseThrottle to gearboxes/throttles and clear manual gyro locks
    if not self.ap.enabled then
        local manualSig = math.floor(clamp(self.ap.baseThrottle, 0, 15))
        self.lastBurnerSignal = manualSig
        tel.burnerCmd = manualSig
        for _, gb in ipairs(self.gearboxes) do
            table.insert(tasks, function() driveSignal(gb, manualSig) end)
        end
        if self.vehicleType == "ZEPPELIN" then
            emitRedstoneBurner(manualSig)
            for _, thr in ipairs(self.throttles) do
                table.insert(tasks, function() driveSignal(thr, manualSig) end)
            end
        end
        for _, gyro in ipairs(self.gyros) do
            if gyro.clearManualTarget then
                table.insert(tasks, function() safeCall(gyro.clearManualTarget) end)
            end
        end
        if #tasks > 0 and parallel and parallel.waitForAll then
            parallel.waitForAll(table.unpack(tasks))
        end
        return tel
    end

    -- 2. Differential Thrust on Analog Transmissions
    if #self.gearboxes >= 2 then
        local portSignal = math.floor(clamp(self.ap.baseThrottle - yawDiff, 0, 15))
        local stbdSignal = math.floor(clamp(self.ap.baseThrottle + yawDiff, 0, 15))
        table.insert(tasks, function() driveSignal(self.gearboxes[1], portSignal) end)
        table.insert(tasks, function() driveSignal(self.gearboxes[2], stbdSignal) end)
    elseif #self.gearboxes == 1 then
        local mainSignal = math.floor(clamp(self.ap.baseThrottle, 0, 15))
        table.insert(tasks, function() driveSignal(self.gearboxes[1], mainSignal) end)
    end

    -- 3. Altitude PID & Attitude Stabilization
    if self.ap.altHold then
        local altCmd = self.altPID:compute(self.ap.targetAlt, tel.altitude, dt)

        if self.vehicleType == "ZEPPELIN" then
            local burnerSignal = math.floor(clamp(8 + altCmd, 0, 15))
            self.lastBurnerSignal = burnerSignal
            tel.burnerCmd = burnerSignal
            emitRedstoneBurner(burnerSignal)
            for _, thr in ipairs(self.throttles) do
                table.insert(tasks, function() driveSignal(thr, burnerSignal) end)
            end
        end

        if #self.gyros > 0 then
            local desiredPitch = clamp(altCmd * 0.025, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)
            local pitchVec = self.pitchPID:compute(desiredPitch, tel.pitch, dt)
            local rollVec  = self.rollPID:compute(0, tel.roll, dt)

            -- In Zeppelins, horizontal gyro deflection steers Yaw; in Aircraft, it stabilizes Roll
            local vx
            if self.vehicleType == "ZEPPELIN" then
                local yawSteer = clamp(yawDiff * 0.035, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)
                vx = math.sin(yawSteer)
            else
                vx = math.sin(clamp(rollVec, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD))
            end
            local vy = math.sin(clamp(pitchVec, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD))
            local vz = math.sqrt(math.max(0, 1 - vx * vx - vy * vy))

            for _, gyro in ipairs(self.gyros) do
                if gyro.setManualTarget then
                    table.insert(tasks, function()
                        safeCall(gyro.setManualTarget, { x = vx, y = vy, z = vz })
                    end)
                end
            end
        end
    end

    -- Execute all mainThread actuator setters in parallel within a single server tick
    if #tasks > 0 and parallel and parallel.waitForAll then
        parallel.waitForAll(table.unpack(tasks))
    end

    return tel
end

return Avionics
