--[[
    Drunken OS - Chat Module
    Extracted from Drunken_OS_Server.lua
]]

local ChatModule = {}

---
-- Handles incoming SimpleChat_Internal messages.
-- @param senderId The Rednet ID of the sender.
-- @param message The message table containing 'from' and 'text'.
-- @param context A table containing server state references (users, chatHistory, queueSave, CHAT_DB).
function ChatModule.handleProtocolMessage(senderId, message, context)
    local active_sessions = context.active_sessions
    local chatHistory = context.chatHistory
    local queueSave = context.queueSave
    local CHAT_DB = context.CHAT_DB

    -- Generic chat message processing
    local nickname = message.from
    if active_sessions and active_sessions[message.from] and active_sessions[message.from].nickname then
        nickname = active_sessions[message.from].nickname
    end
    local entry = string.format("[%s]: %s", nickname, message.text)
    
    table.insert(chatHistory, entry)
    if #chatHistory > 100 then table.remove(chatHistory, 1) end
    
    queueSave(CHAT_DB)
    
    -- Relay message to all clients on the internal network
    rednet.broadcast({ from = nickname, text = message.text, senderId = senderId }, "SimpleChat_Internal") 
end

---
-- Handles the 'get_chat_history' SimpleMail request.
-- @param senderId The Rednet ID of the requester.
-- @param message The request message.
-- @param context A table containing server state references (chatHistory).
function ChatModule.handleGetHistory(senderId, message, context)
    rednet.send(senderId, { history = context.chatHistory }, "SimpleMail")
end

return ChatModule
