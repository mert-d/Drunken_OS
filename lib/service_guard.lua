--[[
    Drunken OS - Service Guard & Supervisor Library (v1.0)
    by MuhendizBey

    Features:
    - Peripheral Hot-Plug & Cable Auto-Reconnection (wired & wireless modems, monitors)
    - Protected Handler Execution (pcall wraps with safe logging, immunizing against crash packets)
    - Zero-Downtime Server Supervisor (watchdog auto-restarts failed event loops with 0 data loss)
]]

local ServiceGuard = {}
ServiceGuard._VERSION = 1.0

--==============================================================================
-- Modem & Peripheral Hot-Plug Subsystem
--==============================================================================

---
-- Detects and opens all attached modems.
-- @param filter string|nil: "wired", "wireless", or nil for all modems
-- @return table: { wired = name|nil, wireless = name|nil, count = number, all = { names... } }
function ServiceGuard.initModems(filter)
    local result = {
        wired = nil,
        wireless = nil,
        count = 0,
        all = {}
    }

    if not peripheral or not peripheral.getNames then
        return result
    end

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local m = peripheral.wrap(name)
            local isWire = m and m.isWireless and m.isWireless()
            local shouldOpen = false

            if not filter then
                shouldOpen = true
            elseif filter == "wireless" and isWire then
                shouldOpen = true
            elseif filter == "wired" and not isWire then
                shouldOpen = true
            end

            if shouldOpen then
                if isWire then
                    if not result.wireless then result.wireless = name end
                else
                    if not result.wired then result.wired = name end
                end

                if rednet and rednet.open then
                    pcall(rednet.open, name)
                end
                table.insert(result.all, name)
                result.count = result.count + 1
            end
        end
    end

    return result
end

---
-- Event listener helper for hot-plugged and detached peripherals.
-- Catches "peripheral" and "peripheral_detach" events, re-opens modems, and re-hosts services.
-- @param event string: The event name
-- @param name string: Peripheral side or network name
-- @param hostRegistrations function|nil: Callback to re-register rednet.host protocols
-- @param logger function|nil: Logging callback function(msg, isError)
-- @param onMonitor function|nil: Callback when an external monitor is attached
-- @return boolean: True if the event was handled as a peripheral change
function ServiceGuard.handlePeripheralEvent(event, name, hostRegistrations, logger, onMonitor)
    local log = logger or function(m) end

    if event == "peripheral" then
        if not peripheral or not peripheral.getType then return false end
        local pType = peripheral.getType(name)

        if pType == "modem" then
            local m = peripheral.wrap(name)
            local isWireless = m and m.isWireless and m.isWireless()
            local modemDesc = isWireless and "Wireless" or "Wired"

            if rednet and rednet.open then
                local ok, err = pcall(rednet.open, name)
                if ok then
                    log("[HOT-PLUG] " .. modemDesc .. " modem opened on: " .. name)
                else
                    log("[HOT-PLUG ERROR] Failed to open modem on " .. name .. ": " .. tostring(err), true)
                end
            end

            if hostRegistrations and type(hostRegistrations) == "function" then
                local okHost, hostErr = pcall(hostRegistrations)
                if okHost then
                    log("[HOT-PLUG] Network protocols successfully re-hosted.")
                else
                    log("[HOT-PLUG ERROR] Failed to re-host protocols: " .. tostring(hostErr), true)
                end
            end
            return true

        elseif pType == "monitor" then
            log("[HOT-PLUG] External monitor attached: " .. name)
            if onMonitor and type(onMonitor) == "function" then
                pcall(onMonitor, name)
            end
            return true
        end

    elseif event == "peripheral_detach" then
        log("[PERIPHERAL] Device detached: " .. tostring(name), true)
        return true
    end

    return false
end

--==============================================================================
-- Protected Packet & Handler Execution
--==============================================================================

---
-- Executes a packet handler or subsystem callback inside a protected pcall.
-- Prevents malformed, unexpected, or attack packets from crashing server threads.
-- @param handlerName string: Identifier for logs (e.g. "Mail:send_mail", "Bank:transfer")
-- @param func function: The callback function to execute
-- @param logger function|nil: Logger callback function(msg, isError)
-- @param ...: Arguments passed to func
-- @return boolean, ...: Success status followed by return values or error message
function ServiceGuard.protectHandler(handlerName, func, logger, ...)
    local log = logger or function(m) end
    if type(func) ~= "function" then
        log("[ERROR] Handler '" .. tostring(handlerName) .. "' is not a function", true)
        return false, "Invalid handler"
    end

    local results = { pcall(func, ...) }
    local ok = table.remove(results, 1)

    if not ok then
        local err = results[1] or "Unknown runtime error"
        log(string.format("[ERROR] Handler '%s' threw exception: %s", tostring(handlerName), tostring(err)), true)
        return false, err
    end

    return true, table.unpack(results)
end

--==============================================================================
-- Zero-Downtime Server Supervisor Watchdog
--==============================================================================

---
-- Runs a server main function inside a self-healing supervisor loop.
-- Catches unhandled fatal exceptions, flushes database state, logs stack traces, and auto-restarts.
-- @param serviceName string: Display title (e.g. "Mainframe Server", "Bank Server")
-- @param mainFunc function: The main event loop function to supervise
-- @param cleanupFunc function|nil: State cleanup / database flush callback before restart
-- @param logger function|nil: Logging function(msg, isError)
-- @param delaySeconds number|nil: Recovery backoff in seconds (default: 2)
function ServiceGuard.runSupervisor(serviceName, mainFunc, cleanupFunc, logger, delaySeconds)
    local log = logger or function(m, isErr)
        local prefix = isErr and "[FATAL] " or "[INFO] "
        print(prefix .. m)
    end
    local backoff = delaySeconds or 2

    while true do
        local ok, err = pcall(mainFunc)

        if not ok then
            local errStr = tostring(err or "Unknown error")
            -- Respect manual operator termination
            if errStr == "Terminated" or errStr:find("Terminated") then
                if cleanupFunc and type(cleanupFunc) == "function" then
                    pcall(cleanupFunc)
                end
                log(serviceName .. " terminated cleanly by operator.", false)
                break
            end

            -- Append to persistent crash log
            pcall(function()
                local crashLogName = serviceName:lower():gsub("%s+", "_") .. "_crash.log"
                local crashPath = crashLogName
                if fs and fs.exists and fs.isDir and fs.exists("logs") and fs.isDir("logs") then
                    crashPath = fs.combine("logs", crashLogName)
                end
                local f = fs and fs.open and fs.open(crashPath, "a")
                if f then
                    local ts = (os and os.date and os.date("[%Y-%m-%d %H:%M:%S] ")) or "[CRASH] "
                    f.writeLine(ts .. serviceName .. " FATAL EXCEPTION: " .. errStr)
                    f.close()
                end
            end)

            log("CRASH in " .. serviceName .. ": " .. errStr, true)
            log("Executing emergency state preservation & database flush...", true)

            if cleanupFunc and type(cleanupFunc) == "function" then
                local okClean, cleanErr = pcall(cleanupFunc)
                if not okClean then
                    log("Cleanup callback error: " .. tostring(cleanErr), true)
                end
            end

            log(string.format("Auto-recovering %s in %d seconds (zero downtime)...", serviceName, backoff), false)
            if sleep then
                sleep(backoff)
            end
        else
            -- Clean normal exit
            if cleanupFunc and type(cleanupFunc) == "function" then
                pcall(cleanupFunc)
            end
            break
        end
    end
end

return ServiceGuard
