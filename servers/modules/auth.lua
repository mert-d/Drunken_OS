--[[
    Drunken OS - Auth Module
    Extracted from Drunken_OS_Server.lua
]]

local AuthModule = {}

-- Requirements
local ok_crypto, crypto = pcall(require, "lib.sha1_hmac")
if not ok_crypto then error("AuthModule: lib.sha1_hmac not found.", 0) end

local ok_auth, AuthClient = pcall(require, "HyperAuthClient/api/auth_client")
if not ok_auth then error("AuthModule: HyperAuthClient API not found.", 0) end

local AUTH_SERVER_PROTOCOL = "auth.secure.v1_Internal"

---
-- Initiates a 2FA (Two-Factor Authentication) request via the HyperAuth service.
-- This is used for both secure registration and login verification.
-- @param username The username to authenticate.
-- @param password The password hash provided by the client.
-- @param nickname (Optional) The display name for new users.
-- @param senderId The rednet ID of the client requesting auth.
-- @param purpose A string indicating the intent ("login" or "register").
-- @param context A table containing server state references (logActivity, pendingAuths).
-- @return {boolean|nil} True if request was sent successfully, nil otherwise.
local function requestAuthCode(username, password, nickname, senderId, purpose, context)
    local logActivity = context.logActivity
    local pendingAuths = context.pendingAuths
    
    logActivity("Requesting auth code for '" .. username .. "'...")
    -- Contact the external HyperAuth server
    local reply, err = AuthClient.requestCode(AUTH_SERVER_PROTOCOL, {
        username = username,
        password = password,
        vendorID = "DrunkenOS_Mainframe",
        computerID = os.getComputerID(),
        extra = { purpose = purpose or "unknown" },
    })
    
    if reply then
        logActivity("HyperAuth raw reply: " .. textutils.serializeJSON(reply))
    end

    if not reply or not reply.request_id then
        local detail = reply and (reply.reason or reply.error or "Field 'request_id' missing") or tostring(err)
        logActivity("HyperAuth error: " .. detail, true)
        rednet.send(senderId, { success = false, reason = "Auth service error: " .. detail }, "SimpleMail")
        return nil
    end
    
    -- Store the request ID temporarily to verify the token later
    logActivity("Auth request ID created: " .. reply.request_id)
    pendingAuths[username] = {
        request_id = reply.request_id,
        password = password,
        nickname = nickname,
        senderId = senderId,
        timestamp = os.time()
    }
    return true
end

function AuthModule.handleRegister(senderId, message, context)
    local users = context.users
    local logActivity = context.logActivity
    
    if users[message.user] then
        rednet.send(senderId, { success = false, reason = "Username taken." }, "SimpleMail")
        return
    end

    if requestAuthCode(message.user, message.pass, message.nickname, senderId, "register", context) then
        rednet.send(senderId, { success = true, needs_auth = true }, "SimpleMail")
    end
end

function AuthModule.handleLogin(senderId, message, context)
    local users = context.users
    local admins = context.admins
    local logActivity = context.logActivity
    local queueSave = context.queueSave
    local USERS_DB = context.USERS_DB
    local getMailCount = context.getMailCount -- Helper passed from main or mail module

    local userData = users[message.user]
    local receivedHash = message.pass

    if not userData then
        rednet.send(senderId, { success = false, reason = "Invalid credentials." }, "SimpleMail")
        return
    end

    local storedHash = userData.password
    local loginSuccess = false
    local needsMigration = false

    if storedHash == receivedHash then
        loginSuccess = true
    elseif storedHash == crypto.hex(receivedHash) then
        loginSuccess = true
        needsMigration = true
        logActivity("Legacy password for '" .. message.user .. "' detected. Migrating.")
    end

    if not loginSuccess then
        rednet.send(senderId, { success = false, reason = "Invalid credentials." }, "SimpleMail")
        return
    end

    if needsMigration then
        users[message.user].password = receivedHash
        queueSave(USERS_DB)
    end
    
    if message.session_token and users[message.user].session_token == message.session_token then
        logActivity("'" .. message.user .. "' logged in via session.")
        rednet.send(senderId, { 
            success = true, 
            needs_auth = false, 
            nickname = users[message.user].nickname, 
            unreadCount = getMailCount(message.user), 
            isAdmin = admins[message.user] or false 
        }, "SimpleMail")
        return
    end
    
    if requestAuthCode(message.user, receivedHash, nil, senderId, "login", context) then
        rednet.send(senderId, { success = true, needs_auth = true }, "SimpleMail")
    end
end

function AuthModule.handleSubmitToken(senderId, message, context)
    local users = context.users
    local admins = context.admins
    local pendingAuths = context.pendingAuths
    local logActivity = context.logActivity
    local queueSave = context.queueSave
    local saveTableToFile = context.saveTableToFile
    local USERS_DB = context.USERS_DB
    local getMailCount = context.getMailCount

    local user, code = message.user, message.token
    logActivity("Received auth submission from '" .. user .. "'")
    
    local authData = pendingAuths[user]
    if not authData then
        rednet.send(senderId, { success = false, reason = "No pending auth." }, "SimpleMail")
        return
    end

    logActivity("Verifying code for RID: " .. authData.request_id)
    local reply, err = AuthClient.verifyCode(AUTH_SERVER_PROTOCOL, { request_id = authData.request_id, code = code })
    
    if not reply then
        logActivity("Auth verify error: " .. tostring(err), true)
        rednet.send(senderId, { success = false, reason = "Auth service error." }, "SimpleMail")
        return
    end

    if reply.ok then
        local payload = {}
        local token = crypto.hex(os.time() .. math.random())
        if not users[user] then -- This is a registration
            users[user] = { password = authData.password, nickname = authData.nickname, session_token = token }
            if saveTableToFile(USERS_DB, users) then
                payload = { 
                    success = true, 
                    unreadCount = 0, 
                    nickname = authData.nickname, 
                    session_token = token, 
                    isAdmin = admins[user] or false 
                }
                logActivity("User '" .. user .. "' registered.")
            else
                payload = { success = false, reason = "DB error." }
            end
        else -- This is a login
            users[user].session_token = token
            queueSave(USERS_DB)
            payload = { 
                success = true, 
                unreadCount = getMailCount(user), 
                nickname = users[user].nickname, 
                session_token = token, 
                isAdmin = admins[user] or false 
            }
            logActivity("User '" .. user .. "' logged in.")
        end
        rednet.send(senderId, payload, "SimpleMail")
        pendingAuths[user] = nil
    else
        rednet.send(senderId, { success = false, reason = reply.reason or "Invalid code." }, "SimpleMail")
        logActivity("Auth fail for " .. user .. ': ' .. (reply.reason or "Unknown"), true)
    end
end

function AuthModule.handleUserExists(senderId, message, context)
   local users = context.users
   local lists = context.lists
   local recipient = message.user
   local exists = false
   if recipient and recipient ~= "" then
       if recipient == "@all" then
           exists = true
       elseif recipient:sub(1, 1) == "@" then
           exists = lists[recipient:sub(2)] ~= nil
       else
           exists = users[recipient] ~= nil
       end
   end
   rednet.send(senderId, { exists = exists }, "SimpleMail")
end

return AuthModule
