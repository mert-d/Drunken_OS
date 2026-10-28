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
        setIntegral = function(self, val)
            integral = math.max(minOut, math.min(maxOut, tonumber(val) or 0))
        end,
        getIntegral = function(self)
            return integral
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

-- Resolves the specific control ID belonging to `dev` (or matching `roleHint` such as "clutch" / "gearshift")
-- Prevents cross-talk when multiple kinetic blocks (e.g. Inverted Clutch + Gearshift) share the same Create shaft network
local function callKineticRole(dev, roleHint, fn, ...)
    if type(fn) ~= "function" then return nil end
    local isForeign = (roleHint == "foreign_gearshift")
    if not isForeign then
        local ok, res = pcall(fn, ...)
        if ok then return res end
    end
    if type(dev) ~= "table" then return nil end

    local beId = (type(dev.getBlockEntityId) == "function") and safeCall(dev.getBlockEntityId) or nil
    local blkId = (type(dev.getBlockId) == "function") and safeCall(dev.getBlockId) or nil
    local pName = (peripheral and peripheral.getName and pcall(peripheral.getName, dev) and peripheral.getName(dev)) or nil
    local pType = (peripheral and peripheral.getType and pcall(peripheral.getType, dev) and peripheral.getType(dev)) or nil

    local kw = isForeign and "gearshift" or (roleHint and roleHint:lower() or nil)
    if not kw then
        local combined = (tostring(blkId or "") .. " " .. tostring(pType or "") .. " " .. tostring(pName or "")):lower()
        if combined:find("gearshift") then kw = "gearshift"
        elseif combined:find("clutch") then kw = "clutch" end
    end
    local otherKw = (kw == "gearshift" and "clutch") or (kw == "clutch" and "gearshift") or nil

    -- 1. If targeting `dev` itself, try its own BlockEntityId first!
    if not isForeign and beId ~= nil and type(beId) ~= "table" then
        local okBe, resBe = pcall(fn, tostring(beId), ...)
        if okBe then return resBe end
    end

    -- 2. Inspect listControls() and match by exact BlockEntityId, peripheral name, or role keyword ("gearshift" vs "clutch")
    if type(dev.listControls) == "function" then
        local okC, ctrls = pcall(dev.listControls)
        if okC and type(ctrls) == "table" then
            local entries = {}
            for k, v in pairs(ctrls) do
                local cid = nil
                local metaParts = { tostring(k) }
                if type(v) == "string" then
                    cid = (type(k) == "string" and not k:match("^%d+$")) and k or v
                    table.insert(metaParts, v)
                elseif type(v) == "table" then
                    cid = v.id or v.blockEntityId or v.control or v.name or (type(k) == "string" and k or nil)
                    for tk, tv in pairs(v) do
                        if type(tv) == "string" or type(tv) == "number" then
                            table.insert(metaParts, tostring(tk) .. ":" .. tostring(tv))
                        end
                    end
                elseif type(k) == "string" then
                    cid = k
                end
                if type(cid) == "string" or type(cid) == "number" then
                    table.insert(entries, {
                        id   = tostring(cid),
                        alt  = (type(v) == "string") and v or nil,
                        meta = table.concat(metaParts, " "):lower()
                    })
                end
            end

            -- Pass A: Exact BlockEntityId or peripheral name match (when controlling `dev` itself)
            if not isForeign then
                for _, e in ipairs(entries) do
                    if (beId and (e.id == tostring(beId) or e.meta:find(tostring(beId):lower(), 1, true)))
                        or (pName and (e.id == tostring(pName) or e.meta:find(tostring(pName):lower(), 1, true))) then
                        local okE, resE = pcall(fn, e.id, ...)
                        if okE then return resE end
                        if e.alt and e.alt ~= e.id then
                            local okA, resA = pcall(fn, e.alt, ...)
                            if okA then return resA end
                        end
                    end
                end
            end

            -- Pass B: Role keyword match ("gearshift" vs "clutch") without matching the opposite role
            if kw then
                for _, e in ipairs(entries) do
                    if e.meta:find(kw, 1, true) and (not otherKw or not e.meta:find(otherKw, 1, true)) then
                        local okE, resE = pcall(fn, e.id, ...)
                        if okE then return resE end
                        if e.alt and e.alt ~= e.id then
                            local okA, resA = pcall(fn, e.alt, ...)
                            if okA then return resA end
                        end
                    end
                end
            end

            -- Pass C: Fallback to non-conflicting entries only when not searching for a foreign roleHint
            if not isForeign then
                for _, e in ipairs(entries) do
                    if not otherKw or not e.meta:find(otherKw, 1, true) then
                        local okE, resE = pcall(fn, e.id, ...)
                        if okE then return resE end
                        if e.alt and e.alt ~= e.id then
                            local okA, resA = pcall(fn, e.alt, ...)
                            if okA then return resA end
                        end
                    end
                end
            end
        end
    end

    if not isForeign then
        for _, idGetter in ipairs({ "getBlockEntityId", "getBlockId", "getNetworkId" }) do
            if type(dev[idGetter]) == "function" then
                local okId, id = pcall(dev[idGetter])
                if okId and id ~= nil then
                    local ok3, res3 = pcall(fn, tostring(id), ...)
                    if ok3 then return res3 end
                end
            end
        end
        if pName then
            local okP, resP = pcall(fn, pName, ...)
            if okP then return resP end
        end
        for _, face in ipairs({ "north", "south", "east", "west", "up", "down", "main", "default" }) do
            local okF, resF = pcall(fn, face, ...)
            if okF then return resF end
        end
    end
    return nil
end

local function callKinetic(dev, fn, ...)
    return callKineticRole(dev, nil, fn, ...)
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
    self.profile = self.config.profile or nil -- "ZEPPELIN", "AIRCRAFT", "MOTHERSHIP", "GUNSHIP", or nil (auto)
    self.hasSavedProfile = false
    self.ioMap = {}
    self.ioDevices = {}
    self.clutchPolarInvert = false -- Auto or manual [K] polarity inversion for clutches
    self.clutchSpinTicks = 0
    self.prevAlt = nil

    self:loadIOMap()
    self:scanPeripherals()

    local startParked = (self.config.startParked == true)

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
        baseThrottle = startParked and 0 or 8, -- 0..15 Redstone/Transmission scale (or 0..256 RPM scale)
        manualYaw    = 0,        -- -5..+5 manual rudder/thruster turn trim
        parkingBrake = startParked,
        reverseGear  = false,    -- Gearshift / Reverse Thrust toggle ([G])
        waypoint     = nil,      -- { x = 0, y = 120, z = 0, name = "HOME" }
        homeBase     = nil,      -- ILS Beacon packet or manual base table
        rtbPhase     = "NONE",   -- NONE, RTB_IAF, RTB_ILS, RTB_MAST
        ilsDev       = { loc = 0.0, gs = 0.0, dist = 0.0 }
    }

    -- Dead-Reckoning Position Estimate & GPS Tick Throttle
    self.pos = { x = 0, y = 0, z = 0 }
    self.gpsTick = 0

    -- PID Controllers (Smooth proportional + derivative damping for equilibrium altitude hold)
    self.altPID   = createPID(1.6, 0.35, 2.2, -8.0, 7.0)
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
                or k:find("sequenced_gearshift") or k:find("throttle_lever")
                or k:find("bearing") or k:find("propeller") then
                table.insert(candidates, item.name)
            end
        end
    end
    local assignedCount = 0
    for _, devName in ipairs(candidates) do
        local cfg = self:getDeviceConfig(devName)
        if forceOverwrite or cfg.role == "AUTO" then
            local n = devName:lower()
            local posRole = nil
            if n:find("fore") and n:find("port") then
                posRole = "LIFT_FL"
            elseif n:find("fore") and (n:find("starboard") or n:find("stbd")) then
                posRole = "LIFT_FR"
            elseif n:find("aft") and n:find("port") then
                if n:find("rear") or n:find("thruster") then posRole = "REAR_LEFT" else posRole = "LIFT_RL" end
            elseif n:find("aft") and (n:find("starboard") or n:find("stbd")) then
                if n:find("rear") or n:find("thruster") then posRole = "REAR_RIGHT" else posRole = "LIFT_RR" end
            elseif n:find("aft") and (n:find("center") or n:find("mid")) then
                posRole = "REAR_CENTER"
            end

            if posRole then
                cfg.role = posRole
            else
                assignedCount = assignedCount + 1
                if assignedCount <= #Avionics.MOTHERSHIP_ROLES then
                    cfg.role = Avionics.MOTHERSHIP_ROLES[assignedCount]
                end
            end
        end
    end
    self:saveIOMap()
end

function Avionics:setVehicleProfile(profileName, forceAutoAssign)
    self.profile = profileName
    self.hasSavedProfile = true
    self.vehicleType = profileName
    if profileName == "MOTHERSHIP" or profileName == "GUNSHIP" then
        self:autoAssignMothershipRoles(forceAutoAssign)
    else
        -- Clear Mothership-specific roles when switching back to ZEPPELIN or AIRCRAFT
        local msRoleSet = {}
        for _, r in ipairs(Avionics.MOTHERSHIP_ROLES) do msRoleSet[r] = true end
        for _, cfg in pairs(self.ioMap or {}) do
            if type(cfg) == "table" and msRoleSet[cfg.role] then
                cfg.role = "AUTO"
            end
        end
    end
    self:saveIOMap()
end

function Avionics:toggleClutchPolarity()
    self.clutchPolarInvert = not self.clutchPolarInvert
    return self.clutchPolarInvert
end

function Avionics:scanPeripherals()
    -- Sensors
    self.altSensor   = peripheral and peripheral.find and peripheral.find("altitude_sensor")
    self.gimbal      = peripheral and peripheral.find and peripheral.find("gimbal_sensor")
    self.nav         = peripheral and peripheral.find and peripheral.find("navigation_table")
    self.velSensor   = peripheral and peripheral.find and peripheral.find("velocity_sensor")
    self.velSensors  = (peripheral and peripheral.find and { peripheral.find("velocity_sensor") }) or {}
    self.laserSensor = peripheral and peripheral.find and peripheral.find("laser_sensor")
    self.steerWheel  = peripheral and peripheral.find and peripheral.find("steering_wheel")
    self.typewriter  = peripheral and peripheral.find and peripheral.find("linked_typewriter")
    self.radar       = peripheral and peripheral.find and peripheral.find("radar")
    self.controller  = peripheral and peripheral.find and peripheral.find("avionics_controller")

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
        self.clutches    = {}
        for _, cType in ipairs({ "create_connected_inverted_clutch", "inverted_clutch", "create_clutch", "clutch" }) do
            local found = { peripheral.find(cType) }
            for _, c in ipairs(found) do table.insert(self.clutches, c) end
        end
        self.gearshifts  = {}
        for _, gType in ipairs({
            "create_gearshift",
            "gearshift",
            "create:gearshift",
            "create_sequenced_gearshift",
            "sequenced_gearshift",
            "create_connected_gearshift",
            "create_connected_sequenced_gearshift",
            "redstone_relay"
        }) do
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

    local function addUniqueHandle(list, h)
        if not h then return end
        local hName = (peripheral and peripheral.getName and pcall(peripheral.getName, h) and peripheral.getName(h)) or nil
        for _, existing in ipairs(list) do
            if existing == h then return end
            if hName and peripheral and peripheral.getName then
                local okE, eName = pcall(peripheral.getName, existing)
                if okE and eName == hName then return end
            end
        end
        table.insert(list, h)
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
                    local h = okW and handle or nil
                    local bId = (h and type(h.getBlockId) == "function" and tostring(safeCall(h.getBlockId) or "")) or ""
                    local combined = (pStr .. " " .. name .. " " .. bId):lower()
                    if h then
                        if combined:find("gearshift") or combined:find("redstone_relay") then
                            addUniqueHandle(self.gearshifts, h)
                        elseif combined:find("clutch") then
                            addUniqueHandle(self.clutches, h)
                        end
                    end
                    self:getDeviceConfig(name)
                    table.insert(self.ioDevices, {
                        name       = name,
                        kind       = pStr,
                        handle     = h,
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
    if self.profile == "MOTHERSHIP" or self.profile == "GUNSHIP" or self.profile == "ZEPPELIN" or self.profile == "AIRCRAFT" then
        self.vehicleType = self.profile
        if self.profile == "MOTHERSHIP" or self.profile == "GUNSHIP" then
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
    local sensorVsi = 0
    local pressure = 1.0
    if self.altSensor then
        alt = tonumber(safeCall(self.altSensor.getHeight))
           or tonumber(safeCall(self.altSensor.getAltitude))
           or 0
        sensorVsi = tonumber(safeCall(self.altSensor.getVerticalSpeed)) or 0
        pressure = tonumber(safeCall(self.altSensor.getAirPressure)) or 1.0
    end
    local vsi = sensorVsi
    if self.prevAlt ~= nil and dt > 0 then
        local rawDeltaVsi = clamp((alt - self.prevAlt) / dt, -20.0, 20.0)
        self.smoothVsi = (self.smoothVsi or 0) * 0.80 + rawDeltaVsi * 0.20
        if sensorVsi == 0 and math.abs(self.smoothVsi) > 0.05 then
            vsi = self.smoothVsi
        end
    end
    self.prevAlt = alt

    -- 2. Attitude (Pitch, Roll, Linear Acceleration from Create: Avionics Gimbal Sensor)
    local pitch, roll = 0, 0
    local linAcc = { x = 0, y = 0, z = 0, 0, 0, 0 }
    if self.gimbal then
        local rads = safeCall(self.gimbal.getAnglesRad)
        if type(rads) == "table" and rads[1] and rads[2] then
            pitch = tonumber(rads[1]) or 0
            roll  = tonumber(rads[2]) or 0
        else
            local degs = safeCall(self.gimbal.getAngles)
            if type(degs) == "table" and degs[1] and degs[2] then
                pitch = math.rad(tonumber(degs[1]) or 0)
                roll  = math.rad(tonumber(degs[2]) or 0)
            else
                pitch = tonumber(safeCall(self.gimbal.getPitch)) or 0
                roll  = tonumber(safeCall(self.gimbal.getRoll)) or 0
            end
        end
        local acc = safeCall(self.gimbal.getLinearAcceleration)
        if type(acc) == "table" then
            local ax = tonumber(acc[1] or acc.x) or 0
            local ay = tonumber(acc[2] or acc.y) or 0
            local az = tonumber(acc[3] or acc.z) or 0
            linAcc = { x = ax, y = ay, z = az, ax, ay, az }
        end
    end

    -- 3. Heading & Navigation Target (Create: Avionics Navigation Table)
    local heading = 0
    local navTarget = nil
    if self.nav then
        local hRad = tonumber(safeCall(self.nav.getHeadingRad))
        if hRad then
            heading = hRad
        else
            local hDeg = tonumber(safeCall(self.nav.getHeading))
            if hDeg then heading = math.rad(hDeg) end
        end

        local hasTgt = safeCall(self.nav.hasTarget)
        if hasTgt == true then
            local tName = safeCall(self.nav.getTargetName) or safeCall(self.nav.getTargetDisplayName) or "WAYPOINT"
            local brgRad = tonumber(safeCall(self.nav.getBearingRad))
            if brgRad == nil and self.nav.getBearing then
                local bDeg = tonumber(safeCall(self.nav.getBearing))
                if bDeg then brgRad = math.rad(bDeg) end
            end
            local dist = tonumber(safeCall(self.nav.getDistanceToTarget))
            local vOff = tonumber(safeCall(self.nav.getVerticalOffsetToTarget))
            local closure = tonumber(safeCall(self.nav.getClosureRate))
            navTarget = {
                active   = true,
                name     = tostring(tName),
                bearing  = brgRad or 0,
                distance = dist or 0,
                vOffset  = vOff or 0,
                closure  = closure or 0
            }
        end
    end

    -- 4. Velocity & Airspeed (Multi-sensor body reconstruction or single-axis sensor)
    local vel = { x = 0, y = vsi, z = 0 }
    local speed = 0
    local rawVel = 0
    local velSensList = (self.velSensors and #self.velSensors > 0) and self.velSensors or (self.velSensor and { self.velSensor } or {})
    if #velSensList > 0 then
        local reconstructed = false
        if #velSensList >= 2 then
            local hasX, hasZ = false, false
            for _, vs in ipairs(velSensList) do
                local axis = tostring(safeCall(vs.getAxis) or ""):lower()
                local val = tonumber(safeCall(vs.getVelocity)) or 0
                if axis == "x" then vel.x = val; hasX = true
                elseif axis == "z" then vel.z = val; hasZ = true
                elseif axis == "y" then vel.y = val
                end
            end
            if hasX or hasZ then
                reconstructed = true
                speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
                rawVel = speed
            end
        end
        if not reconstructed then
            local vs = velSensList[1]
            local v = safeCall(vs.getVelocity)
            if type(v) == "table" then
                vel.x = tonumber(v[1] or v.x) or 0
                vel.y = tonumber(v[2] or v.y) or vsi
                vel.z = tonumber(v[3] or v.z) or 0
                speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
                rawVel = speed
            elseif type(v) == "number" then
                rawVel = v
                speed = math.abs(v)
                local horizSpeed = math.sqrt(math.max(0, speed * speed - vsi * vsi))
                local dirSign = (self.ap and self.ap.reverseGear) and -1 or 1
                vel.x = -horizSpeed * math.sin(heading) * dirSign
                vel.z =  horizSpeed * math.cos(heading) * dirSign
            end
        end
    end

    -- Update Position (INS Dead-Reckoning every tick + GPS sync when available)
    self.pos.x = self.pos.x + vel.x * dt
    self.pos.y = alt
    self.pos.z = self.pos.z + vel.z * dt

    if self.config.useGPS and gps and gps.locate and (self.gpsTick % 40 == 1) then
        local okGps, gx, gy, gz = pcall(gps.locate, 0.05)
        if okGps and gx and gz then
            self.pos.x, self.pos.z = gx, gz
            if not self.altSensor and gy then
                self.pos.y = gy
            end
            self.gpsLocked = true
        else
            self.gpsLocked = false
        end
    end

    -- 5. Laser Radar Altimeter (AGL - Create: Avionics Laser Sensor)
    local agl = nil
    if self.laserSensor then
        agl = tonumber(safeCall(self.laserSensor.getClosestHitDistance))
           or tonumber(safeCall(self.laserSensor.getDistance))
           or tonumber(safeCall(self.laserSensor.getHitDistance))
    end

    -- 5b. Radar Mk.1 Beam & Contact Processing
    local radarContact = nil
    local radarGpws = false
    if self.radar then
        local contact = safeCall(self.radar.getContact)
        if type(contact) == "table" then
            radarContact = {
                kind         = contact.kind,
                distance     = tonumber(contact.distance) or 0,
                closingSpeed = tonumber(contact.closingSpeed) or 0,
                name         = contact.name
            }
            if contact.kind == "terrain" and (tonumber(contact.distance) or 999) < 40 and (tonumber(contact.closingSpeed) or 0) > 2 then
                radarGpws = true
            end
        end
    end

    -- 6. Weight-on-Wheels & Landing Gear Retraction (Create: Avionics Wheel Mount)
    local weightOnWheels = false
    local gearRetracted = false
    for _, w in ipairs(self.wheels) do
        local fric = tonumber(safeCall(w.getTouchingFriction)) or 0
        if fric > 0 then
            weightOnWheels = true
        end
        if safeCall(w.isLiftedUp) == true then
            gearRetracted = true
        end
    end

    -- 7. Engine, Clutch & Burner SCADA (RPM, Overstress, Burner Signal, Balloon Volume Change)
    local maxRpm = 0
    local clutchOutRpm = nil
    local overstressed = false
    local gasType = "NONE"
    local burnerActual = 0
    local burnerActive = false
    local balloonVolChange = 0

    local totalFuel = 0
    local maxFuel = 0
    for _, eng in ipairs(self.engines) do
        local engRpm = tonumber(safeCall(eng.getRpm)) or tonumber(safeCall(eng.getSpeed)) or 0
        maxRpm = math.max(maxRpm, math.abs(engRpm))
        if safeCall(eng.isOverstressed) == true then
            overstressed = true
        end
        local bTime = tonumber(safeCall(eng.getBurnTime))
        local tTime = tonumber(safeCall(eng.getTotalBurnTime))
        if bTime and tTime and tTime > 0 then
            totalFuel = totalFuel + bTime
            maxFuel = maxFuel + tTime
        end
    end

    for _, cl in ipairs(self.clutches or {}) do
        local outSpd = tonumber(callKinetic(cl, cl.getOutputSpeed))
        if outSpd ~= nil then
            clutchOutRpm = math.max(clutchOutRpm or 0, math.abs(outSpd))
        end
        local clRpm = outSpd
                   or tonumber(callKinetic(cl, cl.getSpeed))
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
        local vc = tonumber(safeCall(b.getBalloonVolumeChange))
        if vc ~= nil then
            balloonVolChange = balloonVolChange + vc
        end
    end

    -- 8. Warnings (GPWS & Stall)
    local gpwsWarning = ((agl ~= nil and agl < 12 and vsi < -3.5 and not weightOnWheels) or radarGpws)
    local stallWarning = (self.vehicleType == "AIRCRAFT" and not weightOnWheels and speed < 3.0 and pitch > math.rad(15))

    return {
        callsign         = self.callsign,
        vehicleType      = self.vehicleType,
        altitude         = alt,
        agl              = agl,
        vSpeed           = vsi,
        pressure         = pressure,
        pitch            = pitch,
        roll             = roll,
        heading          = heading,
        speed            = speed,
        velocity         = vel,
        linAcc           = linAcc,
        pos              = { x = self.pos.x, y = self.pos.y, z = self.pos.z },
        weightOnWheels   = weightOnWheels,
        rpm              = maxRpm,
        clutchOutRpm     = clutchOutRpm,
        overstressed     = overstressed,
        gasType          = gasType,
        burnerCmd        = self.lastBurnerSignal or 0,
        burnerActual     = burnerActual,
        burnerActive     = burnerActive,
        balloonVolChange = balloonVolChange,
        mothership       = self.lastMothershipState or { fl = 0, fr = 0, rl = 0, rr = 0, rearL = 0, rearC = 0, rearR = 0 },
        gpwsWarning      = gpwsWarning,
        stallWarning     = stallWarning,
        fuelPct          = (maxFuel > 0 and (totalFuel / maxFuel)) or 1.0,
        navTarget        = navTarget,
        radarContact     = radarContact,
        gearRetracted    = gearRetracted,
        transponder      = (self.controller and safeCall(self.controller.isTransponderOn) == true)
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
    self.ap.parkingBrake = false
    self.ap.mode     = "RTB"

    if (self.vehicleType == "ZEPPELIN" or self.vehicleType == "MOTHERSHIP" or self.vehicleType == "GUNSHIP") and self.ap.homeBase.zeppelinMast then
        self.ap.rtbPhase = "RTB_MAST"
    else
        self.ap.rtbPhase = "RTB_IAF"
    end
    local prevInt = self.ap.altHold and self.altPID:getIntegral() or 1.0
    self.altPID:reset()
    self.altPID:setIntegral(prevInt)
    self.hdgPID:reset()
    return true
end

function Avionics:setMode(modeName, currentTel)
    local wasAltHold = self.ap.altHold
    local savedIntegral = self.altPID:getIntegral()
    self.ap.mode = modeName
    self.altPID:reset()
    self.hdgPID:reset()
    self.pitchPID:reset()
    self.rollPID:reset()
    self.msPitchPID:reset()
    self.msRollPID:reset()

    -- Preserve learned equilibrium integral when switching between autopilot modes; use gentle 1.0 (burner=9) from MANUAL
    local bumplessInt = wasAltHold and savedIntegral or clamp((self.lastBurnerSignal and self.lastBurnerSignal > 0) and (self.lastBurnerSignal - 8.0) or 1.0, 0.0, 3.0)

    if modeName == "MANUAL" then
        self.ap.enabled = false
        self.ap.altHold = false
        self.ap.hdgHold = false
        self.ap.rtbPhase = "NONE"
    elseif modeName == "CRUISE" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
        self.ap.parkingBrake = false
        if self.ap.baseThrottle <= 0 then
            self.ap.baseThrottle = 8
        end
        if currentTel then
            self.ap.targetAlt = math.floor(currentTel.altitude + 0.5)
            self.ap.targetHdg = currentTel.heading
        end
        self.altPID:setIntegral(bumplessInt)
    elseif modeName == "HOVER" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
        self.ap.baseThrottle = 0
        self.ap.parkingBrake = true -- Strictly cut forward propeller/clutch while hovering
        self.ap.manualYaw = 0
        if currentTel then
            self.ap.targetAlt = math.floor(currentTel.altitude + 0.5)
            self.ap.targetHdg = currentTel.heading
        end
        self.altPID:setIntegral(bumplessInt)
    elseif modeName == "LNAV" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
        self.ap.parkingBrake = false
        if self.ap.baseThrottle <= 0 then
            self.ap.baseThrottle = 8
        end
        self.altPID:setIntegral(bumplessInt)
    elseif modeName == "AUTOLAND" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
    elseif modeName == "RTB" then
        self:engageRTB(currentTel)
    end
end

function Avionics:executeAtcCommand(msg, currentTel)
    if type(msg) ~= "table" or msg.type ~= "AVIONICS_ATC_CMD" then
        return false, nil
    end
    local myCall = (currentTel and currentTel.callsign) or self.callsign
    if msg.target and msg.target ~= "ALL" and msg.target ~= myCall then
        return false, nil
    end

    if type(msg.beacon) == "table" and msg.beacon.type == "AVIONICS_ILS_BEACON" then
        self:setHomeBase(msg.beacon)
    end

    local cmd = tostring(msg.cmd or ""):upper()
    if cmd == "RTB" then
        if self:engageRTB(currentTel) then
            local bName = (self.ap.homeBase and self.ap.homeBase.baseName) or "KULE"
            return true, "ATC KULE EMRI: RTB -> " .. tostring(bName)
        end
        return false, "ATC KULE EMRI: RTB BASARISIZ (BEACON YOK)"
    elseif cmd == "HOVER" then
        self:setMode("HOVER", currentTel)
        if tonumber(msg.targetAlt) then
            self.ap.targetAlt = tonumber(msg.targetAlt)
        end
        return true, string.format("ATC KULE EMRI: HOVER (%.0fm)", self.ap.targetAlt)
    elseif cmd == "AUTOLAND" then
        self:setMode("AUTOLAND", currentTel)
        return true, "ATC KULE EMRI: OTONOM INIS (AUTOLAND)"
    elseif cmd == "PARK" then
        self.ap.baseThrottle = 0
        self.ap.parkingBrake = true
        self:setMode("MANUAL", currentTel)
        return true, "ATC KULE EMRI: ACIL PARK & MOTOR KESME"
    elseif cmd == "ALT_DELTA" then
        local delta = tonumber(msg.delta) or 0
        local baseAlt = self.ap.enabled and self.ap.targetAlt or ((currentTel and currentTel.altitude) or self.ap.targetAlt)
        local newAlt = clamp(baseAlt + delta, 10, 320)
        if not self.ap.enabled then
            self:setMode("HOVER", currentTel)
        end
        self.ap.targetAlt = newAlt
        return true, string.format("ATC IRTIFA EMRI: %.0fm (%+dm)", self.ap.targetAlt, delta)
    elseif cmd == "WAYPOINT" or cmd == "LNAV" then
        if type(msg.waypoint) == "table" and msg.waypoint.x and msg.waypoint.z then
            self.ap.waypoint = {
                x = tonumber(msg.waypoint.x) or 0,
                y = tonumber(msg.waypoint.y) or self.ap.targetAlt,
                z = tonumber(msg.waypoint.z) or 0
            }
            self.ap.targetAlt = self.ap.waypoint.y
            self:setMode("LNAV", currentTel)
            return true, string.format("ATC ROTA EMRI: (%d, %d, %d)", self.ap.waypoint.x, self.ap.waypoint.y, self.ap.waypoint.z)
        end
    elseif cmd == "INS_SYNC" then
        if type(msg.pos) == "table" and msg.pos.x and msg.pos.z then
            self.pos.x = tonumber(msg.pos.x) or 0
            self.pos.z = tonumber(msg.pos.z) or 0
            return true, string.format("ATC INS KALIBRASYON: (%d, %d, %d)", self.pos.x, math.floor(self.pos.y), self.pos.z)
        end
    end
    return false, nil
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

    -- Enforce zero forward throttle in HOVER mode; in other modes, advancing throttle > 0 releases parking brake
    if self.ap.mode == "HOVER" then
        self.ap.baseThrottle = 0
        self.ap.parkingBrake = true
    elseif self.ap.parkingBrake and self.ap.baseThrottle > 0 then
        self.ap.parkingBrake = false
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
        elseif self.vehicleType == "ZEPPELIN" or self.vehicleType == "MOTHERSHIP" or self.vehicleType == "GUNSHIP" then
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

    -- Supports Create Rotation Speed Controllers (-256..+256 RPM) and 0..15 Signal / Throttle Lever peripherals
    local function driveSignal(dev, sig, inv)
        if dev.setTargetSpeed then
            local rpm = math.floor((sig / 15.0) * 256 + 0.5)
            if inv then rpm = -rpm end
            callKinetic(dev, dev.setTargetSpeed, rpm)
            return
        end
        local clampedSig = math.floor(clamp(math.abs(sig), 0, 15))
        local outSig = inv and (15 - clampedSig) or clampedSig
        local called = false
        if dev.setSignal then callKinetic(dev, dev.setSignal, outSig); called = true end
        if dev.setThrottle then callKinetic(dev, dev.setThrottle, outSig); called = true end
        if dev.setControl then callKinetic(dev, dev.setControl, outSig); called = true end
        if dev.setTarget then callKinetic(dev, dev.setTarget, outSig); called = true end
        if dev.setLevel then callKinetic(dev, dev.setLevel, outSig); called = true end
        if dev.setOutput then callKinetic(dev, dev.setOutput, outSig); called = true end
        if dev.setSignalStrength then callKinetic(dev, dev.setSignalStrength, outSig); called = true end
        if not called and dev.setSpeed then callKinetic(dev, dev.setSpeed, outSig) end
    end

    local function driveBooleanOrSignal(dev, active, sigVal, inv, roleHint)
        local finalActive = inv and (not active) or active
        local finalSig = inv and (15 - sigVal) or sigVal
        local called = false
        if dev.setPowered then
            callKineticRole(dev, roleHint, dev.setPowered, finalActive)
            called = true
        end
        if dev.setSignal then
            callKineticRole(dev, roleHint, dev.setSignal, finalSig)
            called = true
        end
        if not called and dev.setControl then
            callKineticRole(dev, roleHint, dev.setControl, finalSig)
            called = true
        end
        if dev.setAnalogOutput then
            for _, s in ipairs({ "front", "back", "left", "right", "top", "bottom" }) do
                pcall(dev.setAnalogOutput, s, finalSig)
            end
            called = true
        elseif dev.setOutput then
            for _, s in ipairs({ "front", "back", "left", "right", "top", "bottom" }) do
                pcall(dev.setOutput, s, finalActive)
            end
            called = true
        end
        if not called then
            driveSignal(dev, sigVal, inv)
        end
    end

    -- Emits analog redstone for Zeppelin Hot Air Burners.
    -- When a `throttle_lever` peripheral is present, `AUTO` redstone sides stay at 0 unless directly touching a burner,
    -- preventing stray burner redstone from triggering adjacent clutches or gearshifts!
    local function emitRedstoneBurner(sig)
        if redstone and redstone.setAnalogOutput then
            for _, side in ipairs({ "left", "right", "front", "back", "top", "bottom" }) do
                local cfg = self:getDeviceConfig("RS:" .. side)
                if cfg.role == "LIFT_BURNER" then
                    local outSig = cfg.invert and (15 - sig) or sig
                    pcall(redstone.setAnalogOutput, side, outSig)
                elseif cfg.role == "AUTO" then
                    local isDirectBurner = false
                    local hasNonBurnerPeriph = false
                    if peripheral and peripheral.getType then
                        local okT, pType = pcall(peripheral.getType, side)
                        if okT and pType ~= nil then
                            local pStr = tostring(pType):lower()
                            if pStr:find("burner") or pStr:find("gas_provider") then
                                isDirectBurner = true
                            else
                                hasNonBurnerPeriph = true
                            end
                        end
                    end
                    if isDirectBurner or (#self.throttles == 0 and not hasNonBurnerPeriph) then
                        local outSig = cfg.invert and (15 - sig) or sig
                        pcall(redstone.setAnalogOutput, side, outSig)
                    else
                        pcall(redstone.setAnalogOutput, side, 0)
                    end
                end
            end
        end
    end

    -- 1. Landing Gear Brakes, Inverted Clutches, Gearshifts & Steering / Rudder Deflection
    local brakeVal = self.ap.parkingBrake and 1.0 or 0.0
    local steerVal = 0.0
    if self.steerWheel then
        steerVal = tonumber(safeCall(self.steerWheel.getNormalizedAngle))
           or (self.steerWheel.getAngle and (tonumber(safeCall(self.steerWheel.getAngle)) or 0) / 90.0)
           or tonumber(safeCall(self.steerWheel.getSteering))
           or 0.0
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

    -- Drive Create Clutches & Inverted Clutches (Propeller power cut / engagement)
    -- Steady-state deterministic polarity (no auto-flipping oscillation loop!)
    local clutchCut = (self.ap.mode == "HOVER") or self.ap.parkingBrake or (self.ap.baseThrottle <= 0)
    for _, cl in ipairs(self.clutches or {}) do
        local clName = (peripheral and peripheral.getName and pcall(peripheral.getName, cl) and peripheral.getName(cl)) or nil
        local clType = (clName and peripheral and peripheral.getType and pcall(peripheral.getType, clName) and peripheral.getType(clName)) or ""
        local clBlk  = (type(cl.getBlockId) == "function" and tostring(safeCall(cl.getBlockId) or "")) or ""
        local isNormalClutch = (not (tostring(clName or "") .. " " .. tostring(clType) .. " " .. clBlk):lower():find("inverted"))
            and ((tostring(clName or "") .. " " .. tostring(clType) .. " " .. clBlk):lower():find("clutch") ~= nil)
        local devInv = clName and self:getDeviceConfig(clName).invert or false
        local totalInv = (self.clutchPolarInvert ~= devInv)
        if isNormalClutch then totalInv = not totalInv end

        local engageActive = not clutchCut
        local engageSig = clutchCut and 0 or 15
        table.insert(tasks, function()
            driveBooleanOrSignal(cl, engageActive, engageSig, totalInv, "clutch")
        end)
    end

    -- Drive Gearshifts (Forward / Backward Movement via [G] or [W]/[S])
    local revActive = self.ap.reverseGear == true
    for _, gs in ipairs(self.gearshifts or {}) do
        local gsName = (peripheral and peripheral.getName and pcall(peripheral.getName, gs) and peripheral.getName(gs)) or nil
        local devInv = gsName and self:getDeviceConfig(gsName).invert or false
        table.insert(tasks, function()
            driveBooleanOrSignal(gs, revActive, revActive and 15 or 0, devInv, "gearshift")
        end)
    end
    -- Also support a Gearshift that shares the kinetic network (`listControls`) with a Clutch without a separate modem
    if #(self.gearshifts or {}) == 0 and #(self.clutches or {}) > 0 then
        local clHost = self.clutches[1]
        if type(clHost.listControls) == "function" then
            table.insert(tasks, function()
                if clHost.setPowered then callKineticRole(clHost, "foreign_gearshift", clHost.setPowered, revActive) end
                if clHost.setSignal then callKineticRole(clHost, "foreign_gearshift", clHost.setSignal, revActive and 15 or 0) end
            end)
        end
    end

    local mainThrottleSig = clutchCut and 0 or math.floor(clamp(self.ap.baseThrottle, 0, 15))
    local portSignal = clutchCut and 0 or math.floor(clamp(self.ap.baseThrottle - yawDiff, 0, 15))
    local stbdSignal = clutchCut and 0 or math.floor(clamp(self.ap.baseThrottle + yawDiff, 0, 15))
    local boostSignal = (not clutchCut and self.ap.baseThrottle >= 12) and 15 or 0
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
        local collectiveLift = self.ap.altHold and clamp(8.0 + altCmd, 3.0, 11.0) or mainThrottleSig
        liftFL = math.floor(clamp(collectiveLift + pitchTrim + rollTrim, 0, 15) + 0.5)
        liftFR = math.floor(clamp(collectiveLift + pitchTrim - rollTrim, 0, 15) + 0.5)
        liftRL = math.floor(clamp(collectiveLift - pitchTrim + rollTrim, 0, 15) + 0.5)
        liftRR = math.floor(clamp(collectiveLift - pitchTrim - rollTrim, 0, 15) + 0.5)
    end

    local fwdSig = clutchCut and 0 or (revActive and -mainThrottleSig or mainThrottleSig)
    local turnYaw = 0
    if not (not self.ap.enabled and self.ap.parkingBrake) then
        turnYaw = self.ap.hdgHold and yawDiff or ((steerVal ~= 0 and (steerVal * 6.0)) or (self.ap.manualYaw or 0))
    end
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

    -- If Autopilot is disabled, apply manual throttle (or 0 if parked) and clear manual gyro locks
    if not self.ap.enabled then
        local manualBurnerSig = self.ap.parkingBrake and 0 or mainThrottleSig
        self.lastBurnerSignal = manualBurnerSig
        tel.burnerCmd = manualBurnerSig
        if self.vehicleType ~= "MOTHERSHIP" and self.vehicleType ~= "GUNSHIP" then
            for _, gb in ipairs(self.gearboxes) do
                table.insert(tasks, function() driveSignal(gb, mainThrottleSig, false) end)
            end
        end
        if self.vehicleType == "ZEPPELIN" then
            emitRedstoneBurner(manualBurnerSig)
            for _, thr in ipairs(self.throttles) do
                table.insert(tasks, function() driveSignal(thr, manualBurnerSig, false) end)
            end
        end
        for _, gyro in ipairs(self.gyros) do
            if gyro.clearManualTarget then
                table.insert(tasks, function() safeCall(gyro.clearManualTarget) end)
            end
        end
        routeCustomRoleDevices(manualBurnerSig)
        if #tasks > 0 and parallel and parallel.waitForAll then
            parallel.waitForAll(table.unpack(tasks))
        end
        return tel
    end

    -- 2. Differential Thrust on Analog Transmissions (for non-Mothership or unassigned gearboxes)
    if self.vehicleType ~= "MOTHERSHIP" and self.vehicleType ~= "GUNSHIP" then
        if #self.gearboxes >= 2 then
            local pSig = (self.ap.mode == "HOVER") and 0 or math.floor(clamp(self.ap.baseThrottle - yawDiff, 0, 15))
            local sSig = (self.ap.mode == "HOVER") and 0 or math.floor(clamp(self.ap.baseThrottle + yawDiff, 0, 15))
            table.insert(tasks, function() driveSignal(self.gearboxes[1], pSig, false) end)
            table.insert(tasks, function() driveSignal(self.gearboxes[2], sSig, false) end)
        elseif #self.gearboxes == 1 then
            table.insert(tasks, function() driveSignal(self.gearboxes[1], mainThrottleSig, false) end)
        end
    end

    -- 3. Altitude PID & Attitude Stabilization
    if self.ap.altHold then
        if self.vehicleType == "ZEPPELIN" then
            -- Cascade Vertical Speed (VSI) & Thermal Buoyancy Controller:
            -- Outer Loop: Target Vertical Speed (m/s) proportional to altitude error, capped at [-1.5 .. +2.0] m/s
            local altErr    = self.ap.targetAlt - tel.altitude
            local targetVsi = clamp(altErr * 0.25, -1.50, 2.00)
            local actualVsi = tel.vSpeed or 0
            local vsiErr    = targetVsi - actualVsi

            -- Inner Loop: Continuously adapt equilibrium hover trim within [6.0 .. 11.5] so high-altitude air density is compensated
            self.hoverTrim = self.hoverTrim or 8.5
            local trimRate = (math.abs(altErr) < 4.0) and ((altErr * 0.12) + (vsiErr * 0.45)) or (vsiErr * 0.55)
            self.hoverTrim = clamp(self.hoverTrim + trimRate * dt, 6.0, 11.5)

            -- Modulate throttle lever around hoverTrim using VSI error + position error + balloon volume rate
            local posTerm = clamp(altErr * 0.25, -2.0, 2.5)
            local vsiTerm = clamp(vsiErr * 2.6, -4.5, 4.5)
            local volTerm = -clamp((tel.balloonVolChange or 0) * 0.40, -1.5, 1.5)

            local minBurner, maxBurner = 3.0, 14.0
            if altErr > 2.5 then
                -- While more than 2.5m below target, never drop burner below equilibrium hover trim (8..14 climb modulation)
                minBurner = math.max(7.0, math.floor(self.hoverTrim))
                maxBurner = 14.0
            elseif altErr < -2.5 then
                -- While more than 2.5m above target, modulate between 2 and hoverTrim for controlled descent
                minBurner = 2.0
                maxBurner = math.min(10.0, math.ceil(self.hoverTrim))
            end

            local desiredBurner = clamp(self.hoverTrim + posTerm + vsiTerm + volTerm, minBurner, maxBurner)
            self.smoothBurner = (self.smoothBurner or self.hoverTrim) * 0.45 + desiredBurner * 0.55
            burnerSignal = math.floor(clamp(self.smoothBurner, minBurner, maxBurner) + 0.5)

            self.lastBurnerSignal = burnerSignal
            tel.burnerCmd = burnerSignal
            emitRedstoneBurner(burnerSignal)
            for _, thr in ipairs(self.throttles) do
                table.insert(tasks, function() driveSignal(thr, burnerSignal, false) end)
            end
        end

        if #self.gyros > 0 then
            if self.ap.mode == "HOVER" and clutchCut then
                -- Do not tilt rear propeller bearing while hovering with propeller cut
                for _, gyro in ipairs(self.gyros) do
                    if gyro.clearManualTarget then
                        table.insert(tasks, function() safeCall(gyro.clearManualTarget) end)
                    end
                end
            else
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
                            safeCall(gyro.setManualTarget, { vx, vy, vz, x = vx, y = vy, z = vz })
                        end)
                    end
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
