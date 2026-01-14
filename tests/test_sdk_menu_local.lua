-- tests/test_sdk_menu_local.lua
-- Unit test for SDK.UI.drawMenu
-- Run with: lua5.3 tests/test_sdk_menu_local.lua (from repo root)

-- Mock Environment
_G.term = {}
_G.keys = { up = 200, down = 208, enter = 28 }
_G.colors = { white = 1, black = 32768, blue = 2048, cyan = 512, gray = 128, lightGray = 256, red = 16384, orange = 2, lime = 32, yellow = 16 }
_G.fs = {
    exists = function() return false end,
    open = function() return nil end
}
_G.textutils = { unserialize = function() return nil end, serialize = function() return "" end }
_G.rednet = { isOpen = function() return false end }
_G.peripheral = { find = function() return nil end, getName = function() return "" end }

-- Mock term
local termOutput = {}
function term.getSize() return 50, 20 end
function term.setCursorPos(x, y) end
function term.setTextColor(c) end
function term.setBackgroundColor(c) end
function term.write(text) table.insert(termOutput, text) end
function term.clear() end
function term.isColor() return true end

-- Mock os.pullEvent
-- We will queue events to simulate user input
local eventQueue = {
    { "key", keys.down },  -- Move selection down (to 2)
    { "key", keys.down },  -- Move selection down (to 3)
    { "key", keys.up },    -- Move selection up (to 2)
    { "key", keys.enter }  -- Select item 2
}
local eventIdx = 0

function os.pullEvent(filter)
    eventIdx = eventIdx + 1
    if eventIdx > #eventQueue then
        error("Test ran out of events!")
    end
    local ev = eventQueue[eventIdx]
    return table.unpack(ev)
end

-- Mock sleep
function sleep(t) end

-- Setup Package Path to find lib modules from root
package.path = "./?.lua;" .. package.path

-- Load SDK
local ok, SDK = pcall(require, "lib.sdk")
if not ok then
    print("Error loading SDK: " .. tostring(SDK))
    os.exit(1)
end

-- Test Execution
print("Testing SDK.UI.drawMenu...")

local options = {"Option 1", "Option 2", "Option 3"}
-- Initial selection 1
-- Inputs: Down (2), Down (3), Up (2), Enter (Select 2)

local result = SDK.UI.drawMenu(options, 1, 2, 4)

print("Result Index: " .. tostring(result))

if result == 2 then
    print("PASS: Selected correct index.")
else
    print("FAIL: Expected 2, got " .. tostring(result))
    os.exit(1)
end
