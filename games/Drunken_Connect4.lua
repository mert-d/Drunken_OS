--[[
    Drunken Connect 4 (games/Drunken_Connect4.lua)
    Version: 1.0
    
    A touch-friendly 7x6 wireless turn-based board game for Pocket Computers
    and Desktops. Features Single-Player vs Smart AI and Wireless P2P Multiplayer.
]]

local theme = require("lib.theme")
local utils = require("lib.utils")
local scoreCache = require("lib.score_cache")

local COLS = 7
local ROWS = 6
local P1 = 1 -- Yellow / 'O'
local P2 = 2 -- Red / 'X'

local game = {
    _VERSION = 1.0,
    name = "Connect 4"
}

--- Creates an empty 7x6 board.
function game.newBoard()
    local b = {}
    for c = 1, COLS do
        b[c] = {}
        for r = 1, ROWS do
            b[c][r] = 0
        end
    end
    return b
end

--- Drops a token into a column. Returns row (1..ROWS) or nil if full.
function game.dropToken(board, col, player)
    if col < 1 or col > COLS then return nil end
    for r = 1, ROWS do
        if board[col][r] == 0 then
            board[col][r] = player
            return r
        end
    end
    return nil
end

--- Checks if a player has connected 4 in any direction.
function game.checkWin(board, p)
    -- 1. Horizontal
    for r = 1, ROWS do
        for c = 1, COLS - 3 do
            if board[c][r] == p and board[c+1][r] == p and board[c+2][r] == p and board[c+3][r] == p then
                return true
            end
        end
    end
    -- 2. Vertical
    for c = 1, COLS do
        for r = 1, ROWS - 3 do
            if board[c][r] == p and board[c][r+1] == p and board[c][r+2] == p and board[c][r+3] == p then
                return true
            end
        end
    end
    -- 3. Diagonal Up (/)
    for c = 1, COLS - 3 do
        for r = 1, ROWS - 3 do
            if board[c][r] == p and board[c+1][r+1] == p and board[c+2][r+2] == p and board[c+3][r+3] == p then
                return true
            end
        end
    end
    -- 4. Diagonal Down (\)
    for c = 1, COLS - 3 do
        for r = 4, ROWS do
            if board[c][r] == p and board[c+1][r-1] == p and board[c+2][r-2] == p and board[c+3][r-3] == p then
                return true
            end
        end
    end
    return false
end

--- Checks if board has any empty slots left.
function game.isFull(board)
    for c = 1, COLS do
        if board[c][ROWS] == 0 then return false end
    end
    return true
end

--- Evaluates the best tactical move for the AI.
function game.getAiMove(board, aiP, humanP)
    -- 1. Check if AI can win this turn
    for c = 1, COLS do
        if board[c][ROWS] == 0 then
            local temp = game.newBoard()
            for x = 1, COLS do for y = 1, ROWS do temp[x][y] = board[x][y] end end
            game.dropToken(temp, c, aiP)
            if game.checkWin(temp, aiP) then return c end
        end
    end
    -- 2. Block human win
    for c = 1, COLS do
        if board[c][ROWS] == 0 then
            local temp = game.newBoard()
            for x = 1, COLS do for y = 1, ROWS do temp[x][y] = board[x][y] end end
            game.dropToken(temp, c, humanP)
            if game.checkWin(temp, humanP) then return c end
        end
    end
    -- 3. Center preference: 4, 3, 5, 2, 6, 1, 7
    local pref = { 4, 3, 5, 2, 6, 1, 7 }
    for _, c in ipairs(pref) do
        if board[c][ROWS] == 0 then return c end
    end
    return 1
end

function game.drawBoard(board, selectedCol, turnText, context)
    local w, h = term.getSize()
    context.drawWindow("Drunken Connect 4")
    
    local startX = math.max(2, math.floor((w - 21) / 2) + 1)
    
    -- Turn Banner
    term.setCursorPos(startX, 3)
    term.setTextColor(theme.highlightText or colors.yellow)
    term.write((turnText or "Your Turn"):sub(1, w - startX))
    
    -- Touch Column Header Buttons
    term.setCursorPos(startX, 4)
    for c = 1, COLS do
        if c == selectedCol then
            term.setTextColor(colors.yellow)
            term.write("▼" .. c .. " ")
        else
            term.setTextColor(theme.mutedText or colors.gray)
            term.write("[" .. c .. "]")
        end
    end
    
    -- Grid rows (render from top row 6 down to bottom row 1)
    local startY = 6
    for r = ROWS, 1, -1 do
        term.setCursorPos(startX, startY + (ROWS - r) * 2)
        for c = 1, COLS do
            local val = board[c][r]
            term.setTextColor(colors.blue)
            term.write("|")
            if val == P1 then
                term.setTextColor(colors.yellow)
                term.write("●")
            elseif val == P2 then
                term.setTextColor(colors.red)
                term.write("■")
            else
                term.setTextColor(colors.gray)
                term.write("·")
            end
            term.setTextColor(colors.blue)
            term.write("|")
        end
    end
    
    -- Bottom frame
    term.setCursorPos(startX, startY + ROWS * 2)
    term.setTextColor(colors.blue)
    term.write(string.rep("═", 21))
    
    -- Navigation Hint
    term.setCursorPos(2, h - 1)
    term.setTextColor(theme.mutedText or colors.gray)
    term.write("Tap [1-7] or press 1-7 • [Q] Quit")
end

function game.run(context)
    context = context or {}
    if not context.drawWindow then
        context.drawWindow = function(t) utils.drawWindow(t, context) end
    end
    
    local w, h = term.getSize()
    local username = (context.parent and context.parent.username) or "Player"
    
    -- Mode Select
    context.drawWindow("Connect 4 - Mode")
    term.setCursorPos(2, 4)
    term.setTextColor(theme.prompt or colors.yellow)
    term.write("Choose Game Mode:")
    
    local modes = { "Single Player (vs AI)", "Wireless P2P Multiplayer", "Back" }
    local choice = 1
    if context.drawMenu then
        choice = context.drawMenu(modes, 1, 2, 6)
    else
        choice = 1
    end
    if choice == 3 then return end
    
    local isMultiplayer = (choice == 2)
    local opponentId = nil
    local myPlayerNum = P1
    
    if isMultiplayer then
        if not rednet.isOpen() then
            local m = peripheral.find("modem")
            if m then rednet.open(peripheral.getName(m)) end
        end
        context.drawWindow("P2P Matchmaking")
        term.setCursorPos(2, 4)
        term.setTextColor(theme.text or colors.white)
        term.write("Broadcasting for opponent...")
        
        rednet.broadcast({ type = "c4_lobby", user = username }, "C4_P2P")
        local sender, msg = rednet.receive("C4_P2P", 5)
        if sender and msg and msg.type == "c4_join" then
            opponentId = sender
            myPlayerNum = P1
            rednet.send(opponentId, { type = "c4_start", turn = P1 }, "C4_P2P")
        elseif sender and msg and msg.type == "c4_lobby" and sender ~= os.getComputerID() then
            opponentId = sender
            myPlayerNum = P2
            rednet.send(opponentId, { type = "c4_join", user = username }, "C4_P2P")
        else
            context.showMessage("P2P", "No opponent found.\nFalling back to AI mode.")
            isMultiplayer = false
        end
    end
    
    local board = game.newBoard()
    local currentTurn = P1
    local selectedCol = 4
    local gameOver = false
    local winner = nil
    
    while not gameOver do
        local isMyTurn = (not isMultiplayer) or (currentTurn == myPlayerNum)
        local turnMsg = isMyTurn and "Your Turn (" .. (myPlayerNum == P1 and "Yellow" or "Red") .. ")" or "Opponent's Turn..."
        
        game.drawBoard(board, selectedCol, turnMsg, context)
        
        if isMyTurn then
            local event, p1, p2, p3 = os.pullEvent()
            local chosenCol = nil
            
            if event == "key" then
                local k = p1
                if k >= keys.one and k <= keys.seven then
                    chosenCol = k - keys.one + 1
                elseif k == keys.left then
                    selectedCol = math.max(1, selectedCol - 1)
                elseif k == keys.right then
                    selectedCol = math.min(COLS, selectedCol + 1)
                elseif k == keys.enter or k == keys.space then
                    chosenCol = selectedCol
                elseif k == keys.q then
                    if isMultiplayer and opponentId then
                        rednet.send(opponentId, { type = "c4_quit" }, "C4_P2P")
                    end
                    break
                end
            elseif event == "mouse_click" then
                local btn, cx, cy = p1, p2, p3
                local startX = math.max(2, math.floor((w - 21) / 2) + 1)
                if cx >= startX and cx < startX + 21 then
                    chosenCol = math.floor((cx - startX) / 3) + 1
                end
            end
            
            if chosenCol and chosenCol >= 1 and chosenCol <= COLS then
                local r = game.dropToken(board, chosenCol, currentTurn)
                if r then
                    if isMultiplayer and opponentId then
                        rednet.send(opponentId, { type = "c4_move", col = chosenCol }, "C4_P2P")
                    end
                    
                    if game.checkWin(board, currentTurn) then
                        gameOver = true
                        winner = currentTurn
                    elseif game.isFull(board) then
                        gameOver = true
                        winner = 0
                    else
                        currentTurn = (currentTurn == P1) and P2 or P1
                    end
                end
            end
        else
            -- Opponent / AI Turn
            if not isMultiplayer then
                sleep(0.4)
                local aiCol = game.getAiMove(board, P2, P1)
                game.dropToken(board, aiCol, P2)
                if game.checkWin(board, P2) then
                    gameOver = true
                    winner = P2
                elseif game.isFull(board) then
                    gameOver = true
                    winner = 0
                else
                    currentTurn = P1
                end
            else
                local timer = os.startTimer(0.5)
                local waitStart = os.epoch("utc")
                while not isMyTurn and not gameOver do
                    local event, p1, p2, p3 = os.pullEvent()
                    if event == "rednet_message" and p1 == opponentId and p3 == "C4_P2P" then
                        local msg = p2
                        if msg and msg.type == "c4_move" then
                            game.dropToken(board, msg.col, currentTurn)
                            if game.checkWin(board, currentTurn) then
                                gameOver = true
                                winner = currentTurn
                            elseif game.isFull(board) then
                                gameOver = true
                                winner = 0
                            else
                                currentTurn = myPlayerNum
                            end
                            break
                        elseif msg and msg.type == "c4_quit" then
                            gameOver = true
                            winner = myPlayerNum
                            if context.showMessage then
                                context.showMessage("P2P", "Opponent disconnected!\nVictory by forfeit.")
                            end
                            break
                        end
                    elseif event == "key" and p1 == keys.q then
                        if opponentId then
                            rednet.send(opponentId, { type = "c4_quit" }, "C4_P2P")
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
    
    -- Game Over Screen
    local winText = "Draw Game!"
    local score = 0
    if winner == myPlayerNum then
        winText = "VICTORY! You Won!"
        score = 100
    elseif winner and winner > 0 then
        winText = "Defeat! Opponent Won."
        score = 25
    end
    
    scoreCache.recordScore("Drunken_Connect4", score, username)
    game.drawBoard(board, selectedCol, winText, context)
    
    local startX = math.max(2, math.floor((w - 21) / 2) + 1)
    term.setCursorPos(startX, 5)
    term.setTextColor(colors.yellow)
    term.write("Best: " .. scoreCache.getPersonalBest("Drunken_Connect4"))
    
    sleep(1.5)
    while true do
        local e = os.pullEvent()
        if e == "key" or e == "mouse_click" then break end
    end
end

return game
