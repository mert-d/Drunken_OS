--[[
    AVX Module: Sky Anchor / Station Keeping (3D Position Lock) v1.0
    (GitHub-delivered extension module for Drunken OS Flight Computer)

    Locks the mothership or aircraft to its current (X, Y, Z, Heading) point:
    - Vertical (Y): Locks altitude via altitude_sensor & 4 wing altimeters.
    - Attitude: Holds horizon level (roll & pitch = 0) with active anti-drift trimming.
    - Horizontal (Surge/Sway): Projects position error into vessel body-frame
      to apply corrective micro-thrust via rear thrusters or rotor tilt.
]]
local M = { name = "SKY_ANCHOR", version = 1 }

local function clamp(val, minV, maxV)
    return math.max(minV, math.min(maxV, val))
end

function M.onTelemetry(fc, tel, dt)
    if not (fc.ap and (fc.ap.mode == "ANCHOR" or fc.ap.anchorActive)) then
        fc.anchorPos = nil
        return
    end

    -- Initialize or lock anchor position upon engagement
    if not fc.anchorPos then
        fc.anchorPos = {
            x       = (tel.pos and tel.pos.x) or 0,
            y       = tel.altitude or 0,
            z       = (tel.pos and tel.pos.z) or 0,
            heading = tel.heading or 0
        }
    end

    local ap = fc.anchorPos
    local px = (tel.pos and tel.pos.x) or 0
    local pz = (tel.pos and tel.pos.z) or 0
    local dx = ap.x - px
    local dz = ap.z - pz
    local dy = ap.y - (tel.altitude or 0)
    local distH = math.sqrt(dx * dx + dz * dz)

    -- Project ground displacement into ship's body frame
    -- Forward (+surge): target is ahead of vessel
    -- Right   (+sway) : target is starboard of vessel
    local hdg = tel.heading or 0
    local sinH = math.sin(hdg)
    local cosH = math.cos(hdg)
    local surge = dx * (-sinH) + dz * cosH
    local sway  = dx * cosH    + dz * sinH

    tel.anchor = {
        active  = true,
        x       = ap.x,
        y       = ap.y,
        z       = ap.z,
        heading = ap.heading,
        surge   = surge,
        sway    = sway,
        dy      = dy,
        dist    = distH
    }
end

function M.onMix(fc, tel, trim, dt)
    local anc = tel and tel.anchor
    if not (anc and anc.active) then return end

    -- Enforce altitude and heading lock
    fc.ap.altHold   = true
    fc.ap.targetAlt = anc.y
    fc.ap.hdgHold   = true
    fc.ap.targetHdg = anc.heading

    -- 1. Anti-Drift Pitch Trim (Tilt rotors slightly to arrest forward/backward drift)
    local pitchCorrection = clamp(-anc.surge * 0.75, -4.0, 4.0)
    trim.pitch = clamp(trim.pitch + pitchCorrection, -6.0, 6.0)

    -- 2. Anti-Drift Roll Trim (Arrest left/right lateral sway)
    local rollCorrection = clamp(anc.sway * 0.75, -4.0, 4.0)
    trim.roll = clamp(trim.roll + rollCorrection, -6.0, 6.0)

    -- 3. Rear Propulsion Counter-Thrust (Surge > 0.5 block)
    if math.abs(anc.surge) > 0.5 then
        trim.surge = math.floor(clamp(anc.surge * 2.0, -8.0, 8.0) + 0.5)
    end
end

return M
