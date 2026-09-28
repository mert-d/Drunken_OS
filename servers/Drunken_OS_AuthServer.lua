--[[
    Drunken OS - Authentication Server (Microservices Architecture)
    Handles login, registration, and session token generation via HyperAuth.
]]

local runningProg = shell and shell.getRunningProgram and shell.getRunningProgram() or ""
local runningDir = fs.getDir(runningProg)

package.path = "/?.lua;?.lua;/lib/?.lua;lib/?.lua;/HyperAuthClient/?.lua;HyperAuthClient/?.lua;/servers/?.lua;servers/?.lua;"
    .. "/disk/?.lua;disk/?.lua;/disk/HyperAuthClient/?.lua;disk/HyperAuthClient/?.lua;"
    .. (runningDir ~= "" and (fs.combine(runningDir, "?.lua") .. ";" .. fs.combine(runningDir, "HyperAuthClient/?.lua") .. ";") or "")
    .. package.path

local crypto = nil
local crypto_candidates = {
    "/lib/sha1_hmac.lua",
    "lib/sha1_hmac.lua",
    "/sha1_hmac.lua",
    "sha1_hmac.lua"
}
for _, p in ipairs(crypto_candidates) do
    if fs.exists(p) then
        local fn, err = loadfile(p)
        if not fn then
            error("Auth Server: Compile error in '" .. p .. "':\n" .. tostring(err), 0)
        end
        local ok, mod = pcall(fn)
        if not ok then
            error("Auth Server: Runtime error in '" .. p .. "':\n" .. tostring(mod), 0)
        end
        crypto = mod
        break
    end
end
if not crypto then
    local ok_crypto, res = pcall(require, "lib.sha1_hmac")
    if not ok_crypto then ok_crypto, res = pcall(require, "lib/sha1_hmac") end
    if not ok_crypto then ok_crypto, res = pcall(require, "sha1_hmac") end
    if ok_crypto then
        crypto = res
    else
        error("Auth Server: lib.sha1_hmac not found: " .. tostring(res), 0)
    end
end

local AuthClient = nil
local client_candidates = {
    "/HyperAuthClient/api/auth_client.lua",
    "HyperAuthClient/api/auth_client.lua",
    "/api/auth_client.lua",
    "api/auth_client.lua",
    "/auth_client.lua",
    "auth_client.lua"
}
for _, p in ipairs(client_candidates) do
    if fs.exists(p) then
        local fn, err = loadfile(p)
        if not fn then
            error("Auth Server: Compile error in '" .. p .. "':\n" .. tostring(err), 0)
        end
        local ok, mod = pcall(fn)
        if not ok then
            error("Auth Server: Runtime error in '" .. p .. "':\n" .. tostring(mod), 0)
        end
        AuthClient = mod
        break
    end
end
if not AuthClient then
    local ok_auth, res = pcall(require, "HyperAuthClient.api.auth_client")
    if not ok_auth then ok_auth, res = pcall(require, "HyperAuthClient/api/auth_client") end
    if not ok_auth then ok_auth, res = pcall(require, "api.auth_client") end
    if not ok_auth then ok_auth, res = pcall(require, "auth_client") end
    if ok_auth then
        AuthClient = res
    else
        error("Auth Server: HyperAuthClient API not found: " .. tostring(res), 0)
    end
end

local DB = require("lib.db")
local ServiceGuard = require("lib.service_guard")

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

-- Protocol hosting helper
local function registerProtocols()
    rednet.host(AUTH_SERVER_PROTOCOL, "auth.server")
end

-- Initialize modems
local modems = ServiceGuard.initModems()
wirelessModem = modems.wireless
wiredModem = modems.wired

if modems.count == 0 then
    error("Auth Server requires at least one modem to function.")
end

-- Load Database
users = DB.loadTableFromFile(USERS_DB, logActivity)

-- Host the auth service
registerProtocols()

local PAIRING_PROTOCOL = "hyperauth.pair.v1"
local args = { ... }
local forcePair = (args[1] == "pair" or args[1] == "--pair")

--- Reads the live HyperAuth client configuration dynamically
local function getHyperAuthConfig()
    package.loaded["HyperAuthClient.config"] = nil
    package.loaded["HyperAuthClient/config"] = nil
    local ok, cfg = pcall(require, "HyperAuthClient/config")
    if not ok then ok, cfg = pcall(require, "HyperAuthClient.config") end
    if ok and type(cfg) == "table" then
        return cfg
    end
    return {
        PROTOCOL_NAME = AUTH_INTERNAL_API,
        CLIENT_ID = "drunken_os_server",
        SHARED_SECRET = "01431f1589d73d826c2a9669ab60fa8b",
        PAIRED = true
    }
end

--- Checks if this Auth Server has completed pairing with HyperAuth
local function isPaired()
    local cfg = getHyperAuthConfig()
    if cfg and cfg.PAIRED == true and cfg.SHARED_SECRET and #cfg.SHARED_SECRET > 0 and cfg.CLIENT_ID ~= "unpaired" then
        return true
    end
    return false
end

--- Performs the interactive auto-pairing handshake with HyperAuth Server
local function performAutoPairing()
    local isColor = term.isColor and term.isColor()
    term.clear()
    term.setCursorPos(1, 1)

    if isColor then term.setTextColor(colors.cyan) end
    print("========================================================")
    print("      DRUNKEN OS AUTH SERVER - HYPERAUTH PAIRING        ")
    print("========================================================")

    math.randomseed(os.epoch("utc") + os.getComputerID())
    local pin = string.format("%04d", math.random(1000, 9999))
    local nonce = crypto.hex(os.epoch("utc") .. tostring(math.random()))
    local myId = os.getComputerID()

    if isColor then term.setTextColor(colors.white) end
    print(string.format("  Computer ID : #%d", myId))
    print(string.format("  Device Name : Drunken OS Auth Server #%d", myId))
    print(string.format("  Protocol    : %s", PAIRING_PROTOCOL))
    print("")
    if isColor then term.setTextColor(colors.yellow) end
    print("  +----------------------------------------------------+")
    print(string.format("  |        ONE-TIME VERIFICATION PIN: [ %s ]         |", pin))
    print("  +----------------------------------------------------+")
    if isColor then term.setTextColor(colors.lightGray or colors.white) end
    print("\n  Broadcasting pairing request to HyperAuth Server...")
    print("  Please approve this request on the HyperAuth console.")
    print("  (Type 'pair accept " .. myId .. "' or 'y' on the Command Computer)")
    print("\n  [Press 'S' to skip pairing and use local defaults]\n")

    -- Ensure modems are open
    if ServiceGuard and ServiceGuard.initModems then
        pcall(ServiceGuard.initModems)
    end

    local timerId = os.startTimer(0.1)
    local broadcastInterval = 2.5
    local lastBroadcast = 0
    local pairingComplete = false

    while not pairingComplete do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == timerId then
            local now = os.epoch("utc") / 1000
            if (now - lastBroadcast) >= broadcastInterval then
                lastBroadcast = now
                local pairPacket = {
                    type = "pair_request",
                    computer_id = myId,
                    label = "Drunken OS Auth #" .. myId,
                    pin = pin,
                    nonce = nonce,
                    timestamp = os.epoch("utc")
                }
                rednet.broadcast(pairPacket, PAIRING_PROTOCOL)
                io.write(".")
            end
            timerId = os.startTimer(0.5)

        elseif event == "rednet_message" then
            local senderId, message, protocol = p1, p2, p3
            if protocol == PAIRING_PROTOCOL and type(message) == "table" then
                if message.type == "pair_accept" and message.nonce == nonce then
                    pairingComplete = true
                    if isColor then term.setTextColor(colors.green) end
                    print("\n\n  ========================================================")
                    print(string.format("  [SUCCESS] PAIRED WITH HYPERAUTH SERVER #%d!", message.server_id or senderId))
                    print("  ========================================================")
                    if isColor then term.setTextColor(colors.white) end
                    print(string.format("  Assigned Vendor ID : %s", message.vendorId))
                    print(string.format("  Cryptographic Key  : %s...", tostring(message.sharedSecret):sub(1, 8)))

                    -- Persist configuration to HyperAuthClient/config.lua
                    local configPath = "HyperAuthClient/config.lua"
                    local configData = string.format([[return {
  PROTOCOL_NAME = %q,

  CLIENT_ID     = %q,
  SHARED_SECRET = %q,

  KNOWN_SERVER_ID         = %s,
  DEFAULT_TIMEOUT_SECONDS = 6,
  PAIRED                  = true,
}
]], message.protocol or "auth.secure.v1", message.vendorId, message.sharedSecret, tostring(message.server_id or senderId))

                    local f = fs.open(configPath, "w")
                    if f then
                        f.write(configData)
                        f.close()
                        logActivity("Pairing configuration saved to " .. configPath)
                    else
                        logActivity("Failed to save " .. configPath, true)
                    end

                    package.loaded["HyperAuthClient.config"] = nil
                    package.loaded["HyperAuthClient/config"] = nil

                    sleep(2)
                    term.clear()
                    term.setCursorPos(1, 1)
                    return true

                elseif message.type == "pair_reject" and message.nonce == nonce then
                    if isColor then term.setTextColor(colors.red) end
                    print(string.format("\n\n  [REJECTED] Pairing was declined by HyperAuth Server: %s", message.reason or "Unknown"))
                    if isColor then term.setTextColor(colors.white) end
                    print("  Press any key to retry or 'S' to skip...")
                    local _, key = os.pullEvent("key")
                    if key == keys.s then return false end
                    return performAutoPairing()
                end
            end

        elseif event == "key" then
            local key = p1
            if key == keys.s then
                if isColor then term.setTextColor(colors.yellow) end
                print("\n\n  Pairing skipped by user. Continuing with local config...")
                sleep(1)
                term.clear()
                term.setCursorPos(1, 1)
                return false
            end
        end
    end
    return false
end

--- Initiates a 2FA request via HyperAuth
local function requestAuthCode(username, password, nickname, senderId, purpose)
    logActivity("Requesting auth code for '" .. username .. "'...")
    local cfg = getHyperAuthConfig()
    local apiProto = cfg.PROTOCOL_NAME or AUTH_INTERNAL_API or "auth.secure.v1"
    local vendorId = cfg.CLIENT_ID or "drunken_os_server"

    local reply, err = AuthClient.requestCode(apiProto, {
        username = username, password = password,
        vendorID = vendorId, computerID = os.getComputerID(),
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
            
            local cfg = getHyperAuthConfig()
            local apiProto = cfg.PROTOCOL_NAME or AUTH_INTERNAL_API or "auth.secure.v1"
            local reply, err = AuthClient.verifyCode(apiProto, { request_id = authData.request_id, code = code })
            
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

local function flushAuthState()
    if users then
        pcall(DB.saveTableToFile, USERS_DB, users, logActivity)
    end
end

local function startServer()
    local haCfg = getHyperAuthConfig()
    logActivity("Auth Server starting up...")
    logActivity("Listening for external auth on: " .. AUTH_SERVER_PROTOCOL)
    logActivity("Listening for interlink on: " .. AUTH_INTERLINK_PROTOCOL)
    logActivity("HyperAuth 2FA Link: Protocol='" .. (haCfg.PROTOCOL_NAME or "auth.secure.v1") .. "', Vendor='" .. (haCfg.CLIENT_ID or "drunken_os_server") .. "'")
    
    while true do
        local event, p1, p2, p3 = os.pullEventRaw()
        if event == "rednet_message" then
            local senderId, message, protocol = p1, p2, p3
            ServiceGuard.protectHandler("Auth:message", handleMessage, logActivity, senderId, message, protocol)
        elseif event == "peripheral" or event == "peripheral_detach" then
            ServiceGuard.handlePeripheralEvent(event, p1, registerProtocols, logActivity)
        elseif event == "terminate" then
            error("Terminated", 0)
        end
    end
end

local function runAuthServer()
    if forcePair or not isPaired() then
        performAutoPairing()
    end
    parallel.waitForAny(startServer, garbageCollectPending)
end

ServiceGuard.runSupervisor("Auth Server", runAuthServer, flushAuthState, logActivity)
