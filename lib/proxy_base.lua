--[[
    Drunken OS - Proxy Base Library (v1.0)
    
    Shared logic for all Network Proxy servers.
    Eliminates code duplication between Mainframe and Bank proxies.
]]

local ServiceGuard = require("lib.service_guard")

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
            local ok, oldTerm = pcall(term.redirect, monitor)
            if ok then
                print(entry)
                term.redirect(oldTerm)
            end
        end

        table.insert(logs, entry)
        if #logs > 100 then table.remove(logs, 1) end
    end

    local internalIdCache = {}

    -- Register/re-register hosts
    local function registerHosts()
        for host, proto in pairs(config.hostMap) do
            local ok, err = pcall(rednet.host, proto, host)
            if ok then
                log("Hosting " .. host .. " (" .. proto .. ")")
            else
                log("Failed to host " .. host .. ": " .. tostring(err), true)
            end
        end
    end

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

    -- Dispatcher: single event loop with hot-plug & protected dispatch
    local function dispatcher()
        while true do
            local event, p1, p2, p3 = os.pullEventRaw()
            
            if event == "rednet_message" then
                local id, msg, protocol = p1, p2, p3
                if config.protocolMap[protocol] then
                    ServiceGuard.protectHandler("Proxy:forward", forward, log, id, msg, protocol)
                elseif internalToPublic[protocol] then
                    ServiceGuard.protectHandler("Proxy:relay", relay, log, id, msg, protocol)
                end
            elseif event == "peripheral" or event == "peripheral_detach" then
                ServiceGuard.handlePeripheralEvent(event, p1, registerHosts, log, function(monSide)
                    monitor = peripheral.wrap(monSide)
                    if monitor then
                        monitor.setTextScale(0.5)
                        monitor.clear()
                        monitor.setCursorPos(1, 1)
                        monitor.write(config.name .. " - Live Feed")
                    end
                end)
            elseif event == "terminate" then
                error("Terminated", 0)
            end
        end
    end

    -- Initialization
    term.clear()
    term.setCursorPos(1, 1)
    print(config.name .. " v" .. config.version)
    print("Initializing modems...")

    local modems = ServiceGuard.initModems()
    local wireless_modem = modems.wireless
    local wired_modem = modems.wired

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

    -- Register initial hosts
    registerHosts()

    log("Proxy Online. Dispatcher active under ServiceGuard supervisor.")
    ServiceGuard.runSupervisor(config.name, dispatcher, nil, log)
end

return ProxyBase
