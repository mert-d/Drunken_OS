-- lib/avionics.lua
-- Drunken OS - Create: Avionics & Aeronautics Flight Control Core
-- Supports Airships (Zeppelins) and Fixed-Wing / VTOL Aircraft

local Avionics = {}
Avionics.__index = Avionics

local ADAPTIVE_CFG_PATH = "/etc/avionics_adaptive.cfg"
local MAX_GYRO_CONE_RAD = math.rad(12) -- Gyroscopic Propeller Bearing 12 deg limit

-- Derivative-on-Measurement & Anti-Windup PID Controller
local function createPID(kp, ki, kd, minOut, maxOut, maxInt)
    local integral = 0
    local prevPV = nil
    local intLimit = maxInt or maxOut

    return {
        compute = function(self, setpoint, pv, dt)
            if dt <= 0 then dt = 0.05 end
            local err = setpoint - pv

            -- Integral with independent anti-windup clamping (for CoM weight offset trim)
            integral = integral + (err * dt * ki)
            if integral > intLimit then integral = intLimit end
            if integral < -intLimit then integral = -intLimit end

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
        end,
        setGains = function(self, newKp, newKi, newKd, newMin, newMax, newInt)
            if newKp then kp = tonumber(newKp) or kp end
            if newKi then ki = tonumber(newKi) or ki end
            if newKd then kd = tonumber(newKd) or kd end
            if newMin then minOut = tonumber(newMin) or minOut end
            if newMax then maxOut = tonumber(newMax) or maxOut end
            if newInt then intLimit = tonumber(newInt) or intLimit end
        end,
        getGains = function(self)
            return kp, ki, kd, minOut, maxOut, intLimit
        end
    }
end

Avionics.createPID = createPID

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
    if kw == "gear_reverse" then kw = "gearshift"
    elseif kw == "clutch_brake" then kw = "clutch" end
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
    "CLUTCH_LIFT",
    "CLUTCH_BRAKE",
    "GEAR_REVERSE",
    "RUDDER_YAW",
    "ALARM_LIGHTS",
    "IGNORE",
    "DISP_NAV",
    "DISP_SCADA",
    "DISP_PFD",
    "DISP_TABLE",
    "DISP_OFF"
}

Avionics.MONITOR_ROLES = {
    "AUTO",
    "DISP_NAV",
    "DISP_SCADA",
    "DISP_PFD",
    "DISP_TABLE",
    "DISP_OFF"
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
    self.pitchBias = tonumber(self.config.pitchBias) or 0.0
    self.rollBias  = tonumber(self.config.rollBias) or 0.0
    self.clutchPolarInvert = false -- Auto or manual [K] polarity inversion for clutches
    self.clutchSpinTicks = 0
    self.prevAlt = nil
    self.alertLevel = self.config.alertLevel or "NORMAL"
    self.alertStrobeTick = 0

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

    -- Sable / Create: Simulated 12-Propeller Telemetry Calibrated Model with Stern Levitite
    -- Front nacelles: 2x propellers each (4 total, Lf = 42.0 blocks)
    -- Rear nacelles:  4x propellers each (8 total, Lr = 16.0 blocks) + Stern Levitite Buoyancy
    self.skyfireModel = {
        mass          = 15120.0,   -- Live mass (15,120 kg with stern Levitite blocks)
        gravityForce  = 166000.0,  -- Downward gravity force in pN (~166 kN)
        maxLiftForce  = 268606.0,  -- 12-propeller maximum lift force in pN
        Lf            = 42.0,      -- Front turbine distance to CoM (blocks)
        Lr            = 16.0,      -- Rear turbine distance to CoM (blocks)
        W             = 37.0,      -- Lateral turbine arm (blocks)
        gammaFront    = 0.762,     -- Static moment balance: (8 props * 16.0) / (4 props * 42.0) = 128 / 168 = 0.762
        gammaRear     = 1.000,     -- Rear rotor reference
        hoverBaseSig  = 8.90,      -- Symmetrical hover equilibrium base throttle (12-propeller calibrated)
        ditherAcc     = { 0, 0, 0, 0 } -- 20 Hz Delta-Sigma fractional accumulator for 4 channels
    }

    -- PID Controllers (Smooth proportional + derivative damping for equilibrium altitude hold)
    self.altPID   = createPID(0.85, 0.04, 0.00, -2.5, 2.5, 0.8) -- Dikey irtifa (Y) - pure PI; velocity damping handled by vsiDamp
    self.hdgPID   = createPID(3.80, 0.10, 1.20, -6.0, 6.0)
    self.pitchPID = createPID(0.80, 0.05, 0.40, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)
    self.rollPID  = createPID(0.80, 0.05, 0.40, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)
    self.yawPID   = createPID(4.00, 0.25, 2.10, -4.5, 4.5) -- Pruva (Psi)

    -- Mothership Quad/Octo Lift Gimbal Horizon Stabilization PIDs (Calibrated critically damped for Stern Levitite)
    self.msPitchPID = createPID(10.0, 0.40, 5.00, -2.5, 2.5, 1.0) -- Calibrated anti-pitch oscillation
    self.msRollPID  = createPID(1.80, 0.02, 3.00, -1.0, 1.0, 0.2) -- Critically damped roll gain for narrow Izz (prevents limit cycles)
    self.gimbalPitchSign   = 1
    self.gimbalRollSign    = 1

    -- Autopilot alias and transmission gear mapping
    self.autopilot = self.ap
    self.gears = (#self.gearboxes >= 4) and self.gearboxes or ((#self.speedControllers >= 4) and self.speedControllers or self.gearboxes)

    -- Model-Independent Full Adaptive Cascade INDI Controller State
    self.adaptive = {
        -- Canlı öğrenilen ve diske kaydedilen denge hafızası
        hoverBase      = 9.0,            -- 0.0 (Tam Levitation) .. 12.0 (Ağır Gemi) arası kalibre
        trimPitch      = 0.0,            -- Ön/Arka kalıcı CoM ve Levitation farkı (-5.0 .. +5.0)
        trimRoll       = 0.0,            -- Sol/Sağ kalıcı CoM ve Levitation farkı (-1.0 .. +1.0)
        pitchSign      = 1,              -- Sensör/Motor yönü (+1 veya -1)
        rollSign       = 1,
        yawSign        = 1,
        motorMap       = { 1, 2, 3, 4 }, -- { SolÖn, SolArka, SağÖn, SağArka }

        -- Kaskad Kontrol Kazançları (Radyan ve Radyan/sn)
        angleKp        = 1.85,           -- Dış Döngü: Açı hatası -> Hedef açısal hız
        maxRateCmd     = 0.16,           -- Maksimum dönüş hızı (~9.1 deg/sn -> Takla atmayı kilitler)
        rateKp         = 9.50,           -- İç Döngü: Açısal hız hatası -> Motor sinyali (Frenleme)
        accelKd        = 1.20,           -- Açısal ivme sönümlemesi
        trimLearnRate  = 1.15,           -- CoM / Levitation kalıcı ofset öğrenme hızı
        maxDiffTorque  = 4.50,           -- Anlık maksimum diferansiyel tork sınırı

        -- Dikey Hız (İrtifa) Kaskad Kazançları
        altVelKp       = 0.45,           -- İrtifa hatası -> Hedef dikey hız (m/sn)
        maxClimbRate   = 3.50,           -- Maksimum tırmanma/alçalma hızı (m/sn)
        vSpeedKp       = 1.80,           -- Dikey hız hatası -> Gaz sinyali
        hoverLearnRate = 0.55,           -- Baz gazı (hoverBase) canlı öğrenme hızı

        -- Filtre ve Delta-Sigma Durumları
        fPitchRate     = 0.0,
        fRollRate      = 0.0,
        fYawRate       = 0.0,
        fVSpeed        = 0.0,
        prevPitchRate  = 0.0,
        prevRollRate   = 0.0,
        ditherAcc      = { 0, 0, 0, 0 },
        saveTimer      = 0.0
    }

    self:loadAdaptiveState()

    self.mods = {}
    self:loadModules(self.config.modDir or "/lib/avx")

    -- Flight Data Recorder (Blackbox / Kara Kutu)
    local okB, BBox = pcall(require, "lib.blackbox")
    if not okB then okB, BBox = pcall(require, "blackbox") end
    if okB and type(BBox) == "table" and BBox.new then
        self.blackbox = BBox.new({ callsign = self.callsign, vehicleType = self.vehicleType })
    end

    -- Flight Management / Route Manager
    local okRM, RMModule = pcall(require, "lib.avx.route_manager")
    if not okRM or type(RMModule) ~= "table" then okRM, RMModule = pcall(require, "avx.route_manager") end
    if okRM and type(RMModule) == "table" and RMModule.RouteManager then
        self.routeManager = RMModule.RouteManager.new()
    end

    -- Apply saved autotune or initialize from live physics if requested
    if self.autotuneParams then
        local okAt, Autotune = pcall(require, "lib.avx.autotune")
        if okAt and Autotune and Autotune.apply then
            pcall(Autotune.apply, self, self.autotuneParams, false)
        end
    elseif self.config.autoTune == true then
        pcall(self.autoTune, self, { persist = false })
    end

    return self
end

-- AVX extension modules (lib/avx/*.lua, installed from GitHub). Core runs without them.
function Avionics:addModule(m)
    if type(m) == "table" then self.mods = self.mods or {}; table.insert(self.mods, m) end
end

function Avionics:loadModules(dir)
    dir = dir or "/lib/avx"
    local found = false
    if fs and fs.isDir then
        for _, d in ipairs({ dir, dir:gsub("^/+", ""), "/" .. dir:gsub("^/+", "") }) do
            if fs.isDir(d) then
                for _, n in ipairs(fs.list(d)) do
                    if n:match("%.lua$") then
                        local ok, m = pcall(dofile, fs.combine(d, n))
                        if ok then self:addModule(m); found = true else self.modErr = tostring(m) end
                    end
                end
                break
            end
        end
    end
    if not found then
        for _, rel in ipairs({ "lib.avx.wing_level", "avx.wing_level", "lib.avx.sky_anchor", "avx.sky_anchor", "lib.avx.route_manager", "avx.route_manager" }) do
            local ok, m = pcall(require, rel)
            if ok and type(m) == "table" then self:addModule(m) end
        end
    end
end

function Avionics:hook(name, ...)
    for _, m in ipairs(self.mods or {}) do
        if m[name] then
            local ok, e = pcall(m[name], self, ...)
            if not ok then self.modErr = tostring(e) end
        end
    end
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
                    if type(parsed.pitchBias) == "number" then self.pitchBias = parsed.pitchBias end
                    if type(parsed.rollBias) == "number" then self.rollBias = parsed.rollBias end
                    if parsed.autotune and type(parsed.autotune) == "table" then
                        self.autotuneParams = parsed.autotune
                    end
                else
                    self.ioMap = parsed
                    if type(parsed.pitchBias) == "number" then self.pitchBias = parsed.pitchBias end
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
                profile   = self.profile,
                ioMap     = self.ioMap,
                pitchBias = self.pitchBias or 0.0,
                rollBias  = self.rollBias or 0.0,
                autotune  = self.autotuneParams
            }))
            f.close()
        end
    end
end

function Avionics:autoTune(opts)
    opts = opts or {}
    local okAt, Autotune = pcall(require, "lib.avx.autotune")
    if not okAt or type(Autotune) ~= "table" then
        okAt, Autotune = pcall(require, "avx.autotune")
    end
    if not okAt or type(Autotune) ~= "table" then
        if fs and fs.exists and (fs.exists("/lib/avx/autotune.lua") or fs.exists("lib/avx/autotune.lua")) then
            local path = fs.exists("/lib/avx/autotune.lua") and "/lib/avx/autotune.lua" or "lib/avx/autotune.lua"
            local okDf, resDf = pcall(dofile, path)
            if okDf and type(resDf) == "table" then
                Autotune = resDf
                okAt = true
            end
        end
    end
    if okAt and Autotune and Autotune.autoCalibrate then
        local ok, res = pcall(Autotune.autoCalibrate, self, opts.persist ~= false)
        return ok and res or false
    end
    return false, "Autotune module not found"
end

function Avionics:runSafeCalibration(logFn)
    local okAt, Autotune = pcall(require, "lib.avx.autotune")
    if not okAt or type(Autotune) ~= "table" then
        okAt, Autotune = pcall(require, "avx.autotune")
    end
    if not okAt or type(Autotune) ~= "table" then
        if fs and fs.exists and (fs.exists("/lib/avx/autotune.lua") or fs.exists("lib/avx/autotune.lua")) then
            local path = fs.exists("/lib/avx/autotune.lua") and "/lib/avx/autotune.lua" or "lib/avx/autotune.lua"
            local okDf, resDf = pcall(dofile, path)
            if okDf and type(resDf) == "table" then
                Autotune = resDf
                okAt = true
            end
        end
    end
    if okAt and Autotune and Autotune.runSafeCalibration then
        return Autotune.runSafeCalibration(self, logFn)
    end
    return false, "Autotune module not found"
end

function Avionics:setPitchBias(val)
    self.pitchBias = clamp(tonumber(val) or 0.0, -6.0, 6.0)
    self:saveIOMap()
    return self.pitchBias
end

function Avionics:adjustPitchBias(delta)
    return self:setPitchBias((self.pitchBias or 0.0) + (tonumber(delta) or 0.0))
end

function Avionics:setAlertLevel(lvl)
    local l = tostring(lvl or "NORMAL"):upper()
    if l == "RED" or l == "YELLOW" or l == "CLEAR" or l == "NORMAL" then
        self.alertLevel = (l == "CLEAR") and "NORMAL" or l
    else
        self.alertLevel = "NORMAL"
    end
    return self.alertLevel
end

function Avionics:getAlertLevel()
    return self.alertLevel or "NORMAL"
end

function Avionics:toggleRedAlert()
    if self.alertLevel == "RED" then
        self.alertLevel = "NORMAL"
    else
        self.alertLevel = "RED"
    end
    return self.alertLevel
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
    local isMon = tostring(devName):lower():find("monitor") ~= nil
    if not isMon and self.ioDevices then
        for _, dev in ipairs(self.ioDevices) do
            if dev.name == devName and (dev.kind == "monitor" or dev.cap == "DISP") then
                isMon = true
                break
            end
        end
    end

    local roleList = isMon and Avionics.MONITOR_ROLES or Avionics.ROLES
    local maxLen = isMon and #roleList or 19 -- exclude display roles when cycling standard motors/redstone
    local idx = 1
    for i = 1, maxLen do
        if roleList[i] == cfg.role then idx = i break end
    end
    idx = ((idx - 1 + dir) % maxLen) + 1
    cfg.role = roleList[idx]
    self:saveIOMap()
    return cfg.role
end

function Avionics:toggleInvert(devName)
    local cfg = self:getDeviceConfig(devName)
    if tostring(devName or ""):lower():find("gimbal") then
        cfg.gimbalMode = ((tonumber(cfg.gimbalMode) or (cfg.invert and 3 or 0)) + 1) % 6
        cfg.invert = (cfg.gimbalMode ~= 0)
        self.gimbalPitchSign   = 1
        self.gimbalRollSign    = 1
        self.pitchDivergeTicks = 0
        self.rollDivergeTicks  = 0
        if self.msPitchPID then self.msPitchPID:reset() end
        if self.msRollPID then self.msRollPID:reset() end
    else
        cfg.invert = not cfg.invert
    end
    self:saveIOMap()
    return cfg.invert
end

function Avionics:resetDeviceRole(devName)
    local cfg = self:getDeviceConfig(devName)
    cfg.role = "AUTO"
    cfg.invert = false
    cfg.gimbalMode = 0
    if tostring(devName or ""):lower():find("gimbal") then
        self.gimbalPitchSign   = 1
        self.gimbalRollSign    = 1
        self.pitchDivergeTicks = 0
        self.rollDivergeTicks  = 0
    end
    self:saveIOMap()
    return cfg.role
end

-- Auto-assigns the first 4 speed controllers/gearboxes to Quad-Lift (FL, FR, RL, RR)
-- and the next 3 to Rear Thrusters (REAR_LEFT, REAR_CENTER, REAR_RIGHT)
function Avionics:autoAssignMothershipRoles(forceOverwrite)
    local candidates = {}
    for _, item in ipairs(self.ioDevices or {}) do
        if not item.isRedstone then
            local k = item.kind:lower()
            if k:find("shaft") and item.cap == "PASSIVE" then
                -- Reset any accidental motor role previously assigned to a passive shaft
                local sCfg = self:getDeviceConfig(item.name)
                if sCfg.role ~= "AUTO" then sCfg.role = "AUTO" end
            elseif (k:find("speed_controller") or k:find("rotationspeedcontroller")
                or k:find("analog_transmission") or k:find("gearbox")
                or k:find("chain_gearshift") or k:find("chain_drive")
                or k:find("sequenced_gearshift") or k:find("throttle_lever")
                or k:find("bearing") or k:find("propeller"))
                and not k:find("shaft") and item.cap ~= "PASSIVE" then
                table.insert(candidates, item.name)
            end
        end
    end

    local usedRoles = {}
    if not forceOverwrite then
        for _, devName in ipairs(candidates) do
            local cfg = self:getDeviceConfig(devName)
            if cfg.role and cfg.role ~= "AUTO" then
                usedRoles[cfg.role] = true
            end
        end
    end

    for _, devName in ipairs(candidates) do
        local cfg = self:getDeviceConfig(devName)
        if forceOverwrite or cfg.role == "AUTO" then
            local n = devName:lower()
            local posRole = nil
            if n:find("rudder") or n:find("yaw") or (n:find("steer") and not n:find("wheel_mount")) then
                posRole = "RUDDER_YAW"
            elseif n:find("fore") and n:find("port") then
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
                usedRoles[posRole] = true
            else
                local picked = nil
                for _, r in ipairs(Avionics.MOTHERSHIP_ROLES) do
                    if not usedRoles[r] then
                        picked = r
                        usedRoles[r] = true
                        break
                    end
                end
                cfg.role = picked or "AUTO"
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
    local hadGimbal  = (self.gimbal ~= nil)
    self.altSensor   = peripheral and peripheral.find and peripheral.find("altitude_sensor")
    self.altSensors  = (peripheral and peripheral.find and { peripheral.find("altitude_sensor") }) or {}
    self.gimbal      = peripheral and peripheral.find and peripheral.find("gimbal_sensor")
    if not hadGimbal and self.gimbal then
        if self.msPitchPID then self.msPitchPID:reset() end
        if self.msRollPID then self.msRollPID:reset() end
        if self.pitchPID then self.pitchPID:reset() end
        if self.rollPID then self.rollPID:reset() end
        self.pitchDivergeTicks = 0
        self.rollDivergeTicks  = 0
    end
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
        local function findAny(types, doSort)
            local res = {}
            for _, t in ipairs(types) do
                local found = { peripheral.find(t) }
                for _, p in ipairs(found) do table.insert(res, p) end
            end
            if doSort and peripheral and peripheral.getName then
                table.sort(res, function(a, b)
                    local na = (pcall(peripheral.getName, a) and peripheral.getName(a)) or ""
                    local nb = (pcall(peripheral.getName, b) and peripheral.getName(b)) or ""
                    return tostring(na) < tostring(nb)
                end)
            end
            return res
        end
        self.burners          = findAny({ "gas_provider" })
        self.gearboxes        = findAny({ "analog_transmission", "adjustable_chain_gearshift", "create:adjustable_chain_gearshift" }, true)
        self.throttles        = findAny({ "throttle_lever" })
        self.gyros            = findAny({ "gyroscopic_propeller_bearing" })
        self.wheels           = findAny({ "wheel_mount" })
        self.engines          = findAny({ "portable_engine" })
        self.clutches         = findAny({ "create_connected_inverted_clutch", "inverted_clutch", "create_clutch", "clutch" })
        self.gearshifts       = findAny({ "create_gearshift", "gearshift", "create:gearshift", "create_sequenced_gearshift", "sequenced_gearshift", "create_connected_gearshift", "create_connected_sequenced_gearshift", "redstone_relay" })
        self.speedControllers = findAny({ "Create_RotationSpeedController", "rotation_speed_controller", "create:rotation_speed_controller", "speed_controller" }, true)
    else
        for _, k in ipairs({ "burners", "gearboxes", "throttles", "gyros", "wheels", "engines", "clutches", "gearshifts", "speedControllers" }) do self[k] = {} end
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
                if pStr ~= "modem" and pStr ~= "speaker" and pStr ~= "drive" and pStr ~= "computer" and pStr ~= "turtle" then
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
                    local cfg = self:getDeviceConfig(name)
                    if cfg.role == "AUTO" then
                        if combined:find("rudder") or combined:find("swivel") or (combined:find("steer") and not combined:find("steering_wheel") and not combined:find("wheel_mount")) then
                            cfg.role = "RUDDER_YAW"
                        elseif combined:find("clutch") and (combined:find("brake") or combined:find("prop")) then
                            cfg.role = "CLUTCH_BRAKE"
                        elseif combined:find("reverse") or combined:find("gearshift") then
                            cfg.role = "GEAR_REVERSE"
                        end
                    end
                    local cap = "PASSIVE"
                    if h then
                        if type(h.setTargetSpeed) == "function" then
                            cap = "RPM"
                        elseif type(h.setSignal) == "function" or type(h.setThrottle) == "function"
                            or type(h.setControl) == "function" or type(h.setPowered) == "function"
                            or type(h.setOutput) == "function" or type(h.setAnalogOutput) == "function"
                            or type(h.setTargetAngle) == "function" or type(h.setTargetAngleRad) == "function"
                            or type(h.setAngle) == "function" or type(h.setSteering) == "function" then
                            cap = "SIG"
                        elseif type(h.getHeight) == "function" or type(h.getAltitude) == "function"
                            or type(h.getAngles) == "function" or type(h.getAnglesRad) == "function"
                            or type(h.getVelocity) == "function" or type(h.getAirPressure) == "function" then
                            cap = "SENS"
                        elseif pStr == "monitor" or type(h.setTextScale) == "function" then
                            cap = "DISP"
                        end
                    end
                    table.insert(self.ioDevices, { name = name, kind = pStr, handle = h, cap = cap, isRedstone = false })
                end
            end
        end
        local capRank = { RPM = 1, SIG = 2, SENS = 3, DISP = 4, PASSIVE = 5 }
        table.sort(self.ioDevices, function(a, b)
            local ra = capRank[a.cap] or 5
            local rb = capRank[b.cap] or 5
            if ra ~= rb then return ra < rb end
            return tostring(a.name) < tostring(b.name)
        end)
    else
        for _, pair in ipairs({ { self.speedControllers, "rotation_speed_controller" }, { self.gearboxes, "analog_transmission" } }) do
            for idx, dev in ipairs(pair[1] or {}) do
                local name = pair[2] .. "_" .. tostring(idx - 1)
                self:getDeviceConfig(name)
                table.insert(self.ioDevices, { name = name, kind = pair[2], handle = dev, cap = (pair[2]:find("speed") and "RPM" or "SIG"), isRedstone = false })
            end
        end
    end
    local hasGearRole = (#self.gearshifts > 0)
    for _, side in ipairs({ "back", "front", "left", "right", "top", "bottom" }) do
        local rsName = "RS:" .. side
        local cfg = self:getDeviceConfig(rsName)
        if cfg.role == "GEAR_REVERSE" then hasGearRole = true end
        table.insert(self.ioDevices, { name = rsName, side = side, kind = "redstone_out", cap = "RS", isRedstone = true })
    end
    if not hasGearRole then
        local bCfg = self:getDeviceConfig("RS:back")
        if bCfg.role == "AUTO" then bCfg.role = "GEAR_REVERSE" end
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
    self.gears = (#self.gearboxes >= 4) and self.gearboxes or ((#self.speedControllers >= 4) and self.speedControllers or self.gearboxes)
end

function Avionics:readTelemetry(dt)
    dt = dt or 0.05

    self.gpsTick = (self.gpsTick or 0) + 1
    if (self.gpsTick % 20 == 0) or (not self.altSensor and not self.velSensor and not self.gimbal) then
        self:scanPeripherals()
    end

    -- 1. Altitude & Vertical Speed (Averages all connected altitude_sensor blocks so corner tilt doesn't skew altitude)
    local alt = 0
    local sensorVsi = 0
    local pressure = 1.0
    if self.altSensors and #self.altSensors > 1 then
        local sumA, cntA, sumV, cntV = 0, 0, 0, 0
        local sumP, cntP = 0, 0
        for _, as in ipairs(self.altSensors) do
            local a = tonumber(safeCall(as.getHeight)) or tonumber(safeCall(as.getAltitude))
            if a then sumA = sumA + a; cntA = cntA + 1 end
            local v = tonumber(safeCall(as.getVerticalSpeed))
            if v then sumV = sumV + v; cntV = cntV + 1 end
            local p = tonumber(safeCall(as.getAirPressure)) or tonumber(safeCall(as.getPressure))
            if p then sumP = sumP + p; cntP = cntP + 1 end
        end
        if cntA > 0 then alt = sumA / cntA end
        if cntV > 0 then sensorVsi = sumV / cntV end
        if cntP > 0 then pressure = sumP / cntP end
    elseif self.altSensor then
        alt = tonumber(safeCall(self.altSensor.getHeight))
           or tonumber(safeCall(self.altSensor.getAltitude))
           or 0
        sensorVsi = tonumber(safeCall(self.altSensor.getVerticalSpeed)) or 0
        pressure = tonumber(safeCall(self.altSensor.getAirPressure)) or tonumber(safeCall(self.altSensor.getPressure)) or 1.0
    end
    local pressureHPa = pressure * 1013.25
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
    local angVel = { x = 0, y = 0, z = 0 }
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
                local p = tonumber(safeCall(self.gimbal.getPitchRad)) or tonumber(safeCall(self.gimbal.getPitch)) or 0
                local r = tonumber(safeCall(self.gimbal.getRollRad)) or tonumber(safeCall(self.gimbal.getRoll)) or 0
                if math.abs(p) > math.pi then p = math.rad(p) end
                if math.abs(r) > math.pi then r = math.rad(r) end
                pitch = p
                roll  = r
            end
        end
        local gName = (peripheral and peripheral.getName and pcall(peripheral.getName, self.gimbal) and peripheral.getName(self.gimbal)) or nil
        local gCfg  = gName and self:getDeviceConfig(gName) or nil
        local gMode = gCfg and tonumber(gCfg.gimbalMode) or 0
        if gMode == 1 then
            roll = -roll
        elseif gMode == 2 then
            pitch = -pitch
        elseif gMode == 3 then
            pitch = -pitch
            roll  = -roll
        elseif gMode == 4 then
            pitch, roll = -roll, -pitch
        elseif gMode == 5 then
            pitch, roll = roll, pitch
        end
        pitch = pitch * (self.gimbalPitchSign or 1)
        roll  = roll  * (self.gimbalRollSign  or 1)
        local acc = safeCall(self.gimbal.getLinearAcceleration)
        if type(acc) == "table" then
            local ax = tonumber(acc[1] or acc.x) or 0
            local ay = tonumber(acc[2] or acc.y) or 0
            local az = tonumber(acc[3] or acc.z) or 0
            linAcc = { x = ax, y = ay, z = az, ax, ay, az }
        end
        local rates = safeCall(self.gimbal.getAngularRatesRad)
                   or safeCall(self.gimbal.getAngularRates)
                   or safeCall(self.gimbal.getAngularVelocity)
        local wx, wy, wz = 0, 0, 0
        if type(rates) == "table" then
            wx = tonumber(rates[1] or rates.x) or 0
            wy = tonumber(rates[2] or rates.y) or 0
            wz = tonumber(rates[3] or rates.z) or 0
            if gMode == 2 or gMode == 3 then wx = -wx end
            if gMode == 1 or gMode == 3 then wz = -wz end
            if gMode == 4 or gMode == 5 then wx, wz = wz, wx end
            wx = wx * (self.gimbalPitchSign or 1)
            wz = wz * (self.gimbalRollSign or 1)
        end
        if (wx == 0 and wz == 0) and dt > 0 and self.prevPitch ~= nil and self.prevRoll ~= nil then
            wx = clamp((pitch - self.prevPitch) / dt, -3.0, 3.0)
            wz = clamp((roll - self.prevRoll) / dt, -3.0, 3.0)
        end
        angVel = { x = wx, y = wy, z = wz }
    end

    -- 3. Heading & Navigation Target (Create: Avionics Navigation Table or Sublevel Pose)
    local heading = 0
    local navTarget = nil
    if _G.sublevel and _G.sublevel.getLogicalPose then
        local okPose, pose = pcall(_G.sublevel.getLogicalPose)
        if okPose and pose and pose.orientation then
            local q = pose.orientation
            local qw = tonumber(q.a) or 0
            local qx = tonumber(q.v and q.v.x) or 0
            local qy = tonumber(q.v and q.v.y) or 0
            local qz = tonumber(q.v and q.v.z) or 0
            local fx = -2 * (qx * qz + qy * qw)
            local fz = 2 * (qx * qx + qy * qy) - 1
            heading = math.atan2(-fx, fz)
        end
    end
    if self.nav then
        local hRad = tonumber(safeCall(self.nav.getHeadingRad))
        if hRad then
            heading = hRad
        else
            local hDeg = tonumber(safeCall(self.nav.getHeading)) or tonumber(safeCall(self.nav.getCurrentAngle))
            if hDeg then heading = math.rad(hDeg) end
        end

        local hasTgt = safeCall(self.nav.hasTarget)
        if hasTgt == nil and self.nav.getTarget then
            local tgtTable = safeCall(self.nav.getTarget)
            if type(tgtTable) == "table" and tgtTable.hasTarget == true then
                hasTgt = true
            end
        end
        if hasTgt == true then
            local tName = safeCall(self.nav.getTargetName) or safeCall(self.nav.getTargetDisplayName) or safeCall(self.nav.getTargetLabel) or "WAYPOINT"
            local brgRad = tonumber(safeCall(self.nav.getBearingRad))
            if brgRad == nil and self.nav.getBearing then
                local bDeg = tonumber(safeCall(self.nav.getBearing))
                if bDeg then brgRad = math.rad(bDeg) end
            elseif brgRad == nil and self.nav.getCurrentAngle then
                local aDeg = tonumber(safeCall(self.nav.getCurrentAngle))
                if aDeg then brgRad = math.rad(aDeg) end
            end
            local dist = tonumber(safeCall(self.nav.getDistanceToTarget)) or tonumber(safeCall(self.nav.getTargetDistance))
            local vOff = tonumber(safeCall(self.nav.getVerticalOffsetToTarget))
            local closure = tonumber(safeCall(self.nav.getClosureRate))
            local tPos = safeCall(self.nav.getTargetPosition) or safeCall(self.nav.getTargetPos)
            navTarget = {
                active   = true,
                name     = tostring(tName),
                bearing  = brgRad or 0,
                distance = (dist and dist >= 0) and dist or 0,
                vOffset  = vOff or 0,
                closure  = closure or 0,
                pos      = tPos
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

    if (vel.x == 0 and vel.z == 0) and _G.sublevel and _G.sublevel.getLinearVelocity then
        local okLv, lv = pcall(_G.sublevel.getLinearVelocity)
        if okLv and type(lv) == "table" and (lv.x or lv.z) then
            vel.x = tonumber(lv.x) or vel.x
            vel.y = tonumber(lv.y) or vel.y
            vel.z = tonumber(lv.z) or vel.z
            speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
            rawVel = speed
        end
    end

    -- Update Position (Multi-Tier Navigation Sensor Fusion)
    -- Tier 1: CC:Sable SubLevel Physics Pose (Absolute Contraption Origin, 20Hz Real-Time)
    -- Tier 2: Navigation Table (Advanced Navigation Table or Standard Nav Table)
    -- Tier 3: GPS Constellation (Trilateration fallback if in open airspace)
    -- Tier 4: INS Dead-Reckoning (Internal speed & altitude integration fallback)
    local posSource = "INS"
    if _G.sublevel and _G.sublevel.getLogicalPose then
        local okPose, pose = pcall(_G.sublevel.getLogicalPose)
        if okPose and pose and pose.position and type(pose.position.x) == "number" then
            self.pos.x = pose.position.x
            self.pos.y = pose.position.y
            self.pos.z = pose.position.z
            self.gpsLocked = true
            posSource = "SUBLEVEL"
        end
    end

    if posSource == "INS" and self.nav then
        local okTab, tabPos = nil, nil
        if self.nav.getTablePosition then
            okTab, tabPos = pcall(self.nav.getTablePosition)
        elseif self.nav.getBlockPos then
            okTab, tabPos = pcall(self.nav.getBlockPos)
        end
        if okTab and tabPos and type(tabPos.x) == "number" and type(tabPos.z) == "number" then
            self.pos.x = tabPos.x
            self.pos.y = tabPos.y or alt
            self.pos.z = tabPos.z
            self.gpsLocked = true
            posSource = "NAV_TABLE"
        end
    end

    if posSource == "INS" and self.config.useGPS and gps and gps.locate and (self.gpsTick % 40 == 1) then
        local okGps, gx, gy, gz = pcall(gps.locate, 0.05)
        if okGps and gx and gz then
            self.pos.x, self.pos.z = gx, gz
            if not self.altSensor and gy then
                self.pos.y = gy
            end
            self.gpsLocked = true
            posSource = "GPS"
        else
            self.gpsLocked = false
        end
    end

    if posSource == "INS" then
        self.pos.x = self.pos.x + vel.x * dt
        self.pos.y = alt
        self.pos.z = self.pos.z + vel.z * dt
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

    -- 8. Warnings (GPWS, Stall & Pitch Anti-Dive)
    local gpwsWarning = ((agl ~= nil and agl < 12 and vsi < -3.5 and not weightOnWheels) or radarGpws)
    local stallWarning = (self.vehicleType == "AIRCRAFT" and not weightOnWheels and speed < 3.0 and pitch > math.rad(15))
    local pitchWarning = (math.abs(pitch) > math.rad(14.0))

    local tel = {
        callsign         = self.callsign,
        vehicleType      = self.vehicleType,
        altitude         = alt,
        agl              = agl,
        vSpeed           = vsi,
        pressure         = pressure,
        pressureHPa      = pressureHPa,
        pitch            = pitch,
        roll             = roll,
        heading          = heading,
        speed            = speed,
        velocity         = vel,
        linAcc           = linAcc,
        angVel           = angVel,
        wx               = angVel.x,
        wy               = angVel.y,
        wz               = angVel.z,
        pos              = { x = self.pos.x, y = self.pos.y, z = self.pos.z },
        posSource        = posSource,
        gpsLocked        = self.gpsLocked,
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
        liftForcePN      = self.lastLiftForcePN or 0,
        twr              = (self.skyfireModel and self.skyfireModel.gravityForce and self.skyfireModel.gravityForce > 0)
            and ((self.lastLiftForcePN or 0) / self.skyfireModel.gravityForce) or 0.0,
        pitchBias        = self.pitchBias or 0.0,
        rollBias         = self.rollBias or 0.0,
        gpwsWarning      = gpwsWarning,
        stallWarning     = stallWarning,
        pitchWarning     = pitchWarning,
        alertLevel       = self.alertLevel or "NORMAL",
        fuelPct          = (maxFuel > 0 and (totalFuel / maxFuel)) or 1.0,
        navTarget        = navTarget,
        radarContact     = radarContact,
        gearRetracted    = gearRetracted,
        transponder      = (self.controller and safeCall(self.controller.isTransponderOn) == true)
    }
    self:hook("onTelemetry", tel, dt)
    return tel
end

function Avionics:triggerSpinTest(devName)
    self.spinTest = { name = devName or "ALL", ticks = 30 } -- 1.5 seconds at 20Hz
end

function Avionics:getRouteManager()
    if not self.routeManager then
        local okRM, RMModule = pcall(require, "lib.avx.route_manager")
        if not okRM or type(RMModule) ~= "table" then okRM, RMModule = pcall(require, "avx.route_manager") end
        if okRM and type(RMModule) == "table" and RMModule.RouteManager then
            self.routeManager = RMModule.RouteManager.new()
        end
    end
    return self.routeManager
end

function Avionics:startRoute(name, tel)
    local rm = self:getRouteManager()
    if not rm then return false, "NO_RM" end
    if name and name ~= "" then
        local okL, errL = rm:loadRoute(name)
        if not okL and (not rm.activeRoute or #rm.activeRoute.waypoints == 0) then
            return false, errL
        end
    end
    if not rm.activeRoute or #rm.activeRoute.waypoints == 0 then
        return false, "EMPTY_ROUTE"
    end
    rm:setActiveIndex(1, tel and tel.pos)
    self:setMode("LNAV", tel)
    return true, rm.activeRoute
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
    self.prevPitch = nil
    self.prevRoll  = nil
    self.smoothVsi = 0.0
    if currentTel and currentTel.altitude then
        self.prevAlt = currentTel.altitude
    end

    -- Preserve learned equilibrium integral when switching between autopilot modes; default 0.0 from MANUAL to avoid climb surge
    local bumplessInt = wasAltHold and savedIntegral or clamp((self.lastBurnerSignal and self.lastBurnerSignal > 0) and (self.lastBurnerSignal - (self.skyfireModel.hoverBaseSig or 10.8)) or 0.0, -1.0, 1.5)

    if modeName ~= "ANCHOR" then self.anchorPos = nil end
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
    elseif modeName == "HOVER" or modeName == "ANCHOR" then
        self.ap.enabled = true
        self.ap.altHold = true
        self.ap.hdgHold = true
        self.ap.baseThrottle = 0
        self.ap.parkingBrake = (modeName == "HOVER")
        self.ap.manualYaw = 0
        if currentTel then
            self.ap.targetAlt = math.floor(currentTel.altitude + 0.5)
            self.ap.targetHdg = currentTel.heading
            if modeName == "ANCHOR" then
                self.anchorPos = {
                    x = (currentTel.pos and currentTel.pos.x) or 0,
                    y = self.ap.targetAlt,
                    z = (currentTel.pos and currentTel.pos.z) or 0,
                    heading = currentTel.heading
                }
            end
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

function Avionics:loadAdaptiveState()
    if not (fs and fs.exists and fs.exists(ADAPTIVE_CFG_PATH)) then return false end
    local f = fs.open(ADAPTIVE_CFG_PATH, "r")
    if not f then return false end
    local raw = f.readAll()
    f.close()
    local ok, data = pcall(textutils.unserialize, raw)
    if ok and type(data) == "table" and self.adaptive then
        local a = self.adaptive
        local loadedHover = tonumber(data.hoverBase)
        if loadedHover and loadedHover >= 0.0 and loadedHover <= 14.0 then
            a.hoverBase = loadedHover
        else
            a.hoverBase = 8.90
        end
        a.trimPitch = clamp(tonumber(data.trimPitch) or a.trimPitch, -4.5, 4.5)
        a.trimRoll  = clamp(tonumber(data.trimRoll)  or a.trimRoll,  -1.0, 1.0)
        a.pitchSign = tonumber(data.pitchSign) or a.pitchSign
        a.rollSign  = tonumber(data.rollSign)  or a.rollSign
        a.yawSign   = tonumber(data.yawSign)   or a.yawSign
        a.motorMap  = (type(data.motorMap) == "table") and data.motorMap or a.motorMap
        return true
    end
    return false
end

function Avionics:saveAdaptiveState()
    if not (self.adaptive and fs and fs.open and textutils and textutils.serialize) then return end
    local a = self.adaptive
    if fs.makeDir and not fs.exists("/etc") then pcall(fs.makeDir, "/etc") end
    local f = fs.open(ADAPTIVE_CFG_PATH, "w")
    if f then
        f.write(textutils.serialize({
            hoverBase = tonumber(string.format("%.3f", a.hoverBase)),
            trimPitch = tonumber(string.format("%.3f", a.trimPitch)),
            trimRoll  = tonumber(string.format("%.3f", a.trimRoll)),
            pitchSign = a.pitchSign,
            rollSign  = a.rollSign,
            yawSign   = a.yawSign,
            motorMap  = a.motorMap
        }))
        f.close()
    end
end

function Avionics:stepGunshipAdaptive(tel, dt, tasks)
    local a = self.adaptive
    local safeDt = clamp(dt or 0.05, 0.02, 0.25)
    local m = self.skyfireModel or {
        mass          = 15120.0,
        gravityForce  = 166000.0,
        maxLiftForce  = 268606.0,
        Lf            = 42.0,
        Lr            = 16.0,
        W             = 37.0,
        gammaFront    = 0.762,
        gammaRear     = 1.000,
        hoverBaseSig  = 8.90,
        ditherAcc     = { 0, 0, 0, 0 }
    }

    -- 1. OTOMATIK BIRIM KORUMASI (Derece gelirse Radyan'a cevir)
    local pitch = tel.pitch or 0
    local roll  = tel.roll  or 0
    local yaw   = tel.yaw   or tel.heading or 0
    if math.abs(pitch) > 1.65 or math.abs(roll) > 1.65 then
        pitch = math.rad(pitch)
        roll  = math.rad(roll)
        yaw   = math.rad(yaw)
    end

    -- 2. FILTRELENMIS ACISAL HIZLAR (rad/sn) VE DIKEY HIZ (m/sn)
    local rawPitchRate = tel.wx or ((pitch - (self.prevPitch or pitch)) / safeDt)
    local rawRollRate  = tel.wz or ((roll  - (self.prevRoll  or roll))  / safeDt)
    local rawVSpeed    = tel.vSpeed or (((tel.altitude or 0) - (self.prevAlt or (tel.altitude or 0))) / safeDt)

    local rawYawDiff = yaw - (self.prevYaw or yaw)
    if rawYawDiff > math.pi then rawYawDiff = rawYawDiff - 2 * math.pi end
    if rawYawDiff < -math.pi then rawYawDiff = rawYawDiff + 2 * math.pi end
    local rawYawRate = rawYawDiff / safeDt

    self.prevPitch = pitch
    self.prevRoll  = roll
    self.prevYaw   = yaw
    self.prevAlt   = tel.altitude or 0

    a.fPitchRate = a.fPitchRate * 0.55 + rawPitchRate * 0.45
    a.fRollRate  = a.fRollRate  * 0.55 + rawRollRate  * 0.45
    a.fYawRate   = a.fYawRate   * 0.60 + rawYawRate   * 0.40
    a.fVSpeed    = a.fVSpeed    * 0.65 + rawVSpeed    * 0.35

    local ap = self.autopilot or self.ap or {}
    local apMode = ap.mode or "MANUAL"
    local isZeroThrottleManual = (not ap.enabled or apMode == "MANUAL") and ((self.manualThrottle or ap.baseThrottle or 0) <= 0 or ap.parkingBrake)

    -- 3. DIKEY ITKI VE CANLI LEVITATION (ANTIGRAVITY) OGRENICISI
    local baseLift = a.hoverBase or m.hoverBaseSig or 8.90
    local downforceAngle = 0.0

    if isZeroThrottleManual then
        self.msPitchPID:reset()
        self.msRollPID:reset()
        baseLift = 0.0
    elseif apMode == "MANUAL" then
        baseLift = clamp(self.manualThrottle or ap.baseThrottle or 0, 0, 15)
    else
        local tgtAlt = ap.targetAltitude or ap.targetAlt or tel.altitude or 0
        local altErr = tgtAlt - (tel.altitude or 0)
        local targetVSpeed = clamp(altErr * a.altVelKp, -a.maxClimbRate, a.maxClimbRate)
        local vSpeedErr    = targetVSpeed - a.fVSpeed

        -- Dikey İrtifa Regülasyonu: altPID (PI) + Doğrudan Dikey Hız (Vy) Sönümlemesi
        local pidAlt = self.altPID:compute(tgtAlt, tel.altitude, safeDt)
        local vsiGain = self.dampVy or 1.60
        local vsiDamp = clamp(a.fVSpeed * vsiGain, -4.5, 4.5)
        local altCmd = clamp(pidAlt - vsiDamp, -4.5, 4.5)

        -- Canlı Hover Taban Gazı: YALNIZCA hedef irtifaya yakın iken (|altErr| < 2.0m) adapte olur
        -- Aktif tırmanış/alçalış manevralarında hoverBase dondurulur (Çift Entegratör Pompalama Koruması)
        local isNearTargetAlt = (math.abs(altErr) < 2.0) and (math.abs(pitch) < 0.20) and (math.abs(roll) < 0.20)
        if isNearTargetAlt and apMode == "HOVER" then
            a.hoverBase = clamp(a.hoverBase + (vSpeedErr * (a.hoverLearnRate or 0.15)) * safeDt, 6.0, 11.5)
            m.hoverBaseSig = a.hoverBase
        end

        local baseCenter = math.max(ap.baseThrottle or 0, a.hoverBase or m.hoverBaseSig or 8.90)
        local rawLiftCmd = baseCenter + altCmd
        baseLift = clamp(rawLiftCmd, 0.0, 15.0)

        -- Aktif Negatif Kanat Acisi (Active Downforce):
        -- Eger Levitation gemiyi motorlar sifirken dahi hedefin uzerine cikarip tasiyorsa
        if rawLiftCmd < -0.15 or (altErr < -0.4 and a.fVSpeed > 0.2 and baseLift <= 1.0) then
            local excessRise = (rawLiftCmd < -0.15) and rawLiftCmd or (-0.4 - (tel.altitude - tgtAlt) * 0.4)
            downforceAngle = clamp(excessRise * 5.0, -25.0, 0.0)
        end
    end

    -- 4. PITCH & ROLL STABILIZASYONU: CRITICALLY DAMPED PID + DOGRUDAN HIZ SONUMLENMESI
    local tgtPitch = clamp(ap.targetPitch or 0, -0.15, 0.15)
    local tgtRoll  = clamp(ap.targetRoll  or 0, -0.15, 0.15)

    local angleErrP = (tgtPitch - pitch) * a.pitchSign
    local angleErrR = (tgtRoll  - roll)  * a.rollSign

    local measRateP = a.fPitchRate * a.pitchSign
    local measRateR = a.fRollRate  * a.rollSign
    local rateErrP  = -measRateP
    local rateErrR  = -measRateR

    -- Canli 3-Eksen CoM & Asimetrik Levitation Auto-Trim
    -- Trim, YALNIZCA açısal hız ve sapma küçükken (durağan eksende) çok yavaş öğrenilir.
    -- Dinamik yuvarlanma/yunuslama salınımında trim dondurulur (Limit Cycle Koruması).
    local isCalmPitch = math.abs(pitch - tgtPitch) < 0.15 and math.abs(a.fPitchRate) < 0.08
    local isCalmRoll  = math.abs(roll - tgtRoll)   < 0.12 and math.abs(a.fRollRate)  < 0.05
    local isActive    = (not isZeroThrottleManual) and ((apMode ~= "MANUAL") or (baseLift > 1.5))

    if isActive then
        if isCalmPitch then
            a.trimPitch = clamp(a.trimPitch + (angleErrP * 1.10 + rateErrP * 0.25) * (a.trimLearnRate or 1.0) * safeDt, -1.0, 1.0)
        else
            -- If pitch is tilted, bleed off any trim pushing in the direction of the error
            if (pitch > tgtPitch and a.trimPitch > 0) or (pitch < tgtPitch and a.trimPitch < 0) then
                local decay = safeDt * 0.6
                if a.trimPitch > 0 then
                    a.trimPitch = math.max(0.0, a.trimPitch - decay)
                else
                    a.trimPitch = math.min(0.0, a.trimPitch + decay)
                end
            end
        end
        if isCalmRoll then
            a.trimRoll = clamp(a.trimRoll + (angleErrR * 0.25 + rateErrR * 0.08) * safeDt, -0.6, 0.6)
        else
            if (roll > tgtRoll and a.trimRoll > 0) or (roll < tgtRoll and a.trimRoll < 0) then
                local decay = safeDt * 0.4
                if a.trimRoll > 0 then
                    a.trimRoll = math.max(0.0, a.trimRoll - decay)
                else
                    a.trimRoll = math.min(0.0, a.trimRoll + decay)
                end
            end
        end
        self.pitchBias = a.trimPitch
        self.rollBias  = a.trimRoll
    end

    local pidPitch = self.msPitchPID:compute(tgtPitch, pitch, safeDt)
    local pidRoll  = self.msRollPID:compute(tgtRoll, roll, safeDt)

    -- Dogrudan acisal hiz sonumlemesi: burun yunuslama hizini (wx) ve yalpalama hizini (wz) aninda frenler
    local wxGain = self.dampWx or 2.5
    local wxDamp = clamp(a.fPitchRate * wxGain, -1.8, 1.8)
    local wzGain = self.dampWz or 3.0
    local wzDamp = clamp(a.fRollRate  * wzGain, -1.0, 1.0)

    -- Anti-Oscillation Tork Limitleri (Aktuator Doyum ve Salinim Korumasi)
    local totalPitchTorque = clamp((a.trimPitch or 0.0) + (pidPitch * a.pitchSign) - (wxDamp * a.pitchSign), -3.0, 3.0)
    -- YALPALAMA (ROLL) TORQUE KISITLAMASI: Dar gövde eylemsizliği (Izz=3.72e6) için aşırı tork üretilmez (+-1.2 maks)
    local totalRollTorque  = clamp((a.trimRoll  or 0.0) + (pidRoll  * a.rollSign)  - (wzDamp * a.rollSign),  -1.2, 1.2)

    -- Anti-dive ve dik aci korumasi (Zarfta kalma kurali)
    local absPitchDeg = math.abs(math.deg(pitch))
    if absPitchDeg > 16.0 then
        local emergencyBoost = clamp((absPitchDeg - 16.0) * 0.35, 0.0, 4.5)
        if pitch > 0 then
            totalPitchTorque = clamp(totalPitchTorque - emergencyBoost * a.pitchSign, -10.5, 10.5)
        else
            totalPitchTorque = clamp(totalPitchTorque + emergencyBoost * a.pitchSign, -10.5, 10.5)
        end
    end
    tel.pitchWarning = (absPitchDeg > 14.0)

    -- HOVER modunda pilot gazi sifirken aktif yatay kayma freni
    if apMode == "HOVER" and (ap.baseThrottle or 0) == 0 and absPitchDeg < 4.0 and math.abs(math.deg(roll)) < 4.0 then
        local hdg = tel.heading or yaw or 0
        local cosH = math.cos(hdg)
        local sinH = math.sin(hdg)
        local vx = (tel.velocity and tel.velocity.x) or 0
        local vz = (tel.velocity and tel.velocity.z) or 0
        local fwdSpeed = vx * (-sinH) + vz * cosH
        local latSpeed = -(vx * cosH + vz * sinH)
        if math.abs(fwdSpeed) > 0.05 then
            local brakePitch = clamp(fwdSpeed * 0.30, -0.8, 0.8)
            totalPitchTorque = clamp(totalPitchTorque + brakePitch, -9.5, 9.5)
        end
        if math.abs(latSpeed) > 0.05 then
            local brakeRoll = clamp(-latSpeed * 0.15, -0.4, 0.4)
            totalRollTorque = clamp(totalRollTorque + brakeRoll, -1.5, 1.5)
        end
    end

    -- Hook into AVX onMix modules (wing leveling altimeter, sky anchor)
    local tHook = { pitch = totalPitchTorque, roll = totalRollTorque, surge = 0, alt = baseLift, yaw = 0 }
    if self.hook then
        self:hook("onMix", tel, tHook, safeDt)
        totalPitchTorque = clamp(tHook.pitch or totalPitchTorque, -10.5, 10.5)
        totalRollTorque  = clamp(tHook.roll or totalRollTorque, -1.8, 1.8)
        if tHook.alt then baseLift = clamp(tHook.alt, 0.0, 15.0) end
    end

    -- Yaw (Pruva) Donusu
    local yawTorque = 0.0
    local tgtHdg = ap.targetHeading or ap.targetHdg
    if apMode ~= "MANUAL" and tgtHdg then
        local hdgErr = (tgtHdg - yaw) * a.yawSign
        if hdgErr > math.pi then hdgErr = hdgErr - 2 * math.pi end
        if hdgErr < -math.pi then hdgErr = hdgErr + 2 * math.pi end
        yawTorque = clamp(self.yawPID:compute(0, -hdgErr, safeDt), -3.0, 3.0)
    end
    if tHook.yaw and math.abs(tHook.yaw) > 0 then
        yawTorque = clamp(yawTorque + tHook.yaw, -3.0, 3.0)
    end

    -- 5. FIZIKSEL MOMENT KOLU KATSAYISI (Lf=42m, Lr=16m, 4 On Motor, 8 Arka Motor -> gammaFront = 0.762)
    -- On motorlar burnun cok ilerisinde oldugundan ayni gazda 1.31 kat daha fazla kaldirma torku uretir.
    -- Bu yuzden On taban gucu gammaFront ile dengelenir.
    local gammaFront = m.gammaFront or 0.762
    local rearBase  = clamp(baseLift, 0.0, 15.0)
    local frontBase = clamp(baseLift * gammaFront, 0.0, 15.0)

    -- Dalistan cikista on motorlarin gazini koru
    local pitchDeg = math.deg(pitch)
    if pitchDeg < -6.0 and baseLift < (a.hoverBase or 8.9) then
        local unpenalizedFront = clamp((a.hoverBase or 8.9) * gammaFront, 0.0, 15.0)
        frontBase = math.max(frontBase, unpenalizedFront)
    end

    -- 4-Kanal Denge Mikseri (FL, RL, FR, RR)
    -- Dikey kaldirma rotorlari sadece Lift, Pitch ve Roll dengeler; Yaw ise kuyruk iticileri ve vectoring gyrolarla yapilir
    local rawFloat = {
        frontBase + totalPitchTorque + totalRollTorque, -- 1: Sol On (FL)
        rearBase  - totalPitchTorque + totalRollTorque, -- 2: Sol Arka (RL)
        frontBase + totalPitchTorque - totalRollTorque, -- 3: Sag On (FR)
        rearBase  - totalPitchTorque - totalRollTorque  -- 4: Sag Arka (RR)
    }

    -- Multirotor Doyma Yonetimi (Desaturate Pair): Kollektif doyuma ulasinca roll/pitch otoritesini korur
    local function desaturatePair(l, r, lo, hi)
        local mx = math.max(l, r)
        if mx > hi then
            local ov = mx - hi
            l, r = l - ov, r - ov
        end
        local mn = math.min(l, r)
        if mn < lo then
            local un = lo - mn
            l, r = l + un, r + un
        end
        return clamp(l, lo, hi), clamp(r, lo, hi)
    end

    if isZeroThrottleManual then
        rawFloat = { 0.0, 0.0, 0.0, 0.0 }
    else
        local minFront = (apMode == "HOVER" or baseLift >= 4.0) and 3.5 or 0.0
        local minRear  = (apMode == "HOVER" or baseLift >= 4.0) and 3.5 or 0.0
        rawFloat[1], rawFloat[3] = desaturatePair(rawFloat[1], rawFloat[3], minFront, 15.0)
        rawFloat[2], rawFloat[4] = desaturatePair(rawFloat[2], rawFloat[4], minRear,  15.0)
    end

    -- 6. 20 Hz DELTA-SIGMA KESIRLI DARBE MODULASYONU (PWM Dithering)
    local sig = {}
    for i = 1, 4 do
        local clamped = math.max(0.0, math.min(15.0, rawFloat[i]))
        if clamped <= 0.05 or clamped >= 14.95 then
            sig[i] = math.floor(clamped + 0.5)
            a.ditherAcc[i] = 0
        else
            local desired = clamped + (a.ditherAcc[i] or 0)
            local outInt  = math.floor(desired + 0.5)
            outInt = math.max(0, math.min(15, outInt))
            a.ditherAcc[i] = desired - outInt
            sig[i] = outInt
        end
    end

    local flSig, rlSig, frSig, rrSig = sig[1], sig[2], sig[3], sig[4]

    -- 7. GYROSCOPIC PROPELLER BEARING (3D Vektoru & Aktif Downforce Destegi)
    local numGyros = #(self.gyros or {})
    if numGyros > 0 then
        local gyroPitchTrim = -0.025
        local downforceRad = math.rad(downforceAngle or 0.0)
        local pitchTilt = math.max(-0.25, math.min(0.25, gyroPitchTrim + downforceRad + (totalPitchTorque * 0.038)))
        local rollTilt  = math.max(-0.18, math.min(0.18, -totalRollTorque * 0.032))
        local yawTilt   = math.max(-0.15, math.min(0.15, yawTorque * 0.035))

        local halfGyros = math.floor(numGyros / 2)
        local effDownVal = (downforceAngle < 0 and downforceAngle or (pitchTilt < 0 and pitchTilt or rollTilt))
        local portVec = {
            x = rollTilt, y = math.cos(pitchTilt + yawTilt), z = math.sin(pitchTilt + yawTilt),
            [1] = effDownVal,
            rollTilt, math.cos(pitchTilt + yawTilt), math.sin(pitchTilt + yawTilt),
            downforce = downforceAngle
        }
        local stbdVec = {
            x = rollTilt, y = math.cos(pitchTilt - yawTilt), z = math.sin(pitchTilt - yawTilt),
            [1] = effDownVal,
            rollTilt, math.cos(pitchTilt - yawTilt), math.sin(pitchTilt - yawTilt),
            downforce = downforceAngle
        }

        for gIdx, gyro in ipairs(self.gyros) do
            local vec = (gIdx <= halfGyros) and portVec or stbdVec
            if tasks then
                table.insert(tasks, function() safeCall(gyro.setManualTarget, vec) end)
            elseif gyro and gyro.setManualTarget then
                safeCall(gyro.setManualTarget, vec)
            end
        end
    end

    self.lastMotorSignals = { flSig, rlSig, frSig, rrSig }
    self.lastMothershipState = {
        fl    = flSig,
        rl    = rlSig,
        fr    = frSig,
        rr    = rrSig,
        flRpm = math.floor((flSig / 15.0) * 256 + 0.5),
        rlRpm = math.floor((rlSig / 15.0) * 256 + 0.5),
        frRpm = math.floor((frSig / 15.0) * 256 + 0.5),
        rrRpm = math.floor((rrSig / 15.0) * 256 + 0.5),
        rearL = (self.lastMothershipState and self.lastMothershipState.rearL) or 0,
        rearC = (self.lastMothershipState and self.lastMothershipState.rearC) or 0,
        rearR = (self.lastMothershipState and self.lastMothershipState.rearR) or 0
    }
    tel.mothership = self.lastMothershipState
    self.lastLiftForcePN = ((flSig + rlSig + frSig + rrSig) / 60.0) * (m.maxLiftForce or 268606.0)

    -- 10 saniyede bir ogrenilen yeni dengeyi diske kaydet
    a.saveTimer = a.saveTimer + safeDt
    if a.saveTimer >= 10.0 then
        a.saveTimer = 0.0
        self:saveAdaptiveState()
    end

    return rawFloat[1], rawFloat[3], rawFloat[2], rawFloat[4], (tHook and tHook.surge) or 0
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

    -- Supports Create Rotation Speed Controllers (-256..+256 RPM with 1-RPM resolution) and 0..15 Signal / Throttle Lever peripherals
    local function driveSignal(dev, sig, inv)
        if dev.setTargetSpeed then
            local rpm = math.floor((sig / 15.0) * 256 + 0.5)
            if inv then rpm = -rpm end
            callKinetic(dev, dev.setTargetSpeed, rpm)
            return
        end
        local clampedSig = math.floor(clamp(math.abs(sig), 0, 15) + 0.5)
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
        end
        if dev.setOutput then
            for _, s in ipairs({ "front", "back", "left", "right", "top", "bottom" }) do
                pcall(dev.setOutput, s, finalActive)
            end
            called = true
        end
        if not called then
            driveSignal(dev, sigVal, inv)
        end
    end

    -- Emits analog & digital redstone for Zeppelin Hot Air Burners (only to direct or assigned burner sides)
    local function emitRedstoneBurner(sig)
        if redstone and redstone.setAnalogOutput then
            for _, side in ipairs({ "left", "right", "front", "back", "top", "bottom" }) do
                local cfg = self:getDeviceConfig("RS:" .. side)
                if cfg.role == "LIFT_BURNER" then
                    local outSig = cfg.invert and (15 - sig) or sig
                    pcall(redstone.setAnalogOutput, side, outSig)
                    if redstone.setOutput then pcall(redstone.setOutput, side, outSig > 0) end
                elseif cfg.role == "AUTO" then
                    local isDirectBurner = false
                    if peripheral and peripheral.getType then
                        local okT, pType = pcall(peripheral.getType, side)
                        if okT and pType ~= nil then
                            local pStr = tostring(pType):lower()
                            if pStr:find("burner") or pStr:find("gas_provider") then
                                isDirectBurner = true
                            end
                        end
                    end
                    if isDirectBurner then
                        local outSig = cfg.invert and (15 - sig) or sig
                        pcall(redstone.setAnalogOutput, side, outSig)
                        if redstone.setOutput then pcall(redstone.setOutput, side, outSig > 0) end
                    end
                end
            end
        end
    end

    -- 1. Landing Gear Brakes, Inverted Clutches, Gearshifts & Steering / Rudder Deflection
    local brakeVal = self.ap.parkingBrake and 1.0 or 0.0
    local steerVal = 0.0
    local steerHeld = false
    if self.steerWheel then
        if self.steerWheel.isHeld and safeCall(self.steerWheel.isHeld) == true then
            steerHeld = true
        end
        local rawWheel = tonumber(safeCall(self.steerWheel.getNormalizedAngle))
           or (self.steerWheel.getAngle and (tonumber(safeCall(self.steerWheel.getAngle)) or 0) / 90.0)
           or tonumber(safeCall(self.steerWheel.getSteering))
        if rawWheel and (steerHeld or math.abs(rawWheel) > 0.02) then
            steerVal = clamp(rawWheel, -1.0, 1.0)
        end
    end

    -- System 3 & System 4: Ground Wheel Steering & Physical Rudder Yaw Control
    if self.ap.enabled and self.ap.hdgHold and not steerHeld and math.abs(steerVal) < 0.02 then
        steerVal = clamp(yawDiff * 0.1667, -1.0, 1.0)
    elseif not self.ap.enabled and math.abs(steerVal) < 0.02 and self.ap.manualYaw and self.ap.manualYaw ~= 0 then
        steerVal = clamp((self.ap.manualYaw or 0) / 6.0, -1.0, 1.0)
    end

    tel.steerCmd = steerVal
    tel.rudderDeflectionDeg = math.floor(steerVal * 45.0 + 0.5)

    -- Drive System 3: Wheel Mounts (Ground Taxi Steering & Braking)
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
    local isSpinTestingAny = (self.spinTest and self.spinTest.ticks and self.spinTest.ticks > 0) or false
    local isAnchorThrust = (self.ap.mode == "ANCHOR" and tel.anchor and math.abs(tel.anchor.surge or 0) > 0.5)
    local clutchCut = (self.ap.mode == "HOVER") or self.ap.parkingBrake or (self.ap.baseThrottle <= 0 and not isAnchorThrust)
    for _, cl in ipairs(self.clutches or {}) do
        local clName = (peripheral and peripheral.getName and pcall(peripheral.getName, cl) and peripheral.getName(cl)) or nil
        local clCfg  = clName and self:getDeviceConfig(clName) or { role = "AUTO", invert = false }
        if clCfg.role == "AUTO" or clCfg.role == "CLUTCH_BRAKE" then
            local clType = (clName and peripheral and peripheral.getType and pcall(peripheral.getType, clName) and peripheral.getType(clName)) or ""
            local clBlk  = (type(cl.getBlockId) == "function" and tostring(safeCall(cl.getBlockId) or "")) or ""
            local isNormalClutch = (not (tostring(clName or "") .. " " .. tostring(clType) .. " " .. clBlk):lower():find("inverted"))
                and ((tostring(clName or "") .. " " .. tostring(clType) .. " " .. clBlk):lower():find("clutch") ~= nil)
            local devInv = clCfg.invert or false
            local totalInv = (self.clutchPolarInvert ~= devInv)
            if isNormalClutch then totalInv = not totalInv end

            local engageActive = isSpinTestingAny or (not clutchCut)
            local engageSig = engageActive and 15 or 0
            table.insert(tasks, function()
                driveBooleanOrSignal(cl, engageActive, engageSig, totalInv, "clutch")
            end)
        end
    end

    -- Drive Gearshifts (Forward / Backward Movement via [G], [W]/[S], or Sky Anchor reverse drift)
    local revActive = (self.ap.reverseGear == true) or (self.ap.mode == "ANCHOR" and tel.anchor and (tel.anchor.surge or 0) < -0.5)
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

    -- Compute Mothership / Gunship Adaptive Cascade INDI Matrix (Zero Static Gamma, 3-Axis Auto-Trim & Active Downforce)
    local isMothershipOrGunship = (self.vehicleType == "MOTHERSHIP" or self.vehicleType == "GUNSHIP")
    local altCmd = 0
    local pitchTrim = 0
    local rollTrim  = 0
    local surgeTrim = 0
    local liftFL, liftFR, liftRL, liftRR = 0, 0, 0, 0
    local rawLiftFL, rawLiftFR, rawLiftRL, rawLiftRR = 0, 0, 0, 0
    local fwdSig = 0

    if isMothershipOrGunship then
        rawLiftFL, rawLiftFR, rawLiftRL, rawLiftRR, surgeTrim = self:stepGunshipAdaptive(tel, dt, tasks)
        liftFL = math.floor(rawLiftFL + 0.5)
        liftFR = math.floor(rawLiftFR + 0.5)
        liftRL = math.floor(rawLiftRL + 0.5)
        liftRR = math.floor(rawLiftRR + 0.5)

        -- Dispatch directly to gearboxes (Analog Transmissions) if 4 or 8 present
        if #self.gearboxes >= 4 then
            local gbSigs = { liftFL, liftRL, liftFR, liftRR }
            for idx, gb in ipairs(self.gearboxes) do
                local groupIdx = ((idx - 1) % 4) + 1
                local targetSig = gbSigs[groupIdx]
                table.insert(tasks, function() driveSignal(gb, targetSig, false) end)
            end
        end

        -- Forward thrust command & Anti-Dive governor for rear propulsion thrusters
        local fwdBase = (revActive and -mainThrottleSig or mainThrottleSig) + (surgeTrim or 0)
        fwdSig = clutchCut and 0 or fwdBase

        local absPitchDeg = math.abs(math.deg(tel.pitch or 0))
        if absPitchDeg > 8.0 and fwdSig > 0 then
            local diveFactor = math.max(0.0, 1.0 - ((absPitchDeg - 8.0) / 14.0))
            fwdSig = fwdSig * diveFactor
        end
        if absPitchDeg > 20.0 then
            fwdSig = 0
            if (self.ap.mode == "CRUISE" or self.ap.mode == "LNAV") and self.ap.enabled then
                self:setMode("HOVER", tel)
            end
        end
    end
    self.prevRoll  = tel.roll
    self.prevPitch = tel.pitch

    local turnYaw = 0
    if not (not self.ap.enabled and self.ap.parkingBrake) then
        if clutchCut and math.abs(steerVal) < 0.02 and (self.ap.manualYaw or 0) == 0 then
            turnYaw = 0
        else
            turnYaw = self.ap.hdgHold and yawDiff or ((steerVal ~= 0 and (steerVal * 6.0)) or (self.ap.manualYaw or 0))
        end
    end
    local minRear = revActive and -15 or 0
    local rearL = math.floor(clamp(fwdSig - turnYaw, minRear, 15) + 0.5)
    local rearC = math.floor(clamp(fwdSig, minRear, 15) + 0.5)
    local rearR = math.floor(clamp(fwdSig + turnYaw, minRear, 15) + 0.5)

    if not isMothershipOrGunship then
        self.lastMothershipState = {
            fl = liftFL, fr = liftFR, rl = liftRL, rr = liftRR,
            flRpm = math.floor((clamp(rawLiftFL, 0, 15) / 15.0) * 256 + 0.5),
            frRpm = math.floor((clamp(rawLiftFR, 0, 15) / 15.0) * 256 + 0.5),
            rlRpm = math.floor((clamp(rawLiftRL, 0, 15) / 15.0) * 256 + 0.5),
            rrRpm = math.floor((clamp(rawLiftRR, 0, 15) / 15.0) * 256 + 0.5),
            rearL = rearL, rearC = rearC, rearR = rearR
        }
    else
        self.lastMothershipState.rearL = rearL
        self.lastMothershipState.rearC = rearC
        self.lastMothershipState.rearR = rearR
    end
    tel.mothership = self.lastMothershipState

    -- Route custom I/O role mappings (Hot-plug peripherals, Mothership 7-motor roles & Redstone sides)
    self.alertStrobeTick = ((self.alertStrobeTick or 0) + 1) % 480
    local anyLiftActive = (rawLiftFL > 0 or rawLiftFR > 0 or rawLiftRL > 0 or rawLiftRR > 0) or isSpinTestingAny
    local spinRole = (isSpinTestingAny and self.spinTest.name and self.spinTest.name ~= "ALL")
        and self:getDeviceConfig(self.spinTest.name).role or nil

    local function routeCustomRoleDevices(bSig)
        for _, item in ipairs(self.ioDevices or {}) do
            local cfg = self:getDeviceConfig(item.name)
            local role = cfg.role
            local inv = cfg.invert == true
            local itemCombined = (tostring(item.name or "") .. " " .. tostring(item.kind or "")):lower()
            local isClutchDev = (not item.isRedstone) and (
                itemCombined:find("clutch") ~= nil
                or itemCombined:find("redstone_relay") ~= nil
                or (item.handle and not item.handle.setTargetSpeed and (type(item.handle.setPowered) == "function" or type(item.handle.setOutput) == "function"))
            )
            local isNormalClutchDev = isClutchDev and itemCombined:find("clutch") ~= nil and (not itemCombined:find("inverted"))

            -- Spin Test Override ([T] in I/O Configurator or Engineering Deck)
            if self.spinTest and (self.spinTest.name == item.name or self.spinTest.name == "ALL") and not item.isRedstone and item.handle then
                local dev = item.handle
                if isClutchDev then
                    local totalInv = (self.clutchPolarInvert ~= inv)
                    if isNormalClutchDev then totalInv = not totalInv end
                    table.insert(tasks, function()
                        driveBooleanOrSignal(dev, true, 15, totalInv, "clutch")
                    end)
                else
                    table.insert(tasks, function()
                        driveSignal(dev, 8, inv)
                    end)
                end
            elseif role ~= "AUTO" or (inv and item.isRedstone) then
                local sig = nil
                local boolState = nil
                local roleSigs = {
                    LIFT_FL = rawLiftFL, LIFT_FR = rawLiftFR, LIFT_RL = rawLiftRL, LIFT_RR = rawLiftRR,
                    REAR_LEFT = rearL, REAR_CENTER = rearC, REAR_RIGHT = rearR,
                    THRUST_MAIN = mainThrottleSig, THRUST_PORT = portSignal, THRUST_STBD = stbdSignal,
                    AUX_BOOST = boostSignal
                }
                sig = roleSigs[role]
                if sig ~= nil and isClutchDev then
                    -- Individual Inverted Clutch in front of a specific motor (LIFT_FL..REAR_RIGHT)
                    local roleTesting = isSpinTestingAny and (self.spinTest.name == "ALL" or spinRole == role or spinRole == "AUTO")
                    boolState = (math.abs(sig) > 0) or roleTesting
                    sig = boolState and 15 or 0
                elseif sig == nil then
                    if role == "LIFT_BURNER" or (role == "AUTO" and item.isRedstone) then
                        sig = bSig
                    elseif role == "CLUTCH_LIFT" then
                        boolState = anyLiftActive
                        sig = anyLiftActive and 15 or 0
                    elseif role == "CLUTCH_BRAKE" then
                        boolState = isSpinTestingAny or (not clutchCut)
                        sig = boolState and 15 or math.max(0, clutchCut and 0 or math.max(1, mainThrottleSig))
                    elseif role == "GEAR_REVERSE" then
                        boolState = revActive
                        sig = revActive and 15 or 0
                    elseif role == "RUDDER_YAW" then
                        sig = math.floor(clamp(8 + steerVal * 7, 0, 15) + 0.5)
                    elseif role == "ALARM_LIGHTS" then
                        local isRed = (self.alertLevel == "RED")
                        local isYel = (self.alertLevel == "YELLOW")
                        if isRed then
                            -- Strobe pattern: 16 ticks period (~0.8s), 10 ticks ON, 6 ticks OFF
                            local strobeOn = ((self.alertStrobeTick or 0) % 16) < 10
                            boolState = strobeOn
                            sig = strobeOn and 15 or 0
                        elseif isYel then
                            -- Slower flash: 24 ticks period (~1.2s), 12 ticks ON, 12 ticks OFF
                            local strobeOn = ((self.alertStrobeTick or 0) % 24) < 12
                            boolState = strobeOn
                            sig = strobeOn and 15 or 0
                        else
                            boolState = false
                            sig = 0
                        end
                    end
                end

                if item.isRedstone and sig ~= nil and redstone then
                    local clamped = math.floor(clamp(math.abs(sig), 0, 15))
                    local outSig = inv and (15 - clamped) or clamped
                    if redstone.setAnalogOutput then pcall(redstone.setAnalogOutput, item.side, outSig) end
                    if redstone.setOutput then pcall(redstone.setOutput, item.side, outSig > 0) end
                elseif not item.isRedstone and item.handle and role ~= "IGNORE" then
                    local dev = item.handle
                    table.insert(tasks, function()
                        if role == "RUDDER_YAW" then
                            local effSteer = inv and -steerVal or steerVal
                            if dev.setSteering then
                                safeCall(dev.setSteering, effSteer)
                            elseif dev.setTargetAngle then
                                safeCall(dev.setTargetAngle, effSteer * 45.0)
                            elseif dev.setTargetAngleRad then
                                safeCall(dev.setTargetAngleRad, effSteer * math.rad(45.0))
                            elseif dev.setAngle then
                                safeCall(dev.setAngle, effSteer * 45.0)
                            elseif dev.setAngleRad then
                                safeCall(dev.setAngleRad, effSteer * math.rad(45.0))
                            elseif sig ~= nil then
                                driveSignal(dev, sig, inv)
                            end
                        elseif boolState ~= nil then
                            local effInv = inv
                            if isClutchDev then
                                effInv = (self.clutchPolarInvert ~= inv)
                                if isNormalClutchDev then effInv = not effInv end
                            end
                            driveBooleanOrSignal(dev, boolState, sig or 0, effInv, isClutchDev and "clutch" or role)
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
        if self.blackbox then
            pcall(self.blackbox.record, self.blackbox, tel, self.ap, self.lastMothershipState, { dt = dt, pitchTrim = 0, rollTrim = 0 })
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

    if self.blackbox then
        pcall(self.blackbox.record, self.blackbox, tel, self.ap, self.lastMothershipState, {
            dt             = dt,
            pitchTrim      = pitchTrim,
            rollTrim       = rollTrim,
            diveFactor     = (diveFactor or 1.0),
            antiDiveActive = (noseDownDeg and noseDownDeg > 12.0)
        })
    end

    return tel
end

return Avionics
