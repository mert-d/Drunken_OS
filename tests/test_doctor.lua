--[[
    Unit Test: System Doctor Diagnostics & Auto-Repair (apps/doctor.lua)
    Verifies hardware profiling, peripheral audits, latency benchmarks,
    filesystem write tests, and 1-click auto-repair routines.
]]

package.path = "./?.lua;" .. package.path
package.path = "/?.lua;" .. package.path

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running System Doctor Diagnostics Tests ===")

-- Mock Environment
local tempFiles = {
    [".doctortest.tmp"] = nil,
    ["orphaned1.tmp"] = "dummy1",
    ["orphaned2.tmp"] = "dummy2",
    ["normal.lua"] = "print('hello')"
}

local deletedFiles = {}
local openedModems = {}
local dnsFlushed = false

_G.term = {
    getSize = function() return 51, 19 end,
    isColor = function() return true end,
    setCursorPos = function() end,
    setTextColor = function() end,
    setBackgroundColor = function() end,
    clear = function() end,
    write = function() end,
    clearLine = function() end
}

_G.os = {
    getComputerID = function() return 42 end,
    epoch = function(m) return 1000 end,
    clock = function() return 10 end,
    pullEvent = function() return "terminate" end
}

_G.fs = {
    getFreeSpace = function(p) return 1024 * 500 end, -- 500 KB
    open = function(path, mode)
        if mode == "w" then
            return {
                write = function(s) end,
                close = function() tempFiles[path] = "written" end
            }
        end
        return nil
    end,
    delete = function(path)
        tempFiles[path] = nil
        table.insert(deletedFiles, path)
    end,
    list = function(dir)
        local l = {}
        for f in pairs(tempFiles) do table.insert(l, f) end
        return l
    end
}

local mockModem = {
    isWireless = function() return true end
}

_G.peripheral = {
    getNames = function() return { "back", "top" } end,
    getType = function(name)
        if name == "back" then return "modem" end
        if name == "top" then return "speaker" end
        return nil
    end,
    wrap = function(name)
        if name == "back" then return mockModem end
        return nil
    end
}

_G.rednet = {
    isOpen = function() return true end,
    open = function(side) table.insert(openedModems, side) end,
    lookup = function(proto, host)
        if proto == "SimpleMail" then return 10
        elseif proto == "SimpleChat" then return 11
        elseif proto == "DB_Bank" then return 12
        elseif proto == "ArcadeGames" then return 13
        elseif proto == "auth.secure.v1" then return 14
        end
        return nil
    end
}

local doctor = require("apps.doctor")

-- 1. Desktop Profile Diagnosis
local report = doctor.diagnose()
assert_eq(type(report), "table", "Doctor returns report table")
assert_eq(report.hardware[1].name, "Terminal Profile", "First hardware item is Terminal Profile")
assert_eq(report.hardware[1].val:find("Advanced Computer") ~= nil, true, "Terminal identified as Advanced Computer on 51x19")
assert_eq(report.hardware[2].val, "16-Color Palette", "Display engine identified as 16-Color Palette")
assert_eq(report.hardware[3].val, "#42", "Computer ID is #42")

-- 2. Peripheral Audit
local modemItem = report.peripherals[1]
assert_eq(modemItem.status, "OK", "Modem status is OK")
assert_eq(modemItem.val:find("Wireless %(back%)") ~= nil, true, "Wireless modem on back detected")

local speakerItem = report.peripherals[2]
assert_eq(speakerItem.status, "OK", "Speaker status is OK")
assert_eq(speakerItem.val:find("top") ~= nil, true, "Speaker on top detected")

-- 3. Network & Server Latencies
assert_eq(report.network[1].status, "OK", "Rednet channel is Active")
assert_eq(#report.network, 6, "Report audited 5 world spawn servers + Rednet State")
assert_eq(report.network[2].val:find("ID 10") ~= nil, true, "Mainframe Gateway resolved ID 10")
assert_eq(report.network[4].val:find("ID 12") ~= nil, true, "DB Bank Server resolved ID 12")

-- 4. Storage & Filesystem
assert_eq(report.storage[1].val, "500 KB", "Free space correctly reported as 500 KB")
assert_eq(report.storage[2].val, "Read/Write Verified", "Filesystem write test passed")
assert_eq(report.storage[3].val:find("2 orphaned %.tmp") ~= nil, true, "2 orphaned .tmp files identified")
assert_eq(report.storage[3].status, "WARN", "Orphaned files trigger WARN status")

-- 5. Overall Health with Warnings
assert_eq(report.overallHealth, "Operational (Warnings)", "Overall health with orphaned files is Operational (Warnings)")

-- 6. Pocket Computer Scaling
term.getSize = function() return 26, 20 end
local pocketReport = doctor.diagnose()
assert_eq(pocketReport.hardware[1].val:find("Pocket Computer") ~= nil, true, "Terminal identified as Pocket Computer on 26x20")

-- 7. 1-Click Auto-Repair Routine
openedModems = {}
deletedFiles = {}
local repairs = doctor.autoRepair()
assert_eq(#repairs >= 3, true, "Auto-repair executed multiple remediation tasks")
assert_eq(#openedModems, 1, "Re-opened modem on back")
assert_eq(openedModems[1], "back", "Modem side is back")
assert_eq(#deletedFiles >= 2, true, "Purged both orphaned .tmp files")
assert_eq(tempFiles["orphaned1.tmp"], nil, "orphaned1.tmp removed from disk")
assert_eq(tempFiles["orphaned2.tmp"], nil, "orphaned2.tmp removed from disk")
assert_eq(tempFiles["normal.lua"], "print('hello')", "normal.lua untouched by temp cleanup")

-- 8. Re-Audit After Auto-Repair
local cleanReport = doctor.diagnose()
assert_eq(cleanReport.storage[3].val, "Clean (0 orphaned)", "Temp file cleanup reports Clean")
assert_eq(cleanReport.storage[3].status, "OK", "Temp file status now OK")
assert_eq(cleanReport.overallHealth, "100% Healthy (All Systems Nominal)", "Overall health now 100% Healthy")

print(">>> All System Doctor Diagnostics tests passed successfully!\n")
return true
