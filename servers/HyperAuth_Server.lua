--[[
    Drunken OS - HyperAuth 2FA Token Authority Server (v1.0)
    by MuhendizBey & HyperRaccoon13

    Purpose:
    Dedicated 2FA authentication authority running on a Minecraft Command Computer.
    Receives cryptographically sealed token requests via Rednet, generates secure
    6-digit random codes, delivers them directly to players in-game via /tellraw,
    and validates verification attempts against rate-limits and expiry windows.
]]

local runningProg = shell and shell.getRunningProgram and shell.getRunningProgram() or ""
local runningDir = fs.getDir(runningProg)

if package then
    package.path = "/?.lua;?.lua;/lib/?.lua;lib/?.lua;/servers/?.lua;servers/?.lua;"
        .. "/servers/hyperauth/?.lua;servers/hyperauth/?.lua;"
        .. "/hyperauth/?.lua;hyperauth/?.lua;"
        .. "/disk/?.lua;disk/?.lua;/disk/servers/?.lua;disk/servers/?.lua;/disk/servers/hyperauth/?.lua;"
        .. (runningDir ~= "" and (fs.combine(runningDir, "?.lua") .. ";" .. fs.combine(runningDir, "hyperauth/?.lua") .. ";") or "")
        .. (package.path or "")
end

local secure = nil
local secure_candidates = {
    "/servers/hyperauth/secure.lua",
    "servers/hyperauth/secure.lua",
    "/hyperauth/secure.lua",
    "hyperauth/secure.lua",
    "/secure.lua",
    "secure.lua",
    "/disk/servers/hyperauth/secure.lua",
    "disk/servers/hyperauth/secure.lua"
}
for _, p in ipairs(secure_candidates) do
    if fs.exists(p) then
        local fn, err = loadfile(p)
        if not fn then
            error("HyperAuth Server: Compile error in '" .. p .. "':\n" .. tostring(err), 0)
        end
        if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
        local ok, mod = pcall(fn)
        if not ok then
            error("HyperAuth Server: Runtime error in '" .. p .. "':\n" .. tostring(mod), 0)
        end
        secure = mod
        break
    end
end
if not secure then
    local ok_secure, mod = pcall(require, "servers.hyperauth.secure")
    if not ok_secure then ok_secure, mod = pcall(require, "servers/hyperauth/secure") end
    if not ok_secure then ok_secure, mod = pcall(require, "hyperauth.secure") end
    if not ok_secure then ok_secure, mod = pcall(require, "secure") end
    if ok_secure then
        secure = mod
    else
        error("HyperAuth Server: Failed to load secure module: " .. tostring(mod), 0)
    end
end

local ServiceGuard = nil
pcall(function() ServiceGuard = require("lib.service_guard") end)

-- Configuration Constants
local PAIRING_PROTOCOL           = "hyperauth.pair.v1"
local PROTOCOLS = {
    "auth.secure.v1_Internal",
    "auth.secure.v1",
    PAIRING_PROTOCOL
}
local VENDOR_REGISTRY_PATH       = "/vendors.jsonl"
if not fs.exists(VENDOR_REGISTRY_PATH) then
    local seedPaths = { "vendors.jsonl", "disk/vendors.jsonl", "/disk/vendors.jsonl" }
    for _, sp in ipairs(seedPaths) do
        if fs.exists(sp) then
            pcall(fs.copy, sp, VENDOR_REGISTRY_PATH)
            break
        end
    end
end
local AUTH_LOG_FILE_PATH         = "/logs/hyperauth.log.jsonl"
local REGISTRY_HOT_RELOAD_MILLIS = 5 * 1000

local CODE_LENGTH_DIGITS         = 6
local CODE_TIME_TO_LIVE_MILLIS   = 5 * 60 * 1000 -- 5 minutes
local MAX_VERIFY_ATTEMPTS        = 5

-- Server State
local vendor_cache_by_id = {}
local vendor_last_loaded_millis = 0
local pending_requests_by_id = {}
local pending_pair_requests = {}
local isRunning = true
local logHistory = {}
local hasCommandsAPI = (commands ~= nil and type(commands.exec) == "function")

-- Utilities
local function current_time_millis()
    return (os.epoch and os.epoch("utc")) or (os.time() * 1000)
end

local function logActivity(msg, isWarn)
    local timestamp = os.date("%H:%M:%S")
    local prefix = isWarn and "[WARN] " or "[INFO] "
    local formatted = string.format("[%s] %s%s", timestamp, prefix, tostring(msg))
    table.insert(logHistory, formatted)
    if #logHistory > 200 then table.remove(logHistory, 1) end
    print(formatted)
end

local function append_log_line(event_table)
    event_table.timestamp_ms = current_time_millis()
    local ok_serialize, json_line = pcall(textutils.serializeJSON, event_table)
    if not ok_serialize then return end

    pcall(function()
        if not fs.exists("/logs") then fs.makeDir("/logs") end
        local file_mode = fs.exists(AUTH_LOG_FILE_PATH) and "a" or "w"
        local file_handle = fs.open(AUTH_LOG_FILE_PATH, file_mode)
        if file_handle then
            file_handle.write(json_line .. "\n")
            file_handle.close()
        end
    end)
end

local function random_digit_string(length_digits)
    secure.seed_rng()
    local digits = "0123456789"
    local buffer = {}
    for i = 1, length_digits do
        local rand_idx = math.random(#digits)
        buffer[i] = digits:sub(rand_idx, rand_idx)
    end
    return table.concat(buffer)
end

-- Vendor Registry Management
local function ensureDefaultVendorFile()
    if not fs.exists(VENDOR_REGISTRY_PATH) then
        local f = fs.open(VENDOR_REGISTRY_PATH, "w")
        if f then
            local defaultVendors = {
                {
                    vendorId = "drunken_os_server",
                    vendorName = "Drunken OS Server",
                    sharedSecret = "01431f1589d73d826c2a9669ab60fa8b",
                    enabled = true
                },
                {
                    vendorId = "DrunkenOS_AuthNode",
                    vendorName = "Drunken OS Auth Node",
                    sharedSecret = "drunken_secret_2026",
                    enabled = true
                }
            }
            for _, v in ipairs(defaultVendors) do
                f.write(textutils.serializeJSON(v) .. "\n")
            end
            f.close()
            logActivity("Created default " .. VENDOR_REGISTRY_PATH .. " with default vendors.")
        end
    end
end

local function load_vendor_registry_file()
    local vendor_map = {}
    ensureDefaultVendorFile()

    if not fs.exists(VENDOR_REGISTRY_PATH) then
        append_log_line({ level = "warn", event = "vendor_registry_missing", path = VENDOR_REGISTRY_PATH })
        return vendor_map
    end

    local file_handle = fs.open(VENDOR_REGISTRY_PATH, "r")
    if not file_handle then return vendor_map end

    while true do
        local json_line = file_handle.readLine()
        if not json_line then break end
        if json_line:match("%S") then
            local ok_parse, record = pcall(textutils.unserializeJSON, json_line)
            if ok_parse and type(record) == "table" then
                local vendor_id = record.vendorId or record.vendorID or record.client_id
                local vendor_name = record.vendorName or vendor_id
                local shared_secret = record.sharedSecret
                local is_enabled = (record.enabled ~= false)
                if vendor_id and shared_secret and is_enabled then
                    vendor_map[tostring(vendor_id)] = {
                        vendorName   = vendor_name,
                        sharedSecret = shared_secret,
                        enabled      = true
                    }
                end
            end
        end
    end
    file_handle.close()
    return vendor_map
end

local function save_vendor_registry_file()
    local f = fs.open(VENDOR_REGISTRY_PATH, "w")
    if not f then
        logActivity("Error: Could not open " .. VENDOR_REGISTRY_PATH .. " for writing!", true)
        return false
    end
    for vid, vdata in pairs(vendor_cache_by_id) do
        local entry = {
            vendorId = vid,
            vendorName = vdata.vendorName or vid,
            sharedSecret = vdata.sharedSecret,
            enabled = (vdata.enabled ~= false)
        }
        f.write(textutils.serializeJSON(entry) .. "\n")
    end
    f.close()
    vendor_last_loaded_millis = current_time_millis()
    return true
end

local function get_vendor_record_by_id(vendor_id)
    local now_millis = current_time_millis()
    if (now_millis - vendor_last_loaded_millis) > REGISTRY_HOT_RELOAD_MILLIS then
        local loaded = load_vendor_registry_file()
        for k, v in pairs(loaded) do
            vendor_cache_by_id[k] = v
        end
        vendor_last_loaded_millis = now_millis
    end
    local target = tostring(vendor_id)
    if vendor_cache_by_id[target] then
        return vendor_cache_by_id[target]
    end
    -- Case-insensitive lookup fallback
    local lowerTarget = target:lower()
    for k, v in pairs(vendor_cache_by_id) do
        if k:lower() == lowerTarget then
            return v
        end
    end
    return nil
end

-- Minecraft In-Game Token Delivery (/tellraw)
local function dm_player_with_code(player_username, code_text, ttl_millis)
    local minutes = math.max(1, math.floor((ttl_millis or 0) / 60000))

    if not hasCommandsAPI then
        logActivity(string.format("[SIMULATED TELLRAW] Code for '%s': %s (Expires %dm)", player_username, code_text, minutes))
        return true
    end

    local function build(hoverKey)
        return {
            "",
            { text = "=== [Drunken OS] Auth Token ===\n", bold = true, color = "aqua" },
            { text = "Security Code: ", color = "yellow" },
            {
                text = code_text,
                bold = true,
                color = "green",
                clickEvent = { action = "copy_to_clipboard", value = code_text },
                hoverEvent = { action = "show_text", [hoverKey] = "Click to copy code" }
            },
            { text = string.format("\nExpires in %d minute(s). Do not share this code!\n", minutes), color = "gray" },
            { text = "================================", bold = true, color = "aqua" }
        }
    end

    local json = textutils.serializeJSON(build("contents"))
    local ok = pcall(function() return commands.exec(string.format("tellraw %s %s", player_username, json)) end)
    if not ok then
        -- Fallback to legacy hoverEvent structure
        json = textutils.serializeJSON(build("value"))
        ok = pcall(function() return commands.exec(string.format("tellraw %s %s", player_username, json)) end)
    end
    return (ok and true or false)
end

-- Networking Setup
local openModems = {}
local function setupNetworking()
    openModems = {}
    if ServiceGuard and ServiceGuard.initModems then
        pcall(ServiceGuard.initModems)
    end
    local names = (peripheral and peripheral.getNames and peripheral.getNames()) or { "left", "right", "top", "bottom", "front", "back" }
    for _, side in ipairs(names) do
        if peripheral.getType(side) == "modem" then
            if rednet and rednet.open then
                pcall(rednet.open, side)
            end
            local isWire = false
            local p = peripheral.wrap(side)
            if p and p.isWireless then isWire = p.isWireless() end
            table.insert(openModems, { side = side, wireless = isWire })
        end
    end

    for _, proto in ipairs(PROTOCOLS) do
        pcall(rednet.host, proto, "hyperauth.server")
    end
    return openModems
end

-- Header Banner
local function drawHeader()
    local cmdStatus = hasCommandsAPI and "Command PC (/tellraw)" or "Simulated Terminal"
    local modemDesc = "None [!]"
    local modemCol = colors.red
    if #openModems > 0 then
        local modemDescs = {}
        for _, m in ipairs(openModems) do
            table.insert(modemDescs, string.format("%s (%s)", m.wireless and "Wireless" or "Wired", m.side))
        end
        modemDesc = table.concat(modemDescs, ", ") .. " [OPEN]"
        modemCol = colors.lime
    end

    local vendorCount = 0
    for _ in pairs(vendor_cache_by_id) do vendorCount = vendorCount + 1 end

    local details = {
        { label = "Service", value = "HyperAuth 2FA Token Authority v1.0", color = colors.white },
        { label = "Commands API", value = cmdStatus, color = hasCommandsAPI and colors.lime or colors.yellow },
        { label = "Modem(s)", value = modemDesc, color = modemCol },
        { label = "Vendors DB", value = string.format("%d active vendor(s)", vendorCount), color = colors.white },
        { label = "Protocols", value = table.concat(PROTOCOLS, ", "), color = colors.lightGray },
    }

    if ServiceGuard and ServiceGuard.drawServerDashboard then
        ServiceGuard.drawServerDashboard("HYPERAUTH 2FA SERVER", details, "ONLINE", "Type 'help' for commands | Listening for auth requests...")
    else
        term.clear(); term.setCursorPos(1, 1)
        print("=== HYPERAUTH 2FA SERVER ===")
    end
end

-- Request Processor
local function handleMessage(sender_computer_id, raw_outer_message, receivedProtocol)
    local outer_envelope = raw_outer_message
    if type(raw_outer_message) == "string" then
        local is_deserialized, res = pcall(textutils.unserialize, raw_outer_message)
        if is_deserialized and type(res) == "table" then
            outer_envelope = res
        else
            local is_json, res_json = pcall(textutils.unserializeJSON, raw_outer_message)
            if is_json and type(res_json) == "table" then
                outer_envelope = res_json
            end
        end
    end

    if type(outer_envelope) ~= "table" then
        append_log_line({ level = "warn", event = "bad_outer_envelope", sender = sender_computer_id })
        rednet.send(sender_computer_id, textutils.serialize({ error = "bad_outer" }), receivedProtocol)
        return
    end

    -- Automatic Pairing Handshake (Zero-Config Automatch)
    if receivedProtocol == PAIRING_PROTOCOL or outer_envelope.type == "pair_request" then
        if outer_envelope.type == "pair_request" then
            local senderId = sender_computer_id
            local pin = tostring(outer_envelope.pin or "")
            local label = tostring(outer_envelope.label or ("Auth Server #" .. senderId))
            local nonce = tostring(outer_envelope.nonce or "")

            pending_pair_requests[senderId] = {
                id = senderId,
                pin = pin,
                label = label,
                nonce = nonce,
                timestamp = current_time_millis()
            }

            local isColor = term.isColor and term.isColor()
            print("")
            if isColor then term.setTextColor(colors.yellow) end
            print("********************************************************")
            print(string.format("  INCOMING PAIRING REQUEST FROM COMPUTER #%d!", senderId))
            print(string.format("  Device : %s", label))
            if #pin > 0 then
                print(string.format("  PIN    : [ %s ]", pin))
            end
            print(string.format("  Action : Type 'pair accept %d' (or 'y') to authorize.", senderId))
            print("********************************************************")
            if isColor then term.setTextColor(colors.white) end
            io.write("hyperauth> ")

            logActivity(string.format("Pair request from PC #%d ('%s', PIN: %s)", senderId, label, pin))
            append_log_line({ level = "info", event = "pair_request", sender = senderId, label = label, pin = pin })
            return
        end
    end

    local vendor_id = tostring(outer_envelope.client_id or outer_envelope.vendorID or "")
    local vendor_record = get_vendor_record_by_id(vendor_id)

    if not vendor_record then
        append_log_line({ level = "warn", event = "unknown_vendor", vendorId = vendor_id, sender = sender_computer_id })
        rednet.send(sender_computer_id, textutils.serialize({ error = "unknown_client_id" }), receivedProtocol)
        logActivity(string.format("Rejected request from PC #%d: unknown vendor '%s'", sender_computer_id, vendor_id), true)
        return
    end

    local reply_header_for_mac = { client_id = vendor_id, version = "v1" }
    local decrypted_payload, open_error = secure.open(vendor_record.sharedSecret, reply_header_for_mac, outer_envelope.packet)

    if not decrypted_payload then
        append_log_line({
            level = "warn", event = "decrypt_or_mac_failed", vendorId = vendor_id,
            vendorName = vendor_record.vendorName, sender = sender_computer_id, detail = open_error
        })
        rednet.send(sender_computer_id, textutils.serialize({ client_id = vendor_id, error = "open_failed", detail = open_error }), receivedProtocol)
        logActivity(string.format("HMAC/Decrypt failure for vendor '%s': %s", vendor_id, tostring(open_error)), true)
        return
    end

    local reply_payload_table

    if decrypted_payload.type == "request_code" then
        local request_id      = decrypted_payload.request_id or secure.random_hex(12)
        local player_username = decrypted_payload.username
        local generated_code  = random_digit_string(CODE_LENGTH_DIGITS)

        pending_requests_by_id[request_id] = {
            code = generated_code,
            player_username = player_username,
            expires_millis = current_time_millis() + CODE_TIME_TO_LIVE_MILLIS,
            attempt_count = 0,
            client_metadata = decrypted_payload
        }

        local dm_sent_ok = dm_player_with_code(player_username, generated_code, CODE_TIME_TO_LIVE_MILLIS)

        reply_payload_table = {
            ok = dm_sent_ok and true or false,
            type = "request_code_reply",
            request_id = request_id,
            expires_in_ms = CODE_TIME_TO_LIVE_MILLIS,
            timestamp_ms = current_time_millis()
        }

        append_log_line({
            level = "info", event = "request_code",
            vendorId = vendor_id, vendorName = vendor_record.vendorName,
            username = player_username, request_id = request_id, dm_sent = dm_sent_ok
        })
        logActivity(string.format("Issued 2FA token for '%s' (Vendor: %s, ID: %s)", player_username, vendor_record.vendorName, request_id:sub(1, 8)))

    elseif decrypted_payload.type == "verify_code" then
        local request_id = decrypted_payload.request_id
        local record_for_request = pending_requests_by_id[request_id]
        local verify_ok = false
        local failure_reason = nil

        if not record_for_request then
            failure_reason = "not_found"
        else
            record_for_request.attempt_count = (record_for_request.attempt_count or 0) + 1
            if record_for_request.attempt_count > MAX_VERIFY_ATTEMPTS then
                failure_reason = "too_many_attempts"
                pending_requests_by_id[request_id] = nil
            elseif record_for_request.expires_millis < current_time_millis() then
                failure_reason = "expired"
                pending_requests_by_id[request_id] = nil
            elseif tostring(decrypted_payload.code_entered) ~= tostring(record_for_request.code) then
                failure_reason = "mismatch"
            else
                verify_ok = true
                pending_requests_by_id[request_id] = nil
            end
        end

        reply_payload_table = {
            ok = verify_ok,
            type = "verify_code_reply",
            request_id = request_id,
            reason = failure_reason,
            timestamp_ms = current_time_millis()
        }

        append_log_line({
            level = verify_ok and "info" or "warn",
            event = "verify_code",
            vendorId = vendor_id, vendorName = vendor_record.vendorName,
            request_id = request_id,
            username = record_for_request and record_for_request.player_username or nil,
            result = verify_ok and "ok" or "fail",
            reason = failure_reason
        })

        if verify_ok then
            logActivity(string.format("Verified token for '%s' (Vendor: %s)", record_for_request and record_for_request.player_username or "unknown", vendor_record.vendorName))
        else
            logActivity(string.format("Verification FAILED for ID %s: %s", tostring(request_id):sub(1, 8), tostring(failure_reason)), true)
        end
    else
        reply_payload_table = { ok = false, error = "unknown_type", timestamp_ms = current_time_millis() }
        append_log_line({ level = "warn", event = "unknown_type", vendorId = vendor_id, payload_type = tostring(decrypted_payload.type) })
    end

    local sealed_packet = secure.seal(vendor_record.sharedSecret, reply_header_for_mac, reply_payload_table)
    rednet.send(sender_computer_id, textutils.serialize({ client_id = vendor_id, packet = sealed_packet }), receivedProtocol)
end

-- Background Network Listener Loop
local function networkLoop()
    local pruneTimer = os.startTimer(5)
    while isRunning do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local sender_id, message, protocol = p1, p2, p3
            if sender_id and message then
                for _, listeningProto in ipairs(PROTOCOLS) do
                    if protocol == listeningProto then
                        pcall(handleMessage, sender_id, message, protocol)
                        break
                    end
                end
            end
        elseif event == "peripheral" or event == "peripheral_detach" then
            setupNetworking()
            logActivity("Peripheral update: modems refreshed.")
        elseif event == "timer" and p1 == pruneTimer then
            -- Prune expired pending requests periodically
            local now = current_time_millis()
            for req_id, rec in pairs(pending_requests_by_id) do
                if rec.expires_millis < now then
                    pending_requests_by_id[req_id] = nil
                end
            end
            pruneTimer = os.startTimer(5)
        end
    end
end

-- Admin CLI Command Processor
local function processAdminCommand(line)
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" then return end

    local parts = {}
    for word in line:gmatch("%S+") do table.insert(parts, word) end
    local cmd = parts[1]:lower()

    if cmd == "help" then
        print("\n=== HyperAuth Admin Commands ===")
        print(" status                - Show server health & stats")
        print(" net / modem           - Check & refresh connected modems")
        print(" pair [list|accept|reject] - Manage Auth Server pairings")
        print(" vendors               - List registered vendors")
        print(" addvendor <id> <name> <secret> - Register new vendor")
        print(" delvendor <id>        - Disable a vendor")
        print(" requests              - Show active 2FA requests")
        print(" testcode <player>     - Dispatch test token to player")
        print(" clear                 - Clear terminal screen")
        print(" exit                  - Shutdown server\n")

    elseif cmd == "status" then
        print("\n--- HyperAuth Authority Status ---")
        print(" Computer ID : #" .. os.getComputerID())
        print(" Commands API: " .. (hasCommandsAPI and "Active (Minecraft /tellraw enabled)" or "Inactive (Simulated)"))
        local vCount = 0
        for _ in pairs(vendor_cache_by_id) do vCount = vCount + 1 end
        print(" Registered  : " .. vCount .. " vendor(s)")
        local rCount = 0
        for _ in pairs(pending_requests_by_id) do rCount = rCount + 1 end
        print(" Active 2FA  : " .. rCount .. " pending request(s)")
        local pCount = 0
        for _ in pairs(pending_pair_requests) do pCount = pCount + 1 end
        print(" Pending Pair: " .. pCount .. " incoming request(s)\n")

    elseif cmd == "net" or cmd == "modem" then
        setupNetworking()
        print("\n--- Network & Modem Status ---")
        if #openModems > 0 then
            for _, m in ipairs(openModems) do
                local isOpen = rednet and rednet.isOpen and rednet.isOpen(m.side)
                print(string.format("  [%s] %s Modem | Rednet: %s",
                    m.side, m.wireless and "Wireless" or "Wired", isOpen and "OPEN" or "CLOSED"))
            end
        else
            print("  [!] NO MODEM DETECTED! Please attach a Wireless Modem to any side of this PC.")
        end
        print("  Hosted Protocols: " .. table.concat(PROTOCOLS, ", "))
        print("")

    elseif cmd == "pair" or cmd == "accept" or cmd == "y" or cmd == "yes" or cmd == "reject" or cmd == "n" or cmd == "no" then
        local sub = parts[1]:lower()
        local targetId = nil

        if sub == "pair" then
            local action = parts[2] and parts[2]:lower() or "list"
            if action == "list" then
                print("\n--- Pending Auth Server Pairing Requests ---")
                local count = 0
                for id, req in pairs(pending_pair_requests) do
                    count = count + 1
                    print(string.format("  [PC #%d] %s | PIN: %s", id, req.label, req.pin))
                end
                if count == 0 then print("  No pending pairing requests.") end
                print("")
                return
            elseif action == "accept" or action == "yes" or action == "y" then
                targetId = tonumber(parts[3])
                sub = "accept"
            elseif action == "reject" or action == "no" or action == "n" then
                targetId = tonumber(parts[3])
                sub = "reject"
            else
                print(" Usage: pair [list | accept <id> | reject <id>]")
                return
            end
        else
            targetId = tonumber(parts[2])
            if sub == "y" or sub == "yes" then sub = "accept" end
            if sub == "n" or sub == "no" then sub = "reject" end
        end

        if not targetId then
            -- Auto-pick if only one request is pending
            local firstId, count = nil, 0
            for id in pairs(pending_pair_requests) do
                firstId = id
                count = count + 1
            end
            if count == 1 then targetId = firstId end
        end

        if not targetId or not pending_pair_requests[targetId] then
            print(" No pending pairing request for ID: " .. tostring(targetId or "unspecified"))
            print(" Type 'pair list' to view pending requests.")
            return
        end

        local req = pending_pair_requests[targetId]

        if sub == "accept" then
            local newSecret = secure.random_hex(32)
            local newVendorId = "drunken_auth_" .. targetId
            local vendorName = req.label or ("Drunken OS Auth #" .. targetId)

            vendor_cache_by_id[newVendorId] = {
                vendorName = vendorName,
                sharedSecret = newSecret,
                enabled = true
            }
            if save_vendor_registry_file() then
                logActivity("Saved vendor pairing to " .. VENDOR_REGISTRY_PATH)
            else
                logActivity("Failed to write vendor pairing to " .. VENDOR_REGISTRY_PATH, true)
            end

            local replyPacket = {
                type = "pair_accept",
                server_id = os.getComputerID(),
                vendorId = newVendorId,
                sharedSecret = newSecret,
                protocol = "auth.secure.v1",
                pin = req.pin,
                nonce = req.nonce,
                timestamp = current_time_millis()
            }
            rednet.send(targetId, replyPacket, PAIRING_PROTOCOL)
            rednet.send(targetId, textutils.serialize(replyPacket), PAIRING_PROTOCOL)
            pending_pair_requests[targetId] = nil

            print(string.format(" [SUCCESS] Paired with PC #%d!", targetId))
            print(string.format(" Assigned Vendor ID : %s", newVendorId))
            print(string.format(" Generated Key      : %s...", newSecret:sub(1, 8)))
            logActivity(string.format("Approved pairing for PC #%d (Vendor: %s)", targetId, newVendorId))
            append_log_line({ level = "info", event = "pair_approved", vendorId = newVendorId, client = targetId })

        elseif sub == "reject" then
            local rejectPacket = {
                type = "pair_reject",
                server_id = os.getComputerID(),
                reason = "Rejected by administrator.",
                pin = req.pin,
                nonce = req.nonce
            }
            rednet.send(targetId, rejectPacket, PAIRING_PROTOCOL)
            rednet.send(targetId, textutils.serialize(rejectPacket), PAIRING_PROTOCOL)
            pending_pair_requests[targetId] = nil
            print(" [REJECTED] Pairing request for PC #" .. targetId .. " rejected.")
            logActivity("Rejected pairing request for PC #" .. targetId, true)
            append_log_line({ level = "warn", event = "pair_rejected", client = targetId })
        end

    elseif cmd == "vendors" then
        print("\n--- Registered Vendors ---")
        local count = 0
        for vid, vdata in pairs(vendor_cache_by_id) do
            count = count + 1
            print(string.format(" [%s] %s (Secret: %s...)", vid, vdata.vendorName or vid, tostring(vdata.sharedSecret):sub(1, 4)))
        end
        if count == 0 then print(" No vendors registered in " .. VENDOR_REGISTRY_PATH) end
        print("")

    elseif cmd == "addvendor" then
        local vid, vname, vsec = parts[2], parts[3], parts[4]
        if not vid or not vname or not vsec then
            print(" Usage: addvendor <vendorId> <vendorName> <sharedSecret>")
            return
        end
        vendor_cache_by_id[vid] = { vendorName = vname, sharedSecret = vsec, enabled = true }
        if save_vendor_registry_file() then
            print(" Vendor '" .. vid .. "' registered successfully.")
        else
            print(" Error: Could not write to " .. VENDOR_REGISTRY_PATH)
        end

    elseif cmd == "delvendor" then
        local vid = parts[2]
        if not vid then
            print(" Usage: delvendor <vendorId>")
            return
        end
        vendor_cache_by_id[vid] = nil
        save_vendor_registry_file()
        print(" Vendor '" .. vid .. "' deleted successfully.")

    elseif cmd == "requests" then
        print("\n--- Active Pending 2FA Requests ---")
        local count = 0
        local now = current_time_millis()
        for req_id, rec in pairs(pending_requests_by_id) do
            count = count + 1
            local remainSec = math.max(0, math.floor((rec.expires_millis - now) / 1000))
            print(string.format(" [%s] User: %-16s Code: %s (Expires: %ds, Attempts: %d)",
                req_id:sub(1, 8), rec.player_username, rec.code, remainSec, rec.attempt_count or 0))
        end
        if count == 0 then print(" No active 2FA requests.") end
        print("")

    elseif cmd == "testcode" then
        local player = parts[2]
        if not player then
            print(" Usage: testcode <minecraft_username>")
            return
        end
        local testCode = random_digit_string(CODE_LENGTH_DIGITS)
        local ok = dm_player_with_code(player, testCode, CODE_TIME_TO_LIVE_MILLIS)
        print(string.format(" Sent test token '%s' to '%s': %s", testCode, player, ok and "SUCCESS" or "FAILED"))

    elseif cmd == "clear" then
        drawHeader()

    elseif cmd == "exit" or cmd == "quit" then
        isRunning = false
        print(" Shutting down HyperAuth Server...")

    else
        print(" Unknown command: '" .. cmd .. "'. Type 'help' for command list.")
    end
end

-- Admin Console Loop
local function adminConsoleLoop()
    while isRunning do
        io.write("hyperauth> ")
        local input = read()
        if input then
            processAdminCommand(input)
        end
    end
end

-- Server Initialization
local function main()
    setupNetworking()
    vendor_cache_by_id = load_vendor_registry_file()
    vendor_last_loaded_millis = current_time_millis()

    drawHeader()
    logActivity("HyperAuth 2FA Server started successfully.")

    parallel.waitForAny(networkLoop, adminConsoleLoop)
    print("HyperAuth Server stopped.")
end

main()
