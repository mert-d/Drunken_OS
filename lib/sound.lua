--[[
    Drunken OS - Speaker Sound Engine (lib/sound.lua)
    by MuhendizBey
    Version: 1.0

    Provides procedural retro 8-bit audio effects, notification chimes,
    coin sounds, and game audio using CC:Tweaked Speaker peripherals.
    Gracefully and silently no-ops when no speaker peripheral is attached.
]]

local Sound = {}
Sound._VERSION = "1.0"

local speakerCache = nil
local audioEnabled = true

---
-- Probes for an attached speaker peripheral, caching the result.
-- @return table|nil: Wrapped speaker peripheral object, or nil if none attached.
local function getSpeaker()
    if speakerCache and peripheral and peripheral.getType then
        -- Validate if still attached
        local ok, pType = pcall(peripheral.getType, speakerCache)
        if ok and pType == "speaker" then
            return speakerCache
        end
        speakerCache = nil
    end

    if peripheral and peripheral.find then
        local ok, sp = pcall(peripheral.find, "speaker")
        if ok and sp then
            speakerCache = sp
            return sp
        end
    end
    return nil
end

---
-- Checks if audio output is enabled and hardware is available.
-- @return boolean: True if audio is enabled and speaker is attached.
function Sound.isAvailable()
    return audioEnabled and (getSpeaker() ~= nil)
end

---
-- Enables or disables all sound output globally.
-- @param enabled boolean
function Sound.setEnabled(enabled)
    audioEnabled = (enabled == true)
end

---
-- Checks if sound output is globally enabled.
-- @return boolean
function Sound.isEnabled()
    return audioEnabled
end

---
-- Direct note playback using Minecraft note block instruments.
-- @param instrument string: e.g. "harp", "bell", "chime", "flute", "bass", "pling", "bit"
-- @param volume number|nil: 0.0 to 3.0 (default: 1.0)
-- @param pitch number|nil: 0 to 24 semitones (default: 12)
-- @return boolean: True if played successfully, false otherwise.
function Sound.playNote(instrument, volume, pitch)
    if not audioEnabled then return false end
    local sp = getSpeaker()
    if not sp or not sp.playNote then return false end

    local vol = volume or 1.0
    local p = pitch or 12
    local inst = instrument or "harp"

    local ok, res = pcall(sp.playNote, inst, vol, p)
    return ok and (res == true)
end

---
-- Plays a floating notification toast chime based on category.
-- @param category string|nil: "mail", "chat", "bank", "airdrop", or nil
-- @return boolean
function Sound.playToast(category)
    if not Sound.isAvailable() then return false end
    local cat = tostring(category or "default"):lower()

    if cat == "mail" then
        -- High dual chime
        Sound.playNote("chime", 1.2, 12)
        Sound.playNote("chime", 1.2, 16)
        return true
    elseif cat == "chat" then
        -- Warm bell tone
        Sound.playNote("bell", 1.0, 14)
        return true
    elseif cat == "bank" then
        -- Crisp coin pling
        Sound.playNote("pling", 1.4, 18)
        return true
    elseif cat == "airdrop" then
        -- Soft double flute
        Sound.playNote("flute", 0.9, 12)
        Sound.playNote("flute", 0.9, 16)
        return true
    else
        -- Default notification blip
        Sound.playNote("pling", 1.0, 12)
        return true
    end
end

---
-- Plays a rising coin pickup sound for ATM, POS, and banking transactions.
-- @return boolean
function Sound.playCoin()
    if not Sound.isAvailable() then return false end
    Sound.playNote("pling", 1.2, 14)
    Sound.playNote("pling", 1.5, 20)
    return true
end

---
-- Plays a subtle, tactile UI button click.
-- @return boolean
function Sound.playClick()
    if not Sound.isAvailable() then return false end
    return Sound.playNote("hat", 0.4, 20)
end

---
-- Plays a two-tone ascending harmonic success chord.
-- @return boolean
function Sound.playSuccess()
    if not Sound.isAvailable() then return false end
    Sound.playNote("harp", 1.0, 12)
    Sound.playNote("harp", 1.0, 19)
    return true
end

---
-- Plays a low, warning error buzz.
-- @return boolean
function Sound.playError()
    if not Sound.isAvailable() then return false end
    return Sound.playNote("bass", 1.2, 4)
end

---
-- Plays a frequency-modulated radar proximity ping.
-- Pitch increases dynamically as distance decreases (closer = higher pitch).
-- @param distance number: Euclidean distance in blocks
-- @return boolean
function Sound.playRadarPing(distance)
    if not Sound.isAvailable() then return false end
    local dist = tonumber(distance) or 100
    local pitch = 12

    if dist <= 10 then
        pitch = 22
    elseif dist <= 25 then
        pitch = 18
    elseif dist <= 50 then
        pitch = 14
    elseif dist <= 80 then
        pitch = 10
    else
        pitch = 6
    end

    return Sound.playNote("pling", 1.0, pitch)
end

---
-- Plays an arcade sound effect.
-- @param effect string: "blip", "hit", "miss", "gameover"
-- @return boolean
function Sound.playGameBeep(effect)
    if not Sound.isAvailable() then return false end
    local eff = tostring(effect or "blip"):lower()

    if eff == "blip" then
        return Sound.playNote("bit", 0.8, 16)
    elseif eff == "hit" then
        Sound.playNote("snare", 1.2, 8)
        Sound.playNote("bass", 1.0, 6)
        return true
    elseif eff == "miss" then
        return Sound.playNote("hat", 0.6, 6)
    elseif eff == "gameover" then
        Sound.playNote("bass", 1.2, 10)
        Sound.playNote("bass", 1.2, 7)
        Sound.playNote("bass", 1.2, 4)
        return true
    end
    return false
end

return Sound
