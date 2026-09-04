--[[
    Drunken OS - Auth Module
    _VERSION = 1.0
    Purpose: Modular authentication handler for Drunken_OS_Server.
    Routes authentication requests (register, login, submit_auth_token, user_exists)
    to the dedicated AuthServer via 'auth.secure.v1' / 'Drunken_Auth_Interlink',
    with local credential fallback when the auth microservice is offline.
]]

local AuthModule = {}
AuthModule._VERSION = 1.0

local AUTH_PROTOCOL = "auth.secure.v1"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"

---
-- Helper to forward a request to the AuthServer and wait for response.
-- @param message table: The request payload.
-- @param timeout number: Timeout in seconds (default 4).
-- @return table|nil: The response from AuthServer, or nil on timeout.
local function queryAuthServer(message, timeout)
    timeout = timeout or 4
    local authServerId = rednet.lookup(AUTH_PROTOCOL, "auth.server")
    if not authServerId then return nil end

    rednet.send(authServerId, message, AUTH_PROTOCOL)
    local senderId, response = rednet.receive(AUTH_PROTOCOL, timeout)
    if senderId == authServerId and type(response) == "table" then
        return response
    end
    return nil
end

---
-- Handles user registration requests.
-- @param senderId number: Rednet ID of the client.
-- @param message table: Contains user, pass, nickname.
-- @param context table: Server context references.
function AuthModule.handleRegister(senderId, message, context)
    local log = context.logActivity or print

    -- Try dedicated AuthServer first
    local resp = queryAuthServer({
        type = "register",
        user = message.user,
        pass = message.pass or message.password,
        nickname = message.nickname
    })

    if resp then
        rednet.send(senderId, resp, "SimpleMail")
        return
    end

    -- Fallback: Local registration if AuthServer is offline
    local users = context.users
    if users then
        if users[message.user] then
            rednet.send(senderId, { success = false, reason = "Username taken." }, "SimpleMail")
            return
        end

        local pass = message.pass or message.password or ""
        users[message.user] = {
            password = pass,
            nickname = message.nickname or message.user,
            registered_at = os.epoch and os.epoch("utc") or os.time()
        }

        if context.queueSave and context.USERS_DB then
            context.queueSave(context.USERS_DB)
        elseif context.saveTableToFile and context.USERS_DB then
            context.saveTableToFile(context.USERS_DB, users)
        end

        log("User registered locally: " .. tostring(message.user))
        rednet.send(senderId, { success = true, needs_auth = false, message = "Registration successful." }, "SimpleMail")
    else
        rednet.send(senderId, { success = false, reason = "Authentication service unavailable." }, "SimpleMail")
    end
end

---
-- Handles user login requests.
-- @param senderId number: Rednet ID of the client.
-- @param message table: Contains user, pass, session_token.
-- @param context table: Server context references.
function AuthModule.handleLogin(senderId, message, context)
    local log = context.logActivity or print

    -- Try dedicated AuthServer first
    local resp = queryAuthServer({
        type = "login",
        user = message.user,
        pass = message.pass or message.password,
        session_token = message.session_token
    })

    if resp then
        if resp.success and resp.session_token and context.active_sessions then
            context.active_sessions[message.user] = {
                token = resp.session_token,
                nickname = resp.nickname or message.user
            }
        end
        rednet.send(senderId, resp, "SimpleMail")
        return
    end

    -- Fallback: Local login
    local users = context.users
    if users and users[message.user] then
        local u = users[message.user]
        local pass = message.pass or message.password or ""

        if u.password == pass then
            local token = tostring(math.random(100000, 999999)) .. tostring(os.epoch and os.epoch("utc") or os.time())
            if context.active_sessions then
                context.active_sessions[message.user] = {
                    token = token,
                    nickname = u.nickname or message.user
                }
            end
            log("User logged in locally: " .. tostring(message.user))
            rednet.send(senderId, {
                success = true,
                needs_auth = false,
                nickname = u.nickname or message.user,
                session_token = token
            }, "SimpleMail")
            return
        end
    end

    rednet.send(senderId, { success = false, reason = "Invalid credentials or Auth service offline." }, "SimpleMail")
end

---
-- Handles 2FA / auth token submission.
-- @param senderId number: Rednet ID of the client.
-- @param message table: Contains user, token.
-- @param context table: Server context references.
function AuthModule.handleSubmitToken(senderId, message, context)
    local resp = queryAuthServer({
        type = "submit_auth_token",
        user = message.user,
        token = message.token or message.code
    })

    if resp then
        if resp.success and resp.session_token and context.active_sessions then
            context.active_sessions[message.user] = {
                token = resp.session_token,
                nickname = resp.nickname or message.user
            }
        end
        rednet.send(senderId, resp, "SimpleMail")
        return
    end

    rednet.send(senderId, { success = false, reason = "Auth service unavailable for 2FA validation." }, "SimpleMail")
end

---
-- Handles checking whether a user exists.
-- @param senderId number: Rednet ID of the client.
-- @param message table: Contains user.
-- @param context table: Server context references.
function AuthModule.handleUserExists(senderId, message, context)
    local authServerId = rednet.lookup(AUTH_PROTOCOL, "auth.server")
    if authServerId then
        rednet.send(authServerId, { type = "user_exists", user = message.user }, AUTH_INTERLINK_PROTOCOL)
        local _, response = rednet.receive(AUTH_INTERLINK_PROTOCOL, 3)
        if response and response.type == "user_exists_response" then
            rednet.send(senderId, { success = true, exists = response.exists }, "SimpleMail")
            return
        end
    end

    -- Local check fallback
    if context.users and context.users[message.user] then
        rednet.send(senderId, { success = true, exists = true }, "SimpleMail")
    else
        rednet.send(senderId, { success = true, exists = false }, "SimpleMail")
    end
end

return AuthModule
