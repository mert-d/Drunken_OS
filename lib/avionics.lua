-- lib/avionics.lua
-- Drunken OS - Create: Avionics & Aeronautics Flight Control Core
-- Supports Airships (Zeppelins) and Fixed-Wing / VTOL Aircraft

local Avionics = {}
Avionics.__index = Avionics

local ADAPTIVE_CFG_PATH = "/etc/avionics_adaptive.cfg"
local HOMEBASE_CFG_PATH = "/etc/avionics_homebase.cfg"
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
        ilsDev       = { loc = 0.0, gs = 0.0, dist = 0.0 },
        pendingCall  = nil,      -- Queued incoming ATC / tower command waiting for pilot accept/reject
        atcAutoAccept = false,   -- When true, incoming ATC calls execute automatically without prompt
        lastAtcNotice = nil,     -- Last human-readable ATC call / response notice
        rtbTransitAlt = nil,     -- Safe en-route cruise altitude maintained during long-range RTB
        obstacleAvoid = true,    -- Autonomous collision/island escape & climb recovery
        escape        = nil,     -- Active 3-phase obstacle escape state (BACKUP -> CLIMB -> BYPASS)
        escapeFloorAlt = nil     -- Elevated minimum transit altitude preserved after escaping an obstacle
    }

    -- Obstacle / Collision Detector Internal State
    self.obsStuckTime       = 0.0
    self.obsCheckPos        = nil
    self.obsPrevHorizSpeed  = 0.0
    self.obsAttempts        = 0
    self.obsLastEscapeClock = -999.0
    self.obsSimClock        = 0.0

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
    self.altPID   = createPID(0.85, 0.04, 0.00, -1.5, 1.5, 0.5) -- Dikey irtifa (Y) - hassas ince trim PI
    self.hdgPID   = createPID(7.50, 0.45, 2.00, -12.0, 12.0, 6.0)
    self.pitchPID = createPID(0.80, 0.05, 0.40, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)
    self.rollPID  = createPID(0.80, 0.05, 0.40, -MAX_GYRO_CONE_RAD, MAX_GYRO_CONE_RAD)
    self.yawPID   = createPID(4.00, 0.25, 2.10, -4.5, 4.5) -- Pruva (Psi)

    -- Mothership Quad/Octo Lift Gimbal Horizon Stabilization PIDs (Critically damped for smooth flight, no derivative noise)
    self.msPitchPID = createPID(10.0, 0.35, 1.80, -2.8, 2.8, 1.0) -- Calibrated anti-pitch oscillation
    self.msRollPID  = createPID(1.80, 0.02, 1.00, -1.0, 1.0, 0.2) -- Critically damped roll gain for narrow Izz (prevents limit cycles)
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
    self:loadHomeBase()

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
            pcall(f.write, textutils.serialize({
                profile   = self.profile,
                ioMap     = self.ioMap,
                pitchBias = self.pitchBias or 0.0,
                rollBias  = self.rollBias or 0.0,
                autotune  = self.autotuneParams
            }))
            pcall(f.close)
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

function Avionics:adjustManualLift(delta)
    local cur = self.manualLift
    if cur == nil then
        cur = (self.adaptive and self.adaptive.hoverBase) or (self.skyfireModel and self.skyfireModel.hoverBaseSig) or 8.90
    end
    self.manualLift = clamp(cur + (tonumber(delta) or 0.0), 0.0, 15.0)
    return self.manualLift
end

function Avionics:setManualLift(val)
    self.manualLift = clamp(tonumber(val) or 0.0, 0.0, 15.0)
    return self.manualLift
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

    -- Batch all independent mainThread peripheral reads into parallel.waitForAll
    local unpackFn = table.unpack or unpack
    local readTasks = {}
    local function addRead(fn)
        table.insert(readTasks, fn)
    end
    local function flushReads()
        if #readTasks == 0 then return end
        local batch = readTasks
        readTasks = {}
        if parallel and parallel.waitForAll then
            parallel.waitForAll(unpackFn(batch))
        else
            for _, fn in ipairs(batch) do fn() end
        end
    end

    -- Queue Batch 1: All independent sensors, physics pose, navigation & SCADA reads
    local altList = (self.altSensors and #self.altSensors > 1) and self.altSensors or (self.altSensor and { self.altSensor } or {})
    local altRes = {}
    for i, as in ipairs(altList) do
        local slot = {}
        altRes[i] = slot
        addRead(function() slot.a = tonumber(safeCall(as.getHeight)) or tonumber(safeCall(as.getAltitude)) end)
        addRead(function() slot.v = tonumber(safeCall(as.getVerticalSpeed)) end)
        addRead(function() slot.p = tonumber(safeCall(as.getAirPressure)) or tonumber(safeCall(as.getPressure)) end)
    end

    local gRads, gDegs, gPitchFallback, gRollFallback = nil, nil, nil, nil
    local gAcc, gRates = nil, nil
    if self.gimbal then
        local g = self.gimbal
        addRead(function()
            local rads = safeCall(g.getAnglesRad)
            if type(rads) == "table" and rads[1] and rads[2] then
                gRads = rads
            else
                local degs = safeCall(g.getAngles)
                if type(degs) == "table" and degs[1] and degs[2] then
                    gDegs = degs
                else
                    gPitchFallback = tonumber(safeCall(g.getPitchRad)) or tonumber(safeCall(g.getPitch)) or 0
                    gRollFallback  = tonumber(safeCall(g.getRollRad)) or tonumber(safeCall(g.getRoll)) or 0
                end
            end
        end)
        addRead(function()
            gAcc = safeCall(g.getLinearAcceleration)
        end)
        addRead(function()
            gRates = safeCall(g.getAngularRatesRad)
                  or safeCall(g.getAngularRates)
                  or safeCall(g.getAngularVelocity)
        end)
    end

    local sublevelPose, sublevelLinVel = nil, nil
    if _G.sublevel then
        if _G.sublevel.getLogicalPose then
            addRead(function()
                local okPose, pose = pcall(_G.sublevel.getLogicalPose)
                if okPose then sublevelPose = pose end
            end)
        end
        if _G.sublevel.getLinearVelocity then
            addRead(function()
                local okLv, lv = pcall(_G.sublevel.getLinearVelocity)
                if okLv then sublevelLinVel = lv end
            end)
        end
    end

    local navHdgRad, navHdgDeg, navHasTgt, navTgtTable, navTabPos = nil, nil, nil, nil, nil
    if self.nav then
        local navDev = self.nav
        addRead(function()
            local hRad = tonumber(safeCall(navDev.getHeadingRad))
            if hRad then
                navHdgRad = hRad
            else
                navHdgDeg = tonumber(safeCall(navDev.getHeading))
            end
        end)
        addRead(function()
            navHasTgt = safeCall(navDev.hasTarget)
            if navHasTgt == nil and navDev.getTarget then
                navTgtTable = safeCall(navDev.getTarget)
            end
        end)
        addRead(function()
            if navDev.getTablePosition then
                local okTab, tabPos = pcall(navDev.getTablePosition)
                if okTab then navTabPos = tabPos end
            elseif navDev.getBlockPos then
                local okTab, tabPos = pcall(navDev.getBlockPos)
                if okTab then navTabPos = tabPos end
            end
        end)
    end

    local velSensList = (self.velSensors and #self.velSensors > 0) and self.velSensors or (self.velSensor and { self.velSensor } or {})
    local vsRes = {}
    if #velSensList >= 2 then
        for i, vs in ipairs(velSensList) do
            local slot = {}
            vsRes[i] = slot
            addRead(function() slot.axis = tostring(safeCall(vs.getAxis) or ""):lower() end)
            addRead(function() slot.val = safeCall(vs.getVelocity) end)
        end
    elseif #velSensList == 1 then
        local vs = velSensList[1]
        local slot = {}
        vsRes[1] = slot
        addRead(function() slot.val = safeCall(vs.getVelocity) end)
    end

    local agl = nil
    if self.laserSensor then
        local ls = self.laserSensor
        addRead(function()
            agl = tonumber(safeCall(ls.getClosestHitDistance))
               or tonumber(safeCall(ls.getDistance))
               or tonumber(safeCall(ls.getHitDistance))
        end)
    end

    local radarRaw = nil
    if self.radar then
        local r = self.radar
        addRead(function()
            radarRaw = safeCall(r.getContact)
        end)
    end

    local wheelRes = {}
    for i, w in ipairs(self.wheels) do
        local slot = {}
        wheelRes[i] = slot
        addRead(function() slot.fric = tonumber(safeCall(w.getTouchingFriction)) or 0 end)
        addRead(function() slot.lifted = safeCall(w.isLiftedUp) end)
    end

    local engRes = {}
    for i, eng in ipairs(self.engines) do
        local slot = {}
        engRes[i] = slot
        addRead(function() slot.rpm = tonumber(safeCall(eng.getRpm)) or tonumber(safeCall(eng.getSpeed)) or 0 end)
        addRead(function() slot.over = (safeCall(eng.isOverstressed) == true) end)
        addRead(function() slot.bTime = tonumber(safeCall(eng.getBurnTime)) end)
        addRead(function() slot.tTime = tonumber(safeCall(eng.getTotalBurnTime)) end)
    end

    local clRes = {}
    for i, cl in ipairs(self.clutches or {}) do
        local slot = {}
        clRes[i] = slot
        addRead(function()
            slot.outSpd = tonumber(callKinetic(cl, cl.getOutputSpeed))
            if slot.outSpd == nil then
                slot.fallbackSpd = tonumber(callKinetic(cl, cl.getSpeed))
                                or tonumber(callKinetic(cl, cl.getGeneratedSpeed))
                                or 0
            end
        end)
        addRead(function() slot.over = (callKinetic(cl, cl.isOverstressed) == true) end)
    end

    local pollSc = (self.gpsTick % 5 == 1) or (self._cachedScRpm == nil)
    local scRes = {}
    if pollSc then
        for i, sc in ipairs(self.speedControllers or {}) do
            local slot = {}
            scRes[i] = slot
            addRead(function()
                slot.rpm = tonumber(callKinetic(sc, sc.getTargetSpeed))
                        or tonumber(callKinetic(sc, sc.getSpeed))
                        or tonumber(callKinetic(sc, sc.getOutputSpeed))
                        or 0
            end)
            addRead(function() slot.over = (callKinetic(sc, sc.isOverstressed) == true) end)
        end
    end

    local burnerRes = {}
    for i, b in ipairs(self.burners) do
        local slot = {}
        burnerRes[i] = slot
        addRead(function() slot.gt = safeCall(b.getGasType) end)
        addRead(function() slot.sig = tonumber(safeCall(b.getSignalStrength)) or 0 end)
        addRead(function() slot.act = (safeCall(b.isActive) == true) end)
        addRead(function() slot.vc = tonumber(safeCall(b.getBalloonVolumeChange)) end)
    end

    local transponderOn = false
    if self.controller then
        local ctrlDev = self.controller
        addRead(function()
            transponderOn = (safeCall(ctrlDev.isTransponderOn) == true)
        end)
    end

    flushReads()

    -- Queue Batch 2 ONLY if navigation_table has an active target
    local navTarget = nil
    local hasTgt = navHasTgt
    if hasTgt == nil and type(navTgtTable) == "table" and navTgtTable.hasTarget == true then
        hasTgt = true
    end
    if self.nav and hasTgt == true then
        local navDev = self.nav
        local tName, brgRad, dist, vOff, closure, tPos = nil, nil, nil, nil, nil, nil
        addRead(function() tName = safeCall(navDev.getTargetName) or safeCall(navDev.getTargetDisplayName) or safeCall(navDev.getTargetLabel) or "WAYPOINT" end)
        addRead(function()
            brgRad = tonumber(safeCall(navDev.getBearingRad))
            if brgRad == nil and navDev.getBearing then
                local bDeg = tonumber(safeCall(navDev.getBearing))
                if bDeg then brgRad = math.rad(bDeg) end
            elseif brgRad == nil and navDev.getCurrentAngle then
                local aDeg = tonumber(safeCall(navDev.getCurrentAngle))
                if aDeg then brgRad = math.rad(aDeg) end
            end
        end)
        addRead(function() dist = tonumber(safeCall(navDev.getDistanceToTarget)) or tonumber(safeCall(navDev.getTargetDistance)) end)
        addRead(function() vOff = tonumber(safeCall(navDev.getVerticalOffsetToTarget)) end)
        addRead(function() closure = tonumber(safeCall(navDev.getClosureRate)) end)
        addRead(function() tPos = safeCall(navDev.getTargetPosition) or safeCall(navDev.getTargetPos) end)
        flushReads()
        navTarget = {
            active   = true,
            name     = tostring(tName or "WAYPOINT"),
            bearing  = brgRad or 0,
            distance = (dist and dist >= 0) and dist or 0,
            vOffset  = vOff or 0,
            closure  = closure or 0,
            pos      = tPos
        }
    end

    -- 1. Altitude & Vertical Speed (Averages all connected altitude_sensor blocks so corner tilt doesn't skew altitude)
    local alt = 0
    local sensorVsi = 0
    local pressure = 1.0
    if #altRes > 1 then
        local sumA, cntA, sumV, cntV = 0, 0, 0, 0
        local sumP, cntP = 0, 0
        for _, slot in ipairs(altRes) do
            if slot.a then sumA = sumA + slot.a; cntA = cntA + 1 end
            if slot.v then sumV = sumV + slot.v; cntV = cntV + 1 end
            if slot.p then sumP = sumP + slot.p; cntP = cntP + 1 end
        end
        if cntA > 0 then alt = sumA / cntA end
        if cntV > 0 then sensorVsi = sumV / cntV end
        if cntP > 0 then pressure = sumP / cntP end
    elseif #altRes == 1 then
        local slot = altRes[1]
        alt = slot.a or 0
        sensorVsi = slot.v or 0
        pressure = slot.p or 1.0
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
        if gRads then
            pitch = tonumber(gRads[1]) or 0
            roll  = tonumber(gRads[2]) or 0
        elseif gDegs then
            pitch = math.rad(tonumber(gDegs[1]) or 0)
            roll  = math.rad(tonumber(gDegs[2]) or 0)
        else
            local p = gPitchFallback or 0
            local r = gRollFallback or 0
            if math.abs(p) > math.pi then p = math.rad(p) end
            if math.abs(r) > math.pi then r = math.rad(r) end
            pitch = p
            roll  = r
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
        if type(gAcc) == "table" then
            local ax = tonumber(gAcc[1] or gAcc.x) or 0
            local ay = tonumber(gAcc[2] or gAcc.y) or 0
            local az = tonumber(gAcc[3] or gAcc.z) or 0
            linAcc = { x = ax, y = ay, z = az, ax, ay, az }
        end
        local wx, wy, wz = 0, 0, 0
        if type(gRates) == "table" then
            wx = tonumber(gRates[1] or gRates.x) or 0
            wy = tonumber(gRates[2] or gRates.y) or 0
            wz = tonumber(gRates[3] or gRates.z) or 0
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

    -- 3. Heading (Create: Avionics Navigation Table or Sublevel Pose)
    local heading = nil
    if sublevelPose and sublevelPose.orientation then
        local q = sublevelPose.orientation
        local qw = tonumber(q.a) or 0
        local qx = tonumber(q.v and q.v.x) or 0
        local qy = tonumber(q.v and q.v.y) or 0
        local qz = tonumber(q.v and q.v.z) or 0
        local fx = -2 * (qx * qz + qy * qw)
        local fz = 2 * (qx * qx + qy * qy) - 1
        heading = (math.atan2(fx, -fz) + 2 * math.pi) % (2 * math.pi)
    end
    if heading == nil and self.nav then
        if navHdgRad then
            heading = (navHdgRad + 2 * math.pi) % (2 * math.pi)
        elseif navHdgDeg then
            heading = (math.rad(navHdgDeg) + 2 * math.pi) % (2 * math.pi)
        end
    end

    -- 4. Velocity & Airspeed (Multi-sensor body reconstruction or single-axis sensor)
    local vel = { x = 0, y = vsi, z = 0 }
    local speed = 0
    local rawVel = 0
    if #velSensList > 0 then
        local reconstructed = false
        if #velSensList >= 2 then
            local hasX, hasZ = false, false
            for _, slot in ipairs(vsRes) do
                local val = tonumber(slot.val) or 0
                if slot.axis == "x" then vel.x = val; hasX = true
                elseif slot.axis == "z" then vel.z = val; hasZ = true
                elseif slot.axis == "y" then vel.y = val
                end
            end
            if hasX or hasZ then
                reconstructed = true
                speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
                rawVel = speed
            end
        end
        if not reconstructed and vsRes[1] then
            local v = vsRes[1].val
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
                local h = heading or self.prevHeading or 0
                vel.x =  horizSpeed * math.sin(h) * dirSign
                vel.z = -horizSpeed * math.cos(h) * dirSign
            end
        end
    end

    if (vel.x == 0 and vel.z == 0) and type(sublevelLinVel) == "table" and (sublevelLinVel.x or sublevelLinVel.z) then
        vel.x = tonumber(sublevelLinVel.x) or vel.x
        vel.y = tonumber(sublevelLinVel.y) or vel.y
        vel.z = tonumber(sublevelLinVel.z) or vel.z
        speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
        rawVel = speed
    end

    if heading == nil and (math.abs(vel.x) > 0.3 or math.abs(vel.z) > 0.3) then
        heading = (math.atan2(vel.x, -vel.z) + 2 * math.pi) % (2 * math.pi)
    end
    if heading == nil then
        heading = self.prevHeading or 0
    else
        self.prevHeading = heading
    end

    -- Update Position (Multi-Tier Navigation Sensor Fusion)
    -- Tier 1: CC:Sable SubLevel Physics Pose (Absolute Contraption Origin, 20Hz Real-Time)
    -- Tier 2: Navigation Table (Advanced Navigation Table or Standard Nav Table)
    -- Tier 3: GPS Constellation (Trilateration fallback if in open airspace)
    -- Tier 4: INS Dead-Reckoning (Internal speed & altitude integration fallback)
    local posSource = "INS"
    if sublevelPose and sublevelPose.position and type(sublevelPose.position.x) == "number" then
        self.pos.x = sublevelPose.position.x
        self.pos.y = sublevelPose.position.y
        self.pos.z = sublevelPose.position.z
        self.gpsLocked = true
        posSource = "SUBLEVEL"
    end

    if posSource == "INS" and navTabPos and type(navTabPos.x) == "number" and type(navTabPos.z) == "number" then
        self.pos.x = navTabPos.x
        self.pos.y = navTabPos.y or alt
        self.pos.z = navTabPos.z
        self.gpsLocked = true
        posSource = "NAV_TABLE"
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

    -- 5b. Radar Mk.1 Beam & Contact Processing
    local radarContact = nil
    local radarGpws = false
    if type(radarRaw) == "table" then
        radarContact = {
            kind         = radarRaw.kind,
            distance     = tonumber(radarRaw.distance) or 0,
            closingSpeed = tonumber(radarRaw.closingSpeed) or 0,
            name         = radarRaw.name
        }
        if radarRaw.kind == "terrain" and (tonumber(radarRaw.distance) or 999) < 40 and (tonumber(radarRaw.closingSpeed) or 0) > 2 then
            radarGpws = true
        end
    end

    -- 6. Weight-on-Wheels & Landing Gear Retraction (Create: Avionics Wheel Mount)
    local weightOnWheels = false
    local gearRetracted = false
    for _, slot in ipairs(wheelRes) do
        if (slot.fric or 0) > 0 then
            weightOnWheels = true
        end
        if slot.lifted == true then
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
    for _, slot in ipairs(engRes) do
        maxRpm = math.max(maxRpm, math.abs(slot.rpm or 0))
        if slot.over then overstressed = true end
        if slot.bTime and slot.tTime and slot.tTime > 0 then
            totalFuel = totalFuel + slot.bTime
            maxFuel = maxFuel + slot.tTime
        end
    end

    for _, slot in ipairs(clRes) do
        if slot.outSpd ~= nil then
            clutchOutRpm = math.max(clutchOutRpm or 0, math.abs(slot.outSpd))
        end
        local clRpm = slot.outSpd or slot.fallbackSpd or 0
        maxRpm = math.max(maxRpm, math.abs(clRpm))
        if slot.over then overstressed = true end
    end

    if pollSc then
        local scMaxRpm = 0
        local scOver = false
        for _, slot in ipairs(scRes) do
            scMaxRpm = math.max(scMaxRpm, math.abs(slot.rpm or 0))
            if slot.over then scOver = true end
        end
        self._cachedScRpm = scMaxRpm
        self._cachedScOverstressed = scOver
    end
    maxRpm = math.max(maxRpm, self._cachedScRpm or 0)
    if self._cachedScOverstressed then overstressed = true end

    for _, slot in ipairs(burnerRes) do
        if gasType == "NONE" and slot.gt then
            gasType = tostring(slot.gt)
        end
        burnerActual = math.max(burnerActual, slot.sig or 0)
        if slot.act then burnerActive = true end
        if slot.vc ~= nil then balloonVolChange = balloonVolChange + slot.vc end
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
        manualLift       = self.manualLift or math.floor(((self.adaptive and self.adaptive.hoverBase) or (self.skyfireModel and self.skyfireModel.hoverBaseSig) or 8.90) + 0.5),
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
        transponder      = transponderOn
    }

    -- Record initial takeoff departure point for fallback RTB (Return To Base)
    if not self.takeoffPos and tel.pos and (tel.pos.x ~= 0 or tel.pos.z ~= 0) then
        self.takeoffPos = {
            x = math.floor(tel.pos.x + 0.5),
            y = math.floor((alt or 120) + 0.5),
            z = math.floor(tel.pos.z + 0.5),
            heading = heading or 0.0
        }
    end

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

local function isCalibratedHomeBase(b)
    if type(b) ~= "table" or b.calibrated == false then return false end
    local p = b.zeppelinMast or b.threshold or b.pos
    if type(p) ~= "table" then return false end
    return ((tonumber(p.x) or 0) ~= 0 or (tonumber(p.z) or 0) ~= 0)
end

local function homeBaseSignature(b)
    if type(b) ~= "table" then return "" end
    local thr = b.threshold or b.pos or b.zeppelinMast or {}
    local mast = b.zeppelinMast or b.threshold or b.pos or {}
    return string.format(
        "%s|%s|%.1f,%.1f,%.1f|%.1f,%.1f,%.1f|%.3f",
        tostring(b.baseName or ""),
        tostring(b.runwayId or ""),
        tonumber(thr.x) or 0, tonumber(thr.y) or 0, tonumber(thr.z) or 0,
        tonumber(mast.x) or 0, tonumber(mast.y) or 0, tonumber(mast.z) or 0,
        tonumber(b.rwyHeadingRad) or 0
    )
end

function Avionics:loadHomeBase()
    if not (fs and fs.exists and fs.exists(HOMEBASE_CFG_PATH)) then return false end
    if not (textutils and textutils.unserialize) then return false end
    local okO, f = pcall(fs.open, HOMEBASE_CFG_PATH, "r")
    if not okO or not f then return false end
    local okR, raw = pcall(f.readAll)
    pcall(f.close)
    if not okR or type(raw) ~= "string" or raw == "" then return false end
    local okU, data = pcall(textutils.unserialize, raw)
    if not okU or not isCalibratedHomeBase(data) then return false end

    local ref = data.zeppelinMast or data.threshold or data.pos
    local rx = tonumber(ref.x) or 0
    local ry = tonumber(ref.y) or 120
    local rz = tonumber(ref.z) or 0
    local thr = type(data.threshold) == "table" and data.threshold or { x = rx, y = ry, z = rz }
    local mast = type(data.zeppelinMast) == "table" and data.zeppelinMast or { x = rx, y = ry, z = rz }
    local pos = type(data.pos) == "table" and data.pos or { x = tonumber(mast.x) or rx, y = tonumber(mast.y) or ry, z = tonumber(mast.z) or rz }

    local clean = {
        type          = "AVIONICS_ILS_BEACON",
        baseName      = tostring(data.baseName or "ANA-US"),
        runwayId      = tostring(data.runwayId or "RWY-36"),
        calibrated    = true,
        threshold     = { x = tonumber(thr.x) or rx, y = tonumber(thr.y) or ry, z = tonumber(thr.z) or rz },
        zeppelinMast  = { x = tonumber(mast.x) or rx, y = tonumber(mast.y) or ry, z = tonumber(mast.z) or rz },
        pos           = { x = tonumber(pos.x) or rx, y = tonumber(pos.y) or ry, z = tonumber(pos.z) or rz },
        rwyHeadingRad = tonumber(data.rwyHeadingRad) or 0.0,
        glideSlopeRad = tonumber(data.glideSlopeRad) or math.rad(8.0),
        approachDist  = tonumber(data.approachDist) or 80.0
    }
    self.ap.homeBase = clean
    self._savedHomeBaseSig = homeBaseSignature(clean)
    return true
end

function Avionics:saveHomeBase(beacon)
    beacon = beacon or self.ap.homeBase
    if not isCalibratedHomeBase(beacon) then return false end
    if not (fs and fs.open and textutils and textutils.serialize) then return false end
    if fs.makeDir and not fs.exists("/etc") then pcall(fs.makeDir, "/etc") end

    local ref = beacon.zeppelinMast or beacon.threshold or beacon.pos
    local rx = tonumber(ref.x) or 0
    local ry = tonumber(ref.y) or 120
    local rz = tonumber(ref.z) or 0
    local thr = type(beacon.threshold) == "table" and beacon.threshold or { x = rx, y = ry, z = rz }
    local mast = type(beacon.zeppelinMast) == "table" and beacon.zeppelinMast or { x = rx, y = ry, z = rz }
    local pos = type(beacon.pos) == "table" and beacon.pos or { x = tonumber(mast.x) or rx, y = tonumber(mast.y) or ry, z = tonumber(mast.z) or rz }

    local payload = {
        type          = "AVIONICS_ILS_BEACON",
        baseName      = tostring(beacon.baseName or "ANA-US"),
        runwayId      = tostring(beacon.runwayId or "RWY-36"),
        calibrated    = true,
        threshold     = { x = tonumber(thr.x) or rx, y = tonumber(thr.y) or ry, z = tonumber(thr.z) or rz },
        zeppelinMast  = { x = tonumber(mast.x) or rx, y = tonumber(mast.y) or ry, z = tonumber(mast.z) or rz },
        pos           = { x = tonumber(pos.x) or rx, y = tonumber(pos.y) or ry, z = tonumber(pos.z) or rz },
        rwyHeadingRad = tonumber(beacon.rwyHeadingRad) or 0.0,
        glideSlopeRad = tonumber(beacon.glideSlopeRad) or math.rad(8.0),
        approachDist  = tonumber(beacon.approachDist) or 80.0
    }
    local ok, f = pcall(fs.open, HOMEBASE_CFG_PATH, "w")
    if ok and f then
        pcall(f.write, textutils.serialize(payload))
        pcall(f.close)
        self._savedHomeBaseSig = homeBaseSignature(payload)
        return true
    end
    return false
end

function Avionics:setHomeBase(ilsBeacon, skipSave)
    if type(ilsBeacon) ~= "table" then return end
    local newPos = ilsBeacon.zeppelinMast or ilsBeacon.threshold or ilsBeacon.pos
    if ilsBeacon.calibrated == false and self.ap.homeBase then
        local curPos = self.ap.homeBase.zeppelinMast or self.ap.homeBase.threshold or self.ap.homeBase.pos
        if curPos and ((tonumber(curPos.x) or 0) ~= 0 or (tonumber(curPos.z) or 0) ~= 0) then
            return
        end
    end
    if newPos and not ilsBeacon.pos then
        ilsBeacon.pos = { x = tonumber(newPos.x) or 0, y = tonumber(newPos.y) or 0, z = tonumber(newPos.z) or 0 }
    end
    self.ap.homeBase = ilsBeacon
    if (not skipSave) and isCalibratedHomeBase(ilsBeacon) then
        local sig = homeBaseSignature(ilsBeacon)
        if sig ~= self._savedHomeBaseSig then
            self:saveHomeBase(ilsBeacon)
        end
    end
end

function Avionics:setCurrentPosAsHomeBase(currentTel, baseName)
    local pos = (currentTel and currentTel.pos) or self.pos
    local px = pos and tonumber(pos.x) or 0
    local pz = pos and tonumber(pos.z) or 0
    local py = (currentTel and tonumber(currentTel.altitude)) or (pos and tonumber(pos.y)) or 120
    if px == 0 and pz == 0 then
        return false, "GECERSIZ KONUM (0,0)"
    end
    local rx = math.floor(px + 0.5)
    local ry = math.floor(py + 0.5)
    local rz = math.floor(pz + 0.5)
    local bName = (type(baseName) == "string" and baseName ~= "") and baseName or "ANA-US"
    local beacon = {
        type          = "AVIONICS_ILS_BEACON",
        baseName      = bName,
        runwayId      = "SHIP-HOME",
        calibrated    = true,
        threshold     = { x = rx, y = math.max(1, ry - 15), z = rz },
        zeppelinMast  = { x = rx, y = ry, z = rz },
        pos           = { x = rx, y = ry, z = rz },
        rwyHeadingRad = (currentTel and tonumber(currentTel.heading)) or self.lastHeading or 0.0,
        glideSlopeRad = math.rad(8.0),
        approachDist  = 80.0
    }
    self:setHomeBase(beacon, false)
    self.ap.lastAtcNotice = string.format("ANA US KAYDEDILDI: %s (%d,%d,%d)", bName, rx, ry, rz)
    return true, self.ap.lastAtcNotice, beacon
end

function Avionics:reverseHeading()
    local cur = self.ap.targetHdg or (self.lastHeading or 0.0)
    local newHdg = (cur + math.pi) % (2 * math.pi)
    self.ap.targetHdg = newHdg
    if self.hdgPID then self.hdgPID:reset() end
    return newHdg
end

function Avionics:engageRTB(currentTel)
    local hbPos = self.ap.homeBase and (self.ap.homeBase.zeppelinMast or self.ap.homeBase.threshold or self.ap.homeBase.pos)
    local isUncalibratedZero = self.ap.homeBase and (self.ap.homeBase.calibrated == false)
        and ((not hbPos) or ((tonumber(hbPos.x) or 0) == 0 and (tonumber(hbPos.z) or 0) == 0))

    if (not self.ap.homeBase) or isUncalibratedZero then
        local isMastShip = (self.vehicleType == "ZEPPELIN" or self.vehicleType == "MOTHERSHIP" or self.vehicleType == "GUNSHIP")
        if self.takeoffPos then
            self.ap.homeBase = {
                baseName      = "KALKIS NOKTASI",
                threshold     = { x = self.takeoffPos.x, y = self.takeoffPos.y, z = self.takeoffPos.z },
                zeppelinMast  = isMastShip and { x = self.takeoffPos.x, y = self.takeoffPos.y, z = self.takeoffPos.z } or nil,
                pos           = { x = self.takeoffPos.x, y = self.takeoffPos.y, z = self.takeoffPos.z },
                rwyHeadingRad = self.takeoffPos.heading or 0.0
            }
        else
            local rm = self.routeManager or (self.getRouteManager and self:getRouteManager())
            local poi = rm and rm.pois and rm.pois[1]
            if poi then
                self.ap.homeBase = {
                    baseName      = tostring(poi.name or "ANA-US"),
                    runwayId      = "POI-HOME",
                    calibrated    = true,
                    threshold     = { x = poi.x, y = math.max(1, (poi.y or 170) - 15), z = poi.z },
                    zeppelinMast  = isMastShip and { x = poi.x, y = poi.y or 170, z = poi.z } or nil,
                    pos           = { x = poi.x, y = poi.y or 170, z = poi.z },
                    rwyHeadingRad = 0.0
                }
            else
                return false
            end
        end
    end
    local mast = self.ap.homeBase.zeppelinMast or self.ap.homeBase.threshold or self.ap.homeBase.pos
    self.ap.rtbTransitAlt = math.max(((mast and tonumber(mast.y)) or 85) + 15.0, (currentTel and tonumber(currentTel.altitude)) or 0, self.ap.escapeFloorAlt or 0)
    self.ap.enabled       = true
    self.ap.altHold       = true
    self.ap.hdgHold       = true
    self.ap.parkingBrake  = false
    self.ap.reverseGear   = false
    self.ap.escape        = nil
    self.obsStuckTime     = 0.0
    self.obsCheckPos      = nil
    self.ap.mode          = "RTB"
    self.ap.lastAtcNotice = string.format("ANA US RTB: %s (%d,%d,%d)",
        tostring(self.ap.homeBase.baseName or "ANA-US"),
        math.floor((mast and tonumber(mast.x)) or 0),
        math.floor((mast and tonumber(mast.y)) or 0),
        math.floor((mast and tonumber(mast.z)) or 0)
    )

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
    local wasMode = self.ap.mode
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
    if modeName == "MANUAL" or modeName == "HOVER" or modeName == "ANCHOR" or modeName == "AUTOLAND" then
        self.ap.escape = nil
        self.obsStuckTime = 0.0
        self.obsCheckPos = nil
        self.ap.escapeFloorAlt = nil
    end
    if modeName == "MANUAL" then
        self.ap.enabled = false
        self.ap.altHold = false
        self.ap.hdgHold = false
        self.ap.rtbPhase = "NONE"
        local isGrounded = (currentTel and (currentTel.weightOnWheels == true or (currentTel.agl and currentTel.agl <= 2.5) or (currentTel.altitude and currentTel.altitude <= 2.0))) or (self.prevAlt and self.prevAlt <= 2.0)
        local isAirborne = not isGrounded
        if isAirborne then
            local eq = (self.adaptive and self.adaptive.hoverBase) or (self.skyfireModel and self.skyfireModel.hoverBaseSig) or 8.90
            self.manualLift = math.floor(eq + 0.5)
        else
            self.manualLift = 0.0
        end
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
        self:setMode("MANUAL", currentTel)
        self.ap.baseThrottle = 0
        self.ap.parkingBrake = true
        self.manualLift = 0
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
            local wpY = tonumber(msg.waypoint.y) or self.ap.targetAlt
            local safeTransit = tonumber(msg.waypoint.transitY)
            self.ap.waypoint = {
                x = tonumber(msg.waypoint.x) or 0,
                y = wpY,
                transitY = safeTransit,
                z = tonumber(msg.waypoint.z) or 0,
                name = tostring(msg.waypoint.name or (msg.beacon and msg.beacon.baseName) or "ATC-WP")
            }
            self.ap.targetAlt = safeTransit or self.ap.waypoint.y
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

function Avionics:receiveAtcCall(msg, currentTel, senderId)
    if type(msg) ~= "table" or msg.type ~= "AVIONICS_ATC_CMD" then
        return nil, nil
    end
    local myCall = (currentTel and currentTel.callsign) or self.callsign
    if msg.target and msg.target ~= "ALL" and msg.target ~= myCall then
        return nil, nil
    end

    if type(msg.beacon) == "table" and msg.beacon.type == "AVIONICS_ILS_BEACON" then
        self:setHomeBase(msg.beacon)
    end

    local cmd = tostring(msg.cmd or ""):upper()
    if cmd == "PARK" or cmd == "INS_SYNC" or msg.force == true or msg.requireConfirm == false or self.ap.atcAutoAccept == true then
        local ok, notice = self:executeAtcCommand(msg, currentTel)
        self.ap.pendingCall = nil
        self.ap.lastAtcNotice = notice
        return (ok and "EXECUTED" or "FAILED"), notice
    end

    local targetPos = nil
    if cmd == "RTB" then
        local tp = (msg.beacon and (msg.beacon.zeppelinMast or msg.beacon.threshold or msg.beacon.pos))
            or (self.ap.homeBase and (self.ap.homeBase.zeppelinMast or self.ap.homeBase.threshold or self.ap.homeBase.pos))
            or self.takeoffPos
        if tp then
            targetPos = { x = tonumber(tp.x) or 0, y = tonumber(tp.y) or 0, z = tonumber(tp.z) or 0 }
        end
    elseif (cmd == "WAYPOINT" or cmd == "LNAV") and type(msg.waypoint) == "table" then
        targetPos = {
            x = tonumber(msg.waypoint.x) or 0,
            y = tonumber(msg.waypoint.y) or (self.ap.targetAlt or 120),
            z = tonumber(msg.waypoint.z) or 0
        }
    end

    local baseName = tostring((msg.beacon and msg.beacon.baseName) or (self.ap.homeBase and self.ap.homeBase.baseName) or "KULE")
    local runwayId = tostring((msg.beacon and msg.beacon.runwayId) or (self.ap.homeBase and self.ap.homeBase.runwayId) or "RWY")
    self.ap.pendingCall = {
        id         = tostring(msg.timestamp or os.clock()),
        cmd        = cmd,
        baseName   = baseName,
        runwayId   = runwayId,
        targetPos  = targetPos,
        delta      = tonumber(msg.delta),
        targetAlt  = tonumber(msg.targetAlt),
        senderId   = senderId,
        receivedAt = (os.epoch and os.epoch("utc")) or os.time(),
        rawMsg     = msg
    }
    self.ap.lastAtcNotice = string.format("GELEN CAGRI [%s]: %s", baseName, cmd)
    return "PENDING", self.ap.lastAtcNotice
end

function Avionics:acceptPendingCall(currentTel)
    if self.ap.pendingCall then
        local call = self.ap.pendingCall
        self.ap.pendingCall = nil
        local ok, notice = self:executeAtcCommand(call.rawMsg, currentTel)
        self.ap.lastAtcNotice = ok and ("KABUL: " .. tostring(notice)) or ("HATA: " .. tostring(notice))
        return ok, notice, call
    end

    local nt = currentTel and currentTel.navTarget
    if nt and nt.active then
        local tx, ty, tz
        local curPos = (currentTel and currentTel.pos) or self.pos or { x = 0, y = 100, z = 0 }
        if type(nt.pos) == "table" and tonumber(nt.pos.x or nt.pos[1]) and tonumber(nt.pos.z or nt.pos[3]) then
            tx = tonumber(nt.pos.x or nt.pos[1])
            tz = tonumber(nt.pos.z or nt.pos[3])
            ty = tonumber(nt.pos.y or nt.pos[2]) or ((tonumber(currentTel.altitude) or 100) + (tonumber(nt.vOffset) or 0))
        else
            local d = tonumber(nt.distance) or 0
            local b = tonumber(nt.bearing) or 0
            tx = (tonumber(curPos.x) or 0) + d * math.sin(b)
            tz = (tonumber(curPos.z) or 0) - d * math.cos(b)
            ty = (tonumber(currentTel.altitude) or 100) + (tonumber(nt.vOffset) or 0)
        end
        local curAlt = tonumber(currentTel.altitude) or ty
        local safeCruiseY = math.max(ty + 15.0, curAlt)
        local dist = math.sqrt((tx - (tonumber(curPos.x) or 0)) ^ 2 + (tz - (tonumber(curPos.z) or 0)) ^ 2)
        self.ap.waypoint = {
            x        = tx,
            y        = ty,
            transitY = safeCruiseY,
            z        = tz,
            name     = tostring(nt.name or "MASA HEDEF")
        }
        self:setMode("LNAV", currentTel)
        self.ap.targetAlt = (dist > 100.0) and safeCruiseY or ty
        self.ap.lastAtcNotice = string.format(
            "MASA HEDEFI: %s (%d,%d,%d)",
            self.ap.waypoint.name,
            math.floor(tx + 0.5),
            math.floor(ty + 0.5),
            math.floor(tz + 0.5)
        )
        return true, self.ap.lastAtcNotice, nil
    end

    return false, "KABUL EDILECEK CAGRI/HEDEF YOK", nil
end

function Avionics:rejectPendingCall()
    if not self.ap.pendingCall then
        return false, "BEKLEYEN CAGRI YOK", nil
    end
    local call = self.ap.pendingCall
    self.ap.pendingCall = nil
    self.ap.lastAtcNotice = "REDDEDILDI: " .. tostring(call.cmd) .. " (" .. tostring(call.baseName) .. ")"
    return true, self.ap.lastAtcNotice, call
end

function Avionics:cancelObstacleEscape()
    self.ap.escape = nil
    self.obsStuckTime = 0.0
    self.obsCheckPos = nil
    return true
end

function Avionics:triggerObstacleEscape(currentTel, reason)
    local nowSec = self.obsSimClock or 0.0
    if (nowSec - (self.obsLastEscapeClock or -999.0)) > 120.0 then
        self.obsAttempts = 0
    end
    self.obsAttempts = (self.obsAttempts or 0) + 1

    if self.obsAttempts > 4 then
        self.ap.escape = nil
        self.obsStuckTime = 0.0
        self.obsAttempts = 0
        self:setMode("HOVER", currentTel)
        self.ap.lastAtcNotice = "ENGEL: 4 DENEME DOLDU -> HOVER (PILOT)"
        return false, self.ap.lastAtcNotice
    end

    local curAlt = (currentTel and tonumber(currentTel.altitude)) or (self.pos and self.pos.y) or self.ap.targetAlt or 120.0
    local curHdg = (currentTel and tonumber(currentTel.heading)) or self.ap.targetHdg or 0.0
    local curX = (currentTel and currentTel.pos and tonumber(currentTel.pos.x)) or (self.pos and self.pos.x) or 0.0
    local curZ = (currentTel and currentTel.pos and tonumber(currentTel.pos.z)) or (self.pos and self.pos.z) or 0.0

    local MAX_ESCAPE_ALT = 305.0
    local thinAir = (currentTel and currentTel.pressure and currentTel.pressure < 0.35)
    local climbStep = thinAir and 0.0 or ((self.obsAttempts >= 2) and 24.0 or 22.0)
    local climbAlt = math.min(MAX_ESCAPE_ALT, curAlt + climbStep)
    local nearCeiling = thinAir or ((climbAlt - curAlt) < 10.0)

    local bypassHdg = nil
    local bypassDur = 0.0
    if self.obsAttempts >= 2 or nearCeiling then
        local sign = (self.obsAttempts % 2 == 1) and 1 or -1
        local angle = nearCeiling and math.rad(65) or math.rad(35)
        bypassHdg = (curHdg + sign * angle) % (2 * math.pi)
        bypassDur = nearCeiling and 6.0 or 5.0
    end

    local prevEsc = self.ap.escape
    local resumeMode = (prevEsc and prevEsc.resumeMode)
        or ((self.ap.mode == "RTB" or self.ap.mode == "LNAV" or self.ap.mode == "CRUISE") and self.ap.mode)
        or "HOVER"
    local resumeThrottle = (prevEsc and prevEsc.resumeThrottle)
        or ((self.ap.baseThrottle and self.ap.baseThrottle > 0) and self.ap.baseThrottle)
        or 8
    local resumeTargetAlt = (prevEsc and prevEsc.resumeTargetAlt) or self.ap.targetAlt or curAlt

    self.ap.enabled = true
    self.ap.altHold = true
    self.ap.hdgHold = true
    self.ap.parkingBrake = false

    self.ap.escape = {
        active          = true,
        phase           = "BACKUP",
        phaseTime       = 0.0,
        backupDur       = (self.obsAttempts >= 2) and 5.5 or 4.5,
        attempt         = self.obsAttempts,
        maxAttempts     = 4,
        reason          = tostring(reason or "ENGEL"),
        startX          = curX,
        startZ          = curZ,
        startAlt        = curAlt,
        holdHdg         = curHdg,
        climbAlt        = climbAlt,
        bypassHdg       = bypassHdg,
        bypassDur       = bypassDur,
        resumeMode      = resumeMode,
        resumeThrottle  = resumeThrottle,
        resumeTargetAlt = resumeTargetAlt
    }

    self.obsStuckTime = 0.0
    self.obsCheckPos = { x = curX, z = curZ }
    self.ap.lastAtcNotice = string.format(
        "ENGEL KURTARMA #%d (%s): GERI + YUKSEL -> %.0fm",
        self.obsAttempts,
        tostring(reason or "ENGEL"),
        climbAlt
    )
    return true, self.ap.lastAtcNotice
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
    local ok, f = pcall(fs.open, ADAPTIVE_CFG_PATH, "w")
    if ok and f then
        pcall(f.write, textutils.serialize({
            hoverBase = tonumber(string.format("%.3f", a.hoverBase)),
            trimPitch = tonumber(string.format("%.3f", a.trimPitch)),
            trimRoll  = tonumber(string.format("%.3f", a.trimRoll)),
            pitchSign = a.pitchSign,
            rollSign  = a.rollSign,
            yawSign   = a.yawSign,
            motorMap  = a.motorMap
        }))
        pcall(f.close)
    end
end

function Avionics:stepGunshipAdaptive(tel, dt, tasks)
    local a = self.adaptive
    local safeDt = clamp(dt or 0.05, 0.02, 0.50)
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
    a.fVSpeed    = a.fVSpeed    * 0.10 + rawVSpeed    * 0.90

    local ap = self.autopilot or self.ap or {}
    local apMode = ap.mode or "MANUAL"
    local isGrounded = (tel and (tel.weightOnWheels == true or (tel.agl and tel.agl <= 2.5) or (tel.altitude and tel.altitude <= 2.0))) or (self.prevAlt and self.prevAlt <= 2.0)
    local isAirborne = not isGrounded
    local manualLift = self.manualLift or self.manualThrottle

    local isZeroThrottleManual = (not ap.enabled or apMode == "MANUAL") and
        (((manualLift or ap.baseThrottle or 0) <= 0) or
         (ap.parkingBrake and (not isAirborne or (manualLift or 0) <= 0)))

    -- 3. DIKEY ITKI VE CANLI LEVITATION (ANTIGRAVITY) OGRENICISI
    local baseLift = a.hoverBase or m.hoverBaseSig or 8.90
    local downforceAngle = 0.0

    if isZeroThrottleManual then
        self.msPitchPID:reset()
        self.msRollPID:reset()
        baseLift = 0.0
    elseif apMode == "MANUAL" then
        baseLift = clamp(manualLift or a.hoverBase or m.hoverBaseSig or 8.90, 0, 15)
    else
        local tgtAlt = ap.targetAltitude or ap.targetAlt or tel.altitude or 0
        local altErr = tgtAlt - (tel.altitude or 0)
        local absAltErr = math.abs(altErr)

        -- 1. Dış Çevrim: Tek Pürüzsüz Aşırı-Sönümlü Hedef Dikey Hız Zarfı (Create Pervane/Rotor Gecikmesi ~1.0 sn için faz-marjlı)
        -- Kp = 0.20 s^-1 (tau = 5.0 sn) -> 0.9-1.2 sn aktüatör/döngü gecikmesinde dahi salınımsız oturma
        local maxClimb = (apMode == "HOVER") and 3.00 or 3.40
        local maxDesc  = (apMode == "HOVER") and 1.80 or 2.20
        local targetVSpeed = clamp(altErr * 0.20, -maxDesc, maxClimb)

        -- 2. İç Çevrim: Doğrudan Dikey Hız Regülatörü (Kv = 0.58; kesintili altPID darbesi kaldırıldı)
        local vErr = targetVSpeed - a.fVSpeed
        local maxCmd = (absAltErr <= 2.5) and 1.20 or 2.40
        local altCmd = clamp(vErr * 0.58, -maxCmd, maxCmd)

        -- 3. Tek Sürekli Adaptif Denge Öğrenicisi (a.hoverBase):
        -- Hava yoğunluğu ve kütle değişimini kesintisiz öğrenir; aşırı düşüş/tırmanışta (|vy| >= 4.5) şişmeyi kilitler
        local isLevelAttitude = (math.abs(pitch) < 0.22) and (math.abs(roll) < 0.22)
        if isLevelAttitude and math.abs(a.fVSpeed) < 4.5 and (apMode == "HOVER" or apMode == "CRUISE" or apMode == "ANCHOR" or apMode == "LNAV" or apMode == "RTB") then
            local learnRate = 0.055
            a.hoverBase = clamp(a.hoverBase + (vErr * learnRate) * safeDt, 6.5, 13.5)
            m.hoverBaseSig = a.hoverBase
        end

        local baseCenter = a.hoverBase or m.hoverBaseSig or 8.90
        local rawLiftCmd = baseCenter + altCmd
        baseLift = clamp(rawLiftCmd, 0.0, 15.0)

        -- Faz Gecikmesiz Koruyucu Slew Limiti (40.0/sn: 20Hz'de 2.0/adım, 3Hz'de anlık frenleme -> pogo salınımını tamamen önler)
        if self.lastBaseLift and (apMode == "HOVER" or apMode == "CRUISE" or apMode == "ANCHOR") then
            local maxStep = 40.0 * safeDt
            baseLift = clamp(baseLift, self.lastBaseLift - maxStep, self.lastBaseLift + maxStep)
        end
        self.lastBaseLift = baseLift

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
    local absPitchDeg = math.abs(math.deg(pitch))
    local wxGain = self.dampWx or 2.20
    local wxMaxLimit = (absPitchDeg > 14.0) and 3.5 or 2.2
    local wxDamp = clamp(a.fPitchRate * wxGain, -wxMaxLimit, wxMaxLimit)

    local wzGain = self.dampWz or 1.80
    local wzDamp = clamp(a.fRollRate  * wzGain, -1.2, 1.2)

    -- Anti-Oscillation Tork Limitleri (Aktuator Doyum ve Salinim Korumasi)
    local maxTorqueLimit = (absPitchDeg > 16.0) and 4.2 or 2.8
    local totalPitchTorque = clamp((a.trimPitch or 0.0) + (pidPitch * a.pitchSign) - (wxDamp * a.pitchSign), -maxTorqueLimit, maxTorqueLimit)
    -- YALPALAMA (ROLL) TORQUE KISITLAMASI: Dar gövde eylemsizliği (Izz=3.72e6) için aşırı tork üretilmez (+-1.2 maks)
    local totalRollTorque  = clamp((a.trimRoll  or 0.0) + (pidRoll  * a.rollSign)  - (wzDamp * a.rollSign),  -1.2, 1.2)

    -- Faz-Duzlemi Anti-Dive ve Asiri Aci Korumasi:
    -- YALNIZCA gemi duzlukten uzaklasiyorsa (diverging) aktif kurtarma torku uygular.
    -- Eger gemi zaten duz konuma dogru donuyorsa (returning), kurtarma torku eklenmez; frenleme (wxDamp) devreye girer.
    if absPitchDeg > 16.0 then
        local pRate = a.fPitchRate * a.pitchSign
        local isDiverging = (pitch > 0 and pRate > -0.08) or (pitch < 0 and pRate < 0.08)
        if isDiverging then
            local emergencyBoost = clamp((absPitchDeg - 16.0) * 0.25, 0.0, 2.0)
            if pitch > 0 then
                totalPitchTorque = clamp(totalPitchTorque - emergencyBoost * a.pitchSign, -4.5, 4.5)
            else
                totalPitchTorque = clamp(totalPitchTorque + emergencyBoost * a.pitchSign, -4.5, 4.5)
            end
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
        flRpm = math.floor((clamp(rawFloat[1], 0, 15) / 15.0) * 256 + 0.5),
        rlRpm = math.floor((clamp(rawFloat[2], 0, 15) / 15.0) * 256 + 0.5),
        frRpm = math.floor((clamp(rawFloat[3], 0, 15) / 15.0) * 256 + 0.5),
        rrRpm = math.floor((clamp(rawFloat[4], 0, 15) / 15.0) * 256 + 0.5),
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

    local safeObsDt = clamp(dt or 0.05, 0.02, 0.50)
    self.obsSimClock = (self.obsSimClock or 0.0) + safeObsDt
    local escapeRevOverride = false

    -- Enforce zero forward throttle in HOVER mode (except during active manual escape); in other modes, advancing throttle > 0 releases parking brake
    if self.ap.mode == "HOVER" and not self.ap.escape then
        self.ap.baseThrottle = 0
        self.ap.parkingBrake = true
    elseif self.ap.parkingBrake and self.ap.baseThrottle > 0 and not self.ap.escape then
        self.ap.parkingBrake = false
    end

    if not (self.ap.escape and self.ap.enabled and not self.ap.parkingBrake) then

    -- Handle Waypoint LNAV Bearing Calculation
    if self.ap.enabled and self.ap.mode == "LNAV" and self.ap.waypoint then
        local dx = self.ap.waypoint.x - tel.pos.x
        local dz = self.ap.waypoint.z - tel.pos.z
        local distSq = dx * dx + dz * dz
        local dist = math.sqrt(distSq)
        self.ap.ilsDev.dist = dist
        if distSq > 25 then -- > 5 blocks away
            self.ap.targetHdg = (math.atan2(dx, -dz) + 2 * math.pi) % (2 * math.pi)
            if self.ap.waypoint.transitY and dist > 100.0 then
                self.ap.targetAlt = self.ap.waypoint.transitY
            elseif self.ap.waypoint.y then
                self.ap.targetAlt = self.ap.waypoint.y
            end
            if dist < 40.0 then
                local cruiseSpd = (self.ap.baseThrottle and self.ap.baseThrottle > 0) and self.ap.baseThrottle or 8
                self.ap.baseThrottle = math.min(cruiseSpd, math.max(3, math.floor(dist * 0.25)))
            end
        elseif self.vehicleType == "ZEPPELIN" or self.vehicleType == "MOTHERSHIP" or self.vehicleType == "GUNSHIP" then
            self.ap.waypoint = nil
            self:setMode("HOVER", tel)
        end
    end

    -- Handle RTB & ILS Approach State Machine
    if self.ap.enabled and self.ap.mode == "RTB" and self.ap.homeBase then
        local base = self.ap.homeBase

        if self.ap.rtbPhase == "RTB_MAST" then
            local mast = base.zeppelinMast or base.threshold or base.pos
            local dx = mast.x - tel.pos.x
            local dz = mast.z - tel.pos.z
            local dist = math.sqrt(dx * dx + dz * dz)
            self.ap.ilsDev.dist = dist
            self.ap.ilsDev.loc  = 0.0

            if dist > 100.0 then
                self.ap.targetHdg = (math.atan2(dx, -dz) + 2 * math.pi) % (2 * math.pi)
                self.ap.targetAlt = math.max(mast.y + 15.0, self.ap.rtbTransitAlt or (mast.y + 15.0))
                self.ap.baseThrottle = 12
            elseif dist > 6.0 then
                self.ap.targetHdg = (math.atan2(dx, -dz) + 2 * math.pi) % (2 * math.pi)
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
            self.ap.ilsDev.gs = (tel.altitude or 0) - (self.ap.targetAlt or mast.y)
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

                self.ap.targetHdg = (math.atan2(dx, -dz) + 2 * math.pi) % (2 * math.pi)
                self.ap.targetAlt = fafY
                self.ap.baseThrottle = math.min(10, math.max(6, (self.ap.baseThrottle and self.ap.baseThrottle > 0) and self.ap.baseThrottle or 8))

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
    end -- end non-escape navigation block

    -- Heading Cascaded Rate Governor (Smooth, Critically-Damped Precision Yaw Control)
    -- Outer Loop: Heading Error -> Target Angular Yaw Rate (rad/s)
    -- Inner Loop: Yaw Rate Error -> Smooth Continuous Differential Thrust (-10..+10)
    local dHdgStep = normalizeAngleRad((tel.heading or 0) - (self.prevYawHdg or tel.heading or 0))
    self.prevYawHdg = tel.heading or 0
    local rawYawRate = clamp(dHdgStep / math.max(dt, 0.02), -2.5, 2.5)
    self.smoothYawRate = (self.smoothYawRate or 0.0) * 0.55 + rawYawRate * 0.45

    -- Autonomous Obstacle / Island Collision Escape State Machine & Multi-Signal Stall Detector
    local function finishObstacleEscape(esc)
        self.obsLastEscapeClock = self.obsSimClock or 0.0
        self.ap.escape = nil
        self.obsStuckTime = 0.0
        self.obsCheckPos = { x = (tel.pos and tel.pos.x) or 0, z = (tel.pos and tel.pos.z) or 0 }
        self.ap.escapeFloorAlt = esc.climbAlt

        local targetMode = esc.resumeMode or "HOVER"
        if targetMode == "HOVER" then
            self:setMode("HOVER", tel)
            self.ap.baseThrottle = 0
        else
            self.ap.mode = targetMode
            self.ap.baseThrottle = esc.resumeThrottle or 8
            self.ap.parkingBrake = false
        end
        self.ap.targetAlt = math.max(esc.resumeTargetAlt or esc.climbAlt, esc.climbAlt)
        if self.ap.rtbTransitAlt or targetMode == "RTB" then
            self.ap.rtbTransitAlt = math.max(self.ap.rtbTransitAlt or 0, esc.climbAlt)
        end
        if self.ap.waypoint then
            self.ap.waypoint.transitY = math.max(self.ap.waypoint.transitY or 0, esc.climbAlt)
        end
        self.ap.lastAtcNotice = string.format("ENGEL ASILDI -> %s (%.0fm)", tostring(targetMode), esc.climbAlt)
    end

    if self.ap.escape and self.ap.enabled and not self.ap.parkingBrake then
        local esc = self.ap.escape
        if esc.phase == "BACKUP" then
            self.ap.targetHdg = esc.holdHdg
            self.ap.targetAlt = esc.climbAlt
            self.ap.baseThrottle = 8
            self.ap.parkingBrake = false
            escapeRevOverride = true
            esc.phaseTime = (esc.phaseTime or 0.0) + safeObsDt
            local backedDist = math.sqrt((((tel.pos and tel.pos.x) or 0) - esc.startX) ^ 2 + (((tel.pos and tel.pos.z) or 0) - esc.startZ) ^ 2)
            if esc.phaseTime >= (esc.backupDur or 4.5) or backedDist >= 20.0 then
                esc.phase = "CLIMB"
                esc.phaseTime = 0.0
                escapeRevOverride = false
                self.ap.baseThrottle = 0
                self.ap.targetHdg = esc.bypassHdg or esc.holdHdg
            end
        elseif esc.phase == "CLIMB" then
            self.ap.targetHdg = esc.bypassHdg or esc.holdHdg
            self.ap.targetAlt = esc.climbAlt
            self.ap.baseThrottle = 0
            escapeRevOverride = false
            esc.phaseTime = (esc.phaseTime or 0.0) + safeObsDt
            if (tel.altitude or 0) >= (esc.climbAlt - 2.0) or esc.phaseTime >= 14.0 then
                if (esc.bypassDur or 0) > 0 and esc.bypassHdg then
                    esc.phase = "BYPASS"
                    esc.phaseTime = 0.0
                    self.ap.baseThrottle = 8
                else
                    finishObstacleEscape(esc)
                end
            end
        elseif esc.phase == "BYPASS" then
            self.ap.targetHdg = esc.bypassHdg
            self.ap.targetAlt = esc.climbAlt
            self.ap.baseThrottle = 8
            escapeRevOverride = false
            esc.phaseTime = (esc.phaseTime or 0.0) + safeObsDt
            if esc.phaseTime >= (esc.bypassDur or 5.0) then
                finishObstacleEscape(esc)
            end
        end
    else
        local isCruisingNav = self.ap.enabled
            and (self.ap.obstacleAvoid ~= false)
            and (not self.ap.parkingBrake)
            and (not self.ap.reverseGear)
            and (self.ap.mode == "CRUISE" or self.ap.mode == "LNAV" or self.ap.mode == "RTB")
            and (not tel.weightOnWheels)
            and (tel.agl == nil or tel.agl > 4.0)
            and ((self.ap.baseThrottle or 0) >= 3)

        local nearDest = ((self.ap.mode == "RTB" or self.ap.mode == "LNAV") and (self.ap.ilsDev and self.ap.ilsDev.dist or 999) <= 12.0)
        if isCruisingNav and not nearDest then
            local vx = (tel.velocity and tel.velocity.x) or 0
            local vz = (tel.velocity and tel.velocity.z) or 0
            local horizSpeed = math.sqrt(vx * vx + vz * vz)
            if vx == 0 and vz == 0 and (tel.speed or 0) > 0 then
                horizSpeed = tel.speed
            end
            local yawRateAbs = math.abs(self.smoothYawRate or 0)

            -- Signal A: Proactive Radar Mk.1 terrain threat ahead
            if tel.radarContact and tel.radarContact.kind == "terrain"
               and (tel.radarContact.distance or 999) < 25
               and (tel.radarContact.closingSpeed or 0) > 1.5 then
                local okEsc = self:triggerObstacleEscape(tel, "RADAR-ENGEL")
                if okEsc and self.ap.escape then
                    self.ap.targetHdg = self.ap.escape.holdHdg
                    self.ap.targetAlt = self.ap.escape.climbAlt
                    self.ap.baseThrottle = 8
                    escapeRevOverride = true
                end
            else
                -- Signal B + C: Physical collision spike or wedged stall against an island
                local px = (tel.pos and tel.pos.x) or 0
                local pz = (tel.pos and tel.pos.z) or 0
                if not self.obsCheckPos then
                    self.obsCheckPos = { x = px, z = pz }
                end
                local movedDist = math.sqrt((px - self.obsCheckPos.x) ^ 2 + (pz - self.obsCheckPos.z) ^ 2)

                if (self.obsPrevHorizSpeed or 0) >= 6.0 and horizSpeed < 1.5 and ((self.obsPrevHorizSpeed or 0) - horizSpeed) >= 5.0 then
                    self.obsStuckTime = math.max(self.obsStuckTime or 0.0, 2.5)
                end

                if horizSpeed >= 2.0 or movedDist >= 3.0 or yawRateAbs >= 0.08 then
                    self.obsStuckTime = 0.0
                    self.obsCheckPos = { x = px, z = pz }
                elseif horizSpeed < 0.85 and movedDist < 2.5 and yawRateAbs < 0.08 then
                    self.obsStuckTime = (self.obsStuckTime or 0.0) + safeObsDt
                    if self.obsStuckTime >= 3.5 then
                        local okEsc = self:triggerObstacleEscape(tel, "CARPISMA")
                        if okEsc and self.ap.escape then
                            self.ap.targetHdg = self.ap.escape.holdHdg
                            self.ap.targetAlt = self.ap.escape.climbAlt
                            self.ap.baseThrottle = 8
                            escapeRevOverride = true
                        end
                    end
                end
                self.obsPrevHorizSpeed = horizSpeed
            end
        else
            self.obsStuckTime = 0.0
            self.obsCheckPos = nil
            self.obsPrevHorizSpeed = 0.0
        end
    end

    local yawDiff = 0.0
    local activeHdgErrRad = 0.0
    if self.ap.hdgHold then
        local hdgErr = normalizeAngleRad(self.ap.targetHdg - (tel.heading or 0))
        local absHdgErr = math.abs(hdgErr)
        activeHdgErrRad = absHdgErr

        if absHdgErr <= math.rad(0.5) and math.abs(self.smoothYawRate) < 0.02 then
            -- Locked on target heading: gently bleed integrator and hold zero differential
            self.yawRateInt = (self.yawRateInt or 0.0) * 0.80
            yawDiff = 0.0
        else
            -- Progressive target yaw rate: gentle fine-lock near target, max ~17 deg/s (0.30 rad/s) on large turns
            local maxYawRate = (absHdgErr > math.rad(45)) and 0.30 or 0.24
            local targetYawRate = clamp(hdgErr * 0.65, -maxYawRate, maxYawRate)
            local yawRateErr = targetYawRate - self.smoothYawRate

            -- Gentle anti-windup integrator ONLY when stalled against static rotational drag
            if math.abs(self.smoothYawRate) < 0.03 and absHdgErr > math.rad(1.0) then
                self.yawRateInt = clamp((self.yawRateInt or 0.0) + hdgErr * 0.60 * dt, -2.5, 2.5)
            else
                self.yawRateInt = (self.yawRateInt or 0.0) * 0.92
            end

            yawDiff = clamp(yawRateErr * 22.0 + (self.yawRateInt or 0.0), -10.0, 10.0)
        end
    else
        self.yawRateInt = 0.0
    end

    -- Supports Create Rotation Speed Controllers (-256..+256 RPM with 1-RPM resolution) and 0..15 Signal / Throttle Lever peripherals
    local revActive = (self.ap.reverseGear == true) or escapeRevOverride or (self.ap.mode == "ANCHOR" and tel.anchor and (tel.anchor.surge or 0) < -0.5)

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
    local isEscapeMove = (self.ap.escape ~= nil and (self.ap.escape.phase == "BACKUP" or self.ap.escape.phase == "BYPASS"))
    local clutchCut = (not isEscapeMove) and ((self.ap.mode == "HOVER") or self.ap.parkingBrake or (self.ap.baseThrottle <= 0 and not isAnchorThrust))
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

    -- Drive Gearshifts (Forward / Backward Movement via [G], [W]/[S], Escape Backup, or Sky Anchor reverse drift)
    revActive = (self.ap.reverseGear == true) or escapeRevOverride or (self.ap.mode == "ANCHOR" and tel.anchor and (tel.anchor.surge or 0) < -0.5)
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
    local portSignal = clutchCut and 0 or math.floor(clamp(self.ap.baseThrottle + yawDiff, 0, 15))
    local stbdSignal = clutchCut and 0 or math.floor(clamp(self.ap.baseThrottle - yawDiff, 0, 15))
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
    if escapeRevOverride then
        turnYaw = clamp(turnYaw, -3.0, 3.0)
    end
    -- Coordinated Turn, Alignment Throttle & Smooth 1-RPM Differential Yaw Mixer:
    -- Positive turnYaw (Right / CW turn) -> Port (Left) increases (+turnYaw), Starboard (Right) decreases (-turnYaw)
    local absTurn = math.abs(turnYaw)
    local effFwd = fwdSig
    if self.ap.enabled and self.ap.hdgHold and effFwd > 0 and activeHdgErrRad > math.rad(25) then
        -- While pointing >25 deg off target, smoothly attenuate forward push (0% at >=90 deg) so vessel pivots cleanly
        local alignFactor = clamp(1.0 - ((activeHdgErrRad - math.rad(25)) / math.rad(65)), 0.0, 1.0)
        effFwd = effFwd * alignFactor
    end
    if effFwd > 0 and (effFwd + absTurn > 15.0) then
        effFwd = 15.0 - absTurn
    elseif effFwd < 0 and (math.abs(effFwd) + absTurn > 15.0) then
        effFwd = -(15.0 - absTurn)
    end
    -- Center thruster smoothly backs off on large heading turns (>= 60 deg -> 0), full thrust when aligned
    local centerAtten = 1.0
    if self.ap.enabled and self.ap.hdgHold and activeHdgErrRad > math.rad(8) then
        centerAtten = clamp(1.0 - ((activeHdgErrRad - math.rad(8)) / math.rad(52)), 0.0, 1.0)
    elseif absTurn > 1.0 then
        centerAtten = math.max(0.0, 1.0 - (absTurn / 10.0))
    end
    -- Allow reverse push-pull on rear outer thrusters in HOVER (fwdSig==0), reverse gear, or large turns (>5.0);
    -- keep fine cruise corrections smoothly positive (0..15) without harsh reverse bangs.
    local allowPushPull = revActive or (math.abs(fwdSig) < 0.5 and absTurn > 0.05) or (absTurn > 5.0) or (activeHdgErrRad > math.rad(45))
    local minRear = allowPushPull and -15.0 or 0.0
    local minCenter = revActive and -15.0 or 0.0

    local rawRearL = clamp(effFwd + turnYaw, minRear, 15.0)
    local rawRearC = clamp(fwdSig * centerAtten, minCenter, 15.0)
    local rawRearR = clamp(effFwd - turnYaw, minRear, 15.0)
    local rearL = math.floor(rawRearL + 0.5)
    local rearC = math.floor(rawRearC + 0.5)
    local rearR = math.floor(rawRearR + 0.5)

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
                    REAR_LEFT = rawRearL, REAR_CENTER = rawRearC, REAR_RIGHT = rawRearR,
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
            local pSig = (self.ap.mode == "HOVER") and 0 or math.floor(clamp(self.ap.baseThrottle + yawDiff, 0, 15))
            local sSig = (self.ap.mode == "HOVER") and 0 or math.floor(clamp(self.ap.baseThrottle - yawDiff, 0, 15))
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
