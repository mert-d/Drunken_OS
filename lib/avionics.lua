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

Avionics.ROLES = {
    "AUTO",
    "LIFT_FL",
    "LIFT_FR",
    "LIFT_RL",
    "LIFT_RR",
    "REAR_LEFT",
    "REAR_CENTER",
    "REAR_RIGHT",
    "LIFT_BURNER",
    "THRUST_MAIN",
    "THRUST_PORT",
    "THRUST_STBD",
    "AUX_BOOST",
    "CLUTCH_BRAKE",
    "GEAR_REVERSE",
    "RUDDER_YAW",
    "IGNORE"
}

Avionics.MOTHERSHIP_ROLES = {
    "LIFT_FL",
    "LIFT_FR",
    "LIFT_RL",
    "LIFT_RR",
    "REAR_LEFT",
    "REAR_CENTER",
    "REAR_RIGHT"
}

local IO_CONFIG_PATH = "/avionics_iomap.cfg"

function Avionics.new(config)
    local self = setmetatable({}, Avionics)
    self.config = config or {}
    self.callsign = self.config.callsign or ("DOS-" .. tostring(os.getComputerID and os.getComputerID() or 0))
    self.profile = self.config.profile or nil -- "ZEPPELIN", "AIRCRAFT", "MOTHERSHIP", or nil (auto)
    self.hasSavedProfile = false
    self.ioMap = {}
    self.ioDevices = {}

    self:loadIOMap()
    self:scanPeripherals()

    -- Autopilot State & Setpoints
    self.ap = {
        enabled      = false,
        mode         = "MANUAL", -- MANUAL, CRUISE, HOVER, LNAV, AUTOLAND, RTB
        altHold      = false,
        hdgHold      = false,
        spdHold      = false,
        sasEnabled   = true,     -- Stability Augmentation System (Gimbal Active Horizon Balance)
        targetAlt    = 120.0,
        targetHdg    = 0.0,      -- Radians
        targetSpd    = 10.0,     -- m/s
        baseThrottle = 8,        -- 0..15 Redstone/Transmission scale (or 0..256 RPM scale)
        manualYaw    = 0,        -- -5..+5 manual rudder/thruster turn trim
        parkingBrake = false,
        reverseGear  = false,    -- Gearshift / Reverse Thrust toggle ([G])
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

    -- Mothership Quad-Lift Gimbal Horizon Stabilization PIDs (output in -6..+6 lift signal units)
    self.msPitchPID = createPID(14.0, 1.5, 4.5, -6.0, 6.0)
    self.msRollPID  = createPID(14.0, 1.5, 4.5, -6.0, 6.0)

    return self
end

function Avionics:loadIOMap()
    if fs and fs.exists and fs.exists(IO_CONFIG_PATH) and textutils and textutils.unserialize then
        local ok, f = pcall(fs.open, IO_CONFIG_PATH, "r")
        if ok and f then
            local content = f.readAll()
            f.close()
            local parsed = textutils.unserialize(content)
            if type(parsed) == "table" then
                if parsed.ioMap and type(parsed.ioMap) == "table" then
                    self.ioMap = parsed.ioMap
                    if type(parsed.profile) == "string" then
                        self.profile = parsed.profile
                        self.hasSavedProfile = true
                    end
                else
                    self.ioMap = parsed
                end
            end
        end
    end
end

function Avionics:saveIOMap()
    if fs and fs.open and textutils and textutils.serialize then
        local ok, f = pcall(fs.open, IO_CONFIG_PATH, "w")
        if ok and f then
            f.write(textutils.serialize({
                profile = self.profile,
                ioMap   = self.ioMap
            }))
            f.close()
        end
    end
end

function Avionics:getDeviceConfig(devName)
    if not self.ioMap[devName] then
        self.ioMap[devName] = { role = "AUTO", invert = false }
    end
    return self.ioMap[devName]
end

function Avionics:setDeviceRole(devName, roleName)
    local cfg = self:getDeviceConfig(devName)
    cfg.role = roleName
    self:saveIOMap()
    return cfg.role
end

function Avionics:cycleRole(devName, dir)
    dir = dir or 1
    local cfg = self:getDeviceConfig(devName)
    local idx = 1
    for i, r in ipairs(Avionics.ROLES) do
        if r == cfg.role then idx = i break end
    end
    idx = ((idx - 1 + dir) % #Avionics.ROLES) + 1
    cfg.role = Avionics.ROLES[idx]
    self:saveIOMap()
    return cfg.role
end

function Avionics:toggleInvert(devName)
    local cfg = self:getDeviceConfig(devName)
    cfg.invert = not cfg.invert
    self:saveIOMap()
    return cfg.invert
end

-- Auto-assigns the first 4 speed controllers/gearboxes to Quad-Lift (FL, FR, RL, RR)
-- and the next 3 to Rear Thrusters (REAR_LEFT, REAR_CENTER, REAR_RIGHT)
function Avionics:autoAssignMothershipRoles(forceOverwrite)
    local candidates = {}
    for _, item in ipairs(self.ioDevices or {}) do
        if not item.isRedstone then
            local k = item.kind:lower()
            if k:find("speed_controller") or k:find("rotationspeedcontroller")
                or k:find("analog_transmission") or k:find("gearbox")
                or k:find("sequenced_gearshift") or k:find("throttle_lever") then
                table.insert(candidates, item.name)
            end
        end
    end
    local assignedCount = 0
    for _, devName in ipairs(candidates) do
        local cfg = self:getDeviceConfig(devName)
        if forceOverwrite or cfg.role == "AUTO" then
            assignedCount = assignedCount + 1
            if assignedCount <= #Avionics.MOTHERSHIP_ROLES then
                cfg.role = Avionics.MOTHERSHIP_ROLES[assignedCount]
            end
        end
    end
    self:saveIOMap()
end

function Avionics:setVehicleProfile(profileName, forceAutoAssign)
    self.profile = profileName
    self.hasSavedProfile = true
    self.vehicleType = profileName
    if profileName == "MOTHERSHIP" then
        self:autoAssignMothershipRoles(forceAutoAssign)
    end
    self:saveIOMap()
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
        self.gearshifts  = {}
        for _, gType in ipairs({ "gearshift", "create_sequenced_gearshift", "create_connected_gearshift", "redstone_relay" }) do
            local found = { peripheral.find(gType) }
            for _, g in ipairs(found) do table.insert(self.gearshifts, g) end
        end
        self.speedControllers = {}
        for _, scType in ipairs({ "Create_RotationSpeedController", "rotation_speed_controller", "create:rotation_speed_controller", "speed_controller" }) do
            local found = { peripheral.find(scType) }
            for _, sc in ipairs(found) do table.insert(self.speedControllers, sc) end
        end
        table.sort(self.speedControllers, function(a, b)
            local na = (peripheral.getName and pcall(peripheral.getName, a) and peripheral.getName(a)) or ""
            local nb = (peripheral.getName and pcall(peripheral.getName, b) and peripheral.getName(b)) or ""
            return tostring(na) < tostring(nb)
        end)
    else
        self.burners          = {}
        self.gearboxes        = {}
        self.throttles        = {}
        self.gyros            = {}
        self.wheels           = {}
        self.engines          = {}
        self.clutches         = {}
        self.gearshifts       = {}
        self.speedControllers = {}
    end

    -- Build unified I/O device list for Hot-Plug & Role Configurator UI
    self.ioDevices = {}
    if peripheral and peripheral.getNames then
        local okNames, names = pcall(peripheral.getNames)
        if okNames and type(names) == "table" then
            table.sort(names)
            for _, name in ipairs(names) do
                local okT, pType = pcall(peripheral.getType, name)
                local pStr = tostring(okT and pType or "peripheral")
                if pStr ~= "modem" and pStr ~= "monitor" and pStr ~= "speaker" and pStr ~= "drive" then
                    local okW, handle = pcall(peripheral.wrap, name)
                    self:getDeviceConfig(name)
                    table.insert(self.ioDevices, {
                        name       = name,
                        kind       = pStr,
                        handle     = okW and handle or nil,
                        isRedstone = false
                    })
                end
            end
        end
    else
        for idx, sc in ipairs(self.speedControllers or {}) do
            local name = "rotation_speed_controller_" .. tostring(idx - 1)
            self:getDeviceConfig(name)
            table.insert(self.ioDevices, {
                name       = name,
                kind       = "rotation_speed_controller",
                handle     = sc,
                isRedstone = false
            })
        end
        for idx, gb in ipairs(self.gearboxes or {}) do
            local name = "analog_transmission_" .. tostring(idx - 1)
            self:getDeviceConfig(name)
            table.insert(self.ioDevices, {
                name       = name,
                kind       = "analog_transmission",
                handle     = gb,
                isRedstone = false
            })
        end
    end
    for _, side in ipairs({ "back", "front", "left", "right", "top", "bottom" }) do
        local rsName = "RS:" .. side
        self:getDeviceConfig(rsName)
        table.insert(self.ioDevices, {
            name       = rsName,
            side       = side,
            kind       = "redstone_out",
            handle     = nil,
            isRedstone = true
        })
    end

    -- Determine Vehicle Type (Respect explicit saved profile first; otherwise auto-detect)
    if self.profile == "MOTHERSHIP" or self.profile == "ZEPPELIN" or self.profile == "AIRCRAFT" then
        self.vehicleType = self.profile
        if self.profile == "MOTHERSHIP" then
            self:autoAssignMothershipRoles(false)
        end
    elseif #self.speedControllers >= 4 or #self.gearboxes >= 4 then
        self.vehicleType = "MOTHERSHIP"
        self:autoAssignMothershipRoles(false)
    elseif #self.burners > 0 then
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

    -- 4. Velocity & Airspeed (Always positive magnitude for SPD display regardless of sensor block axis orientation)
    local vel = { x = 0, y = vsi, z = 0 }
    local speed = 0
    local rawVel = 0
    if self.velSensor then
        local v = safeCall(self.velSensor.getVelocity)
        if type(v) == "table" then
            vel.x = tonumber(v.x) or 0
            vel.y = tonumber(v.y) or vsi
            vel.z = tonumber(v.z) or 0
            speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
            rawVel = speed
        elseif type(v) == "number" then
            rawVel = v
            speed = math.abs(v)
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

    for _, sc in ipairs(self.speedControllers or {}) do
        local scRpm = tonumber(callKinetic(sc, sc.getTargetSpeed))
                   or tonumber(callKinetic(sc, sc.getSpeed))
                   or tonumber(callKinetic(sc, sc.getOutputSpeed))
                   or 0
        maxRpm = math.max(maxRpm, math.abs(scRpm))
        if callKinetic(sc, sc.isOverstressed) == true then
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
        mothership     = self.lastMothershipState or { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 },
        gpwsWarning    = gpwsWarning,
        stallWarning   = stallWarning
    }
end

function Avionics:triggerSpinTest(devName)
    self.spinTest = { name = devName, ticks = 30 } -- 1.5 seconds at 20Hz
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

    if (self.vehicleType == "ZEPPELIN" or self.vehicleType == "MOTHERSHIP") and self.ap.homeBase.zeppelinMast then
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
    self.msPitchPID:reset()
    self.msRollPID:reset()

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
        self.ap.manualYaw = 0
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

    if self.spinTest and self.spinTest.ticks > 0 then
        self.spinTest.ticks = self.spinTest.ticks - 1
        if self.spinTest.ticks <= 0 then self.spinTest = nil end
    end

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
        elseif self.vehicleType == "ZEPPELIN" or self.vehicleType == "MOTHERSHIP" then
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

    -- Supports both Create Rotation Speed Controllers (setTargetSpeed in -256..+256 RPM) and 0..15 Signal peripherals
    local function driveSignal(dev, sig, inv)
        if dev.setTargetSpeed then
            local rpm = math.floor((sig / 15.0) * 256 + 0.5)
            if inv then rpm = -rpm end
            callKinetic(dev, dev.setTargetSpeed, rpm)
            return
        end
        local clampedSig = math.floor(clamp(math.abs(sig), 0, 15))
        local outSig = inv and (15 - clampedSig) or clampedSig
        if dev.setSignal then callKinetic(dev, dev.setSignal, outSig)
        elseif dev.setThrottle then callKinetic(dev, dev.setThrottle, outSig)
        elseif dev.setTarget then callKinetic(dev, dev.setTarget, outSig)
        elseif dev.setLevel then callKinetic(dev, dev.setLevel, outSig)
        elseif dev.setOutput then callKinetic(dev, dev.setOutput, outSig)
        elseif dev.setSignalStrength then callKinetic(dev, dev.setSignalStrength, outSig)
        elseif dev.setControl then callKinetic(dev, dev.setControl, outSig)
        elseif dev.setSpeed then callKinetic(dev, dev.setSpeed, outSig)
        end
    end

    local function driveBooleanOrSignal(dev, active, sigVal, inv)
        local finalActive = inv and (not active) or active
        local finalSig = inv and (15 - sigVal) or sigVal
        if dev.setPowered then callKinetic(dev, dev.setPowered, finalActive) end
        if dev.setSignal then callKinetic(dev, dev.setSignal, finalSig)
        else driveSignal(dev, sigVal, inv) end
    end

    local function emitRedstoneBurner(sig)
        if redstone and redstone.setAnalogOutput then
            for _, side in ipairs({ "left", "right", "front", "back", "top", "bottom" }) do
                local cfg = self:getDeviceConfig("RS:" .. side)
                if cfg.role == "AUTO" or cfg.role == "LIFT_BURNER" then
                    local outSig = cfg.invert and (15 - sig) or sig
                    pcall(redstone.setAnalogOutput, side, outSig)
                end
            end
        end
    end

    -- 1. Landing Gear Brakes, Inverted Clutches, Gearshifts & Steering / Rudder Deflection
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

    -- Drive Gearshifts (Reverse Thrust / Reverse Gear [G])
    local revActive = self.ap.reverseGear == true
    for _, gs in ipairs(self.gearshifts or {}) do
        table.insert(tasks, function()
            driveBooleanOrSignal(gs, revActive, revActive and 15 or 0, false)
        end)
    end

    local mainThrottleSig = math.floor(clamp(self.ap.baseThrottle, 0, 15))
    local portSignal = math.floor(clamp(self.ap.baseThrottle - yawDiff, 0, 15))
    local stbdSignal = math.floor(clamp(self.ap.baseThrottle + yawDiff, 0, 15))
    local boostSignal = (self.ap.baseThrottle >= 12) and 15 or 0
    local burnerSignal = mainThrottleSig

    -- Compute Mothership 4-Lift + 3-Rear Thruster Mixing Matrix (Gimbal Pitch/Roll + Altitude + Yaw)
    local altCmd = 0
    if self.ap.altHold then
        altCmd = self.altPID:compute(self.ap.targetAlt, tel.altitude, dt)
    end
    local pitchTrim = 0
    local rollTrim  = 0
    if self.ap.sasEnabled then
        pitchTrim = self.msPitchPID:compute(0, tel.pitch, dt)
        rollTrim  = self.msRollPID:compute(0, tel.roll, dt)
    end

    local liftFL, liftFR, liftRL, liftRR = 0, 0, 0, 0
    if not (not self.ap.enabled and self.ap.parkingBrake) then
        local hoverBase = self.ap.altHold and 8.0 or mainThrottleSig
        liftFL = math.floor(clamp(hoverBase + altCmd + pitchTrim + rollTrim, 0, 15) + 0.5)
        liftFR = math.floor(clamp(hoverBase + altCmd + pitchTrim - rollTrim, 0, 15) + 0.5)
        liftRL = math.floor(clamp(hoverBase + altCmd - pitchTrim + rollTrim, 0, 15) + 0.5)
        liftRR = math.floor(clamp(hoverBase + altCmd - pitchTrim - rollTrim, 0, 15) + 0.5)
    end

    local fwdSig = self.ap.parkingBrake and 0 or (revActive and -mainThrottleSig or mainThrottleSig)
    local turnYaw = self.ap.hdgHold and yawDiff or ((steerVal ~= 0 and (steerVal * 6.0)) or (self.ap.manualYaw or 0))
    local rearL = math.floor(clamp(fwdSig - turnYaw, -15, 15) + 0.5)
    local rearC = math.floor(clamp(fwdSig, -15, 15) + 0.5)
    local rearR = math.floor(clamp(fwdSig + turnYaw, -15, 15) + 0.5)

    self.lastMothershipState = {
        fl    = liftFL,
        fr    = liftFR,
        rl    = liftRL,
        rr    = liftRR,
        rearL = rearL,
        rearC = rearC,
        rearR = rearR
    }
    tel.mothership = self.lastMothershipState

    -- Route custom I/O role mappings (Hot-plug peripherals, Mothership 7-motor roles & Redstone sides)
    local function routeCustomRoleDevices(bSig)
        for _, item in ipairs(self.ioDevices or {}) do
            local cfg = self:getDeviceConfig(item.name)
            local role = cfg.role
            local inv = cfg.invert == true

            -- Spin Test Override ([T] in I/O Configurator)
            if self.spinTest and self.spinTest.name == item.name and not item.isRedstone and item.handle then
                local dev = item.handle
                table.insert(tasks, function()
                    driveSignal(dev, 8, inv)
                end)
            elseif role ~= "AUTO" or (inv and item.isRedstone) then
                local sig = nil
                local boolState = nil
                if role == "IGNORE" then
                    sig = nil
                elseif role == "LIFT_FL" then
                    sig = liftFL
                elseif role == "LIFT_FR" then
                    sig = liftFR
                elseif role == "LIFT_RL" then
                    sig = liftRL
                elseif role == "LIFT_RR" then
                    sig = liftRR
                elseif role == "REAR_LEFT" then
                    sig = rearL
                elseif role == "REAR_CENTER" then
                    sig = rearC
                elseif role == "REAR_RIGHT" then
                    sig = rearR
                elseif role == "LIFT_BURNER" or (role == "AUTO" and item.isRedstone) then
                    sig = bSig
                elseif role == "THRUST_MAIN" then
                    sig = mainThrottleSig
                elseif role == "THRUST_PORT" then
                    sig = portSignal
                elseif role == "THRUST_STBD" then
                    sig = stbdSignal
                elseif role == "AUX_BOOST" then
                    sig = boostSignal
                elseif role == "CLUTCH_BRAKE" then
                    boolState = not clutchCut
                    sig = clutchCut and 0 or math.max(1, mainThrottleSig)
                elseif role == "GEAR_REVERSE" then
                    boolState = revActive
                    sig = revActive and 15 or 0
                elseif role == "RUDDER_YAW" then
                    sig = math.floor(clamp(8 + steerVal * 7, 0, 15))
                end

                if item.isRedstone and sig ~= nil and redstone and redstone.setAnalogOutput then
                    local clamped = math.floor(clamp(math.abs(sig), 0, 15))
                    local outSig = inv and (15 - clamped) or clamped
                    pcall(redstone.setAnalogOutput, item.side, outSig)
                elseif not item.isRedstone and item.handle and role ~= "IGNORE" then
                    local dev = item.handle
                    table.insert(tasks, function()
                        if role == "RUDDER_YAW" and dev.setSteering then
                            safeCall(dev.setSteering, inv and -steerVal or steerVal)
                        elseif boolState ~= nil then
                            driveBooleanOrSignal(dev, boolState, sig or 0, inv)
                        elseif sig ~= nil then
                            driveSignal(dev, sig, inv)
                        end
                    end)
                end
            end
        end
    end

    -- If Autopilot is disabled, apply baseThrottle to gearboxes/throttles and clear manual gyro locks
    if not self.ap.enabled then
        self.lastBurnerSignal = mainThrottleSig
        tel.burnerCmd = mainThrottleSig
        if self.vehicleType ~= "MOTHERSHIP" then
            for _, gb in ipairs(self.gearboxes) do
                table.insert(tasks, function() driveSignal(gb, mainThrottleSig, false) end)
            end
        end
        if self.vehicleType == "ZEPPELIN" then
            emitRedstoneBurner(mainThrottleSig)
            for _, thr in ipairs(self.throttles) do
                table.insert(tasks, function() driveSignal(thr, mainThrottleSig, false) end)
            end
        end
        for _, gyro in ipairs(self.gyros) do
            if gyro.clearManualTarget then
                table.insert(tasks, function() safeCall(gyro.clearManualTarget) end)
            end
        end
        routeCustomRoleDevices(mainThrottleSig)
        if #tasks > 0 and parallel and parallel.waitForAll then
            parallel.waitForAll(table.unpack(tasks))
        end
        return tel
    end

    -- 2. Differential Thrust on Analog Transmissions (for non-Mothership or unassigned gearboxes)
    if self.vehicleType ~= "MOTHERSHIP" then
        if #self.gearboxes >= 2 then
            table.insert(tasks, function() driveSignal(self.gearboxes[1], portSignal, false) end)
            table.insert(tasks, function() driveSignal(self.gearboxes[2], stbdSignal, false) end)
        elseif #self.gearboxes == 1 then
            table.insert(tasks, function() driveSignal(self.gearboxes[1], mainThrottleSig, false) end)
        end
    end

    -- 3. Altitude PID & Attitude Stabilization
    if self.ap.altHold then
        if self.vehicleType == "ZEPPELIN" then
            burnerSignal = math.floor(clamp(8 + altCmd, 0, 15))
            self.lastBurnerSignal = burnerSignal
            tel.burnerCmd = burnerSignal
            emitRedstoneBurner(burnerSignal)
            for _, thr in ipairs(self.throttles) do
                table.insert(tasks, function() driveSignal(thr, burnerSignal, false) end)
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

    routeCustomRoleDevices(burnerSignal)

    -- Execute all mainThread actuator setters in parallel within a single server tick
    if #tasks > 0 and parallel and parallel.waitForAll then
        parallel.waitForAll(table.unpack(tasks))
    end

    return tel
end

return Avionics
