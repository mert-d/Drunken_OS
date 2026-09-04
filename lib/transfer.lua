--[[
    Drunken OS - Chunked & Reliable File Transfer Protocol (lib/transfer.lua)
    Version: 1.0
    
    Transfers large files (games, cloud documents, mail attachments) in 2KB packets.
    Provides transfer progress callbacks, sequence ACKs, and end-to-end SHA-1 checksum verification.
]]

local sha1 = require("lib.sha1_hmac")

local transfer = {
    _VERSION = "1.0",
    CHUNK_SIZE = 2048, -- 2KB chunks
    DEFAULT_TIMEOUT = 3 -- 3 seconds timeout per chunk
}

local function getEpochMs()
    if os.epoch then
        return os.epoch("utc")
    elseif os.clock then
        return math.floor(os.clock() * 1000)
    elseif os.time then
        return math.floor(os.time() * 1000)
    end
    return 0
end

--- Slices a raw string or byte buffer into sized chunks.
-- @param data string: The complete file contents.
-- @param chunkSize number: (Optional) Size of each chunk in bytes (defaults to 2048).
-- @return table: Array of string chunks.
function transfer.encodeChunks(data, chunkSize)
    local sz = chunkSize or transfer.CHUNK_SIZE
    local chunks = {}
    local len = #data
    local pos = 1
    while pos <= len do
        table.insert(chunks, data:sub(pos, pos + sz - 1))
        pos = pos + sz
    end
    return chunks
end

--- Reassembles chunks into full data and verifies SHA-1 checksum.
-- @param chunks table: Array of chunks indexed 1..N.
-- @param expectedHash string: (Optional) Expected hex SHA-1 hash.
-- @return boolean, string: (true, fullData) on success, or (false, errorReason) on failure.
function transfer.decodeChunks(chunks, expectedHash)
    local fullData = table.concat(chunks)
    if expectedHash then
        local actualHash = sha1.hex(fullData)
        if actualHash ~= expectedHash then
            return false, string.format("Checksum mismatch! Expected: %s, Got: %s", expectedHash, actualHash)
        end
    end
    return true, fullData
end

--- Synchronously sends a large file or string over Rednet using chunked streaming.
-- @param targetId number: Recipient Rednet ID.
-- @param data string: Full file contents.
-- @param filename string: Name of the file being sent.
-- @param protocol string: Rednet protocol for transfer.
-- @param onProgress function: (Optional) callback(bytesSent, totalBytes, chunkIdx, totalChunks).
-- @return boolean, string: (true, "OK") on success, or (false, errorReason) on failure.
function transfer.send(targetId, data, filename, protocol, onProgress)
    if not rednet or not rednet.isOpen() then
        return false, "Rednet is not open"
    end
    
    local totalBytes = #data
    local chunks = transfer.encodeChunks(data, transfer.CHUNK_SIZE)
    local totalChunks = #chunks
    local fullHash = sha1.hex(data)
    local transferId = string.format("xfer_%d_%d_%04x", os.getComputerID(), getEpochMs(), math.random(0, 0xFFFF))
    
    -- 1. Initialize Transfer
    local initMsg = {
        type = "xfer_init",
        transferId = transferId,
        filename = filename,
        totalBytes = totalBytes,
        totalChunks = totalChunks,
        hash = fullHash
    }
    
    rednet.send(targetId, initMsg, protocol)
    local id, reply = rednet.receive(protocol, transfer.DEFAULT_TIMEOUT)
    if id ~= targetId or type(reply) ~= "table" or reply.type ~= "xfer_ack_init" or reply.transferId ~= transferId then
        return false, "Recipient failed to acknowledge transfer initialization"
    end
    
    -- 2. Stream Chunks
    local bytesSent = 0
    for i = 1, totalChunks do
        local chunkData = chunks[i]
        local retries = 3
        local acked = false
        
        while retries > 0 and not acked do
            rednet.send(targetId, {
                type = "xfer_chunk",
                transferId = transferId,
                index = i,
                chunk = chunkData
            }, protocol)
            
            local ackId, ackMsg = rednet.receive(protocol, transfer.DEFAULT_TIMEOUT)
            if ackId == targetId and type(ackMsg) == "table" and ackMsg.type == "xfer_ack" and ackMsg.index == i and ackMsg.transferId == transferId then
                acked = true
            else
                retries = retries - 1
            end
        end
        
        if not acked then
            return false, string.format("Failed to transmit chunk %d/%d (timeout after retries)", i, totalChunks)
        end
        
        bytesSent = bytesSent + #chunkData
        if onProgress then
            pcall(onProgress, bytesSent, totalBytes, i, totalChunks)
        end
    end
    
    -- 3. Finalize Transfer
    rednet.send(targetId, {
        type = "xfer_done",
        transferId = transferId
    }, protocol)
    
    local doneId, doneMsg = rednet.receive(protocol, transfer.DEFAULT_TIMEOUT)
    if doneId == targetId and type(doneMsg) == "table" and doneMsg.type == "xfer_ack_done" and doneMsg.success then
        return true, "Transfer completed successfully"
    end
    
    return false, "Recipient reported transfer validation failure"
end

--- Creates an in-memory receiver session manager to handle multiple chunked streams.
function transfer.createReceiver(onComplete, onProgress)
    local sessions = {}
    
    local receiver = {}
    
    function receiver.handleMessage(senderId, msg, protocol)
        if type(msg) ~= "table" or not msg.type or not msg.transferId then return false end
        local tId = msg.transferId
        
        if msg.type == "xfer_init" then
            sessions[tId] = {
                senderId = senderId,
                filename = msg.filename,
                totalBytes = msg.totalBytes,
                totalChunks = msg.totalChunks,
                hash = msg.hash,
                chunks = {},
                receivedBytes = 0
            }
            rednet.send(senderId, { type = "xfer_ack_init", transferId = tId }, protocol)
            return true
            
        elseif msg.type == "xfer_chunk" then
            local session = sessions[tId]
            if session and session.senderId == senderId then
                if not session.chunks[msg.index] then
                    session.chunks[msg.index] = msg.chunk
                    session.receivedBytes = session.receivedBytes + #msg.chunk
                end
                
                rednet.send(senderId, {
                    type = "xfer_ack",
                    transferId = tId,
                    index = msg.index
                }, protocol)
                
                if onProgress then
                    pcall(onProgress, session.receivedBytes, session.totalBytes, msg.index, session.totalChunks, session.filename)
                end
                return true
            end
            
        elseif msg.type == "xfer_done" then
            local session = sessions[tId]
            if session and session.senderId == senderId then
                local ok, result = transfer.decodeChunks(session.chunks, session.hash)
                if ok then
                    rednet.send(senderId, {
                        type = "xfer_ack_done",
                        transferId = tId,
                        success = true
                    }, protocol)
                    if onComplete then
                        pcall(onComplete, result, session.filename, senderId)
                    end
                else
                    rednet.send(senderId, {
                        type = "xfer_ack_done",
                        transferId = tId,
                        success = false,
                        error = result
                    }, protocol)
                end
                sessions[tId] = nil
                return true
            end
        end
        
        return false
    end
    
    return receiver
end

return transfer
