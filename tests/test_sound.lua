--[[
    Unit Test: Speaker Audio Engine (lib/sound.lua)
    Verifies 8-bit note playback, category toast chimes, radar proximity pitch scaling,
    global mute controls, and silent fallback when no speaker is attached.
]]

package.path = "./?.lua;" .. package.path
local Sound = require("lib.sound")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Speaker Sound Engine Tests ===")

-- 1. Silent fallback when no speaker is present
_G.peripheral = {
    find = function(ptype) return nil end,
    getType = function(obj) return nil end
}

Sound.setEnabled(true)
assert_eq(Sound.isAvailable(), false, "isAvailable returns false when no speaker attached")
assert_eq(Sound.playNote("harp", 1.0, 12), false, "playNote fails silently without throwing")
assert_eq(Sound.playToast("mail"), false, "playToast fails silently without throwing")
assert_eq(Sound.playCoin(), false, "playCoin fails silently without throwing")
assert_eq(Sound.playClick(), false, "playClick fails silently without throwing")
assert_eq(Sound.playSuccess(), false, "playSuccess fails silently without throwing")
assert_eq(Sound.playError(), false, "playError fails silently without throwing")
assert_eq(Sound.playRadarPing(10), false, "playRadarPing fails silently without throwing")
assert_eq(Sound.playGameBeep("blip"), false, "playGameBeep fails silently without throwing")

-- 2. Audio with mocked speaker peripheral
local playedNotes = {}
local mockSpeaker = {
    playNote = function(instrument, volume, pitch)
        table.insert(playedNotes, { inst = instrument, vol = volume, pitch = pitch })
        return true
    end
}

_G.peripheral = {
    find = function(ptype)
        if ptype == "speaker" then return mockSpeaker end
        return nil
    end,
    getType = function(obj)
        if obj == mockSpeaker then return "speaker" end
        return nil
    end
}

assert_eq(Sound.isAvailable(), true, "isAvailable returns true when speaker is attached")

-- 3. Direct Note Playback
playedNotes = {}
local played = Sound.playNote("harp", 1.0, 12)
assert_eq(played, true, "playNote succeeds with attached speaker")
assert_eq(#playedNotes, 1, "Speaker recorded 1 note played")
assert_eq(playedNotes[1].inst, "harp", "Instrument is harp")
assert_eq(playedNotes[1].vol, 1.0, "Volume is 1.0")
assert_eq(playedNotes[1].pitch, 12, "Pitch is 12")

-- 4. Global Mute & Unmute
Sound.setEnabled(false)
assert_eq(Sound.isEnabled(), false, "Sound is globally muted")
playedNotes = {}
local mutePlayed = Sound.playNote("harp", 1.0, 12)
assert_eq(mutePlayed, false, "playNote returns false when muted")
assert_eq(#playedNotes, 0, "No notes played to hardware when muted")

Sound.setEnabled(true)
assert_eq(Sound.isEnabled(), true, "Sound is unmuted")

-- 5. Notification Toast Chimes
playedNotes = {}
Sound.playToast("mail")
assert_eq(#playedNotes, 2, "Mail toast plays 2 chimes")
assert_eq(playedNotes[1].inst, "chime", "Mail toast uses chime instrument")

playedNotes = {}
Sound.playToast("chat")
assert_eq(#playedNotes, 1, "Chat toast plays 1 bell chime")
assert_eq(playedNotes[1].inst, "bell", "Chat toast uses bell instrument")

playedNotes = {}
Sound.playToast("bank")
assert_eq(#playedNotes, 1, "Bank toast plays 1 pling")
assert_eq(playedNotes[1].inst, "pling", "Bank toast uses pling")

-- 6. Interactive Banking Coin Sound
playedNotes = {}
Sound.playCoin()
assert_eq(#playedNotes, 2, "Coin sound plays 2 rising plings")
assert_eq(playedNotes[1].pitch < playedNotes[2].pitch, true, "Coin tones ascend in pitch (14 -> 20)")

-- 7. Radar Proximity Pitch Scaling
playedNotes = {}
Sound.playRadarPing(5)   -- Very close (<= 10 blocks)
Sound.playRadarPing(20)  -- Close (<= 25 blocks)
Sound.playRadarPing(45)  -- Medium (<= 50 blocks)
Sound.playRadarPing(70)  -- Far (<= 80 blocks)
Sound.playRadarPing(120) -- Very far (> 80 blocks)

assert_eq(#playedNotes, 5, "Radar ping played 5 tests")
assert_eq(playedNotes[1].pitch, 22, "Immediate proximity <=10m pitch is 22")
assert_eq(playedNotes[2].pitch, 18, "Proximity <=25m pitch is 18")
assert_eq(playedNotes[3].pitch, 14, "Proximity <=50m pitch is 14")
assert_eq(playedNotes[4].pitch, 10, "Proximity <=80m pitch is 10")
assert_eq(playedNotes[5].pitch, 6, "Distant proximity >80m pitch is 6")

-- 8. Arcade Beeps
playedNotes = {}
Sound.playGameBeep("blip")
assert_eq(playedNotes[1].inst, "bit", "Arcade blip uses retro bit instrument")

playedNotes = {}
Sound.playGameBeep("gameover")
assert_eq(#playedNotes, 3, "Arcade gameover plays 3 descending bass tones")
assert_eq(playedNotes[1].pitch > playedNotes[3].pitch, true, "Gameover bass notes descend")

print(">>> All Speaker Audio Engine tests passed successfully!\n")
return true
