--[[
    AVX Module: Sky Anchor / Station Keeping (3D Position Lock) v1.1
    (GitHub-delivered extension module for Drunken OS Flight Computer)

    Locks the mothership or aircraft to its current (X, Y, Z, Heading) point:
    - Vertical (Y): Locks altitude via altitude_sensor & 4 wing altimeters.
    - Attitude: Holds horizon level (roll & pitch = 0) with active anti-drift trimming.
    - Horizontal (Surge/Sway): Projects position error into vessel body-frame
      with velocity damping to apply corrective micro-thrust without overshoot.
]]
local M = { name = "SKY_ANCHOR", version = 2 }

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
            y       = fc.ap.targetAlt or tel.altitude or 0,
            z       = (tel.pos and tel.pos.z) or 0,
            heading = fc.ap.targetHdg or tel.heading or 0
        }
    end

    local ap = fc.anchorPos
    -- Adopt pilot fine-tuning if target was manually nudged via [Up/Dn] or [Lt/Rt]
    if fc.ap.targetAlt and math.abs(fc.ap.targetAlt - ap.y) > 0.1 then
        ap.y = fc.ap.targetAlt
    end
    if fc.ap.targetHdg and math.abs(fc.ap.targetHdg - ap.heading) > 0.02 then
        ap.heading = fc.ap.targetHdg
    end

    local px = (tel.pos and tel.pos.x) or 0
    local pz = (tel.pos and tel.pos.z) or 0
    local dx = ap.x - px
    local dz = ap.z - pz
    local dy = ap.y - (tel.altitude or 0)
    local distH = math.sqrt(dx * dx + dz * dz)

    -- Project ground displacement and velocity into ship's body frame
    -- Forward (+surge): target is ahead of vessel
    -- Right   (+sway) : target is starboard of vessel
    local hdg = tel.heading or 0
    local sinH = math.sin(hdg)
    local cosH = math.cos(hdg)
    local surge = dx * (-sinH) + dz * cosH
    local sway  = dx * cosH    + dz * sinH

    local vx = (tel.velocity and tel.velocity.x) or 0
    local vz = (tel.velocity and tel.velocity.z) or 0
    local velSurge = vx * (-sinH) + vz * cosH
    local velSway  = vx * cosH    + vz * sinH

    tel.anchor = {
        active   = true,
        x        = ap.x,
        y        = ap.y,
        z        = ap.z,
        heading  = ap.heading,
        surge    = surge,
        sway     = sway,
        velSurge = velSurge,
        velSway  = velSway,
        dy       = dy,
        dist     = distH
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

    local vs = anc.velSurge or 0
    local vw = anc.velSway or 0

    -- 1. Anti-Drift Pitch Trim with velocity damping (Tilt rotors forward/backward)
    local pitchCorrection = clamp(-(anc.surge * 0.70 - vs * 0.35), -4.0, 4.0)
    trim.pitch = clamp(trim.pitch + pitchCorrection, -6.0, 6.0)

    -- 2. Anti-Drift Roll Trim with velocity damping (Arrest left/right lateral sway)
    local rollCorrection = clamp(anc.sway * 0.70 - vw * 0.35, -4.0, 4.0)
    trim.roll = clamp(trim.roll + rollCorrection, -6.0, 6.0)

    -- 3. Rear Propulsion Counter-Thrust (Surge > 0.5 block)
    if math.abs(anc.surge) > 0.5 then
        local thrustCmd = clamp((anc.surge * 1.8 - vs * 0.5), -8.0, 8.0)
        trim.surge = math.floor(thrustCmd + 0.5)
    end
end

return M
