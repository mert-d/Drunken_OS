--[[
    Drunken OS - Authentication Server (Microservices Architecture)
    Handles login, registration, and session token generation via HyperAuth.
]]

package.path = "/?.lua;" .. package.path

local ok_crypto, crypto = pcall(require, "lib.sha1_hmac")
if not ok_crypto then error("Auth Server: lib.sha1_hmac not found.", 0) end

local ok_auth, AuthClient = pcall(require, "HyperAuthClient/api/auth_client")
if not ok_auth then error("Auth Server: HyperAuthClient API not found.", 0) end

local DB = require("lib.db")

-- State
local users = {}
local pendingAuths = {}
local USERS_DB = "users.db"
local AUTH_SERVER_PROTOCOL = "auth.secure.v1"
local AUTH_INTERNAL_API = "auth.secure.v1_Internal"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"

-- Modems
local wirelessModem = nil
local wiredModem = nil

local function logActivity(msg, isError)
    local pfx = isError and "[ERROR] " or "[INFO] "
    print(os.date("[%H:%M:%S] ") .. pfx .. msg)
end

-- Initialize modems
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        if peripheral.call(name, "isWireless") then
            wirelessModem = name
            rednet.open(name)
        else
            wiredModem = name
            rednet.open(name)
        end
    end
end

if not wirelessModem and not wiredModem then
    error("Auth Server requires at least one modem to function.")
end

-- Load Database
users = DB.loadTableFromFile(USERS_DB, logActivity)

-- Host the auth service
rednet.host(AUTH_SERVER_PROTOCOL, "auth.server")

--- Initiates a 2FA request via HyperAuth
local function requestAuthCode(username, password, nickname, senderId, purpose)
    logActivity("Requesting auth code for '" .. username .. "'...")
    local reply, err = AuthClient.requestCode(AUTH_INTERNAL_API, {
        username = username, password = password,
        vendorID = "DrunkenOS_AuthNode", computerID = os.getComputerID(),
        extra = { purpose = purpose or "unknown" },
    })

    if not reply or not reply.request_id then
        local detail = reply and (reply.reason or reply.error or "Missing request_id") or tostring(err)
        logActivity("HyperAuth error: " .. detail, true)
        rednet.send(senderId, { success = false, reason = "Auth service error: " .. detail }, AUTH_SERVER_PROTOCOL)
        return false
    end
    
    logActivity("Auth request ID created: " .. reply.request_id)
    pendingAuths[username] = {
        request_id = reply.request_id, password = password, nickname = nickname,
        senderId = senderId, timestamp = os.epoch("utc")
    }
    return true
end

-- Broadcasts session validity to the Mainframe
local function broadcastSession(user, nickname, token)
    if wiredModem then
        rednet.broadcast({
            type = "session_authorized",
            user = user,
            nickname = nickname,
            session_token = token
            -- isAdmin will be checked natively by Mainframe via admins.db
        }, AUTH_INTERLINK_PROTOCOL)
    end
end

local function handleMessage(senderId, message, protocol)
    if not message or type(message) ~= "table" then return end
    
    -- Client Auth Operations
    if protocol == AUTH_SERVER_PROTOCOL then
        if message.type == "register" then
            if users[message.user] then
                rednet.send(senderId, { success = false, reason = "Username taken." }, AUTH_SERVER_PROTOCOL)
                return
            end
            if requestAuthCode(message.user, message.pass, message.nickname, senderId, "register") then
                rednet.send(senderId, { success = true, needs_auth = true }, AUTH_SERVER_PROTOCOL)
            end
            
        elseif message.type == "login" then
            local userData = users[message.user]
            local receivedHash = message.pass
            
            if not userData then
                rednet.send(senderId, { success = false, reason = "Invalid credentials." }, AUTH_SERVER_PROTOCOL)
                return
            end
            
            -- Session Token fast-path
            if message.session_token and userData.session_token == message.session_token then
                logActivity("'" .. message.user .. "' logged in via existing session.")
                broadcastSession(message.user, userData.nickname, userData.session_token)
                rednet.send(senderId, { 
                    success = true, needs_auth = false,
                    nickname = userData.nickname, session_token = userData.session_token
                }, AUTH_SERVER_PROTOCOL)
                return
            end
            
            local loginSuccess = (userData.password == receivedHash or userData.password == crypto.hex(receivedHash))
            
            if not loginSuccess then
                rednet.send(senderId, { success = false, reason = "Invalid credentials." }, AUTH_SERVER_PROTOCOL)
                return
            end
            
            if requestAuthCode(message.user, receivedHash, nil, senderId, "login") then
                rednet.send(senderId, { success = true, needs_auth = true }, AUTH_SERVER_PROTOCOL)
            end
            
        elseif message.type == "submit_auth_token" then
            local user = message.user
            local code = message.token
            local authData = pendingAuths[user]
            
            if not authData then
                rednet.send(senderId, { success = false, reason = "No pending auth." }, AUTH_SERVER_PROTOCOL)
                return
            end
            
            local reply, err = AuthClient.verifyCode(AUTH_INTERNAL_API, { request_id = authData.request_id, code = code })
            
            if reply and reply.ok then
                local token = crypto.hex(os.time() .. math.random())
                if not users[user] then
                    users[user] = { password = authData.password, nickname = authData.nickname, session_token = token }
                    DB.saveTableToFile(USERS_DB, users, logActivity)
                    logActivity("User '" .. user .. "' registered.")
                else
                    users[user].session_token = token
                    DB.saveTableToFile(USERS_DB, users, logActivity)
                    logActivity("User '" .. user .. "' logged in.")
                end
                
                broadcastSession(user, users[user].nickname, token)
                
                rednet.send(senderId, { 
                    success = true, nickname = users[user].nickname, session_token = token 
                }, AUTH_SERVER_PROTOCOL)
                
                pendingAuths[user] = nil
            else
                rednet.send(senderId, { success = false, reason = (reply and reply.reason) or "Invalid code." }, AUTH_SERVER_PROTOCOL)
            end
            
        elseif message.type == "set_nickname" then
            local user = message.user
            local token = message.session_token
            if not user or not users[user] or users[user].session_token ~= token then
                rednet.send(senderId, { success = false, reason = "Unauthorized." }, AUTH_SERVER_PROTOCOL)
                return
            end
            
            users[user].nickname = message.new_nickname
            DB.saveTableToFile(USERS_DB, users, logActivity)
            
            -- Re-broadcast session so Mainframe updates any local UI
            broadcastSession(user, users[user].nickname, token)
            
            rednet.send(senderId, { success = true, new_nickname = users[user].nickname }, AUTH_SERVER_PROTOCOL)
            logActivity("User '" .. user .. "' changed nickname to '" .. users[user].nickname .. "'")
        end
        
    -- Internal Interlink Operations (from Mainframe/MailServer)
    elseif protocol == AUTH_INTERLINK_PROTOCOL then
        if message.type == "user_exists" then
            local user = message.user
            local exists = (users[user] ~= nil)
            rednet.send(senderId, { type = "user_exists_response", user = user, exists = exists }, AUTH_INTERLINK_PROTOCOL)
        end
    end
end

local function garbageCollectPending()
    while true do
        sleep(60)
        local now = os.epoch("utc")
        for u, auth in pairs(pendingAuths) do
            if (now - (auth.timestamp or 0)) > 600000 then
                pendingAuths[u] = nil
                logActivity("Expired pending auth for '" .. u .. "'")
            end
        end
    end
end

local function startServer()
    logActivity("Auth Server starting up...")
    logActivity("Listening for external auth on: " .. AUTH_SERVER_PROTOCOL)
    logActivity("Listening for interlink on: " .. AUTH_INTERLINK_PROTOCOL)
    
    while true do
        local event, senderId, message, protocol = os.pullEvent("rednet_message")
        handleMessage(senderId, message, protocol)
    end
end

parallel.waitForAny(startServer, garbageCollectPending)
