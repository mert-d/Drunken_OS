--[[
    Unit Test: Theme & Color Subsystem
    Verifies palette presets, blit conversion, and safeColor fallback logic.
]]

package.path = "./?.lua;" .. package.path
local theme = require("lib.theme")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Theme & Color Tests ===")

-- 1. Default Colors
assert_eq(type(theme.bg), "number", "theme.bg is numeric")
assert_eq(type(theme.text), "number", "theme.text is numeric")
assert_eq(type(theme.highlightBg), "number", "theme.highlightBg is numeric")

-- 2. Presets
assert_eq(type(theme.presets["Default"]), "table", "Default preset exists")
assert_eq(type(theme.presets["Red Alert"]), "table", "Red Alert preset exists")
assert_eq(type(theme.presets["Matrix"]), "table", "Matrix preset exists")
assert_eq(type(theme.presets["Midnight"]), "table", "Midnight preset exists")

-- 3. Blit Conversion
assert_eq(theme.toBlit(1), "0", "White to blit '0'")
assert_eq(theme.toBlit(2), "1", "Orange to blit '1'")
assert_eq(theme.toBlit(32768), "f", "Black to blit 'f'")
assert_eq(theme.toBlit(999999), "0", "Unknown color fallback to '0'")

-- 4. Game colors
assert_eq(type(theme.game.snake), "number", "theme.game.snake is numeric")
assert_eq(type(theme.game.fruit), "number", "theme.game.fruit is numeric")
assert_eq(type(theme.game.wall), "number", "theme.game.wall is numeric")

-- 5. safeColor
assert_eq(theme.safeColor("white", 1), 1, "safeColor returns fallback or valid color")

print(">>> All Theme tests passed successfully!\n")
return true
