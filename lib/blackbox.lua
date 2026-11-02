-- lib/blackbox.lua
-- Drunken OS - Flight Data Recorder (FDR / Kara Kutu)
-- Records flight dynamics, attitude, rotor RPMs, and autopilot commands for post-flight analysis

local Blackbox = {}
Blackbox.__index = Blackbox

local DEFAULT_LOG_TXT = "/flight_log.txt"
local DEFAULT_LOG_CSV = "/flight_log.csv"
local MAX_ENTRIES     = 1200 -- 60 seconds at 20Hz or 240 seconds at 5Hz

function Blackbox.new(opts)
    opts = opts or {}
    local self = setmetatable({
        txtPath      = opts.txtPath or DEFAULT_LOG_TXT,
        csvPath      = opts.csvPath or DEFAULT_LOG_CSV,
        maxEntries   = opts.maxEntries or MAX_ENTRIES,
        entries      = {},
        isAirborne   = false,
        takeoffTick  = 0,
        currentTick  = 0,
        prevPitch    = 0,
        flushTimer   = 0,
        autoFlushSec = opts.autoFlushSec or 1.0,
        callsign     = opts.callsign or "SKYFIRE-01",
        vehicleType  = opts.vehicleType or "MOTHERSHIP"
    }, Blackbox)
    return self
end

function Blackbox:record(tel, apState, msState, ctrl)
    self.currentTick = self.currentTick + 1
    tel     = tel     or {}
    apState = apState or {}
    msState = msState or {}
    ctrl    = ctrl    or {}

    local pitchDeg = math.deg(tel.pitch or 0)
    local rollDeg  = math.deg(tel.roll or 0)
    local hdgDeg   = math.deg(tel.heading or 0)
    local alt      = tel.altitude or 0
    local vy       = tel.vSpeed or 0
    local vz       = (tel.velocity and tel.velocity.z) or (tel.speed or 0)
    local dt       = ctrl.dt or 0.05

    -- Angular pitch velocity (deg/s)
    local wxDeg = 0
    if dt > 0 and self.prevPitch ~= nil then
        wxDeg = (pitchDeg - self.prevPitch) / dt
    end
    self.prevPitch = pitchDeg

    -- Detect takeoff / unfreeze transition
    local movingOrLift = (math.abs(vy) > 0.1 or math.abs(vz) > 0.2 or (msState.flRpm and msState.flRpm > 50))
    local airborneNow = (not tel.weightOnWheels) and movingOrLift and (not apState.parkingBrake or apState.enabled)
    if airborneNow and not self.isAirborne then
        self.isAirborne = true
        self.takeoffTick = self.currentTick
    elseif not airborneNow and (apState.parkingBrake and not apState.enabled) then
        self.isAirborne = false
    end

    local tSec = (self.currentTick - (self.takeoffTick or self.currentTick)) * dt
    if not self.isAirborne then tSec = 0.0 end

    -- Determine status label
    local status = "TERAZI"
    if ctrl.antiDiveActive or tel.pitchWarning then
        status = "ANTI-DIVE"
    elseif math.abs(pitchDeg) > 18 then
        status = (pitchDeg > 0) and "ASIRI-BURUN-YUKARI" or "ASIRI-BURUN-ASAGI"
    elseif math.abs(pitchDeg) > 8 then
        status = (pitchDeg > 0) and "YUNUSLAMA-YUKARI" or "YUNUSLAMA-ASAGI"
    elseif math.abs(rollDeg) > 8 then
        status = "YATIS-ROLL"
    elseif vz > 10.0 then
        status = "HIZLI-ILERI"
    elseif vy > 2.0 then
        status = "TIRMANIS"
    elseif vy < -2.0 then
        status = "ALCALIS"
    elseif self.isAirborne then
        status = (apState.mode or "HOVER")
    else
        status = "PARKED"
    end

    local entry = {
        tick        = self.currentTick,
        tSec        = tSec,
        mode        = tostring(apState.mode or "MANUAL"),
        alt         = alt,
        vy          = vy,
        vz          = vz,
        pitchDeg    = pitchDeg,
        rollDeg     = rollDeg,
        hdgDeg      = hdgDeg,
        wxDeg       = wxDeg,
        flRpm       = msState.flRpm or 0,
        frRpm       = msState.frRpm or 0,
        rlRpm       = msState.rlRpm or 0,
        rrRpm       = msState.rrRpm or 0,
        rearL       = msState.rearL or 0,
        rearC       = msState.rearC or 0,
        rearR       = msState.rearR or 0,
        pitchTrim   = ctrl.pitchTrim or 0,
        diveFactor  = ctrl.diveFactor or 1.0,
        antiDive    = (ctrl.antiDiveActive == true or tel.pitchWarning == true),
        status      = status
    }

    table.insert(self.entries, entry)
    if #self.entries > self.maxEntries then
        table.remove(self.entries, 1)
    end

    -- Periodic disk flush
    self.flushTimer = self.flushTimer + dt
    if self.flushTimer >= self.autoFlushSec or entry.antiDive then
        self.flushTimer = 0
        self:flush()
    end

    return entry
end

function Blackbox:flush()
    if not (fs and fs.open) then return false end
    self:writeTextLog()
    self:writeCsvLog()
    return true
end

function Blackbox:writeTextLog()
    local ok, f = pcall(fs.open, self.txtPath, "w")
    if not (ok and f) then return false end

    f.writeLine("==========================================================================================================")
    f.writeLine(string.format("DRUNKEN OS - UCUS TELEMETRI & KARA KUTU KAYDI (FLIGHT DATA RECORDER)"))
    f.writeLine(string.format("Hava Araci : %s | Tip: %s | Toplam Kayit: %d", self.callsign, self.vehicleType, #self.entries))
    f.writeLine("==========================================================================================================")
    f.writeLine(string.format(
        "%-6s | %-6s | %-7s | %-8s | %-8s | %-6s | %-6s | %-8s | %-15s | %-9s | %s",
        "Zaman", "Mod", "Irtifa", "Vy(m/s)", "Vz(m/s)", "Pitch", "Roll", "wx(dg/s)", "FL/FR/RL/RR", "Arka(L/C/R)", "Durum"
    ))
    f.writeLine("-------+--------+---------+----------+----------+--------+--------+----------+-----------------+-----------+-------------------------")

    -- Write entries with stride if buffer is large, always keeping first, events, and last 40
    local total = #self.entries
    local startIdx = math.max(1, total - 80)
    for i = startIdx, total do
        local e = self.entries[i]
        local liftStr = string.format("%3d/%3d/%3d/%3d", e.flRpm, e.frRpm, e.rlRpm, e.rrRpm)
        local rearStr = string.format("%2d/%2d/%2d", e.rearL, e.rearC, e.rearR)
        local line = string.format(
            "T%+4.1fs | %-6s | %6.1fm | %+7.2f | %+7.2f | %+5.1f° | %+5.1f° | %+7.1f° | %-15s | %-9s | %s",
            e.tSec, e.mode:sub(1, 6), e.alt, e.vy, e.vz, e.pitchDeg, e.rollDeg, e.wxDeg, liftStr, rearStr, e.status
        )
        f.writeLine(line)
    end
    f.writeLine("==========================================================================================================")
    f.close()
    return true
end

function Blackbox:writeCsvLog()
    local ok, f = pcall(fs.open, self.csvPath, "w")
    if not (ok and f) then return false end

    f.writeLine("tick,time_s,mode,alt_m,vy_mps,vz_mps,pitch_deg,roll_deg,hdg_deg,wx_deg_s,rpm_fl,rpm_fr,rpm_rl,rpm_rr,rear_l,rear_c,rear_r,pitch_trim,dive_factor,anti_dive,status")
    for _, e in ipairs(self.entries) do
        f.writeLine(string.format(
            "%d,%.2f,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%s,%s",
            e.tick, e.tSec, e.mode, e.alt, e.vy, e.vz, e.pitchDeg, e.rollDeg, e.hdgDeg, e.wxDeg,
            e.flRpm, e.frRpm, e.rlRpm, e.rrRpm, e.rearL, e.rearC, e.rearR,
            e.pitchTrim, e.diveFactor, e.antiDive and "1" or "0", e.status
        ))
    end
    f.close()
    return true
end

function Blackbox:getMarkdownTable(numRows)
    numRows = numRows or 20
    local total = #self.entries
    local startIdx = math.max(1, total - numRows + 1)

    local lines = {}
    table.insert(lines, "| Zaman | Mod | İrtifa ($Y$) | Dikey Hız ($V_y$) | İleri Hız ($V_z$) | Yunuslama (Pitch) | $\\omega_x$ (Açısal Hız) | Kaldırma RPM (FL/FR/RL/RR) | Arka İtki | Durum |")
    table.insert(lines, "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |")

    for i = startIdx, total do
        local e = self.entries[i]
        local liftStr = string.format("%d / %d / %d / %d", e.flRpm, e.frRpm, e.rlRpm, e.rrRpm)
        local rearStr = string.format("%d / %d / %d", e.rearL, e.rearC, e.rearR)
        table.insert(lines, string.format(
            "| **T%+4.1fs** | `%s` | $%.2f\\text{ m}$ | $%+.2f\\text{ m/s}$ | $%+.2f\\text{ m/s}$ | $%+.1f^\\circ$ | $%+.1f^\\circ/\\text{s}$ | `%s` | `%s` | %s |",
            e.tSec, e.mode, e.alt, e.vy, e.vz, e.pitchDeg, e.wxDeg, liftStr, rearStr, e.status
        ))
    end

    return table.concat(lines, "\n")
end

function Blackbox:clear()
    self.entries = {}
    self.takeoffTick = self.currentTick
    if fs and fs.delete then
        pcall(fs.delete, self.txtPath)
        pcall(fs.delete, self.csvPath)
    end
end

return Blackbox
