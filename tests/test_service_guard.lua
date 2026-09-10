--[[
    Unit Test: Service Guard & Supervisor Library (lib/service_guard.lua)
    Verifies modem detection, peripheral hot-plug callbacks, protected packet execution,
    and self-healing supervisor watchdog with zero-downtime auto-restart.
]]

package.path = "./?.lua;" .. package.path

local openedModems = {}
local registeredHosts = 0
local monitorAttached = nil
local logs = {}
local writtenFiles = {}

-- Mock rednet
_G.rednet = {
    open = function(side)
        table.insert(openedModems, side)
        return true
    end,
    host = function(protocol, name)
        registeredHosts = registeredHosts + 1
    end
}

-- Mock peripheral
local peripherals = {
    top = {
        type = "modem",
        wrapped = {
            isWireless = function() return false end
        }
    },
    back = {
        type = "modem",
        wrapped = {
            isWireless = function() return true end
        }
    },
    left = {
        type = "monitor",
        wrapped = {}
    }
}

_G.peripheral = {
    getNames = function()
        local list = {}
        for name, _ in pairs(peripherals) do
            table.insert(list, name)
        end
        table.sort(list)
        return list
    end,
    getType = function(name)
        if peripherals[name] then
            return peripherals[name].type
        end
        return nil
    end,
    wrap = function(name)
        if peripherals[name] then
            return peripherals[name].wrapped
        end
        return nil
    end
}

-- Mock fs
_G.fs = {
    exists = function(path) return true end,
    isDir = function(path) return true end,
    combine = function(a, b) return a .. "/" .. b end,
    open = function(path, mode)
        writtenFiles[path] = writtenFiles[path] or {}
        return {
            writeLine = function(line)
                table.insert(writtenFiles[path], line)
            end,
            close = function() end
        }
    end
}

-- Mock sleep
_G.sleep = function(sec) end

local ServiceGuard = require("lib.service_guard")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

local function testLogger(msg, isErr)
    table.insert(logs, { msg = msg, isErr = isErr })
end

print("=== Running Service Guard & Watchdog Tests ===")

-- 1. Modem Auto-Discovery & Filtering
openedModems = {}
local allModems = ServiceGuard.initModems()
assert_eq(allModems.count, 2, "Discovered both wired & wireless modems")
assert_eq(allModems.wired, "top", "Identified wired modem on top")
assert_eq(allModems.wireless, "back", "Identified wireless modem on back")
assert_eq(#openedModems, 2, "Both modems opened via rednet")

openedModems = {}
local wirelessOnly = ServiceGuard.initModems("wireless")
assert_eq(wirelessOnly.count, 1, "Filtered to wireless only")
assert_eq(wirelessOnly.wireless, "back", "Wireless is back")
assert_eq(wirelessOnly.wired, nil, "Wired is nil in wireless filter")

openedModems = {}
local wiredOnly = ServiceGuard.initModems("wired")
assert_eq(wiredOnly.count, 1, "Filtered to wired only")
assert_eq(wiredOnly.wired, "top", "Wired is top")
assert_eq(wiredOnly.wireless, nil, "Wireless is nil in wired filter")

-- 2. Peripheral Hot-Plug & Cable Auto-Reconnection
openedModems = {}
logs = {}
local hostCallbackFired = false
local function rehost()
    hostCallbackFired = true
end

-- Hot-plug new modem "right" (wireless)
peripherals["right"] = {
    type = "modem",
    wrapped = { isWireless = function() return true end }
}
local handledModem = ServiceGuard.handlePeripheralEvent("peripheral", "right", rehost, testLogger)
assert_eq(handledModem, true, "Modem peripheral event handled")
assert_eq(#openedModems, 1, "Newly attached modem opened on rednet")
assert_eq(openedModems[1], "right", "Modem opened side is right")
assert_eq(hostCallbackFired, true, "Network protocols re-hosted on hot-plug")

-- Hot-plug monitor "front"
local monitorFired = nil
local function onMon(name)
    monitorFired = name
end
local handledMon = ServiceGuard.handlePeripheralEvent("peripheral", "front", rehost, testLogger, onMon)
peripherals["front"] = { type = "monitor", wrapped = {} }
handledMon = ServiceGuard.handlePeripheralEvent("peripheral", "front", rehost, testLogger, onMon)
assert_eq(handledMon, true, "Monitor peripheral event handled")
assert_eq(monitorFired, "front", "External monitor callback invoked with front")

-- Peripheral detach
local handledDetach = ServiceGuard.handlePeripheralEvent("peripheral_detach", "right", rehost, testLogger)
assert_eq(handledDetach, true, "Peripheral detach event handled")

-- Non-peripheral event pass-through
local handledOther = ServiceGuard.handlePeripheralEvent("mouse_click", 1, rehost, testLogger)
assert_eq(handledOther, false, "Non-peripheral events ignored")

-- 3. Protected Handler Execution (Crash Immunization)
logs = {}
local function safeCalc(a, b)
    return a * b, a + b
end

local okCalc, res1, res2 = ServiceGuard.protectHandler("Calc:multiply_add", safeCalc, testLogger, 6, 7)
assert_eq(okCalc, true, "Valid handler executed successfully")
assert_eq(res1, 42, "First return value matches")
assert_eq(res2, 13, "Second return value matches")

-- Malformed packet / handler exception
local function explodingHandler()
    error("Corrupted packet payload: nil field 'target'")
end

local okCrash, errCrash = ServiceGuard.protectHandler("Bank:transfer", explodingHandler, testLogger)
assert_eq(okCrash, false, "Exploding handler was safely caught by pcall")
assert_eq(type(errCrash), "string", "Error message captured")
assert_eq(#logs > 0, true, "Crash logged via logger")
assert_eq(logs[#logs].isErr, true, "Logged with error flag")

-- Invalid handler callback
local okInvalid, errInvalid = ServiceGuard.protectHandler("BadHandler", nil, testLogger)
assert_eq(okInvalid, false, "Nil handler rejected")
assert_eq(errInvalid, "Invalid handler", "Error returned for non-function")

-- 4. Zero-Downtime Server Supervisor Watchdog
logs = {}
writtenFiles = {}
local cleanupsFired = 0
local function cleanup()
    cleanupsFired = cleanupsFired + 1
end

-- Case A: Normal single run
local normalRuns = 0
ServiceGuard.runSupervisor("TestServerA", function()
    normalRuns = normalRuns + 1
end, cleanup, testLogger, 0)

assert_eq(normalRuns, 1, "Supervisor ran normal service once")
assert_eq(cleanupsFired, 1, "Cleanup callback fired on normal exit")

-- Case B: Crash and auto-recover (Zero Downtime)
local attempts = 0
ServiceGuard.runSupervisor("BankServer", function()
    attempts = attempts + 1
    if attempts == 1 then
        error("Unexpected Nil Reference in Database Buffer")
    end
    -- Succeeds on attempt 2
end, cleanup, testLogger, 0)

assert_eq(attempts, 2, "Supervisor caught crash and auto-restarted server")
assert_eq(cleanupsFired, 3, "Database state flushed before restart and after normal exit")
assert_eq(writtenFiles["logs/bankserver_crash.log"] ~= nil, true, "Crash log generated in logs/")
local crashLog = writtenFiles["logs/bankserver_crash.log"]
assert_eq(#crashLog > 0, true, "Crash line written to log file")
assert_eq(crashLog[1]:find("BankServer FATAL EXCEPTION") ~= nil, true, "Log mentions fatal exception details")

-- Case C: Clean operator termination (Ctrl+T / Terminated)
local termRuns = 0
ServiceGuard.runSupervisor("ArcadeServer", function()
    termRuns = termRuns + 1
    error("Terminated")
end, cleanup, testLogger, 0)

assert_eq(termRuns, 1, "Operator termination respected without looping")
assert_eq(cleanupsFired, 4, "State flushed on operator termination")

print(">>> All Service Guard & Watchdog tests passed successfully!")
return true
