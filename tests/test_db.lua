--[[
    Unit Test: Database & Persistence Layer (lib/db.lua)
    Verifies atomic saves, crash recovery from .tmp, and dirty tracking.
]]

package.path = "./?.lua;" .. package.path

-- Setup lightweight mock of ComputerCraft fs and textutils for headless execution
local storage = {}

local mockFs = {
    exists = function(path) return storage[path] ~= nil end,
    delete = function(path) storage[path] = nil end,
    move = function(from, to)
        if storage[from] then
            storage[to] = storage[from]
            storage[from] = nil
        end
    end,
    open = function(path, mode)
        if mode == "w" then
            return {
                write = function(content) storage[path] = content end,
                close = function() end
            }
        elseif mode == "r" then
            if not storage[path] then return nil end
            return {
                readAll = function() return storage[path] end,
                close = function() end
            }
        end
        return nil
    end
}

local mockTextutils = {
    serialize = function(tbl)
        local parts = {}
        for k, v in pairs(tbl) do
            table.insert(parts, string.format("%s=%q", tostring(k), tostring(v)))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end,
    unserialize = function(str)
        local fn = load("return " .. str)
        if fn then return fn() end
        return nil
    end
}

if not _G.fs then _G.fs = mockFs end
if not _G.textutils then _G.textutils = mockTextutils end

local DB = require("lib.db")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running DB & Persistence Tests ===")

-- 1. Save and Load
local testData = { name = "Steve", balance = "100" }
local okSave = DB.saveTableToFile("test_db.lua", testData)
assert_eq(okSave, true, "Save table succeeds")
assert_eq(storage["test_db.lua"] ~= nil, true, "File written to storage")

local loaded = DB.loadTableFromFile("test_db.lua")
assert_eq(loaded.name, "Steve", "Loaded field name")
assert_eq(loaded.balance, "100", "Loaded field balance")

-- 2. Crash Recovery: Main file deleted, .tmp exists
storage["recovered.lua"] = nil
storage["recovered.lua.tmp"] = '{recovered="true"}'

local recovered = DB.loadTableFromFile("recovered.lua")
assert_eq(recovered.recovered, "true", "Crash recovery restores from .tmp")
assert_eq(storage["recovered.lua"] ~= nil, true, "Restored file moved into place")
assert_eq(storage["recovered.lua.tmp"] == nil, true, ".tmp removed after recovery")

-- 3. Dirty Tracker
local dbStore = {
    ["db1.lua"] = { key = "val1" },
    ["db2.lua"] = { key = "val2" }
}

local pointers = {
    ["db1.lua"] = function() return dbStore["db1.lua"] end,
    ["db2.lua"] = function() return dbStore["db2.lua"] end
}

local tracker = DB.createDirtyTracker(pointers)
assert_eq(tracker.hasPendingSaves(), false, "Initially no pending saves")

tracker.queueSave("db1.lua")
assert_eq(tracker.hasPendingSaves(), true, "Pending saves detected after queueSave")

tracker.backgroundSave()
assert_eq(tracker.hasPendingSaves(), false, "No pending saves after backgroundSave")
assert_eq(storage["db1.lua"] ~= nil, true, "db1 written by background save")

print(">>> All DB & Persistence tests passed successfully!\n")
return true
