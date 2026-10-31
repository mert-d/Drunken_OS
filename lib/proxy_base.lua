--[[
    Drunken OS - Proxy Base Library (v2.0 - Non-Scrolling Dashboard Edition)
    
    Shared logic for all Network Proxy servers.
    Eliminates code duplication between Mainframe and Bank proxies.
    Standardized on ServiceGuard managed dashboard with live packet telemetry.
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
    local proxyDashboard = nil
    local packetsForwarded = 0
    local packetsRelayed = 0

    -- Build reverse map: Internal -> Public
    local internalToPublic = {}
    for pub, priv in pairs(config.protocolMap) do
        internalToPublic[priv] = pub
    end

    local transparentProtocols = config.transparentProtocols or {}

    -- Logging
    local function log(msg, isError)
        local prefix = isError and "[ERROR] " or "[INFO] "
        local entry = os.date("[%H:%M:%S] ") .. prefix .. tostring(msg or "")
        
        table.insert(logs, entry)
        if #logs > 100 then table.remove(logs, 1) end

        if proxyDashboard then
            proxyDashboard:log(entry, isError)
        else
            print(entry)
        end

        if monitor then
            pcall(function()
                local ok, oldTerm = pcall(term.redirect, monitor)
                if ok then
                    print(entry)
                    term.redirect(oldTerm)
                end
            end)
        end
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

        packetsForwarded = packetsForwarded + 1
        log("REQ [" .. protocol .. "] from #" .. senderId)
        
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

        if proxyDashboard and (packetsForwarded % 5 == 0) then
            proxyDashboard:refreshDetails()
        end
    end

    -- Relay: Internal/Wired -> Wireless/External
    local function relay(senderId, message, protocol)
        local publicProtocol = internalToPublic[protocol]
        if not publicProtocol then return end

        packetsRelayed = packetsRelayed + 1
        if type(message) == "table" and message.proxy_orig_sender then
            log("RESP [" .. publicProtocol .. "] to #" .. tostring(message.proxy_orig_sender))
            rednet.send(message.proxy_orig_sender, message.proxy_response, publicProtocol)
        else
            log("RELAY [" .. publicProtocol .. "] from internal")
            rednet.broadcast(message, publicProtocol)
        end

        if proxyDashboard and (packetsRelayed % 5 == 0) then
            proxyDashboard:refreshDetails()
        end
    end

    local wireless_modem = nil
    local wired_modem = nil

    local function getDashboardDetails()
        local hostCount = 0
        for _ in pairs(config.hostMap) do hostCount = hostCount + 1 end

        return {
            { label = "Service", value = config.name .. " v" .. config.version, color = colors.white },
            { label = "Wireless Mesh", value = wireless_modem and ("ONLINE (" .. wireless_modem .. ")") or "NOT DETECTED", color = wireless_modem and colors.lime or colors.yellow },
            { label = "Wired Link", value = wired_modem and ("CONNECTED (" .. wired_modem .. ")") or "NOT DETECTED", color = wired_modem and colors.lime or colors.yellow },
            { label = "Packets Fwd", value = string.format("%d packet(s)", packetsForwarded), color = colors.cyan },
            { label = "Packets Relay", value = string.format("%d packet(s)", packetsRelayed), color = colors.lime },
            { label = "Hosted Endpts", value = string.format("%d service host(s)", hostCount), color = colors.lightGray },
        }
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
                local m = ServiceGuard.initModems()
                wireless_modem = m.wireless
                wired_modem = m.wired
                if proxyDashboard then proxyDashboard:refreshDetails() end
            elseif event == "key" then
                local key = p1
                if key == keys.c then
                    if proxyDashboard then proxyDashboard:clearLogs() end
                elseif key == keys.q then
                    error("Terminated", 0)
                end
            elseif event == "terminate" then
                error("Terminated", 0)
            end
        end
    end

    -- Initialization
    local modems = ServiceGuard.initModems()
    wireless_modem = modems.wireless
    wired_modem = modems.wired

    proxyDashboard = ServiceGuard.createDashboard({
        serverName = config.name:upper(),
        details = getDashboardDetails,
        status = "ONLINE",
        hintText = "[C] Clear Logs | [Q] Quit | Zero-Downtime Proxy Supervisor",
        maxLogs = 100
    })

    proxyDashboard:draw()

    if not wireless_modem then log("Warning: No wireless modem found.", true) end
    if not wired_modem then log("Warning: No wired modem found.", true) end

    -- Monitor
    monitor = peripheral.find and peripheral.find("monitor")
    if monitor then
        pcall(function()
            monitor.setTextScale(0.5)
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.write(config.name .. " - Live Feed\n")
        end)
    end

    -- Register initial hosts
    registerHosts()

    log("Proxy Online. Dispatcher active under ServiceGuard supervisor.")
    ServiceGuard.runSupervisor(config.name, dispatcher, nil, log)
end

return ProxyBase
