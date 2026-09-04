--[[
    Unit Test: Battleship Tactical Combat & AI (games/Drunken_Battleship.lua)
    Verifies fleet auto-deployment, missile strike evaluation, fleet destruction, and AI hunt mode.
]]

package.path = "./?.lua;" .. package.path

local bs = require("games.Drunken_Battleship")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Battleship Combat Tests ===")

-- 1. Fleet Deployment Verification
local fleet = bs.autoDeployFleet()
local shipTiles = 0
for x = 1, 6 do
    for y = 1, 6 do
        if fleet[x][y].hasShip then
            shipTiles = shipTiles + 1
        end
    end
end
assert_eq(shipTiles, 8, "Fleet auto-deployed exactly 8 ship tiles (Cruiser 3, Destroyer 2, Sub 2, Patrol 1)")

-- 2. Missile Firing Evaluation
local grid = bs.newGrid()
grid[2][3].hasShip = true
grid[2][3].shipName = "Cruiser"

local res1, ship1 = bs.fireShot(grid, 2, 3)
assert_eq(res1, "hit", "Direct hit detected")
assert_eq(ship1, "Cruiser", "Hit identified Cruiser")
assert_eq(grid[2][3].hit, true, "Cell marked as hit")

local res2, ship2 = bs.fireShot(grid, 1, 1)
assert_eq(res2, "miss", "Water shot is a miss")
assert_eq(grid[1][1].hit, false, "Water cell not marked as hit")

local res3 = bs.fireShot(grid, 2, 3)
assert_eq(res3, "already_fired", "Cannot fire twice at same coordinate")

-- 3. Fleet Destruction Condition
assert_eq(bs.isFleetSunk(fleet), false, "Fleet is not sunk initially")

-- Hit all ship tiles in fleet
for x = 1, 6 do
    for y = 1, 6 do
        if fleet[x][y].hasShip then
            fleet[x][y].hit = true
        end
    end
end
assert_eq(bs.isFleetSunk(fleet), true, "Fleet is declared sunk when all 8 tiles destroyed")

-- 4. Naval AI Targeting (Hunt Mode)
local radar = bs.newGrid()
-- Simulate a hit at (3, 3)
radar[3][3].probed = true
radar[3][3].hit = true

local targetX, targetY = bs.getAiTarget(radar)
local isAdjacent = (math.abs(targetX - 3) + math.abs(targetY - 3)) == 1
assert_eq(isAdjacent, true, "AI enters Hunt Mode and targets cell adjacent to hit at (3,3)")

print(">>> All Battleship tests passed successfully!\n")
return true
