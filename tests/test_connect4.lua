--[[
    Unit Test: Connect 4 Physics, Win Detection & AI (games/Drunken_Connect4.lua)
    Verifies column gravity, win detection across 4 axes, and tactical AI lookahead.
]]

package.path = "./?.lua;" .. package.path

local c4 = require("games.Drunken_Connect4")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Connect 4 Game Logic Tests ===")

-- 1. Board Creation & Gravity Drops
local b = c4.newBoard()
local r1 = c4.dropToken(b, 4, 1)
assert_eq(r1, 1, "First token in column 4 lands on bottom row 1")

local r2 = c4.dropToken(b, 4, 2)
assert_eq(r2, 2, "Second token in column 4 stacks on row 2")

for i = 3, 6 do c4.dropToken(b, 4, 1) end
local rFull = c4.dropToken(b, 4, 1)
assert_eq(rFull, nil, "Dropping into filled column returns nil")

-- 2. Horizontal Win Detection
local bHoriz = c4.newBoard()
c4.dropToken(bHoriz, 1, 1)
c4.dropToken(bHoriz, 2, 1)
c4.dropToken(bHoriz, 3, 1)
assert_eq(c4.checkWin(bHoriz, 1), false, "3 in a row is not a win")
c4.dropToken(bHoriz, 4, 1)
assert_eq(c4.checkWin(bHoriz, 1), true, "4 in a row horizontally is a win")

-- 3. Vertical Win Detection
local bVert = c4.newBoard()
for i = 1, 4 do c4.dropToken(bVert, 3, 2) end
assert_eq(c4.checkWin(bVert, 2), true, "4 in a row vertically is a win")
assert_eq(c4.checkWin(bVert, 1), false, "Opponent did not win")

-- 4. Diagonal Up Win Detection (/)
local bDiagUp = c4.newBoard()
-- Col 1: (1)
c4.dropToken(bDiagUp, 1, 1)
-- Col 2: (O), (1)
c4.dropToken(bDiagUp, 2, 2)
c4.dropToken(bDiagUp, 2, 1)
-- Col 3: (O), (O), (1)
c4.dropToken(bDiagUp, 3, 2)
c4.dropToken(bDiagUp, 3, 2)
c4.dropToken(bDiagUp, 3, 1)
-- Col 4: (O), (O), (O), (1)
c4.dropToken(bDiagUp, 4, 2)
c4.dropToken(bDiagUp, 4, 2)
c4.dropToken(bDiagUp, 4, 2)
c4.dropToken(bDiagUp, 4, 1)

assert_eq(c4.checkWin(bDiagUp, 1), true, "Diagonal up (/) 4 in a row detected")

-- 5. AI Tactical Lookahead (Win & Block)
-- A. AI Winning Move
local bAiWin = c4.newBoard()
c4.dropToken(bAiWin, 1, 2)
c4.dropToken(bAiWin, 2, 2)
c4.dropToken(bAiWin, 3, 2)
-- AI (2) can win on column 4!
local aiChoice = c4.getAiMove(bAiWin, 2, 1)
assert_eq(aiChoice, 4, "AI seizes immediate winning move on column 4")

-- B. AI Blocking Move
local bAiBlock = c4.newBoard()
c4.dropToken(bAiBlock, 5, 1)
c4.dropToken(bAiBlock, 6, 1)
c4.dropToken(bAiBlock, 7, 1)
-- Human (1) is about to win on column 4, AI must block!
local blockChoice = c4.getAiMove(bAiBlock, 2, 1)
assert_eq(blockChoice, 4, "AI detects threat and blocks human winning column 4")

print(">>> All Connect 4 tests passed successfully!\n")
return true
