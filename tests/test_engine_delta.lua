--[[
    Unit Test: Engine Delta-Row Terminal Buffering (lib/engine.lua)
    Verifies that identical screen rows are suppressed from redundant term.blit calls,
    slashing network packet bandwidth in ComputerCraft.
]]

package.path = "./?.lua;" .. package.path

local blitCallCount = 0
local cursorCalls = {}

_G.term = {
    getSize = function() return 10, 10 end,
    setCursorPos = function(x, y)
        table.insert(cursorCalls, { x = x, y = y })
    end,
    blit = function(txt, fg, bg)
        blitCallCount = blitCallCount + 1
    end
}

local Engine = require("lib.engine")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Engine Delta-Row Buffer Tests ===")

local map = Engine.newMap(10, 10, { char = ".", fg = 1, bg = 32768 })
local camera = Engine.newCamera(1, 1, 10, 10)

Engine.Renderer.resetStats()
blitCallCount = 0

-- 1. First frame: All 10 lines must be drawn
Engine.Renderer.draw(map, camera, 1, 1)
local s1 = Engine.Renderer.getStats()
assert_eq(s1.drawnLines, 10, "Frame 1 drawn lines")
assert_eq(s1.skippedLines, 0, "Frame 1 skipped lines")
assert_eq(blitCallCount, 10, "Frame 1 term.blit call count")

-- 2. Second frame (Identical): 0 lines drawn, all 10 lines skipped!
Engine.Renderer.draw(map, camera, 1, 1)
local s2 = Engine.Renderer.getStats()
assert_eq(s2.drawnLines, 10, "Frame 2 total drawn remains 10")
assert_eq(s2.skippedLines, 10, "Frame 2 skipped lines is 10")
assert_eq(blitCallCount, 10, "Frame 2 term.blit call count stayed at 10 (0 packets sent)")

-- 3. Third frame: Modify tile on row 5 only
map:set(4, 5, { char = "@", fg = 2, bg = 32768 })
Engine.Renderer.draw(map, camera, 1, 1)
local s3 = Engine.Renderer.getStats()
assert_eq(s3.drawnLines, 11, "Frame 3 only 1 modified line drawn")
assert_eq(s3.skippedLines, 19, "Frame 3 9 lines skipped")
assert_eq(blitCallCount, 11, "Only 1 term.blit packet sent for row 5")

-- 4. Invalidation forces full redraw
Engine.Renderer.invalidate()
Engine.Renderer.draw(map, camera, 1, 1)
local s4 = Engine.Renderer.getStats()
assert_eq(s4.drawnLines, 21, "Invalidate caused all 10 lines to redraw")
assert_eq(blitCallCount, 21, "term.blit issued for full screen")

print(">>> All Engine Delta Buffer tests passed successfully!\n")
return true
