--[[
    Unit Test: Universal DNS & Discovery Cache (lib/dns.lua)
    Verifies lookup caching, TTL expiration, invalidation, and monkey-patching.
]]

package.path = "./?.lua;" .. package.path
local dns = require("lib.dns")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running DNS & Discovery Cache Tests ===")

-- Mock rednet.lookup
local mockLookupCount = 0
local mockRegistry = {
    ["SimpleMail:mail.server"] = 10,
    ["DB_Bank:bank.server"] = 20,
    ["ArcadeGames:arcade.server"] = 30
}

_G.rednet = {
    lookup = function(protocol, hostname)
        mockLookupCount = mockLookupCount + 1
        local key = tostring(protocol or "") .. ":" .. tostring(hostname or "")
        return mockRegistry[key]
    end
}

dns.flush()

-- 1. Initial Lookup (Cache Miss)
local id1 = dns.lookup("SimpleMail", "mail.server")
assert_eq(id1, 10, "First lookup resolves ID 10")
assert_eq(mockLookupCount, 1, "Raw lookup called once on miss")

-- 2. Subsequent Lookup (Cache Hit)
local id2 = dns.lookup("SimpleMail", "mail.server")
assert_eq(id2, 10, "Second lookup returns cached ID 10")
assert_eq(mockLookupCount, 1, "Raw lookup NOT called on hit")

local stats = dns.getStats()
assert_eq(stats.hits, 1, "Stats recorded 1 hit")
assert_eq(stats.misses, 1, "Stats recorded 1 miss")

-- 3. Invalidation
dns.invalidate("SimpleMail", "mail.server")
local id3 = dns.lookup("SimpleMail", "mail.server")
assert_eq(id3, 10, "Post-invalidation lookup resolves")
assert_eq(mockLookupCount, 2, "Raw lookup called again after invalidation")

-- 4. TTL Expiration with short TTL
local id4 = dns.lookup("DB_Bank", "bank.server", 0.001) -- 1ms TTL
assert_eq(id4, 20, "Bank lookup resolves ID 20")
assert_eq(mockLookupCount, 3, "Lookup count is 3")

-- Wait for TTL to expire
local start = os.clock()
while os.clock() - start < 0.01 do end

local id5 = dns.lookup("DB_Bank", "bank.server", 0.001)
assert_eq(id5, 20, "Bank lookup resolves again")
assert_eq(mockLookupCount, 4, "Raw lookup called after TTL expired")

-- 5. rednet.lookup monkey-patching
dns.patchRednet()
local idPatched = rednet.lookup("ArcadeGames", "arcade.server")
assert_eq(idPatched, 30, "Patched rednet.lookup returns 30")
assert_eq(mockLookupCount, 5, "Patched lookup triggered raw call on miss")

local idPatched2 = rednet.lookup("ArcadeGames", "arcade.server")
assert_eq(idPatched2, 30, "Patched rednet.lookup hits cache")
assert_eq(mockLookupCount, 5, "Raw lookup NOT called through patched rednet")

dns.unpatchRednet()

-- 6. Stale-While-Revalidate Fallback (Sleeping / Unloaded Chunks)
-- Wait for bank entry TTL to expire
local start2 = os.clock()
while os.clock() - start2 < 0.01 do end

-- Simulate server being unloaded / offline
mockRegistry["DB_Bank:bank.server"] = nil

-- Lookup with allowStale = true (default) should return stale ID 20
local idStale = dns.lookup("DB_Bank", "bank.server", 0.001)
assert_eq(idStale, 20, "Stale fallback returns cached ID 20 when server is sleeping/unloaded")
local statsAfterStale = dns.getStats()
assert_eq(statsAfterStale.stale_hits, 1, "Stale hits counter incremented to 1")

-- Lookup with allowStale = false should return nil
local idStrict = dns.lookup("DB_Bank", "bank.server", 0.001, false)
assert_eq(idStrict, nil, "Strict lookup (allowStale=false) returns nil when offline")

-- 7. Persistent Cache & Flush
dns.saveCache()
local statsBeforeFlush = dns.getStats()
assert_eq(statsBeforeFlush.entries > 0, true, "Active entries present before flush")
dns.flush()
local statsAfterFlush = dns.getStats()
assert_eq(statsAfterFlush.entries, 0, "Cache completely empty after flush")

print(">>> All DNS Cache tests passed successfully!\n")
return true
