--[[
    Unit Test: Calculator & Create Mod Ratio Logic (apps/calc.lua)
    Verifies math expression evaluation, stack calculation, and gear ratio logic.
]]

package.path = "./?.lua;" .. package.path

local calc = require("apps.calc")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Calculator & Create Mod Tests ===")

-- 1. Standard Arithmetic
local r1 = calc.evaluateMath("64 * 4 + 16")
assert_eq(r1, 272, "Basic arithmetic: 64*4+16")

local r2 = calc.evaluateMath("(1200 - 450) / 2")
assert_eq(r2, 375, "Parentheses: (1200-450)/2")

local r3 = calc.evaluateMath("2^8")
assert_eq(r3, 256, "Exponentiation: 2^8")

-- 2. Injection & Syntax Safety
local badRes, badErr = calc.evaluateMath("os.shutdown()")
assert_eq(badRes, nil, "Malicious code rejected")
assert_eq(badErr ~= nil, true, "Safety error reported for code injection")

-- 3. Minecraft Stacks Division
local s1 = calc.toStacks(272)
assert_eq(s1, "4 stacks + 16 (4x64 + 16)", "272 items = 4 stacks + 16")

local s2 = calc.toStacks(128)
assert_eq(s2, "2 stacks (2x64)", "128 items = exactly 2 stacks")

local s3 = calc.toStacks(45)
assert_eq(s3, "45 items", "45 items = under 1 stack")

-- 4. Create Mod Rotational Gear Ratios
-- 16 RPM -> 64 RPM (4x speed up = 2 cogwheel pairs)
local gear1 = calc.calculateCreateRatio(16, 64)
assert_eq(gear1.ratio, 4, "16 to 64 RPM is 4x ratio")
assert_eq(gear1.steps[1]:find("Use 2 Large->Small Cogwheel", 1, true) ~= nil, true, "Recommends 2 large-to-small pairs")

-- 128 RPM -> 32 RPM (0.25x step down = 2 cogwheel pairs)
local gear2 = calc.calculateCreateRatio(128, 32)
assert_eq(gear2.ratio, 0.25, "128 to 32 RPM is 0.25x ratio")
assert_eq(gear2.steps[1]:find("Use 2 Small->Large Cogwheel", 1, true) ~= nil, true, "Recommends 2 small-to-large pairs")

-- 16 RPM -> 16 RPM (1:1 direct shaft)
local gear3 = calc.calculateCreateRatio(16, 16)
assert_eq(gear3.ratio, 1, "16 to 16 RPM is 1:1 ratio")
assert_eq(gear3.description:find("Direct shaft", 1, true) ~= nil, true, "Recommends direct shaft")

print(">>> All Calculator & Create Mod tests passed successfully!\n")
return true
