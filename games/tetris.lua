--[[
    Pocket Tetris (Gem Standard v1.8)
    by Gemini Gem

    Purpose:
    Updated for Drunken OS v12.0 distribution.
]]

local currentVersion = 1.8
-- ... rest of the tetris game code

--==============================================================================
-- Configuration & State
--==============================================================================

local args = {...}
local username = args[1] or "Guest" -- Fallback to Guest

local gameName = "Tetris" -- For the leaderboard
local arcadeServerId = nil

-- Game Board
local board = {}
local boardWidth, boardHeight = 10, 18

-- Game state
local score, level, linesCleared, gameOver = 0, 1, 0, false
local currentPiece, nextPiece = nil, nil

-- A check to see if the computer supports color.
local hasColor = term.isColor and term.isColor()
local function safeColor(colorName, fallbackColor)
    if hasColor and colors[colorName] ~= nil then return colors[colorName] end
    return fallbackColor
end

-- The color theme, consistent with the mail client.
local theme = {
    bg = safeColor("black", colors.black),
    text = safeColor("white", colors.white),
    windowBg = safeColor("darkGray", colors.gray),
    title = safeColor("green", colors.lime),
    prompt = safeColor("cyan", colors.cyan),
    statusBarBg = safeColor("gray", colors.lightGray),
    statusBarText = safeColor("white", colors.white),
}

-- Tetromino shapes and colors
local pieces = {
    { {{0,0,0,0}, {1,1,1,1}, {0,0,0,0}, {0,0,0,0}}, color = colors.cyan },   --
I
    { {{1,1}, {1,1}}, color = colors.yellow },                            -- O
    { {{0,1,0}, {1,1,1}, {0,0,0}}, color = colors.purple },                -- T
    { {{0,0,1}, {1,1,1}, {0,0,0}}, color = colors.blue },                  -- J
    { {{1,0,0}, {1,1,1}, {0,0,0}}, color = colors.orange },                -- L
    { {{0,1,1}, {1,1,0}, {0,0,0}}, color = colors.green },                 -- S
    { {{1,1,0}, {0,1,1}, {0,0,0}}, color = colors.red },                   -- Z
}

--==============================================================================
-- Core Game Logic
--==============================================================================

local function getSafeSize()
    local w, h = term.getSize()
    while not w or not h do
        sleep(0.05)
        w, h = term.getSize()
    end
    return w, h
end

local function newPiece()
    currentPiece = nextPiece or pieces[math.random(#pieces)]
    nextPiece = pieces[math.random(#pieces)]
    currentPiece.x = math.floor(boardWidth / 2) - 1
    currentPiece.y = 1

    if not isValid(currentPiece) then
        gameOver = true
    end
end

function isValid(piece)
    for r = 1, #piece[1] do
        for c = 1, #piece[1][r] do
            if piece[1][r][c] == 1 then
                local boardX = piece.x + c
                local boardY = piece.y + r
                if boardX < 1 or boardX > boardWidth or
                   boardY < 1 or boardY > boardHeight or
                   (board[boardY] and board[boardY][boardX]) then
                    return false
                end
            end
        end
    end
    return true
end

function rotatePiece(piece)
    local size = #piece[1]
    local newShape = {}
    for i = 1, size do newShape[i] = {} end

    for r = 1, size do
        for c = 1, size do
            newShape[c][size - r + 1] = piece[1][r][c]
        end
    end
    return newShape
end

function lockPiece()
    for r = 1, #currentPiece[1] do
        for c = 1, #currentPiece[1][r] do
            if currentPiece[1][r][c] == 1 then
                local boardX = currentPiece.x + c
                local boardY = currentPiece.y + r
                if not board[boardY] then board[boardY] = {} end
                board[boardY][boardX] = currentPiece.color
            end
        end
    end

    local lines = 0
    for r = 1, boardHeight do
        local isLine = true
        for c = 1, boardWidth do
            if not board[r] or not board[r][c] then
                isLine = false
                break
            end
        end
        if isLine then
            lines = lines + 1
            table.remove(board, r)
            table.insert(board, 1, {})
        end
    end

    if lines > 0 then
        linesCleared = linesCleared + lines
        if lines == 1 then score = score + 40 * level
        elseif lines == 2 then score = score + 100 * level
        elseif lines == 3 then score = score + 300 * level
        elseif lines == 4 then score = score + 1200 * level end
        level = math.floor(linesCleared / 10) + 1
    end
end

--==============================================================================
-- UI & Drawing Functions
--==============================================================================

-- **FIXED**: The draw function now uses a superior adaptive layout.
local function draw()
    term.setBackgroundColor(theme.windowBg)
    term.clear()
    local w, h = getSafeSize()

    local boardPixelWidth = boardWidth * 2
    local boardXOffset = math.floor((w - boardPixelWidth) / 2)
    local boardYOffset = 3 -- Pushed down to make space for top UI

    -- Draw board border
    term.setTextColor(colors.gray)
    for y = 1, boardHeight do
        term.setCursorPos(boardXOffset - 1, boardYOffset + y - 1); term.write("[
")
        term.setCursorPos(boardXOffset + boardPixelWidth, boardYOffset + y - 1);
 term.write("]")
    end

    -- Draw locked pieces
    for y = 1, boardHeight do
        if board[y] then
            for x = 1, boardWidth do
                if board[y][x] then
                    term.setBackgroundColor(board[y][x])
                    term.setCursorPos(boardXOffset + (x - 1) * 2, boardYOffset +
 y - 1)
                    term.write("  ")
                end
            end
        end
    end

    -- Draw current piece
    if currentPiece then
        term.setBackgroundColor(currentPiece.color)
        for r = 1, #currentPiece[1] do
            for c = 1, #currentPiece[1][r] do
                if currentPiece[1][r][c] == 1 then
                    term.setCursorPos(boardXOffset + (currentPiece.x + c - 1) *
2, boardYOffset + currentPiece.y + r - 1)
                    term.write("  ")
                end
            end
        end
    end

    -- Draw UI text and next piece preview
    term.setBackgroundColor(theme.windowBg)
    term.setTextColor(theme.text)

    -- On narrow screens, draw UI at the top. On wide screens, draw it to the si
de.
    if w > boardPixelWidth + 15 then
        local uiX = boardXOffset + boardPixelWidth + 3
        local uiY = boardYOffset
        term.setCursorPos(uiX, uiY); term.write("Score: " .. score)
        term.setCursorPos(uiX, uiY + 2); term.write("Level: " .. level)
        term.setCursorPos(uiX, uiY + 4); term.write("Lines: " .. linesCleared)
        term.setCursorPos(uiX, uiY + 7); term.write("Next:")
        if nextPiece then
            term.setBackgroundColor(nextPiece.color)
            for r = 1, #nextPiece[1] do
                for c = 1, #nextPiece[1][r] do
                    if nextPiece[1][r][c] == 1 then
                        term.setCursorPos(uiX + (c-1)*2, uiY + 8 + r)
                        term.write("  ")
                    end
                end
            end
        end
    else
        local scoreText = "S:"..score
        local levelText = "L:"..level
        local linesText = "N:"..linesCleared
        term.setCursorPos(2, 1); term.write(scoreText)
        term.setCursorPos(math.floor(w/2 - #levelText/2), 1); term.write(levelTe
xt)
        term.setCursorPos(w - #linesText, 1); term.write(linesText)
    end
end

--==============================================================================
-- Leaderboard & Game Over Functions
--==============================================================================

local function submitScore() if arcadeServerId then rednet.send(arcadeServerId,
{type = "submit_score", game = gameName, user = username, score = score}, "Arcad
eGames") end end

local function showGameOverScreen()
    submitScore()

    local w, h = getSafeSize()
    term.setBackgroundColor(theme.windowBg); term.clear()

    local boxWidth = 32
    local boxHeight = 18
    local boxX = math.floor((w - boxWidth) / 2)
    local boxY = math.floor((h - boxHeight) / 2)

    term.setBackgroundColor(theme.windowBg)
    for y = 0, boxHeight - 1 do term.setCursorPos(boxX, boxY + y); term.write(st
ring.rep(" ", boxWidth)) end

    local title = "Game Over"
    term.setCursorPos(boxX + math.floor((boxWidth - #title) / 2), boxY + 1); ter
m.setTextColor(colors.red); term.write(title)

    local scoreText = "Final Score: " .. score
    term.setCursorPos(boxX + math.floor((boxWidth - #scoreText) / 2), boxY + 3);
 term.setTextColor(theme.text); term.write(scoreText)

    if arcadeServerId then
        rednet.send(arcadeServerId, {type = "get_leaderboard", game = gameName},
 "ArcadeGames")
        local _, response = rednet.receive("ArcadeGames", 3)
        if response and response.leaderboard then
            local sortedScores = {}; for user, s in pairs(response.leaderboard)
do table.insert(sortedScores, {user = user, score = s}) end
            table.sort(sortedScores, function(a,b) return a.score > b.score end)

            local lbTitle = "--- Leaderboard ---"
            term.setCursorPos(boxX + math.floor((boxWidth - #lbTitle) / 2), boxY
 + 5); term.setTextColor(theme.title); term.write(lbTitle)

            term.setTextColor(theme.text)
            for i = 1, math.min(10, #sortedScores) do
                local entry = string.format("%2d. %-15s %d", i, sortedScores[i].
user, sortedScores[i].score)
                term.setCursorPos(boxX + 2, boxY + 6 + i)
                term.write(entry)
            end
        end
    end

    local prompt = "Press any key to exit..."
    term.setCursorPos(boxX + math.floor((boxWidth - #prompt) / 2), boxY + boxHei
ght - 2); term.setTextColor(theme.prompt); term.write(prompt)

    os.pullEvent("key")
end

--==============================================================================
-- Main Game Loop
--==============================================================================

rednet.open("back")
arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

for y = 1, boardHeight do board[y] = {} end
newPiece()

local dropTimer = os.startTimer(0.5)

while true do
    local event, p1 = os.pullEvent()

    if event == "key" then
        if p1 == keys.left then
            currentPiece.x = currentPiece.x - 1
            if not isValid(currentPiece) then currentPiece.x = currentPiece.x +
1 end
        elseif p1 == keys.right then
            currentPiece.x = currentPiece.x + 1
            if not isValid(currentPiece) then currentPiece.x = currentPiece.x -
1 end
        elseif p1 == keys.up then
            local originalShape = currentPiece[1]
            currentPiece[1] = rotatePiece(currentPiece)
            if not isValid(currentPiece) then currentPiece[1] = originalShape en
d
        elseif p1 == keys.down then
            currentPiece.y = currentPiece.y + 1
            if not isValid(currentPiece) then
                currentPiece.y = currentPiece.y - 1
                lockPiece()
                newPiece()
            else
                score = score + 1
            end
        elseif p1 == keys.space then
             while isValid(currentPiece) do
                currentPiece.y = currentPiece.y + 1
                score = score + 2
             end
             currentPiece.y = currentPiece.y - 1
             lockPiece()
             newPiece()
        elseif p1 == keys.q then
            gameOver = true
        end
    elseif event == "timer" and p1 == dropTimer then
        currentPiece.y = currentPiece.y + 1
        if not isValid(currentPiece) then
            currentPiece.y = currentPiece.y - 1
            lockPiece()
            newPiece()
        end
        local speed = math.max(0.1, 0.5 - (level - 1) * 0.05)
        dropTimer = os.startTimer(speed)
    elseif event == "terminate" then
        break
    end

    draw()

    if gameOver then
        break
    end
end

showGameOverScreen()
clear()
