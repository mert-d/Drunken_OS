--[[
    Unit Test: Chunked & Streaming File Transfer (lib/transfer.lua)
    Verifies chunk slicing, reassembly, SHA-1 checksum validation, and receiver state machine.
]]

package.path = "./?.lua;" .. package.path

-- Mock rednet for receiver tests
local sentMessages = {}
_G.rednet = {
    isOpen = function() return true end,
    send = function(targetId, msg, proto)
        table.insert(sentMessages, { targetId = targetId, msg = msg, proto = proto })
    end
}

local sha1 = require("lib.sha1_hmac")
local transfer = require("lib.transfer")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Chunked File Transfer Tests ===")

-- 1. Slicing & Reassembly
local testData = string.rep("0123456789ABCDEF", 300) -- 4800 bytes
local chunks = transfer.encodeChunks(testData, 1000)
assert_eq(#chunks, 5, "4800 bytes sliced into 5 chunks of 1000b")
assert_eq(#chunks[1], 1000, "Chunk 1 size")
assert_eq(#chunks[5], 800, "Chunk 5 remainder size")

local okDecode, reassembled = transfer.decodeChunks(chunks, sha1.hex(testData))
assert_eq(okDecode, true, "Reassembly with matching SHA-1 succeeds")
assert_eq(reassembled == testData, true, "Reassembled data matches original byte-for-byte")

-- 2. Corrupted Chunk Detection
local corruptedChunks = { chunks[1], chunks[2], "CORRUPTED_DATA", chunks[4], chunks[5] }
local okBad, badErr = transfer.decodeChunks(corruptedChunks, sha1.hex(testData))
assert_eq(okBad, false, "Corrupted chunk detected")
assert_eq(badErr:find("Checksum mismatch") ~= nil, true, "Checksum mismatch error reported")

-- 3. Receiver Session Simulation
local completedFile = nil
local progressUpdates = 0

local receiver = transfer.createReceiver(
    function(fullData, filename, senderId)
        completedFile = fullData
    end,
    function(bytesRcvd, totalBytes, idx, total)
        progressUpdates = progressUpdates + 1
    end
)

local transferId = "test_xfer_1001"
local fileHash = sha1.hex(testData)

-- A. Init
sentMessages = {}
local handledInit = receiver.handleMessage(1, {
    type = "xfer_init",
    transferId = transferId,
    filename = "game.lua",
    totalBytes = #testData,
    totalChunks = #chunks,
    hash = fileHash
}, "ArcadeGames")
assert_eq(handledInit, true, "Receiver handled xfer_init")
assert_eq(#sentMessages, 1, "ACK init sent back")
assert_eq(sentMessages[1].msg.type, "xfer_ack_init", "ACK init message type")

-- B. Stream all 5 chunks
for i = 1, #chunks do
    local handledChunk = receiver.handleMessage(1, {
        type = "xfer_chunk",
        transferId = transferId,
        index = i,
        chunk = chunks[i]
    }, "ArcadeGames")
    assert_eq(handledChunk, true, "Receiver handled chunk " .. i)
end
assert_eq(progressUpdates, 5, "Progress callback fired 5 times")

-- C. Done
local handledDone = receiver.handleMessage(1, {
    type = "xfer_done",
    transferId = transferId
}, "ArcadeGames")
assert_eq(handledDone, true, "Receiver handled xfer_done")
assert_eq(completedFile == testData, true, "Complete file received and verified via SHA-1")

print(">>> All Chunked File Transfer tests passed successfully!\n")
return true
