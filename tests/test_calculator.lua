--[[
    Unit Test: Calculator & Create Mod Engineering Tool (apps/calc.lua)
    Verifies:
    1. Math expression evaluator & syntax safety.
    2. Minecraft stack conversion (x64 math).
    3. Create Mod gear ratio calculations (speed up / step down).
    4. Create Mod Stress Units (SU) generator capacity and machine impact.
    5. Clean execution and module export.
]]

package.path = "./?.lua;./lib/?.lua;" .. package.path

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

local function assert_true(cond, desc)
    if not cond then
        error("FAILED [" .. desc .. "]: condition was false", 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Calculator & Create Mod Tool Tests ===")

local calc = require("apps.calc")
assert_true(type(calc) == "table", "apps/calc loaded as table")
assert_true(type(calc.run) == "function", "calc.run is callable")

-- 1. Math Evaluator Tests
local r1, err1 = calc.evaluateMath("2 + 2")
assert_eq(r1, 4, "2 + 2 = 4")

local r2, err2 = calc.evaluateMath("64 * 4 + 16")
assert_eq(r2, 272, "64 * 4 + 16 = 272")

local r3, err3 = calc.evaluateMath("100 / (2 + 3)")
assert_eq(r3, 20, "100 / (2 + 3) = 20")

local r4, err4 = calc.evaluateMath("os.execute('bad')")
assert_true(r4 == nil and err4 ~= nil, "Malicious characters blocked by evaluator")

-- 2. Minecraft Stack Conversion
assert_eq(calc.toStacks(0), "0 items", "0 items stacks correctly")
assert_eq(calc.toStacks(64), "1 stacks (1x64)", "64 items is 1 stack")
assert_eq(calc.toStacks(128), "2 stacks (2x64)", "128 items is 2 stacks")
assert_eq(calc.toStacks(272), "4 stacks + 16 (4x64 + 16)", "272 items is 4 stacks + 16")

-- 3. Create Gear Ratio (RPM) Tests
local ratioDirect = calc.calculateCreateRatio(16, 16)
assert_eq(ratioDirect.ratio, 1, "16 to 16 RPM is 1:1 ratio")

local ratioUp = calc.calculateCreateRatio(16, 128)
assert_eq(ratioUp.ratio, 8, "16 to 128 RPM is 8x ratio")
assert_true(#ratioUp.steps > 0, "Steps generated for 8x speed up")
assert_true(ratioUp.steps[1]:find("3 Large->Small", 1, true), "Recommends 3 cogwheel pairs for 8x")

local ratioDown = calc.calculateCreateRatio(128, 16)
assert_eq(ratioDown.ratio, 0.125, "128 to 16 RPM is 1/8x ratio")
assert_true(ratioDown.steps[1]:find("3 Small->Large", 1, true), "Recommends 3 small->large pairs for 1/8x")

-- 4. Create Stress Units (SU) Tests
-- Water Wheel
local suWw = calc.calculateCreateSU("ww 8")
assert_true(suWw ~= nil, "Waterwheel parsed successfully")
assert_true(suWw.res:find("256 SU"), "Water wheel at 8 RPM generates 256 SU")

-- Large Water Wheel
local suLww = calc.calculateCreateSU("lww 8")
assert_true(suLww ~= nil, "Large waterwheel parsed successfully")
assert_true(suLww.res:find("1024 SU"), "Large water wheel at 8 RPM generates 1024 SU")

-- Windmill
local suWind = calc.calculateCreateSU("wind 16")
assert_true(suWind ~= nil, "Windmill parsed successfully")
assert_true(suWind.res:find("8192 SU"), "Windmill with 16 sails generates 8192 SU")

-- Steam Engine
local suSteam = calc.calculateCreateSU("steam 1 2")
assert_true(suSteam ~= nil, "Steam boiler parsed successfully")
assert_true(suSteam.res:find("4096 SU"), "Level 1 Boiler with 2 engines generates 4096 SU")

local suSteam3 = calc.calculateCreateSU("steam 3 1")
assert_true(suSteam3 ~= nil, "Level 3 Steam boiler parsed")
assert_true(suSteam3.res:find("65536 SU"), "Level 3 Boiler generates 65536 SU")

-- Machine Impact
local suPress = calc.calculateCreateSU("press 128")
assert_true(suPress ~= nil, "Mechanical press parsed")
assert_true(suPress.res:find("1024 SU"), "Mechanical press at 128 RPM has 1024 SU impact")

local suCrusher = calc.calculateCreateSU("2 crusher 256")
assert_true(suCrusher ~= nil, "Crushing wheels parsed")
assert_true(suCrusher.res:find("8192 SU"), "2 Crushing wheels at 256 RPM has 8192 SU impact")

-- Custom formula
local suMath = calc.calculateCreateSU("2048 / 8")
assert_true(suMath ~= nil, "Custom formula parsed")
assert_true(suMath.res:find("256.00"), "2048 / 8 = 256 max RPM")

print(">>> All Calculator & Create Mod Tool tests passed successfully!")
