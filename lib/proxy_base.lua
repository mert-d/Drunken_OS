--[[
    Drunken OS - Proxy Base Library (v1.0)
    
    Shared logic for all Network Proxy servers.
    Eliminates code duplication between Mainframe and Bank proxies.
]]

local ProxyBase = {}

---
-- Creates and runs a proxy server with the given configuration.
-- @param config Table with fields:
--   name: Display name for this proxy (e.g., "Mainframe Proxy")
--   version: Version string
--   protocolMap: Table mapping public protocol names to internal names
--   hostMap: Table mapping public hostnames to public protocols
--   transparentProtocols: (Optional) Table of protocols that should NOT be wrapped
function ProxyBase.run(config)
    local logs = {}
    local monitor = nil

    -- Build reverse map: Internal -> Public
    local internalToPublic = {}
    for pub, priv in pairs(config.protocolMap) do
        internalToPublic[priv] = pub
    end

    local transparentProtocols = config.transparentProtocols or {}

    -- Logging
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

    local internalIdCache = {}

    -- Forward: Wireless/External -> Internal/Wired
    local function forward(senderId, message, protocol)
        local internalProtocol = config.protocolMap[protocol]
        if not internalProtocol then return end

        log("REQ [" .. protocol .. "] from " .. senderId)
        
        local internalId = internalIdCache[internalProtocol]
        if not internalId then
            internalId = rednet.lookup(internalProtocol)
            if internalId then
                internalIdCache[internalProtocol] = internalId
            end
        end

        if not internalId then
            log("No internal server for " .. protocol, true)
            return
        end

        if transparentProtocols[protocol] then
            rednet.send(internalId, message, internalProtocol)
        else
            rednet.send(internalId, { 
                proxy_orig_sender = senderId,
                proxy_orig_msg = message 
            }, internalProtocol)
        end
    end

    -- Relay: Internal/Wired -> Wireless/External
    local function relay(senderId, message, protocol)
        local publicProtocol = internalToPublic[protocol]
        if not publicProtocol then return end

        if type(message) == "table" and message.proxy_orig_sender then
            log("RESP [" .. publicProtocol .. "] to " .. message.proxy_orig_sender)
            rednet.send(message.proxy_orig_sender, message.proxy_response, publicProtocol)
        else
            log("RELAY [" .. publicProtocol .. "] from internal")
            rednet.broadcast(message, publicProtocol)
        end
    end

    -- Dispatcher: single event loop
    local function dispatcher()
        while true do
            local event, id, msg, protocol = os.pullEventRaw("rednet_message")
            
            if config.protocolMap[protocol] then
                forward(id, msg, protocol)
            elseif internalToPublic[protocol] then
                relay(id, msg, protocol)
            end
        end
    end

    -- Initialization
    term.clear()
    term.setCursorPos(1, 1)
    print(config.name .. " v" .. config.version)
    print("Initializing modems...")

    local wireless_modem, wired_modem = nil, nil
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

    if not wireless_modem then log("Warning: No wireless modem found.", true) end
    if not wired_modem then log("Warning: No wired modem found.", true) end

    -- Monitor
    monitor = peripheral.find("monitor")
    if monitor then
        monitor.setTextScale(0.5)
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write(config.name .. " - Live Feed")
    end

    -- Register hosts
    for host, proto in pairs(config.hostMap) do
        local ok, err = pcall(rednet.host, proto, host)
        if ok then
            log("Hosting " .. host .. " (" .. proto .. ")")
        else
            log("Failed to host " .. host .. ": " .. tostring(err), true)
        end
    end

    log("Proxy Online. Dispatcher active.")
    dispatcher()
end

return ProxyBase
