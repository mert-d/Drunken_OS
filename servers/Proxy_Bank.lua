--[[
    Drunken OS - Network Proxy (v1.4 - Banking Core)
    by Gemini Gem & MuhendizBey

    Purpose:
    Specialized proxy for Banking services. Handles DB_Bank and 
    associated reports. Separated from Mainframe traffic to 
    prevent high-volume reports from blocking OS communications.
]]

local PROXY_VERSION = "1.4-BANK"

--==============================================================================
-- Networking Configuration
--==============================================================================

local wireless_modem, wired_modem = nil, nil
local logs = {}
local monitor = nil

-- Protocol Mapping: Public Name -> Internal Name
local PROTOCOL_MAP = {
    ["DB_Bank"] = "DB_Bank_Internal",
}

-- Protocols that should NOT be wrapped in a proxy table
local TRANSPARENT_PROTOCOLS = {}

-- Host Mappings: Public Hostname -> Public Protocol
local HOST_MAP = {
    ["bank.server"] = "DB_Bank",
}

-- Reversed Map for Internal -> Public relay
local INTERNAL_TO_PUBLIC = {}
for pub, priv in pairs(PROTOCOL_MAP) do
    INTERNAL_TO_PUBLIC[priv] = pub
end

--==============================================================================
-- UI & Logging
--==============================================================================

local function log(msg, isError)
    local prefix = isError and "[ERROR] " or "[INFO] "
    local entry = os.date("[%H:%M:%S] ") .. prefix .. msg
    print(entry)
    
    if monitor then
        local oldTerm = term.redirect(monitor)
        print(entry)
        term.redirect(oldTerm)
    end

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
        log("No bank server for " .. protocol, true)
        return
    end

    -- Standard Drunken OS wrapping
    rednet.send(internalId, { 
        proxy_orig_sender = senderId,
        proxy_orig_msg = message 
    }, internalProtocol)
end

local function relay(senderId, message, protocol)
    local publicProtocol = INTERNAL_TO_PUBLIC[protocol]
    if not publicProtocol then return end

    if type(message) == "table" and message.proxy_orig_sender then
        -- This is a direct response to a previous request
        log("RESP [" .. publicProtocol .. "] to " .. message.proxy_orig_sender)
        rednet.send(message.proxy_orig_sender, message.proxy_response, publicProtocol)
    else
        -- This is a broadcast or server-initiated message
        log("RELAY [" .. publicProtocol .. "] from bank server")
        rednet.broadcast(message, publicProtocol)
    end
end

local function dispatcher()
    while true do
        local id, msg, protocol = rednet.receive()
        
        if PROTOCOL_MAP[protocol] then
            -- Traffic coming from Wireless -> Proxy (Target: Internal)
            forward(id, msg, protocol)
        elseif INTERNAL_TO_PUBLIC[protocol] then
            -- Traffic coming from Wired -> Proxy (Target: Public/Client)
            relay(id, msg, protocol)
        end
    end
end

--==============================================================================
-- Initialization
--==============================================================================

local function main()
    term.clear()
    term.setCursorPos(1,1)
    print("Drunken OS Bank Proxy v" .. PROXY_VERSION)
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

    if not wireless_modem then log("Warning: No wireless modem found.", true); end
    if not wired_modem then log("Warning: No wired modem found.", true); end

    -- Monitor Initialization
    monitor = peripheral.find("monitor")
    if monitor then
        monitor.setTextScale(0.5)
        monitor.clear()
        monitor.setCursorPos(1,1)
        monitor.write("Drunken OS Bank Proxy - Live")
    end

    -- Register hosts
    for host, proto in pairs(HOST_MAP) do
        local ok, err = pcall(rednet.host, proto, host)
        if ok then
            log("Hosting " .. host .. " (" .. proto .. ")")
        else
            log("Failed to host " .. host .. ": " .. tostring(err), true)
        end
    end

    log("Bank Proxy Online. Dispatcher active.")
    dispatcher()
end

main()
