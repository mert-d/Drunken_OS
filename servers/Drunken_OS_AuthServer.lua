--[[
    Drunken OS - Authentication Server (Microservices Architecture)
    Handles login, registration, and session token generation via HyperAuth.
]]

local runningProg = shell and shell.getRunningProgram and shell.getRunningProgram() or ""
local runningDir = fs.getDir(runningProg)

if package then
    package.path = "/?.lua;?.lua;/lib/?.lua;lib/?.lua;/HyperAuthClient/?.lua;HyperAuthClient/?.lua;/servers/?.lua;servers/?.lua;"
        .. "/disk/?.lua;disk/?.lua;/disk/HyperAuthClient/?.lua;disk/HyperAuthClient/?.lua;"
        .. (runningDir ~= "" and (fs.combine(runningDir, "?.lua") .. ";" .. fs.combine(runningDir, "HyperAuthClient/?.lua") .. ";") or "")
        .. (package.path or "")
end

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
        if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
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
        if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
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

local APChatBox = nil
local chatbox_candidates = {
    "/lib/ap_chatbox.lua",
    "lib/ap_chatbox.lua",
    "/ap_chatbox.lua",
    "ap_chatbox.lua",
    "/disk/lib/ap_chatbox.lua",
    "disk/lib/ap_chatbox.lua"
}
for _, p in ipairs(chatbox_candidates) do
    if fs and fs.exists and fs.exists(p) then
        local fn, err = loadfile(p)
        if fn then
            if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
            local ok, mod = pcall(fn)
            if ok and type(mod) == "table" then
                APChatBox = mod
                break
            end
        end
    end
end
if not APChatBox then
    local ok_ap, mod = pcall(require, "lib.ap_chatbox")
    if not ok_ap then ok_ap, mod = pcall(require, "lib/ap_chatbox") end
    if not ok_ap then ok_ap, mod = pcall(require, "ap_chatbox") end
    if ok_ap and type(mod) == "table" then
        APChatBox = mod
    end
end

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

local serverDashboard = nil
local logHistory = {}

local function logActivity(msg, isError)
    local pfx = isError and "[ERROR] " or "[INFO] "
    local logEntry = os.date("[%H:%M:%S] ") .. pfx .. tostring(msg or "")
    table.insert(logHistory, logEntry)
    if #logHistory > 100 then table.remove(logHistory, 1) end
    if serverDashboard then
        serverDashboard:log(logEntry, isError)
    else
        print(logEntry)
    end
end

-- Protocol hosting helper
local function registerProtocols()
    if rednet and rednet.unhost then
        pcall(rednet.unhost, AUTH_SERVER_PROTOCOL, "auth.server")
    end
    if rednet and rednet.host then
        local ok, err = pcall(rednet.host, AUTH_SERVER_PROTOCOL, "auth.server")
        if not ok then
            local existingId = rednet.lookup and rednet.lookup(AUTH_SERVER_PROTOCOL, "auth.server")
            if existingId and existingId == os.getComputerID() then
                return
            end
            if existingId then
                logActivity(string.format("Conflict: Computer #%s is already hosting '%s' on '%s'!", 
                    tostring(existingId), "auth.server", AUTH_SERVER_PROTOCOL), true)
                print(string.format("\n[ERROR] Hostname Conflict! Computer #%s is already running as the Auth Server on this network.", tostring(existingId)))
                print("Please shut down Computer #" .. tostring(existingId) .. " if you wish to run on this machine.\n")
                error("Hostname in use by Computer #" .. tostring(existingId), 0)
            else
                logActivity("Warning: Failed to host '" .. AUTH_SERVER_PROTOCOL .. "': " .. tostring(err), true)
            end
        end
    end
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
    local candidates = {
        "/HyperAuthClient/config.lua",
        "HyperAuthClient/config.lua",
        "/config.lua",
        "config.lua"
    }
    for _, p in ipairs(candidates) do
        if fs and fs.exists and fs.exists(p) then
            local fn, err = loadfile(p)
            if fn then
                if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
                local ok, cfg = pcall(fn)
                if ok and type(cfg) == "table" then
                    return cfg
                end
            end
        end
    end

    if package and package.loaded then
        package.loaded["HyperAuthClient.config"] = nil
        package.loaded["HyperAuthClient/config"] = nil
    end
    if require then
        local ok, cfg = pcall(require, "HyperAuthClient/config")
        if not ok then ok, cfg = pcall(require, "HyperAuthClient.config") end
        if ok and type(cfg) == "table" then
            return cfg
        end
    end
    return {
        PROTOCOL_NAME = AUTH_INTERNAL_API,
        CLIENT_ID = "drunken_os_server",
        SHARED_SECRET = "01431f1589d73d826c2a9669ab60fa8b",
        PAIRED = true
    }
end

--- Checks if this Auth Server has completed pairing with HyperAuth
--- Checks if this Auth Server has completed pairing with HyperAuth
local function isPaired()
    local cfg = getHyperAuthConfig()
    if cfg and cfg.PAIRED == true and cfg.SHARED_SECRET and #cfg.SHARED_SECRET > 0 and cfg.CLIENT_ID ~= "unpaired" then
        return true
    end
    return false
end

--- Checks if this Auth Server has explicitly configured Standalone Mode
local function isStandalone()
    local cfg = getHyperAuthConfig()
    if cfg and (cfg.STANDALONE == true or (cfg.PAIRED == false and cfg.CLIENT_ID == "standalone_server")) then
        return true
    end
    return false
end

--- Checks if this server has a valid pairing or standalone configuration
local function isConfigured()
    return isPaired() or isStandalone()
end

--- Persists standalone configuration so reboot or chunk reload does not trap the server in pairing mode
local function saveStandaloneConfig()
    local configPath = "HyperAuthClient/config.lua"
    local configData = [[return {
  PROTOCOL_NAME = "auth.secure.v1",

  CLIENT_ID     = "standalone_server",
  SHARED_SECRET = "standalone_local_secret",

  KNOWN_SERVER_ID         = nil,
  DEFAULT_TIMEOUT_SECONDS = 6,
  PAIRED                  = false,
  STANDALONE              = true,
}
]]
    if not fs.exists("HyperAuthClient") then
        pcall(fs.makeDir, "HyperAuthClient")
    end
    local f = fs.open(configPath, "w")
    if f then
        f.write(configData)
        f.close()
        logActivity("Standalone configuration saved to " .. configPath)
    else
        logActivity("Failed to write standalone configuration to " .. configPath, true)
    end
    if package and package.loaded then
        package.loaded["HyperAuthClient.config"] = nil
        package.loaded["HyperAuthClient/config"] = nil
    end
end

--- Performs the interactive auto-pairing handshake with HyperAuth Server.
-- Strictly fits within 51x19 terminal dimensions with zero scrolling.
local function performAutoPairing()
    local w, h = term.getSize()
    local isColor = term.isColor and term.isColor()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- 1. Top Title Bar (Row 1)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(isColor and colors.blue or colors.black)
    term.clearLine()
    term.setTextColor(colors.white)
    local titleLeft = " [*] HYPERAUTH 2FA PAIRING"
    term.write(titleLeft)
    local myId = os.getComputerID()
    local titleRight = "#" .. myId .. " "
    if w > #titleLeft + #titleRight then
        term.setCursorPos(w - #titleRight + 1, 1)
        term.write(titleRight)
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)

    math.randomseed(os.epoch("utc") + myId)
    local pin = string.format("%04d", math.random(1000, 9999))
    local nonce = crypto.hex(os.epoch("utc") .. tostring(math.random()))

    -- Metadata Details (Rows 3..5)
    term.setCursorPos(3, 3)
    term.setTextColor(isColor and colors.cyan or colors.white)
    term.write(string.format("%-14s: ", "Host ID"))
    term.setTextColor(colors.white)
    term.write("#" .. myId)

    term.setCursorPos(3, 4)
    term.setTextColor(isColor and colors.cyan or colors.white)
    term.write(string.format("%-14s: ", "Service"))
    term.setTextColor(colors.white)
    term.write("Drunken OS Auth Server")

    term.setCursorPos(3, 5)
    term.setTextColor(isColor and colors.cyan or colors.white)
    term.write(string.format("%-14s: ", "Pair Proto"))
    term.setTextColor(isColor and colors.lightGray or colors.white)
    term.write(PAIRING_PROTOCOL)

    -- Verification PIN Box (Rows 7..9)
    term.setCursorPos(4, 7)
    term.setTextColor(isColor and colors.yellow or colors.white)
    term.write("+-------------------------------------------+")
    term.setCursorPos(4, 8)
    term.write(string.format("|     ONE-TIME VERIFICATION PIN: [ %s ]     |", pin))
    term.setCursorPos(4, 9)
    term.write("+-------------------------------------------+")

    -- Instructions (Rows 11..14)
    term.setCursorPos(3, 11)
    term.setTextColor(isColor and colors.white or colors.white)
    term.write("Broadcasting pairing request to HyperAuth...")

    term.setCursorPos(3, 12)
    term.setTextColor(isColor and colors.lightGray or colors.white)
    term.write("Approve on Command PC: 'pair accept " .. myId .. "' or 'y'")

    local hasChatBox = APChatBox and APChatBox.isAvailable and APChatBox.isAvailable()
    term.setCursorPos(3, 14)
    if hasChatBox then
        term.setTextColor(isColor and colors.lime or colors.white)
        term.write("[+] AP Chat Box detected (Standalone 2FA ready)")
    else
        term.setTextColor(isColor and colors.lightGray or colors.white)
        term.write("[!] AP Chat Box not detected (using fallback)")
    end

    -- Controls (Row 15)
    term.setCursorPos(3, 15)
    term.setTextColor(isColor and colors.yellow or colors.white)
    term.write("Controls: [S] Skip & Use Standalone | [Q] Abort")

    -- Footer (Row h)
    term.setCursorPos(1, h)
    term.setBackgroundColor(isColor and colors.gray or colors.black)
    term.clearLine()
    term.setTextColor(colors.white)
    term.setCursorPos(2, h)
    term.write("[PAIRING] Waiting for authorization... | Press S to skip")
    term.setBackgroundColor(colors.black)

    -- Ensure modems are open
    if ServiceGuard and ServiceGuard.initModems then
        pcall(ServiceGuard.initModems)
    end

    local timerId = os.startTimer(0.1)
    local broadcastInterval = 2.5
    local lastBroadcast = 0
    local attemptCount = 0
    local spinnerChars = { "/", "-", "\\", "|" }
    local spinnerIdx = 1
    local autoTimeoutRemaining = 15 -- seconds for auto-boot when AP Chat Box is present
    local pairingComplete = false

    while not pairingComplete do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == timerId then
            local now = os.epoch("utc") / 1000

            -- Send pairing request every broadcastInterval
            if (now - lastBroadcast) >= broadcastInterval then
                lastBroadcast = now
                attemptCount = attemptCount + 1
                if not (rednet and rednet.isOpen and rednet.isOpen()) then
                    if ServiceGuard and ServiceGuard.initModems then
                        pcall(ServiceGuard.initModems)
                    end
                end
                local pairPacket = {
                    type = "pair_request",
                    computer_id = myId,
                    label = "Drunken OS Auth #" .. myId,
                    pin = pin,
                    nonce = nonce,
                    timestamp = os.epoch("utc")
                }
                rednet.broadcast(pairPacket, PAIRING_PROTOCOL)
                rednet.broadcast(textutils.serialize(pairPacket), PAIRING_PROTOCOL)
            end

            -- Update countdown if AP Chat Box is active
            if hasChatBox then
                autoTimeoutRemaining = autoTimeoutRemaining - 0.25
                if autoTimeoutRemaining <= 0 then
                    saveStandaloneConfig()
                    term.setCursorPos(3, 17)
                    term.clearLine()
                    term.setTextColor(isColor and colors.lime or colors.white)
                    term.write("[AUTO-BOOT] Standalone AP 2FA activated.")
                    sleep(1)
                    term.clear()
                    return false
                end
            end

            -- In-place animated status line at Row 17 (NO SCROLLING!)
            spinnerIdx = (spinnerIdx % #spinnerChars) + 1
            local spinChar = spinnerChars[spinnerIdx]
            term.setCursorPos(3, 17)
            term.clearLine()
            term.setTextColor(isColor and colors.cyan or colors.white)
            if hasChatBox then
                term.write(string.format("[%s] Waiting for HyperAuth... (Attempt #%d | Auto-boot: %02ds)",
                    spinChar, attemptCount, math.ceil(math.max(0, autoTimeoutRemaining))))
            else
                term.write(string.format("[%s] Waiting for HyperAuth... (Attempt #%d)",
                    spinChar, attemptCount))
            end

            timerId = os.startTimer(0.25)

        elseif event == "peripheral" or event == "peripheral_detach" then
            if ServiceGuard and ServiceGuard.initModems then
                pcall(ServiceGuard.initModems)
            end
            if APChatBox then
                hasChatBox = APChatBox.isAvailable and APChatBox.isAvailable()
            end

        elseif event == "rednet_message" then
            local senderId, rawMessage, protocol = p1, p2, p3
            local message = rawMessage
            if type(rawMessage) == "string" then
                local ok, res = pcall(textutils.unserialize, rawMessage)
                if ok and type(res) == "table" then
                    message = res
                else
                    local ok_j, res_j = pcall(textutils.unserializeJSON, rawMessage)
                    if ok_j and type(res_j) == "table" then
                        message = res_j
                    end
                end
            end
            if protocol == PAIRING_PROTOCOL and type(message) == "table" then
                if message.type == "pair_accept" and message.nonce == nonce then
                    pairingComplete = true
                    term.setCursorPos(3, 17)
                    term.clearLine()
                    term.setTextColor(isColor and colors.lime or colors.white)
                    term.write(string.format("[SUCCESS] PAIRED WITH HYPERAUTH #%d!", message.server_id or senderId))

                    -- Persist configuration to HyperAuthClient/config.lua
                    local configPath = "HyperAuthClient/config.lua"
                    if not fs.exists("HyperAuthClient") then pcall(fs.makeDir, "HyperAuthClient") end
                    local configData = string.format([[return {
  PROTOCOL_NAME = %q,

  CLIENT_ID     = %q,
  SHARED_SECRET = %q,

  KNOWN_SERVER_ID         = %s,
  DEFAULT_TIMEOUT_SECONDS = 6,
  PAIRED                  = true,
  STANDALONE              = false,
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

                    if package and package.loaded then
                        package.loaded["HyperAuthClient.config"] = nil
                        package.loaded["HyperAuthClient/config"] = nil
                    end

                    sleep(1.5)
                    term.clear()
                    return true

                elseif message.type == "pair_reject" and message.nonce == nonce then
                    term.setCursorPos(3, 17)
                    term.clearLine()
                    term.setTextColor(isColor and colors.red or colors.white)
                    term.write(string.format("[REJECTED] %s. [R] Retry | [S] Skip", tostring(message.reason or "Declined")))
                    local _, key = os.pullEvent("key")
                    if key == keys.s then
                        saveStandaloneConfig()
                        term.clear()
                        return false
                    elseif key == keys.r then
                        return performAutoPairing()
                    end
                end
            end

        elseif event == "key" then
            local key = p1
            if key == keys.s then
                saveStandaloneConfig()
                term.setCursorPos(3, 17)
                term.clearLine()
                term.setTextColor(isColor and colors.yellow or colors.white)
                term.write("[+] Standalone mode saved. Continuing...")
                sleep(1)
                term.clear()
                return false
            elseif key == keys.q then
                term.clear()
                return false
            end
        end
    end
    return false
end

--- Initiates a 2FA request via HyperAuth (Command PC) or fallback AP Chat Box
local function requestAuthCode(username, password, nickname, senderId, purpose)
    logActivity("Requesting auth code for '" .. username .. "' (purpose: " .. (purpose or "unknown") .. ")...")
    
    local chatBoxAvailable = (APChatBox and APChatBox.isAvailable and APChatBox.isAvailable())
    local hyperAuthPaired = isPaired()
    local lastError = nil

    -- 1. Try HyperAuth Server via Command Computer if configured and paired
    if hyperAuthPaired then
        local cfg = getHyperAuthConfig()
        local apiProto = cfg.PROTOCOL_NAME or AUTH_INTERNAL_API or "auth.secure.v1"
        local vendorId = cfg.CLIENT_ID or "drunken_os_server"

        local reply, err = AuthClient.requestCode(apiProto, {
            username = username, password = password,
            vendorID = vendorId, computerID = os.getComputerID(),
            extra = { purpose = purpose or "unknown" },
        })

        if reply and reply.request_id then
            logActivity("HyperAuth request ID created: " .. reply.request_id)
            pendingAuths[username] = {
                request_id = reply.request_id,
                provider = "hyperauth",
                password = password,
                nickname = nickname,
                senderId = senderId,
                timestamp = os.epoch("utc")
            }
            return true
        else
            lastError = reply and (reply.reason or reply.error or "Missing request_id") or tostring(err)
            logActivity("HyperAuth unavailable (" .. tostring(lastError) .. "). Evaluating Chat Box fallback...", true)
        end
    else
        lastError = "HyperAuth is unpaired"
    end

    -- 2. Fallback / Standalone: Dispatch via Advanced Peripherals Chat Box
    if chatBoxAvailable then
        logActivity("Activating AP Chat Box 2FA dispatch for '" .. username .. "'...")
        math.randomseed(os.epoch("utc") + os.getComputerID() + math.random(1000, 9999))
        local code = string.format("%06d", math.random(100000, 999999))
        local reqId = "ap_" .. crypto.hex(os.epoch("utc") .. username .. tostring(math.random()))

        local sendOk, sendErr = APChatBox.sendAuthCode(username, code, 5)
        if sendOk then
            logActivity("AP Chat Box delivered 2FA code to '" .. username .. "' (Req: " .. reqId .. ")")
            pendingAuths[username] = {
                request_id = reqId,
                local_code = code,
                provider = "chatbox",
                password = password,
                nickname = nickname,
                senderId = senderId,
                timestamp = os.epoch("utc")
            }
            return true
        else
            logActivity("AP Chat Box dispatch failed for '" .. username .. "': " .. tostring(sendErr), true)
            rednet.send(senderId, {
                success = false,
                reason = "2FA Delivery failed: Player '" .. username .. "' unreachable via Chat Box."
            }, AUTH_SERVER_PROTOCOL)
            return false
        end
    end

    -- 3. If neither 2FA provider succeeded
    local reasonMsg = "2FA service unavailable: " .. tostring(lastError)
    if not chatBoxAvailable then
        reasonMsg = reasonMsg .. " (No AP Chat Box attached)"
    end
    logActivity("Auth failed for '" .. username .. "': " .. reasonMsg, true)
    rednet.send(senderId, { success = false, reason = reasonMsg }, AUTH_SERVER_PROTOCOL)
    return false
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
            
            local tokenVerified = false
            local verifyReason = nil

            if authData.local_code then
                -- Local verification for AP Chat Box 2FA
                if tostring(code) == tostring(authData.local_code) then
                    tokenVerified = true
                else
                    verifyReason = "Invalid verification code."
                end
            else
                -- Upstream HyperAuth Command Computer verification
                local cfg = getHyperAuthConfig()
                local apiProto = cfg.PROTOCOL_NAME or AUTH_INTERNAL_API or "auth.secure.v1"
                local reply, err = AuthClient.verifyCode(apiProto, { request_id = authData.request_id, code = code })
                if reply and reply.ok then
                    tokenVerified = true
                else
                    verifyReason = (reply and (reply.reason or reply.error)) or "Invalid code."
                end
            end
            
            if tokenVerified then
                local token = crypto.hex(os.time() .. math.random())
                local authMethod = authData.provider or "hyperauth"
                if not users[user] then
                    users[user] = { password = authData.password, nickname = authData.nickname, session_token = token }
                    DB.saveTableToFile(USERS_DB, users, logActivity)
                    logActivity("User '" .. user .. "' registered (2FA: " .. authMethod .. ").")
                else
                    users[user].session_token = token
                    DB.saveTableToFile(USERS_DB, users, logActivity)
                    logActivity("User '" .. user .. "' logged in (2FA: " .. authMethod .. ").")
                end
                if serverDashboard then serverDashboard:refreshDetails() end
                
                broadcastSession(user, users[user].nickname, token)
                
                rednet.send(senderId, { 
                    success = true, nickname = users[user].nickname, session_token = token 
                }, AUTH_SERVER_PROTOCOL)
                
                pendingAuths[user] = nil
            else
                rednet.send(senderId, { success = false, reason = verifyReason or "Invalid code." }, AUTH_SERVER_PROTOCOL)
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
            if serverDashboard then serverDashboard:refreshDetails() end
            
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
        elseif message.type == "verify_session" then
            local user = message.user
            local token = message.session_token
            local valid = false
            local nick = nil
            if user and token and users[user] and users[user].session_token == token then
                valid = true
                nick = users[user].nickname
            end
            rednet.send(senderId, { type = "verify_session_response", user = user, valid = valid, nickname = nick }, AUTH_INTERLINK_PROTOCOL)
        elseif message.type == "get_user_list" or message.type == "get_all_users" then
            local userList = {}
            if users then
                for u in pairs(users) do
                    table.insert(userList, u)
                end
            end
            table.sort(userList)
            rednet.send(senderId, { type = "user_list_response", users = userList }, AUTH_INTERLINK_PROTOCOL)
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
    local function getDashboardDetails()
        local haCfg = getHyperAuthConfig()
        local userCount = 0
        if users then for _ in pairs(users) do userCount = userCount + 1 end end

        local cbStatus = APChatBox and APChatBox.getStatus and APChatBox.getStatus()
        local apStatusStr = "NOT DETECTED"
        local apColor = colors.lightGray
        if cbStatus and cbStatus.available then
            apStatusStr = string.format("ONLINE (%s)", cbStatus.name or "chatBox")
            apColor = colors.lime
        end

        local haLinkStr = "UNPAIRED (Standalone)"
        local haColor = colors.yellow
        if isPaired() then
            haLinkStr = "PAIRED (" .. (haCfg.CLIENT_ID or "ok") .. ")"
            haColor = colors.lime
        end

        return {
            { label = "Service", value = "Drunken OS Authentication Authority", color = colors.white },
            { label = "User Database", value = string.format("%d registered user(s)", userCount), color = colors.lime },
            { label = "HyperAuth Link", value = haLinkStr, color = haColor },
            { label = "AP ChatBox 2FA", value = apStatusStr, color = apColor },
            { label = "External Proto", value = AUTH_SERVER_PROTOCOL, color = colors.lightGray },
            { label = "Interlink Proto", value = AUTH_INTERLINK_PROTOCOL, color = colors.lightGray },
        }
    end

    serverDashboard = ServiceGuard.createDashboard({
        serverName = "AUTH SERVER",
        details = getDashboardDetails,
        status = "ONLINE",
        hintText = "[P] Pair HyperAuth | [C] Clear | [Q] Quit | Zero-Downtime Supervisor",
        maxLogs = 100
    })

    serverDashboard:draw()

    local haCfg = getHyperAuthConfig()
    local cbStatus = APChatBox and APChatBox.getStatus and APChatBox.getStatus()
    logActivity("Auth Server starting up...")
    logActivity("Listening for external auth on: " .. AUTH_SERVER_PROTOCOL)
    logActivity("Listening for interlink on: " .. AUTH_INTERLINK_PROTOCOL)
    logActivity("HyperAuth 2FA Link: Protocol='" .. (haCfg.PROTOCOL_NAME or "auth.secure.v1") .. "', Vendor='" .. (haCfg.CLIENT_ID or "drunken_os_server") .. "'")
    if cbStatus and cbStatus.available then
        logActivity("AP Chat Box 2FA: Online on '" .. tostring(cbStatus.name) .. "' (Toast=" .. tostring(cbStatus.canToast) .. ", Formatted=" .. tostring(cbStatus.canFormatted) .. ")")
    else
        logActivity("AP Chat Box 2FA: Not detected (ready for hotplug)")
    end
    
    while true do
        local event, p1, p2, p3 = os.pullEventRaw()
        if event == "rednet_message" then
            local senderId, message, protocol = p1, p2, p3
            ServiceGuard.protectHandler("Auth:message", handleMessage, logActivity, senderId, message, protocol)
        elseif event == "peripheral" or event == "peripheral_detach" then
            ServiceGuard.handlePeripheralEvent(event, p1, registerProtocols, logActivity)
            if event == "peripheral" and APChatBox then
                local cb, name = APChatBox.find()
                if cb and (p1 == name or peripheral.getType(p1) == "chatBox" or peripheral.getType(p1) == "chat_box") then
                    logActivity("Advanced Peripherals Chat Box attached on '" .. tostring(p1) .. "'")
                end
            elseif event == "peripheral_detach" then
                if APChatBox and not APChatBox.isAvailable() then
                    logActivity("Advanced Peripherals Chat Box detached ('" .. tostring(p1) .. "')", true)
                end
            end
            if serverDashboard then serverDashboard:refreshDetails() end
        elseif event == "key" then
            local key = p1
            if key == keys.p then
                performAutoPairing()
                if serverDashboard then serverDashboard:draw() end
            elseif key == keys.c then
                if serverDashboard then serverDashboard:clearLogs() end
            elseif key == keys.q then
                error("Terminated", 0)
            end
        elseif event == "terminate" then
            error("Terminated", 0)
        end
    end
end

local function runAuthServer()
    if forcePair or not isConfigured() then
        performAutoPairing()
    end
    parallel.waitForAny(startServer, garbageCollectPending)
end

ServiceGuard.runSupervisor("Auth Server", runAuthServer, flushAuthState, logActivity)
