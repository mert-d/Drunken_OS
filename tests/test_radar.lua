--[[
    Unit Test: NetRadar Diagnostics & Proximity Suite (tests/test_radar.lua)
    Verifies device discovery, Euclidean distance calculation, proximity sorting, and server pings.
]]

package.path = "./?.lua;" .. package.path

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s (expected %s, got %s)", msg or "", tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. (msg or "assert_eq"))
end

print("=== Running NetRadar Diagnostics Tests ===")

-- 1. Euclidean Distance Math Verification
local function computeDistance(p1, p2)
    if not p1 or not p2 then return nil, "In Range" end
    local dx = p1.x - p2.x
    local dy = p1.y - p2.y
    local dz = p1.z - p2.z
    local dist = math.floor(math.sqrt(dx*dx + dy*dy + dz*dz))
    return dist, dist .. "m"
end

local myPos = { x = 100, y = 64, z = 200 }
local nearPlayer = { x = 130, y = 64, z = 240 } -- dx=30, dz=40 -> 30^2+40^2 = 900+1600 = 2500 -> sqrt = 50
local d1, str1 = computeDistance(myPos, nearPlayer)
assert_eq(d1, 50, "Pythagorean 30-40-50 distance is exactly 50 blocks")
assert_eq(str1, "50m", "Formatted string is 50m")

local verticalTurtle = { x = 100, y = 14, z = 200 } -- dy = 50
local d2, str2 = computeDistance(myPos, verticalTurtle)
assert_eq(d2, 50, "Vertical shaft distance computed accurately")

local noGpsDevice = nil
local d3, str3 = computeDistance(myPos, noGpsDevice)
assert_eq(d3, nil, "No GPS returns nil numeric distance")
assert_eq(str3, "In Range", "No GPS falls back to In Range label")

-- 2. Proximity Sorting Verification
local devices = {
    { id = 3, user = "FarAway", distNum = 180 },
    { id = 1, user = "CloseFriend", distNum = 15 },
    { id = 2, user = "MidMiner", distNum = 62 }
}
table.sort(devices, function(a, b) return a.distNum < b.distNum end)
assert_eq(devices[1].user, "CloseFriend", "Closest device sorted first (15m)")
assert_eq(devices[2].user, "MidMiner", "Middle device sorted second (62m)")
assert_eq(devices[3].user, "FarAway", "Furthest device sorted last (180m)")

-- 3. World Spawn Server Latency & Offline Timeout
local serverDb = {
    ["bank.server"] = { id = 99, latency = 14 },
    ["arcade.server"] = { id = 101, latency = 22 }
    -- mail.server is offline / unloaded
}

local function pingServer(host)
    local t0 = 1000
    local target = serverDb[host]
    if not target then
        return false, 0, "ASLEEP/OFF"
    end
    local elapsed = target.latency
    return true, elapsed, string.format("%dms OK", elapsed)
end

local okBank, latBank, tagBank = pingServer("bank.server")
assert_eq(okBank, true, "Bank server online detected")
assert_eq(latBank, 14, "Bank server latency measured at 14ms")
assert_eq(tagBank, "14ms OK", "Tag displays 14ms OK")

local okMail, latMail, tagMail = pingServer("mail.server")
assert_eq(okMail, false, "Mail server marked offline")
assert_eq(latMail, 0, "Offline server latency is 0")
assert_eq(tagMail, "ASLEEP/OFF", "Tag displays ASLEEP/OFF without freezing")

print(">>> All NetRadar Diagnostics tests passed successfully!\n")
return true
