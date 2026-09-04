--[[
    Drunken OS - Non-Blocking RPC & Transaction Multiplexer (lib/rpc.lua)
    Version: 1.0
    
    Provides request correlation (tx_id) to eliminate Head-of-Line blocking and message loss.
    Guarantees that waiting for a response does not drop unrelated messages on other protocols.
]]

local rpc = {
    _VERSION = "1.0",
    DEFAULT_TIMEOUT = 5
}

local pendingInbox = {}
local requestCounter = 0

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

--- Generates a unique transaction identifier
function rpc.newTxId()
    requestCounter = (requestCounter + 1) % 100000
    local cid = os.getComputerID and os.getComputerID() or 0
    return string.format("tx_%d_%d_%d_%04x", cid, getEpochMs(), requestCounter, math.random(0, 0xFFFF))
end

--- Performs a correlated RPC call to a remote computer.
-- Dispatches request with a unique tx_id and safely waits for the matching reply.
-- Any unrelated rednet messages received while waiting are preserved in the pending inbox.
-- @param targetId number: Destination Rednet ID.
-- @param payload table|string: Request data.
-- @param protocol string: Rednet protocol.
-- @param timeout number: (Optional) Max wait time in seconds (defaults to 5).
-- @return boolean, any: (true, response) on success, or (false, errorMsg) on failure/timeout.
function rpc.call(targetId, payload, protocol, timeout)
    if not rednet or not rednet.isOpen() then
        return false, "Rednet is closed"
    end
    
    local txId = rpc.newTxId()
    local envelope = {
        rpc_tx = txId,
        req = payload
    }
    
    rednet.send(targetId, envelope, protocol)
    
    local maxTime = timeout or rpc.DEFAULT_TIMEOUT
    local timerId = os.startTimer(maxTime)
    
    -- Check if response is already in inbox
    for i, item in ipairs(pendingInbox) do
        if item.senderId == targetId and item.protocol == protocol and type(item.msg) == "table" and item.msg.rpc_reply == txId then
            table.remove(pendingInbox, i)
            local reply = item.msg
            if reply.success ~= false then
                return true, reply.resp
            else
                return false, reply.error or "Remote error"
            end
        end
    end
    
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, msg, msgProto = p1, p2, p3
            
            if senderId == targetId and (msgProto == protocol or not protocol) and type(msg) == "table" and msg.rpc_reply == txId then
                if msg.success ~= false then
                    return true, msg.resp
                else
                    return false, msg.error or "Remote error"
                end
            else
                -- Not the reply we are waiting for: preserve in inbox so nothing is lost!
                table.insert(pendingInbox, { senderId = senderId, msg = msg, protocol = msgProto })
            end
            
        elseif event == "timer" and p1 == timerId then
            return false, "RPC timeout: no response from host " .. tostring(targetId)
        end
    end
end

--- Replies to an incoming correlated RPC request.
-- @param senderId number: Rednet ID of the original requester.
-- @param txId string: The rpc_tx correlation ID from the request.
-- @param responsePayload any: The result payload to send back.
-- @param protocol string: Rednet protocol to respond on.
-- @param success boolean: (Optional) true for success (default), false for error.
-- @param errorMsg string: (Optional) Error description if success is false.
function rpc.respond(senderId, txId, responsePayload, protocol, success, errorMsg)
    if not rednet or not rednet.isOpen() then return false end
    
    local reply = {
        rpc_reply = txId,
        resp = responsePayload,
        success = (success ~= false),
        error = errorMsg
    }
    
    rednet.send(senderId, reply, protocol)
    return true
end

--- Pulls the next message from Rednet, checking the preserved inbox before pulling from the OS queue.
-- Replaces rednet.receive() without discarding non-matching messages.
-- @param protocol string: (Optional) Filter protocol.
-- @param timeout number: (Optional) Timeout in seconds.
-- @return number, any, string: senderId, message, protocol (or nil on timeout).
function rpc.receive(protocol, timeout)
    -- 1. Check preserved inbox first
    for i, item in ipairs(pendingInbox) do
        if not protocol or item.protocol == protocol then
            table.remove(pendingInbox, i)
            return item.senderId, item.msg, item.protocol
        end
    end
    
    -- 2. Pull from event queue
    local timerId = timeout and os.startTimer(timeout)
    
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local senderId, msg, msgProto = p1, p2, p3
            if not protocol or msgProto == protocol then
                return senderId, msg, msgProto
            else
                table.insert(pendingInbox, { senderId = senderId, msg = msg, protocol = msgProto })
            end
        elseif event == "timer" and timerId and p1 == timerId then
            return nil
        end
    end
end

--- Returns the current backlog count in the RPC inbox.
function rpc.getInboxCount()
    return #pendingInbox
end

--- Clears the preserved inbox.
function rpc.flushInbox()
    pendingInbox = {}
end

return rpc
