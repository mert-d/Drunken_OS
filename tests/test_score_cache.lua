--[[
    Unit Test: Offline-First Score Cache & Sync (lib/score_cache.lua)
    Verifies offline score persistence, pending queue, and automatic server sync.
]]

package.path = "./?.lua;" .. package.path

local memoryFS = {}
_G.fs = {
    exists = function(path) return memoryFS[path] ~= nil end,
    open = function(path, mode)
        if mode == "r" then
            if not memoryFS[path] then return nil end
            return {
                readAll = function() return memoryFS[path] end,
                close = function() end
            }
        elseif mode == "w" then
            return {
                write = function(content) memoryFS[path] = content end,
                close = function() end
            }
        end
    end,
    delete = function(path) memoryFS[path] = nil end,
    move = function(from, to)
        memoryFS[to] = memoryFS[from]
        memoryFS[from] = nil
    end
}

local function serializeVal(v)
    if type(v) == "string" then return string.format("%q", v)
    elseif type(v) == "table" then
        local p = {}
        for k, val in pairs(v) do
            local keyStr = (type(k) == "number") and ("[" .. k .. "]") or (type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. string.format("%q", tostring(k)) .. "]"))
            table.insert(p, keyStr .. "=" .. serializeVal(val))
        end
        return "{" .. table.concat(p, ",") .. "}"
    else
        return tostring(v)
    end
end

_G.textutils = _G.textutils or {}
_G.textutils.serialize = serializeVal
_G.textutils.unserialize = function(s)
    local fn = load("return " .. s)
    if fn then return fn() end
    return nil
end

local serverPackets = {}
local networkOpen = false
local serverFound = false

_G.rednet = {
    isOpen = function() return networkOpen end,
    lookup = function(proto, name)
        if serverFound and proto == "ArcadeGames" and name == "arcade.server" then
            return 99
        end
        return nil
    end,
    send = function(target, msg, proto)
        table.insert(serverPackets, { target = target, msg = msg, proto = proto })
    end
}

local scoreCache = require("lib.score_cache")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Score Cache & Sync Tests ===")

-- 1. Offline Score Recording
networkOpen = false
serverFound = false
serverPackets = {}

local ok1, status1 = scoreCache.recordScore("Tetris", 500, "Mert")
assert_eq(ok1, true, "Offline score recorded")
assert_eq(status1, "queued", "Score queued for deferred sync")
assert_eq(scoreCache.getPersonalBest("Tetris"), 500, "Personal best updated locally")
assert_eq(scoreCache.getPendingCount(), 1, "Pending sync queue count is 1")
assert_eq(#serverPackets, 0, "No network packets sent while offline")

-- 2. Higher score while still offline
local ok2, status2 = scoreCache.recordScore("Tetris", 1200, "Mert")
assert_eq(status2, "queued", "Second score queued")
assert_eq(scoreCache.getPersonalBest("Tetris"), 1200, "Personal best updated to 1200")
assert_eq(scoreCache.getPendingCount(), 2, "Pending sync queue count is 2")

-- 3. Local Leaderboard Verification
local localBoard = scoreCache.getLocalLeaderboard("Tetris")
assert_eq(#localBoard, 2, "2 local scores in leaderboard")
assert_eq(localBoard[1].score, 1200, "Top local score is 1200")

-- 4. Server Reconnects & Deferred Sync
networkOpen = true
serverFound = true
serverPackets = {}

local synced, remaining = scoreCache.syncPending()
assert_eq(synced, 2, "Both queued scores synchronized to server")
assert_eq(remaining, 0, "0 pending scores remaining")
assert_eq(scoreCache.getPendingCount(), 0, "Pending queue cleared")
assert_eq(#serverPackets, 2, "2 score packets delivered to Arcade Server")
assert_eq(serverPackets[1].target, 99, "Target is Arcade Server ID 99")

-- 5. Online Score Recording (Immediate Submission)
serverPackets = {}
local okOnline, statusOnline = scoreCache.recordScore("Tetris", 1500, "Mert")
assert_eq(okOnline, true, "Online score recorded")
assert_eq(statusOnline, "submitted", "Online score submitted immediately")
assert_eq(scoreCache.getPendingCount(), 0, "Pending count remains 0")
assert_eq(#serverPackets, 1, "Immediate score packet sent to server")
assert_eq(serverPackets[1].msg.score, 1500, "Packet score is 1500")

-- 6. P2P Socket Integration (Pong / Duels / Dungeons)
_G.peripheral = {
    find = function(t) if t == "modem" then return "top" end end,
    getName = function(p) return p end
}
local P2P_Socket = require("lib.p2p_socket")
local sock = P2P_Socket.new("DrunkenPong", 1.0, "DrunkenPong_Game")
local p2pOk = sock:submitScore("Mert", 8)
assert_eq(p2pOk, true, "P2P Socket score recorded through score cache")
assert_eq(scoreCache.getPersonalBest("DrunkenPong"), 8, "P2P score saved in local database")

print(">>> All Score Cache & Sync tests passed successfully!\n")
return true
