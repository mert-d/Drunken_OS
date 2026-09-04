--[[
    Unit Test: Non-Blocking RPC & Packet Multiplexer (lib/rpc.lua)
    Verifies transaction ID generation, response formatting, and non-discarding inbox queue.
]]

package.path = "./?.lua;" .. package.path

local eventQueue = {}
local sentPackets = {}

_G.os = _G.os or {}
_G.os.pullEvent = function()
    if #eventQueue > 0 then
        local ev = table.remove(eventQueue, 1)
        return table.unpack(ev)
    end
    return "timer", -1
end
_G.os.startTimer = function() return 999 end

_G.rednet = {
    isOpen = function() return true end,
    send = function(targetId, msg, proto)
        table.insert(sentPackets, { targetId = targetId, msg = msg, proto = proto })
    end
}

local rpc = require("lib.rpc")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Non-Blocking RPC & Inbox Tests ===")

-- 1. TxID Generation & Uniqueness
local id1 = rpc.newTxId()
local id2 = rpc.newTxId()
assert_eq(type(id1), "string", "TxID is string")
assert_eq(id1:sub(1, 3), "tx_", "TxID starts with tx_")
assert_eq(id1 ~= id2, true, "Sequential TxIDs are distinct")

-- 2. Response formatting
sentPackets = {}
rpc.respond(5, id1, { balance = 1200 }, "DB_Bank", true)
assert_eq(#sentPackets, 1, "Packet sent via rednet")
assert_eq(sentPackets[1].targetId, 5, "Target recipient ID")
assert_eq(sentPackets[1].proto, "DB_Bank", "Protocol is DB_Bank")
assert_eq(sentPackets[1].msg.rpc_reply, id1, "Reply correlation ID matches request TxID")
assert_eq(sentPackets[1].msg.success, true, "Success flag is true")
assert_eq(sentPackets[1].msg.resp.balance, 1200, "Response data preserved")

-- 3. Non-Discarding Inbox Queue
rpc.flushInbox()
assert_eq(rpc.getInboxCount(), 0, "Inbox starts empty")

-- Simulate 3 messages arriving in the OS event queue:
-- Message A: SimpleChat from ID 10
-- Message B: DB_Bank from ID 20
-- Message C: ArcadeGames from ID 30
table.insert(eventQueue, { "rednet_message", 10, { text = "Hello Chat" }, "SimpleChat" })
table.insert(eventQueue, { "rednet_message", 20, { balance = 999 }, "DB_Bank" })
table.insert(eventQueue, { "rednet_message", 30, { game = "Snake" }, "ArcadeGames" })

-- Target request: We only want the "DB_Bank" message
local bSender, bMsg, bProto = rpc.receive("DB_Bank", 1)
assert_eq(bSender, 20, "Target DB_Bank sender returned")
assert_eq(bProto, "DB_Bank", "Target protocol returned")
assert_eq(bMsg.balance, 999, "Target message payload returned")

-- CRITICAL TEST: The earlier "SimpleChat" message must NOT have been discarded!
-- It must now reside in the preserved inbox!
assert_eq(rpc.getInboxCount(), 1, "Non-matching SimpleChat message preserved in inbox")

-- Next receive on SimpleChat: pulls immediately from inbox without pulling from OS queue!
local cSender, cMsg, cProto = rpc.receive("SimpleChat", 1)
assert_eq(cSender, 10, "SimpleChat message retrieved from inbox")
assert_eq(cMsg.text, "Hello Chat", "SimpleChat text matches")
assert_eq(rpc.getInboxCount(), 0, "Inbox cleared after retrieval")

-- Now receive ArcadeGames from remaining event queue
local aSender, aMsg, aProto = rpc.receive("ArcadeGames", 1)
assert_eq(aSender, 30, "ArcadeGames sender retrieved")
assert_eq(aMsg.game, "Snake", "ArcadeGames payload matches")

print(">>> All RPC & Inbox tests passed successfully!\n")
return true
