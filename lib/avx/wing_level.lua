--[[
    AVX Module: Quad Wing Altimeter Differential Auto-Leveling v1.1
    (GitHub-delivered extension; the avionics core runs fine without it)

    Any wired altitude_sensor assigned a LIFT_FL/FR/RL/RR role in the I/O
    configurator is treated as that corner's wing altimeter.
      dR = left wings - right wings altitude (roll error, blocks)
      dP = front wings - rear wings altitude (pitch error, blocks)
    The low side receives more lift. With >= 2 present, altitude = average.
    Gain: config.wingAltGain (default 1.5 signal per block, clamped +/-6).
]]
local M = { name = "WING_LEVEL", version = 2 }

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

function M.onTelemetry(fc, tel, dt)
    dt = dt or 0.05
    local wA, wN, sumAlt = {}, 0, 0
    for _, it in ipairs(fc.ioDevices or {}) do
        local r = (fc.ioMap[it.name] or {}).role or ""
        if it.kind == "altitude_sensor" and it.handle and r:find("^LIFT_") then
            local okH, h = pcall(it.handle.getHeight)
            if not (okH and tonumber(h)) and it.handle.getAltitude then okH, h = pcall(it.handle.getAltitude) end
            h = okH and tonumber(h)
            if h then
                wA[r:sub(6)] = h
                wN = wN + 1
                sumAlt = sumAlt + h
            end
        end
    end
    local function av(a, b) a, b = wA[a], wA[b]; return a and b and (a + b) / 2 or a or b end
    local L, R, F, B = av("FL", "RL"), av("FR", "RR"), av("FL", "FR"), av("RL", "RR")
    fc.wingAlt = wN > 1 and { dR = L and R and L - R or 0, dP = F and B and F - B or 0, n = wN } or nil
    tel.wingAlt = fc.wingAlt

    if wN >= 2 then
        local avgAlt = sumAlt / wN
        tel.altitude = avgAlt
        fc.pos.y = avgAlt
        if fc.prevWingAlt and dt > 0 then
            local rawVsi = clamp((avgAlt - fc.prevWingAlt) / dt, -20.0, 20.0)
            fc.smoothWingVsi = (fc.smoothWingVsi or rawVsi) * 0.80 + rawVsi * 0.20
            if (not fc.altSensor) or math.abs(tel.vSpeed or 0) < 0.02 then
                tel.vSpeed = fc.smoothWingVsi
            end
        end
        fc.prevWingAlt = avgAlt
    end
end

-- trim = { pitch = n, roll = n } (Mothership quad-lift SAS trims, modified in place)
function M.onMix(fc, tel, trim, dt)
    local w = fc.wingAlt
    if not w then return end
    local k = fc.config.wingAltGain or 1.5
    trim.roll  = clamp(trim.roll - w.dR * k, -6, 6)
    trim.pitch = clamp(trim.pitch - w.dP * k, -6, 6)
end

return M
