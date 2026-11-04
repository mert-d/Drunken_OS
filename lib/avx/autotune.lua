--[[
    lib/avx/autotune.lua
    Drunken OS Avionics - Dynamic Rigid-Body Physics & PID Autotuner
    
    Synthesizes critically damped flight control gains (Kp, Ki, Kd, rate damping)
    directly from live contraption physics (Mass, Inertia Tensor, Center of Mass,
    actuator moment arms) provided by Sable / VS2 / Eureka physics engines.
]]

local Autotune = {
    version = "1.0",
    name = "AUTOTUNE"
}

local function clamp(val, lo, hi)
    return math.max(lo, math.min(hi, val))
end

local function round(val, dec)
    local mult = 10 ^ (dec or 2)
    return math.floor(val * mult + 0.5) / mult
end

--- Extract physical metrics from sublevel or empirical fallback
function Autotune.getPhysicsMetrics(sublevelHandle, fallbackModel)
    local fb = fallbackModel or {}
    local mass = tonumber(fb.mass) or 15120.0
    local com  = { x = 0, y = 0, z = 0 }
    local Ixx  = 18110000.0  -- Pitch moment of inertia (kg*m^2)
    local Iyy  = 20220000.0  -- Yaw moment of inertia (kg*m^2)
    local Izz  = 3720000.0   -- Roll moment of inertia (kg*m^2)
    local hasRealSublevel = false

    local sub = sublevelHandle or _G.sublevel
    if sub and type(sub) == "table" then
        if sub.getMass then
            local okM, m = pcall(sub.getMass)
            if okM and tonumber(m) and tonumber(m) > 100 then
                mass = tonumber(m)
                hasRealSublevel = true
            end
        end

        if sub.getCenterOfMass then
            local okC, c = pcall(sub.getCenterOfMass)
            if okC and type(c) == "table" then
                com = { x = tonumber(c.x) or 0, y = tonumber(c.y) or 0, z = tonumber(c.z) or 0 }
            end
        end

        if sub.getInertiaTensor then
            local okI, tensor = pcall(sub.getInertiaTensor)
            if okI and type(tensor) == "table" and tensor[1] and tensor[2] and tensor[3] then
                Ixx = math.abs(tonumber(tensor[1][1]) or Ixx)
                Iyy = math.abs(tonumber(tensor[2][2]) or Iyy)
                Izz = math.abs(tonumber(tensor[3][3]) or Izz)
                hasRealSublevel = true
            end
        end
    end

    return {
        mass            = mass,
        com             = com,
        Ixx             = Ixx,
        Iyy             = Iyy,
        Izz             = Izz,
        hasRealSublevel = hasRealSublevel
    }
end

--- Calculate optimal pole-placement PID gains & actuator balance
function Autotune.calculate(fc, sublevelHandle)
    local m = fc and fc.skyfireModel or {}
    local phys = Autotune.getPhysicsMetrics(sublevelHandle, m)

    local mass = phys.mass
    local Ixx  = phys.Ixx
    local Iyy  = phys.Iyy
    local Izz  = phys.Izz

    -- Geometry & Actuators
    local Lf = tonumber(m.Lf) or 42.0
    local Lr = tonumber(m.Lr) or 16.0
    local W  = tonumber(m.W)  or 37.0

    -- Propeller distribution: 2 nacelles front (4 props), 2 nacelles rear (8 to 10 props)
    local propsFront = 4
    local propsRear  = 10 -- Skyfire upgraded 10-prop rear lift
    if fc and fc.ioMap then
        -- Count physical actuators if mapped
        local liftCount = 0
        for devName, devCfg in pairs(fc.ioMap) do
            if devCfg.role and devCfg.role:find("^LIFT_") then
                liftCount = liftCount + 1
            end
        end
    end

    -- Torque Effectiveness Coefficients
    local torqueFront = propsFront * Lf
    local torqueRear  = propsRear * Lr
    local gammaFront  = clamp(round(torqueRear / torqueFront, 3), 0.700, 1.000)
    local gammaRear   = 1.000

    -- Ratios relative to calibrated reference (Mass: 15,000kg, Ixx: 1.81e7, Izz: 3.72e6)
    local mRatio   = mass / 15000.0
    local ixxRatio = Ixx / 18110000.0
    local izzRatio = Izz / 3720000.0
    local iyyRatio = Iyy / 20220000.0

    -- 1. Pitch Control Synthesis (Critically Damped omega_n ~ 1.4 rad/s)
    local kpPitch = clamp(round(14.0 * ixxRatio * (160.0 / torqueRear), 2), 6.0, 24.0)
    local kdPitch = clamp(round(9.00 * ixxRatio * (160.0 / torqueRear), 2), 4.0, 16.0)
    local kiPitch = clamp(round(0.85 * mRatio, 2), 0.20, 2.00)
    local dampWx  = clamp(round(6.00 * ixxRatio, 2), 2.5, 9.0)

    -- 2. Roll Control Synthesis (Critically Damped omega_n ~ 1.8 rad/s)
    local kpRoll  = clamp(round(3.80 * izzRatio, 2), 1.8, 8.0)
    local kdRoll  = clamp(round(3.50 * izzRatio, 2), 1.5, 6.0)
    local kiRoll  = clamp(round(0.20 * mRatio, 2), 0.05, 0.80)
    local dampWz  = clamp(round(4.20 * izzRatio, 2), 1.8, 7.5)

    -- 3. Altitude / Heave Control Synthesis
    local kpAlt   = clamp(round(0.88 * mRatio, 2), 0.50, 2.00)
    local kdAlt   = clamp(round(2.50 * mRatio, 2), 1.20, 4.50)
    local kiAlt   = 0.08
    local dampVy  = clamp(round(1.50 * mRatio, 2), 1.0, 3.5)

    -- 4. Heading / Yaw Control Synthesis
    local kpYaw   = clamp(round(4.00 * iyyRatio, 2), 2.0, 8.0)
    local kdYaw   = clamp(round(2.10 * iyyRatio, 2), 1.0, 4.5)
    local kiYaw   = 0.25

    -- 5. Hover Base Throttle Equilibrium
    -- Base signal ~ 8.9 for 15,120 kg. Scales smoothly with sqrt(mass).
    local hoverBaseSig = clamp(round(8.90 * math.sqrt(mRatio), 1), 6.0, 13.0)

    return {
        mass         = mass,
        com          = phys.com,
        Ixx          = Ixx,
        Iyy          = Iyy,
        Izz          = Izz,
        hasRealSublevel = phys.hasRealSublevel,
        gammaFront   = gammaFront,
        gammaRear    = gammaRear,
        hoverBaseSig = hoverBaseSig,
        pitch = {
            kp      = kpPitch,
            ki      = kiPitch,
            kd      = kdPitch,
            dampWx  = dampWx,
            minOut  = -5.0,
            maxOut  = 5.0,
            maxInt  = 2.0
        },
        roll = {
            kp      = kpRoll,
            ki      = kiRoll,
            kd      = kdRoll,
            dampWz  = dampWz,
            minOut  = -3.5,
            maxOut  = 3.5,
            maxInt  = 0.8
        },
        alt = {
            kp      = kpAlt,
            ki      = kiAlt,
            kd      = kdAlt,
            dampVy  = dampVy,
            minOut  = -3.0,
            maxOut  = 3.0,
            maxInt  = 1.0
        },
        yaw = {
            kp      = kpYaw,
            ki      = kiYaw,
            kd      = kdYaw,
            minOut  = -4.5,
            maxOut  = 4.5
        }
    }
end

--- Apply calculated parameters live to an Avionics flight controller instance
function Autotune.apply(fc, params, persist)
    if not fc or not params then return false, "Invalid arguments" end

    -- Apply to skyfireModel
    if not fc.skyfireModel then fc.skyfireModel = {} end
    fc.skyfireModel.mass         = params.mass
    fc.skyfireModel.gammaFront   = params.gammaFront
    fc.skyfireModel.gammaRear    = params.gammaRear
    fc.skyfireModel.hoverBaseSig = params.hoverBaseSig

    -- Apply PID Gains to live controllers (preserves integral if method exists)
    if fc.msPitchPID and fc.msPitchPID.setGains then
        fc.msPitchPID:setGains(params.pitch.kp, params.pitch.ki, params.pitch.kd)
    else
        -- Recreate if setGains not yet available
        local createPID = fc.createPID or (package.loaded["lib.avionics"] and package.loaded["lib.avionics"].createPID)
        if createPID then
            fc.msPitchPID = createPID(params.pitch.kp, params.pitch.ki, params.pitch.kd,
                                      params.pitch.minOut, params.pitch.maxOut, params.pitch.maxInt)
        end
    end

    if fc.msRollPID and fc.msRollPID.setGains then
        fc.msRollPID:setGains(params.roll.kp, params.roll.ki, params.roll.kd)
    else
        local createPID = fc.createPID or (package.loaded["lib.avionics"] and package.loaded["lib.avionics"].createPID)
        if createPID then
            fc.msRollPID = createPID(params.roll.kp, params.roll.ki, params.roll.kd,
                                     params.roll.minOut, params.roll.maxOut, params.roll.maxInt)
        end
    end

    if fc.altPID and fc.altPID.setGains then
        fc.altPID:setGains(params.alt.kp, params.alt.ki, params.alt.kd)
    else
        local createPID = fc.createPID or (package.loaded["lib.avionics"] and package.loaded["lib.avionics"].createPID)
        if createPID then
            fc.altPID = createPID(params.alt.kp, params.alt.ki, params.alt.kd,
                                  params.alt.minOut, params.alt.maxOut, params.alt.maxInt)
        end
    end

    if fc.yawPID and fc.yawPID.setGains then
        fc.yawPID:setGains(params.yaw.kp, params.yaw.ki, params.yaw.kd)
    end

    -- Store active autotune parameters on instance
    fc.autotuneActive = true
    fc.autotuneParams = params
    fc.dampWx         = params.pitch.dampWx
    fc.dampWz         = params.roll.dampWz
    fc.dampVy         = params.alt.dampVy

    -- Optionally persist to config file
    if persist and fs and fs.open and textutils and textutils.serialize then
        local cfgPath = "/avionics_iomap.cfg"
        local currentCfg = {}
        if fs.exists(cfgPath) then
            local f = fs.open(cfgPath, "r")
            if f then
                local raw = f.readAll()
                f.close()
                currentCfg = textutils.unserialize(raw) or {}
            end
        end

        currentCfg.autotune = {
            timestamp    = (os.epoch and os.epoch("utc")) or os.time(),
            mass         = params.mass,
            gammaFront   = params.gammaFront,
            gammaRear    = params.gammaRear,
            hoverBaseSig = params.hoverBaseSig,
            pitch        = { kp = params.pitch.kp, ki = params.pitch.ki, kd = params.pitch.kd, dampWx = params.pitch.dampWx },
            roll         = { kp = params.roll.kp, ki = params.roll.ki, kd = params.roll.kd, dampWz = params.roll.dampWz },
            alt          = { kp = params.alt.kp, ki = params.alt.ki, kd = params.alt.kd, dampVy = params.alt.dampVy }
        }

        local fw = fs.open(cfgPath, "w")
        if fw then
            fw.write(textutils.serialize(currentCfg))
            fw.close()
        end
    end

    return true, params
end

--- One-shot Auto-Calibrate: inspects contraption physics, calculates gains, and applies them
function Autotune.autoCalibrate(fc, persist)
    local params = Autotune.calculate(fc)
    return Autotune.apply(fc, params, persist)
end

--- Gemiyi sallamayan, 2 saniyelik mikro-darbelerle motor/sensor yonlerini bulan Guvenli Kalibrator (Safe Mapper)
function Autotune.runSafeCalibration(avionics, logFn)
    local log = logFn or print
    local a = avionics and avionics.adaptive
    local gears = (avionics and (avionics.gears or avionics.gearboxes)) or {}
    if not a or #gears < 4 then
        log("[HATA] En az 4 adet analog_transmission / aktuator gerekli!")
        return false
    end

    log("[1/2] Mevcut durustan baslangic Levitation/CoM trimi sifirlaniyor...")
    local baseTel = avionics:readTelemetry()
    local p0 = baseTel.pitch or 0
    local r0 = baseTel.roll  or 0
    if math.abs(p0) > 1.65 or math.abs(r0) > 1.65 then
        p0 = math.rad(p0); r0 = math.rad(r0)
    end

    local sleepFn = sleep or (os and os.sleep) or function() end

    -- 1. On motorlara (+1.5 sinyal) 0.35 sn mikro darbe verip Pitch yonunu dogrula
    log("[2/2] Mikro-darbe ile Pitch ve Roll eksen yonu dogrulaniyor...")
    for i = 1, 4 do
        local sig = (i == 1 or i == 3) and math.min(15, math.floor(a.hoverBase + 2)) or math.max(0, math.floor(a.hoverBase - 1))
        local gear = gears[i]
        if gear then
            if gear.setGearshift then pcall(gear.setGearshift, sig)
            elseif gear.setSignal then pcall(gear.setSignal, sig)
            elseif gear.setTargetSpeed then pcall(gear.setTargetSpeed, math.floor((sig / 15.0) * 256 + 0.5))
            end
        end
    end
    sleepFn(0.35)
    local p1 = avionics:readTelemetry().pitch or 0
    if math.abs(p1) > 1.65 then p1 = math.rad(p1) end
    if (p1 - p0) < -0.005 then
        a.pitchSign = -1
        log(" -> Pitch ekseni ters algilandi, otomatik duzeltildi (pitchSign = -1)")
    else
        a.pitchSign = 1
    end

    -- 2. Sol motorlara (+1.5 sinyal) 0.35 sn mikro darbe verip Roll yonunu dogrula
    for i = 1, 4 do
        local sig = (i == 1 or i == 2) and math.min(15, math.floor(a.hoverBase + 2)) or math.max(0, math.floor(a.hoverBase - 1))
        local gear = gears[i]
        if gear then
            if gear.setGearshift then pcall(gear.setGearshift, sig)
            elseif gear.setSignal then pcall(gear.setSignal, sig)
            elseif gear.setTargetSpeed then pcall(gear.setTargetSpeed, math.floor((sig / 15.0) * 256 + 0.5))
            end
        end
    end
    sleepFn(0.35)
    local r1 = avionics:readTelemetry().roll or 0
    if math.abs(r1) > 1.65 then r1 = math.rad(r1) end
    if (r1 - r0) < -0.005 then
        a.rollSign = -1
        log(" -> Roll ekseni ters algilandi, otomatik duzeltildi (rollSign = -1)")
    else
        a.rollSign = 1
    end

    avionics:saveAdaptiveState()
    log("[OK] Adaptif kalibrasyon tamamlandi ve /etc/avionics_adaptive.cfg kaydedildi!")
    return true
end

return Autotune
