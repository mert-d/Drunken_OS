--[[
    Drunken Battleship (games/Drunken_Battleship.lua)
    Version: 1.0
    
    A touch-friendly 6x6 naval tactical combat game for Pocket Computers
    and Desktops. Features Auto-Deploy, Single Player vs Naval AI, and
    Wireless P2P Multiplayer over Rednet.
]]

local theme = require("lib.theme")
local utils = require("lib.utils")
local scoreCache = require("lib.score_cache")
local ok_sound, Sound = pcall(require, "lib.sound")
if not ok_sound or type(Sound) ~= "table" then
    Sound = { playClick = function() end, playNote = function() end, playSuccess = function() end }
end

local SIZE = 6
local SHIPS = {
    { name = "Cruiser", len = 3 },
    { name = "Destroyer", len = 2 },
    { name = "Submarine", len = 2 },
    { name = "Patrol", len = 1 }
}

local game = {
    _VERSION = 1.0,
    name = "Battleship"
}

--- Creates an empty 6x6 grid.
function game.newGrid()
    local g = {}
    for x = 1, SIZE do
        g[x] = {}
        for y = 1, SIZE do
            g[x][y] = { hasShip = false, probed = false, hit = false, shipName = nil }
        end
    end
    return g
end

--- Automatically places the fleet tactically without overlaps.
function game.autoDeployFleet()
    local grid = game.newGrid()
    for _, ship in ipairs(SHIPS) do
        local placed = false
        local attempts = 0
        while not placed and attempts < 100 do
            attempts = attempts + 1
            local isHoriz = math.random(1, 2) == 1
            local x = isHoriz and math.random(1, SIZE - ship.len + 1) or math.random(1, SIZE)
            local y = isHoriz and math.random(1, SIZE) or math.random(1, SIZE - ship.len + 1)
            
            -- Verify collision
            local canPlace = true
            for i = 0, ship.len - 1 do
                local cx = isHoriz and (x + i) or x
                local cy = isHoriz and y or (y + i)
                if grid[cx][cy].hasShip then
                    canPlace = false
                    break
                end
            end
            
            if canPlace then
                for i = 0, ship.len - 1 do
                    local cx = isHoriz and (x + i) or x
                    local cy = isHoriz and y or (y + i)
                    grid[cx][cy].hasShip = true
                    grid[cx][cy].shipName = ship.name
                end
                placed = true
            end
        end
    end
    return grid
end

--- Fires at a coordinate. Returns "hit", "miss", or "already_fired", and optional shipName.
function game.fireShot(grid, x, y)
    if x < 1 or x > SIZE or y < 1 or y > SIZE then return "invalid" end
    local cell = grid[x][y]
    if cell.probed then return "already_fired" end
    
    cell.probed = true
    if cell.hasShip then
        cell.hit = true
        return "hit", cell.shipName
    else
        return "miss", nil
    end
end

--- Checks if all ships on a grid are destroyed.
function game.isFleetSunk(grid)
    for x = 1, SIZE do
        for y = 1, SIZE do
            if grid[x][y].hasShip and not grid[x][y].hit then
                return false
            end
        end
    end
    return true
end

--- Smart Naval AI targeting with hunt-and-target mode.
function game.getAiTarget(enemyRadar)
    -- 1. Check if there is an active hit with adjacent unprobed waters
    for x = 1, SIZE do
        for y = 1, SIZE do
            if enemyRadar[x][y].hit then
                local adj = { {x=x+1, y=y}, {x=x-1, y=y}, {x=x, y=y+1}, {x=x, y=y-1} }
                for _, pos in ipairs(adj) do
                    if pos.x >= 1 and pos.x <= SIZE and pos.y >= 1 and pos.y <= SIZE then
                        if not enemyRadar[pos.x][pos.y].probed then
                            return pos.x, pos.y
                        end
                    end
                end
            end
        end
    end
    
    -- 2. Random unprobed selection
    local unprobed = {}
    for x = 1, SIZE do
        for y = 1, SIZE do
            if not enemyRadar[x][y].probed then
                table.insert(unprobed, { x = x, y = y })
            end
        end
    end
    
    if #unprobed > 0 then
        local pick = unprobed[math.random(1, #unprobed)]
        return pick.x, pick.y
    end
    return 1, 1
end

function game.drawRadar(enemyRadar, myFleet, curX, curY, statusText, context)
    local w, h = term.getSize()
    context.drawWindow("Drunken Battleship")
    
    local startX = 3
    local startY = 3
    
    -- Status Banner
    term.setCursorPos(startX, startY)
    term.setTextColor(theme.highlightText or colors.yellow)
    term.write((statusText or "Naval Radar"):sub(1, w - startX))
    
    -- Enemy Waters Radar Grid
    term.setCursorPos(startX, startY + 2)
    term.setTextColor(theme.prompt or colors.cyan)
    term.write("   1 2 3 4 5 6  (Radar)")
    
    for y = 1, SIZE do
        term.setCursorPos(startX, startY + 2 + y)
        term.setTextColor(theme.prompt or colors.cyan)
        term.write(string.char(64 + y) .. " ") -- A, B, C, D, E, F
        
        for x = 1, SIZE do
            local cell = enemyRadar[x][y]
            if x == curX and y == curY then
                term.setBackgroundColor(colors.gray)
            else
                term.setBackgroundColor(colors.black)
            end
            
            if cell.hit then
                term.setTextColor(colors.red)
                term.write("X ")
            elseif cell.probed then
                term.setTextColor(colors.lightGray)
                term.write("O ")
            else
                term.setTextColor(colors.blue)
                term.write("~ ")
            end
        end
        term.setBackgroundColor(colors.black)
    end
    
    -- Friendly Fleet Status
    local fleetY = startY + 10
    if fleetY < h - 2 then
        term.setCursorPos(startX, fleetY)
        term.setTextColor(theme.text or colors.white)
        term.write("Friendly Fleet Status:")
        
        local damageCount = 0
        local totalTiles = 8
        for x = 1, SIZE do
            for y = 1, SIZE do
                if myFleet[x][y].hasShip and myFleet[x][y].hit then
                    damageCount = damageCount + 1
                end
            end
        end
        
        local remaining = totalTiles - damageCount
        term.setCursorPos(startX, fleetY + 1)
        term.setTextColor(remaining > 3 and colors.lime or colors.red)
        term.write(string.format("Operational Ships: %d/8 tiles", remaining))
    end
    
    -- Footer Hint
    term.setCursorPos(2, h - 1)
    term.setTextColor(theme.mutedText or colors.gray)
    if w <= 30 then
        term.write("Arrows+Enter [Q]Quit")
    else
        term.write("Tap Radar Cell or Arrows+Enter - [Q] Quit")
    end
end

function game.run(context)
    context = context or {}
    if not context.drawWindow then
        context.drawWindow = function(t) utils.drawWindow(t, context) end
    end
    
    local w, h = term.getSize()
    local username = (context.parent and context.parent.username) or "Captain"
    
    -- Mode Select
    context.drawWindow("Battleship - Mode")
    term.setCursorPos(2, 4)
    term.setTextColor(theme.prompt or colors.yellow)
    term.write("Select Battle Theatre:")
    
    local modes = { "Single Player (vs Naval AI)", "Wireless P2P Naval Combat", "Back" }
    local choice = 1
    if context.drawMenu then
        choice = context.drawMenu(modes, 1, 2, 6)
    else
        choice = 1
    end
    if choice == 3 then return end
    
    local isMultiplayer = (choice == 2)
    local opponentId = nil
    local myTurn = true
    
    if isMultiplayer then
        if not rednet.isOpen() then
            local m = peripheral.find("modem")
            if m then rednet.open(peripheral.getName(m)) end
        end
        context.drawWindow("Naval Matchmaking")
        term.setCursorPos(2, 4)
        term.setTextColor(theme.text or colors.white)
        term.write("Pinging for opposing fleet...")
        
        rednet.broadcast({ type = "bs_lobby", user = username }, "Battleship_P2P")
        local sender, msg = rednet.receive("Battleship_P2P", 5)
        if sender and msg and msg.type == "bs_join" then
            opponentId = sender
            myTurn = true
            rednet.send(opponentId, { type = "bs_start" }, "Battleship_P2P")
        elseif sender and msg and msg.type == "bs_lobby" and sender ~= os.getComputerID() then
            opponentId = sender
            myTurn = false
            rednet.send(opponentId, { type = "bs_join", user = username }, "Battleship_P2P")
        else
            context.showMessage("P2P", "No enemy fleet found.\nEngaging Naval AI.")
            isMultiplayer = false
            myTurn = true
        end
    end
    
    -- Deploy Fleet
    local myFleet = game.autoDeployFleet()
    local enemyRadar = game.newGrid()
    local enemyFleet = (not isMultiplayer) and game.autoDeployFleet() or nil
    
    local curX, curY = 1, 1
    local gameOver = false
    local winner = nil
    local statusMsg = myTurn and "Target coordinates and fire!" or "Enemy fleet targeting..."
    
    while not gameOver do
        game.drawRadar(enemyRadar, myFleet, curX, curY, statusMsg, context)
        
        if myTurn then
            local event, p1, p2, p3 = os.pullEvent()
            local fireX, fireY = nil, nil
            
            if event == "key" then
                local k = p1
                if k == keys.up then curY = math.max(1, curY - 1)
                elseif k == keys.down then curY = math.min(SIZE, curY + 1)
                elseif k == keys.left then curX = math.max(1, curX - 1)
                elseif k == keys.right then curX = math.min(SIZE, curX + 1)
                elseif k == keys.enter or k == keys.space then
                    fireX, fireY = curX, curY
                elseif k == keys.q then
                    if isMultiplayer and opponentId then
                        rednet.send(opponentId, { type = "bs_quit" }, "Battleship_P2P")
                    end
                    break
                end
            elseif event == "mouse_click" then
                local btn, cx, cy = p1, p2, p3
                local startX = 3
                local startY = 5
                if cy >= startY + 1 and cy <= startY + SIZE then
                    local gridY = cy - startY
                    if cx >= startX + 2 and cx <= startX + 2 + (SIZE * 2) then
                        local gridX = math.floor((cx - (startX + 2)) / 2) + 1
                        if gridX >= 1 and gridX <= SIZE and gridY >= 1 and gridY <= SIZE then
                            curX, curY = gridX, gridY
                            fireX, fireY = gridX, gridY
                        end
                    end
                end
            end
            
            if fireX and fireY then
                if not enemyRadar[fireX][fireY].probed then
                    Sound.playNote("snare", 0.8, 10)
                    if not isMultiplayer then
                        -- AI Opponent evaluation
                        local res, ship = game.fireShot(enemyFleet, fireX, fireY)
                        enemyRadar[fireX][fireY].probed = true
                        if res == "hit" then
                            enemyRadar[fireX][fireY].hit = true
                            statusMsg = "DIRECT HIT on " .. (ship or "Warship") .. "!"
                            Sound.playNote("bass", 1.5, 4)
                            if game.isFleetSunk(enemyFleet) then
                                gameOver = true
                                winner = "Player"
                                Sound.playSuccess()
                            end
                        else
                            statusMsg = "Splash! Shot missed."
                            Sound.playNote("chime", 0.5, 8)
                            myTurn = false
                        end
                    else
                        -- P2P Shot transmission
                        rednet.send(opponentId, { type = "bs_fire", x = fireX, y = fireY }, "Battleship_P2P")
                        local sender, res = rednet.receive("Battleship_P2P", 2.0)
                        if sender == opponentId and res and res.type == "bs_result" then
                            enemyRadar[fireX][fireY].probed = true
                            if res.hit then
                                enemyRadar[fireX][fireY].hit = true
                                statusMsg = "DIRECT HIT on " .. (res.ship or "ship") .. "!"
                                Sound.playNote("bass", 1.5, 4)
                                if res.fleetSunk then
                                    gameOver = true
                                    winner = "Player"
                                    Sound.playSuccess()
                                end
                            else
                                statusMsg = "Splash! Shot missed."
                                Sound.playNote("chime", 0.5, 8)
                                myTurn = false
                            end
                        else
                            statusMsg = "Missile launched..."
                            myTurn = false
                        end
                    end
                else
                    statusMsg = "Already probed that sector!"
                end
            end
        else
            -- Opponent Turn
            if not isMultiplayer then
                sleep(0.6)
                local aiX, aiY = game.getAiTarget(myFleet)
                local res, ship = game.fireShot(myFleet, aiX, aiY)
                if res == "hit" then
                    statusMsg = string.format("WARNING: Enemy struck %s at %s%d!", ship or "ship", string.char(64+aiY), aiX)
                    Sound.playNote("bass", 1.2, 5)
                    if game.isFleetSunk(myFleet) then
                        gameOver = true
                        winner = "Opponent"
                        Sound.playNote("bass", 1.5, 3)
                    end
                else
                    statusMsg = string.format("Enemy missed at %s%d! Your turn.", string.char(64+aiY), aiX)
                    Sound.playNote("chime", 0.4, 8)
                    myTurn = true
                end
            else
                local timer = os.startTimer(0.5)
                local waitStart = os.epoch("utc")
                while not myTurn and not gameOver do
                    local event, p1, p2, p3 = os.pullEvent()
                    if event == "rednet_message" and p1 == opponentId and p3 == "Battleship_P2P" then
                        local msg = p2
                        if msg and msg.type == "bs_fire" then
                            local res, ship = game.fireShot(myFleet, msg.x, msg.y)
                            local sunk = game.isFleetSunk(myFleet)
                            rednet.send(opponentId, { type = "bs_result", hit = (res == "hit"), ship = ship, fleetSunk = sunk }, "Battleship_P2P")
                            if res == "hit" then
                                statusMsg = string.format("Enemy hit your %s!", ship or "ship")
                                if sunk then
                                    gameOver = true
                                    winner = "Opponent"
                                end
                            else
                                statusMsg = "Enemy missed! Your turn."
                                myTurn = true
                            end
                            break
                        elseif msg and msg.type == "bs_quit" then
                            gameOver = true
                            winner = "Player"
                            if context.showMessage then
                                context.showMessage("P2P", "Enemy admiral retreated!\nVictory by forfeit.")
                            end
                            break
                        end
                    elseif event == "key" and p1 == keys.q then
                        if opponentId then
                            rednet.send(opponentId, { type = "bs_quit" }, "Battleship_P2P")
                        end
                        gameOver = true
                        break
                    elseif event == "timer" and p1 == timer then
                        if os.epoch("utc") - waitStart > 45000 then
                            gameOver = true
                            if context.showMessage then
                                context.showMessage("P2P", "Opponent timed out / out of range.")
                            end
                            break
                        end
                        timer = os.startTimer(0.5)
                    end
                end
            end
        end
    end
    
    -- Game Over
    local winBanner = (winner == "Player") and "NAVAL VICTORY! Enemy Fleet Destroyed!" or "DEFEAT! Your Fleet Has Sunk."
    local finalScore = (winner == "Player") and 150 or 30
    scoreCache.recordScore("Drunken_Battleship", finalScore, username)
    
    game.drawRadar(enemyRadar, myFleet, curX, curY, winBanner, context)
    term.setCursorPos(3, 4)
    term.setTextColor(colors.yellow)
    term.write("Personal Best: " .. scoreCache.getPersonalBest("Drunken_Battleship"))
    
    sleep(2.0)
    while true do
        local e = os.pullEvent()
        if e == "key" or e == "mouse_click" then break end
    end
end

return game
