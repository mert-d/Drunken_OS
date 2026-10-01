--[[
    Drunken Sweeper (v2.0)
    Authentic Windows 95 Style Minesweeper for Drunken OS
    by Gemini Gem & Antigravity
]]

if package and package.path then package.path = "/?.lua;" .. package.path end
local sharedTheme = require("lib.theme")
local scoreCache = require("lib.score_cache")

local ok_sound, Sound = pcall(require, "lib.sound")
if not ok_sound or type(Sound) ~= "table" then
    Sound = {
        playClick = function() end,
        playNote = function() end,
        playSuccess = function() end
    }
end

local gameVersion = 2.0
local gameName = "DrunkenSweeper"

local function safeColor(col, fallback)
    if term and term.isColor and term.isColor() and colors and colors[col] then
        return colors[col]
    end
    return fallback or colors.white
end

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"
    
    local w, h = term.getSize()
    local isPocket = (w <= 30)

    -- Windows 95 Palette
    local cWinBg = safeColor("lightGray", colors.black)
    local cWinText = colors.black
    local cTitleBg = safeColor("blue", colors.gray)
    local cTitleText = colors.white
    local cDarkBorder = safeColor("gray", colors.gray)
    local cLightBorder = colors.white
    local cLedBg = colors.black
    local cLedText = colors.red

    -- Number colors (classic Windows 95 colors)
    local numColors = {
        [1] = safeColor("blue", colors.white),
        [2] = safeColor("green", colors.white),
        [3] = safeColor("red", colors.white),
        [4] = safeColor("purple", colors.white),
        [5] = safeColor("brown", colors.white),
        [6] = safeColor("cyan", colors.white),
        [7] = colors.black,
        [8] = colors.gray
    }

    -- Board Configuration
    -- Pocket (w<=30): 8x8 with 10 mines; Desktop: 9x9 with 10 mines (Beginner)
    local BOARD_W = isPocket and 8 or 9
    local BOARD_H = isPocket and 8 or 9
    local MINE_COUNT = isPocket and 10 or 10

    -- Board State
    local board = {}
    local revealed = {}
    local flagged = {}
    local cursor = { x = 1, y = 1 }
    local gameState = "playing" -- "playing", "won", "lost"
    local firstClick = true
    local touchMode = "dig" -- "dig" or "flag" for 1-touch mobile
    local faceState = ":-)"
    
    local startTime = 0
    local timerSeconds = 0
    local timerId = nil

    local function initBoard()
        board = {}
        revealed = {}
        flagged = {}
        for y = 1, BOARD_H do
            board[y] = {}
            revealed[y] = {}
            flagged[y] = {}
            for x = 1, BOARD_W do
                board[y][x] = 0
                revealed[y][x] = false
                flagged[y][x] = false
            end
        end
        firstClick = true
        gameState = "playing"
        faceState = ":-)"
        cursor = { x = math.floor(BOARD_W / 2), y = math.floor(BOARD_H / 2) }
        startTime = 0
        timerSeconds = 0
        if timerId then timerId = nil end
    end

    local function populateMines(excludeX, excludeY)
        local placed = 0
        while placed < MINE_COUNT do
            local rx = math.random(1, BOARD_W)
            local ry = math.random(1, BOARD_H)
            -- Never place a mine on the first clicked tile or its immediate neighbors
            local isExcluded = (math.abs(rx - excludeX) <= 1 and math.abs(ry - excludeY) <= 1)
            if not isExcluded and board[ry][rx] ~= -1 then
                board[ry][rx] = -1
                placed = placed + 1
            end
        end

        -- Calculate adjacent mine counts
        for y = 1, BOARD_H do
            for x = 1, BOARD_W do
                if board[y][x] ~= -1 then
                    local count = 0
                    for dy = -1, 1 do
                        for dx = -1, 1 do
                            local ny, nx = y + dy, x + dx
                            if board[ny] and board[ny][nx] == -1 then
                                count = count + 1
                            end
                        end
                    end
                    board[y][x] = count
                end
            end
        end
    end

    local function getFlagsRemaining()
        local count = 0
        for y = 1, BOARD_H do
            for x = 1, BOARD_W do
                if flagged[y][x] then count = count + 1 end
            end
        end
        return MINE_COUNT - count
    end

    local function floodFill(x, y)
        if x < 1 or x > BOARD_W or y < 1 or y > BOARD_H then return end
        if revealed[y][x] or flagged[y][x] then return end
        
        revealed[y][x] = true
        if board[y][x] == 0 then
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if not (dx == 0 and dy == 0) then
                        floodFill(x + dx, y + dy)
                    end
                end
            end
        end
    end

    local function checkWin()
        local unrevealedSafe = 0
        for y = 1, BOARD_H do
            for x = 1, BOARD_W do
                if board[y][x] ~= -1 and not revealed[y][x] then
                    unrevealedSafe = unrevealedSafe + 1
                end
            end
        end

        if unrevealedSafe == 0 then
            gameState = "won"
            faceState = "B-)"
            Sound.playSuccess()
            -- Auto flag all mines
            for y = 1, BOARD_H do
                for x = 1, BOARD_W do
                    if board[y][x] == -1 then flagged[y][x] = true end
                end
            end
            local finalScore = math.max(100, 1000 - timerSeconds * 2)
            scoreCache.recordScore(gameName, finalScore, username)
            return true
        end
        return false
    end

    local function uncoverCell(x, y)
        if x < 1 or x > BOARD_W or y < 1 or y > BOARD_H then return end
        if flagged[y][x] or revealed[y][x] then return end

        if firstClick then
            populateMines(x, y)
            firstClick = false
            startTime = os.epoch("utc")
            timerId = os.startTimer(1)
        end

        if board[y][x] == -1 then
            -- Detonation
            gameState = "lost"
            faceState = "X-("
            Sound.playNote("bass", 1.5, 6)
            for ry = 1, BOARD_H do
                for rx = 1, BOARD_W do
                    if board[ry][rx] == -1 then revealed[ry][rx] = true end
                end
            end
        else
            Sound.playClick()
            floodFill(x, y)
            checkWin()
        end
    end

    local function toggleFlag(x, y)
        if x < 1 or x > BOARD_W or y < 1 or y > BOARD_H then return end
        if revealed[y][x] then return end

        flagged[y][x] = not flagged[y][x]
        Sound.playNote("pling", 0.8, 18)
    end

    -- Chording: if clicked cell is already revealed and surrounding flags == mine count, uncover neighbors
    local function chordCell(x, y)
        if not revealed[y][x] or board[y][x] <= 0 then return end
        local flagCount = 0
        for dy = -1, 1 do
            for dx = -1, 1 do
                local ny, nx = y + dy, x + dx
                if flagged[ny] and flagged[ny][nx] then flagCount = flagCount + 1 end
            end
        end

        if flagCount == board[y][x] then
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local ny, nx = y + dy, x + dx
                    if ny >= 1 and ny <= BOARD_H and nx >= 1 and nx <= BOARD_W then
                        if not flagged[ny][nx] and not revealed[ny][nx] then
                            uncoverCell(nx, ny)
                        end
                    end
                end
            end
        end
    end

    -- Draw Windows 95 UI
    local function drawGame()
        w, h = term.getSize()
        isPocket = (w <= 30)
        
        -- Background
        term.setBackgroundColor(cWinBg)
        term.clear()

        -- Title Bar
        term.setCursorPos(1, 1)
        term.setBackgroundColor(cTitleBg)
        term.setTextColor(cTitleText)
        term.clearLine()
        local title = " Drunken Sweeper"
        term.write(title)
        term.setCursorPos(w - 2, 1)
        term.write("[X]")

        -- Top Scoreboard Panel (Digital LEDs & Smiley Face)
        local scoreY = 3
        local boardStartX = math.floor((w - (BOARD_W * 3)) / 2) + 1
        local boardStartY = scoreY + 3

        -- Mine Counter LCD [015]
        local flagsLeft = math.max(-99, math.min(999, getFlagsRemaining()))
        local ledMines = string.format("%03d", flagsLeft)
        if flagsLeft < 0 then ledMines = string.format("-%02d", math.abs(flagsLeft)) end
        
        term.setCursorPos(boardStartX, scoreY)
        term.setBackgroundColor(cLedBg)
        term.setTextColor(cLedText)
        term.write(ledMines)

        -- Smiley Face Button [:)]
        local faceStr = "[" .. faceState .. "]"
        local faceX = math.floor(boardStartX + (BOARD_W * 3) / 2 - #faceStr / 2)
        term.setCursorPos(faceX, scoreY)
        term.setBackgroundColor(colors.yellow)
        term.setTextColor(colors.black)
        term.write(faceStr)

        -- Timer LCD [000]
        local ledTime = string.format("%03d", math.min(999, timerSeconds))
        local timerX = boardStartX + (BOARD_W * 3) - 3
        term.setCursorPos(timerX, scoreY)
        term.setBackgroundColor(cLedBg)
        term.setTextColor(cLedText)
        term.write(ledTime)

        -- Divider Bar
        term.setCursorPos(boardStartX, scoreY + 1)
        term.setBackgroundColor(cWinBg)
        term.setTextColor(cDarkBorder)
        term.write(string.rep("-", BOARD_W * 3))

        -- Grid Drawing
        for by = 1, BOARD_H do
            term.setCursorPos(boardStartX, boardStartY + by - 1)
            for bx = 1, BOARD_W do
                local isCursor = (cursor.x == bx and cursor.y == by and gameState == "playing")
                local isRev = revealed[by][bx]
                local isFlag = flagged[by][bx]
                local val = board[by][bx]

                local bg = isRev and colors.lightGray or colors.gray
                local fg = colors.white
                local cellTxt = "   "

                if isRev then
                    if val == -1 then
                        bg = colors.red
                        fg = colors.white
                        cellTxt = " * "
                    elseif val == 0 then
                        bg = cWinBg
                        cellTxt = "   "
                    else
                        bg = cWinBg
                        fg = numColors[val] or colors.black
                        cellTxt = " " .. val .. " "
                    end
                elseif isFlag then
                    bg = colors.gray
                    fg = colors.yellow
                    cellTxt = " P "
                else
                    -- Unrevealed
                    bg = colors.gray
                    fg = colors.white
                    cellTxt = " . "
                end

                if isCursor then
                    bg = colors.cyan
                    fg = colors.black
                end

                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(cellTxt)
            end
        end

        -- Footer / Controls Status Bar
        term.setCursorPos(1, h)
        term.setBackgroundColor(cDarkBorder)
        term.setTextColor(colors.white)
        term.clearLine()
        
        if isPocket then
            local modeBtn = (touchMode == "dig") and "[Mode: DIG (Tap)]" or "[Mode: FLAG (P)]"
            term.setCursorPos(2, h)
            term.setTextColor(touchMode == "dig" and colors.lime or colors.yellow)
            term.write(modeBtn)
            term.setTextColor(colors.lightGray)
            term.setCursorPos(w - 7, h)
            term.write("[Q:Quit]")
        else
            term.setCursorPos(2, h)
            term.write("L-Click: Dig | R-Click/Space: Flag | Enter: Chord | Q: Quit")
        end
    end

    initBoard()

    while true do
        drawGame()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == timerId then
            if gameState == "playing" and not firstClick then
                timerSeconds = timerSeconds + 1
                timerId = os.startTimer(1)
            end

        elseif event == "key" then
            local key = p1
            if key == keys.q or key == keys.tab then
                break
            elseif key == keys.r then
                initBoard()
            elseif gameState == "playing" then
                if key == keys.up and cursor.y > 1 then cursor.y = cursor.y - 1
                elseif key == keys.down and cursor.y < BOARD_H then cursor.y = cursor.y + 1
                elseif key == keys.left and cursor.x > 1 then cursor.x = cursor.x - 1
                elseif key == keys.right and cursor.x < BOARD_W then cursor.x = cursor.x + 1
                elseif key == keys.space then
                    toggleFlag(cursor.x, cursor.y)
                elseif key == keys.enter then
                    if revealed[cursor.y][cursor.x] then
                        chordCell(cursor.x, cursor.y)
                    else
                        uncoverCell(cursor.x, cursor.y)
                    end
                elseif key == keys.m then
                    touchMode = (touchMode == "dig") and "flag" or "dig"
                end
            elseif gameState ~= "playing" then
                if key == keys.enter or key == keys.space then
                    initBoard()
                end
            end

        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            local boardStartX = math.floor((w - (BOARD_W * 3)) / 2) + 1
            local scoreY = 3
            local boardStartY = scoreY + 3

            -- Click Title Bar [X] to exit
            if cy == 1 and cx >= w - 3 then
                break
            end

            -- Click Smiley Face to restart
            local faceStr = "[" .. faceState .. "]"
            local faceX = math.floor(boardStartX + (BOARD_W * 3) / 2 - #faceStr / 2)
            if cy == scoreY and cx >= faceX and cx <= faceX + #faceStr then
                initBoard()
            end

            -- Click on Mobile Mode Switch Button in footer
            if isPocket and cy == h then
                if cx <= 18 then
                    touchMode = (touchMode == "dig") and "flag" or "dig"
                    Sound.playClick()
                elseif cx >= w - 7 then
                    break
                end
            end

            -- Click inside Grid
            if cy >= boardStartY and cy < boardStartY + BOARD_H then
                local gridY = cy - boardStartY + 1
                local relX = cx - boardStartX
                if relX >= 0 and relX < (BOARD_W * 3) then
                    local gridX = math.floor(relX / 3) + 1
                    if gridX >= 1 and gridX <= BOARD_W and gridY >= 1 and gridY <= BOARD_H then
                        cursor = { x = gridX, y = gridY }

                        if gameState == "playing" then
                            if btn == 2 or (btn == 1 and isPocket and touchMode == "flag") then
                                -- Right click or Pocket Flag Mode
                                toggleFlag(gridX, gridY)
                            elseif btn == 1 then
                                -- Left click
                                if revealed[gridY][gridX] then
                                    chordCell(gridX, gridY)
                                else
                                    uncoverCell(gridX, gridY)
                                end
                            end
                        else
                            -- Game Over / Win: clicking grid restarts
                            initBoard()
                        end
                    end
                end
            end
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local ok, err = pcall(mainGame, ...)
if not ok and err then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("Drunken Sweeper Error: " .. tostring(err))
    print("Press any key to return...")
    pcall(os.pullEvent)
end
