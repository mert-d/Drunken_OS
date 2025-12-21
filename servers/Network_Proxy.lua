--[[
    Drunken OS - Network Proxy (v1.0)
    by Antigravity

    Purpose:
    Acts as a secure gateway (firewall) between the external Wireless/Ender network
    and the internal Wired network. All server traffic must pass through this
    proxy, allowing for logging and filtering.
]]

--==============================================================================
-- Configuration & State
--==============================================================================

local PROXY_VERSION = 1.0
local wireless_modem, wired_modem = nil, nil
local logs = {}

-- Protocol Mappings: Public Protocol -> Internal Protocol
local PROTOCOL_MAP = {
    ["SimpleMail"] = "SimpleMail_Internal",
    ["SimpleChat"] = "SimpleChat_Internal",
    ["ArcadeGames"] = "ArcadeGames_Internal",
    ["Drunken_Admin"] = "Drunken_Admin_Internal",
    ["DB_Bank"] = "DB_Bank_Internal",
}

-- Host Mappings: Public Hostname -> Public Protocol
local HOST_MAP = {
    ["mail.server"] = "SimpleMail",
    ["chat.server"] = "SimpleChat",
    ["arcade.server"] = "ArcadeGames",
    ["admin.server"] = "Drunken_Admin",
    ["bank.server"] = "DB_Bank",
}

--==============================================================================
-- UI & Logging
--==============================================================================

local function log(msg, isError)
    local prefix = isError and "[ERROR] " or "[INFO] "
    local entry = os.date("[%H:%M:%S] ") .. prefix .. msg
    print(entry)
    table.insert(logs, entry)
    if #logs > 100 then table.remove(logs, 1) end
end

--==============================================================================
-- Logic
--==============================================================================

local function forward(senderId, message, protocol)
    local internalProtocol = PROTOCOL_MAP[protocol]
    if not internalProtocol then return end

    log("REQ [" .. protocol .. "] from " .. senderId)
    
    -- Find internal server on Wired network
    local internalId = rednet.lookup(internalProtocol)
    if not internalId then
        log("No internal server for " .. protocol, true)
        return
    end

    -- Forward to internal server. 
    -- We include the original senderId in the message wrapper for response tracking.
    rednet.send(internalId, { 
        proxy_orig_sender = senderId,
        proxy_orig_msg = message 
    }, internalProtocol)
end

-- Listener for internal responses
local function responseListener()
    while true do
        local id, msg, protocol = rednet.receive()
        -- Internal protocols end with _Internal
        local publicProtocol = nil
        for pub, priv in pairs(PROTOCOL_MAP) do
            if protocol == priv then
                publicProtocol = pub
                break
            end
        end

        if publicProtocol and msg.proxy_orig_sender then
            log("RESP [" .. publicProtocol .. "] to " .. msg.proxy_orig_sender)
            rednet.send(msg.proxy_orig_sender, msg.proxy_response, publicProtocol)
        end
    end
end

local function mainListener()
    while true do
        local id, msg, protocol = rednet.receive()
        if PROTOCOL_MAP[protocol] then
            forward(id, msg, protocol)
        end
    end
end

--==============================================================================
-- Initialization
--==============================================================================

local function main()
    term.clear()
    term.setCursorPos(1,1)
    print("Drunken OS Network Proxy v" .. PROXY_VERSION)
    print("Initializing modems...")

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local m = peripheral.wrap(name)
            if m.isWireless() then
                wireless_modem = name
            else
                wired_modem = name
            end
            rednet.open(name)
        end
    end

    if not wireless_modem then print("Warning: No wireless modem found."); end
    if not wired_modem then print("Warning: No wired modem found."); end

    -- Register hosts
    for host, proto in pairs(HOST_MAP) do
        rednet.host(proto, host)
        log("Hosting " .. host .. " (" .. proto .. ")")
    end

    log("Proxy Online. Bridging Wireless <-> Wired.")
    parallel.waitForAny(mainListener, responseListener)
end

main()
