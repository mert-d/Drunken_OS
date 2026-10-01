--[[
    Classic Tetris (v2.0)
    Windows 95 Arcade Edition for Drunken OS
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
local gameName = "Tetris"

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
    local cBoardBg = colors.black
    local cTitleBg = safeColor("blue", colors.gray)
    local cTitleText = colors.white
    local cBorder = safeColor("gray", colors.gray)
    local cGhost = safeColor("gray", colors.black)

    -- Board Dimensions: 10 columns, 16-18 rows (fits on CC:Tweaked screen)
    local boardW = 10
    local boardH = isPocket and 14 or 16
    local board = {}

    -- Tetromino Definitions
    local PIECES = {
        -- I
        {
            shapes = {
                {{0,0,0,0},{1,1,1,1},{0,0,0,0},{0,0,0,0}},
                {{0,0,1,0},{0,0,1,0},{0,0,1,0},{0,0,1,0}}
            },
            color = safeColor("cyan", colors.white)
        },
        -- O
        {
            shapes = {
                {{1,1},{1,1}}
            },
            color = safeColor("yellow", colors.white)
        },
        -- T
        {
            shapes = {
                {{0,1,0},{1,1,1},{0,0,0}},
                {{0,1,0},{0,1,1},{0,1,0}},
                {{0,0,0},{1,1,1},{0,1,0}},
                {{0,1,0},{1,1,0},{0,1,0}}
            },
            color = safeColor("purple", colors.white)
        },
        -- S
        {
            shapes = {
                {{0,1,1},{1,1,0},{0,0,0}},
                {{0,1,0},{0,1,1},{0,0,1}}
            },
            color = safeColor("lime", colors.white)
        },
        -- Z
        {
            shapes = {
                {{1,1,0},{0,1,1},{0,0,0}},
                {{0,0,1},{0,1,1},{0,1,0}}
            },
            color = safeColor("red", colors.white)
        },
        -- J
        {
            shapes = {
                {{1,0,0},{1,1,1},{0,0,0}},
                {{0,1,1},{0,1,0},{0,1,0}},
                {{0,0,0},{1,1,1},{0,0,1}},
                {{0,1,0},{0,1,0},{1,1,0}}
            },
            color = safeColor("blue", colors.white)
        },
        -- L
        {
            shapes = {
                {{0,0,1},{1,1,1},{0,0,0}},
                {{0,1,0},{0,1,0},{0,1,1}},
                {{0,0,0},{1,1,1},{1,0,0}},
                {{1,1,0},{0,1,0},{0,1,0}}
            },
            color = safeColor("orange", colors.white)
        }
    }

    -- Game State
    local score = 0
    local lines = 0
    local level = 1
    local gameOver = false
    local personalBest = scoreCache.getPersonalBest(gameName)

    local currentPiece = nil
    local nextPiece = nil
    local dropTimer = nil

    local function getRandomPiece()
        local pIdx = math.random(#PIECES)
        local def = PIECES[pIdx]
        return {
            def = def,
            rotIdx = 1,
            color = def.color,
            x = math.floor(boardW / 2) - 1,
            y = 1
        }
    end

    local function getShape(piece)
        local shapes = piece.def.shapes
        return shapes[piece.rotIdx]
    end

    local function isValid(piece, testX, testY, testRot)
        local shapes = piece.def.shapes
        local shape = shapes[testRot or piece.rotIdx]
        local px = testX or piece.x
        local py = testY or piece.y

        for r = 1, #shape do
            for c = 1, #shape[r] do
                if shape[r][c] == 1 then
                    local bx = px + c - 1
                    local by = py + r - 1

                    if bx < 1 or bx > boardW or by > boardH then
                        return false
                    end
                    if by >= 1 and board[by] and board[by][bx] then
                        return false
                    end
                end
            end
        end
        return true
    end

    local function lockPiece()
        local shape = getShape(currentPiece)
        for r = 1, #shape do
            for c = 1, #shape[r] do
                if shape[r][c] == 1 then
                    local bx = currentPiece.x + c - 1
                    local by = currentPiece.y + r - 1
                    if by >= 1 and by <= boardH and bx >= 1 and bx <= boardW then
                        board[by][bx] = currentPiece.color
                    end
                end
            end
        end
        Sound.playNote("hat", 0.8, 12)
    end

    local function clearLines()
        local cleared = 0
        local y = boardH
        while y >= 1 do
            local full = true
            for x = 1, boardW do
                if not board[y][x] then
                    full = false
                    break
                end
            end

            if full then
                cleared = cleared + 1
                table.remove(board, y)
                local newRow = {}
                for x = 1, boardW do newRow[x] = nil end
                table.insert(board, 1, newRow)
            else
                y = y - 1
            end
        end

        if cleared > 0 then
            lines = lines + cleared
            level = math.floor(lines / 10) + 1

            local lineScores = { [1] = 100, [2] = 300, [3] = 500, [4] = 800 }
            local pts = (lineScores[cleared] or (cleared * 200)) * level
            score = score + pts

            if cleared == 4 then
                -- TETRIS!
                Sound.playSuccess()
            else
                Sound.playNote("pling", 1.2, 16 + cleared * 2)
            end
        end
    end

    local function getGhostY()
        if not currentPiece then return 1 end
        local testY = currentPiece.y
        while isValid(currentPiece, currentPiece.x, testY + 1) do
            testY = testY + 1
        end
        return testY
    end

    local function spawnNextPiece()
        if not nextPiece then
            nextPiece = getRandomPiece()
        end
        currentPiece = nextPiece
        currentPiece.x = math.floor(boardW / 2) - 1
        currentPiece.y = 1
        nextPiece = getRandomPiece()

        if not isValid(currentPiece) then
            gameOver = true
            Sound.playNote("bass", 1.5, 4)
            scoreCache.recordScore(gameName, score, username)
        end
    end

    local function initGame()
        w, h = term.getSize()
        isPocket = (w <= 30)
        boardH = isPocket and 14 or 16

        board = {}
        for y = 1, boardH do
            board[y] = {}
            for x = 1, boardW do
                board[y][x] = nil
            end
        end

        score = 0
        lines = 0
        level = 1
        gameOver = false
        personalBest = scoreCache.getPersonalBest(gameName)
        nextPiece = nil
        spawnNextPiece()
    end

    local function rotatePiece()
        if not currentPiece or gameOver then return end
        local maxRot = #currentPiece.def.shapes
        local nextRot = (currentPiece.rotIdx % maxRot) + 1

        -- Try standard rotation
        if isValid(currentPiece, currentPiece.x, currentPiece.y, nextRot) then
            currentPiece.rotIdx = nextRot
            Sound.playClick()
            return
        end

        -- Wall kick right/left
        if isValid(currentPiece, currentPiece.x + 1, currentPiece.y, nextRot) then
            currentPiece.x = currentPiece.x + 1
            currentPiece.rotIdx = nextRot
            Sound.playClick()
            return
        elseif isValid(currentPiece, currentPiece.x - 1, currentPiece.y, nextRot) then
            currentPiece.x = currentPiece.x - 1
            currentPiece.rotIdx = nextRot
            Sound.playClick()
            return
        end
    end

    local function hardDrop()
        if not currentPiece or gameOver then return end
        local dropY = getGhostY()
        currentPiece.y = dropY
        lockPiece()
        clearLines()
        spawnNextPiece()
    end

    local function softDrop()
        if not currentPiece or gameOver then return end
        if isValid(currentPiece, currentPiece.x, currentPiece.y + 1) then
            currentPiece.y = currentPiece.y + 1
            score = score + 1
        else
            lockPiece()
            clearLines()
            spawnNextPiece()
        end
    end

    local function moveHorizontal(dx)
        if not currentPiece or gameOver then return end
        if isValid(currentPiece, currentPiece.x + dx, currentPiece.y) then
            currentPiece.x = currentPiece.x + dx
            Sound.playClick()
        end
    end

    -- Draw Windows 95 UI & Tetris Grid
    local function drawGame()
        w, h = term.getSize()
        isPocket = (w <= 30)

        term.setBackgroundColor(cWinBg)
        term.clear()

        -- Title Bar
        term.setCursorPos(1, 1)
        term.setBackgroundColor(cTitleBg)
        term.setTextColor(cTitleText)
        term.clearLine()
        term.write(" Classic Tetris")
        term.setCursorPos(w - 2, 1)
        term.write("[X]")

        -- Board Positioning
        local boardCellW = 2 -- 2 chars per cell for square look
        local totalBoardW = boardW * boardCellW
        local boardStartX = isPocket and 2 or 3
        local boardStartY = 3

        -- Draw Board Frame
        term.setCursorPos(boardStartX - 1, boardStartY - 1)
        term.setBackgroundColor(cBorder)
        term.write("+" .. string.rep("-", totalBoardW) .. "+")

        for by = 1, boardH do
            term.setCursorPos(boardStartX - 1, boardStartY + by - 1)
            term.setBackgroundColor(cBorder)
            term.write("|")
            term.setCursorPos(boardStartX + totalBoardW, boardStartY + by - 1)
            term.write("|")
        end

        term.setCursorPos(boardStartX - 1, boardStartY + boardH)
        term.write("+" .. string.rep("-", totalBoardW) .. "+")

        -- Clear Board Interior (Black)
        term.setBackgroundColor(cBoardBg)
        for by = 1, boardH do
            term.setCursorPos(boardStartX, boardStartY + by - 1)
            term.write(string.rep(" ", totalBoardW))
        end

        -- Draw Fixed Blocks
        for by = 1, boardH do
            for bx = 1, boardW do
                local col = board[by][bx]
                if col then
                    local sx = boardStartX + (bx - 1) * boardCellW
                    local sy = boardStartY + by - 1
                    term.setCursorPos(sx, sy)
                    term.setBackgroundColor(col)
                    term.setTextColor(colors.white)
                    term.write("[]")
                end
            end
        end

        -- Draw Ghost Piece (Landing preview)
        if currentPiece and not gameOver then
            local ghostY = getGhostY()
            local shape = getShape(currentPiece)
            for r = 1, #shape do
                for c = 1, #shape[r] do
                    if shape[r][c] == 1 then
                        local bx = currentPiece.x + c - 1
                        local by = ghostY + r - 1
                        if by >= 1 and by <= boardH and bx >= 1 and bx <= boardW and not board[by][bx] then
                            local sx = boardStartX + (bx - 1) * boardCellW
                            local sy = boardStartY + by - 1
                            term.setCursorPos(sx, sy)
                            term.setBackgroundColor(cBoardBg)
                            term.setTextColor(cGhost)
                            term.write("::")
                        end
                    end
                end
            end
        end

        -- Draw Current Active Piece
        if currentPiece and not gameOver then
            local shape = getShape(currentPiece)
            for r = 1, #shape do
                for c = 1, #shape[r] do
                    if shape[r][c] == 1 then
                        local bx = currentPiece.x + c - 1
                        local by = currentPiece.y + r - 1
                        if by >= 1 and by <= boardH and bx >= 1 and bx <= boardW then
                            local sx = boardStartX + (bx - 1) * boardCellW
                            local sy = boardStartY + by - 1
                            term.setCursorPos(sx, sy)
                            term.setBackgroundColor(currentPiece.color)
                            term.setTextColor(colors.white)
                            term.write("[]")
                        end
                    end
                end
            end
        end

        -- Side Panel (Next Piece & Stats)
        local panelX = boardStartX + totalBoardW + 2
        if panelX <= w - 6 then
            -- Next Box
            term.setCursorPos(panelX, 3)
            term.setBackgroundColor(cWinBg)
            term.setTextColor(colors.black)
            term.write("NEXT:")

            -- Draw Next Piece preview
            if nextPiece then
                local nShape = getShape(nextPiece)
                for nr = 1, 3 do
                    term.setCursorPos(panelX, 4 + nr - 1)
                    term.setBackgroundColor(cWinBg)
                    term.write("      ")
                end
                for nr = 1, #nShape do
                    for nc = 1, #nShape[nr] do
                        if nShape[nr][nc] == 1 then
                            term.setCursorPos(panelX + (nc - 1) * 2, 4 + nr - 1)
                            term.setBackgroundColor(nextPiece.color)
                            term.setTextColor(colors.white)
                            term.write("[]")
                        end
                    end
                end
            end

            -- Stats Labels
            term.setBackgroundColor(cWinBg)
            term.setTextColor(colors.black)
            term.setCursorPos(panelX, 8); term.write("SCORE:")
            term.setCursorPos(panelX, 9); term.setTextColor(colors.blue); term.write(string.format("%06d", score))

            term.setTextColor(colors.black)
            term.setCursorPos(panelX, 11); term.write("LINES:")
            term.setCursorPos(panelX, 12); term.setTextColor(colors.black); term.write(string.format("%03d", lines))

            term.setCursorPos(panelX, 14); term.write("LEVEL:")
            term.setCursorPos(panelX, 15); term.setTextColor(colors.red); term.write(string.format("%02d", level))
        end

        -- Footer Controls / Touch Buttons
        term.setCursorPos(1, h)
        term.setBackgroundColor(cBorder)
        term.setTextColor(colors.white)
        term.clearLine()

        if isPocket then
            -- Interactive Touch Bar for mobile
            term.setCursorPos(2, h)
            term.write("[<] [Rot] [>] [Drop]")
            term.setCursorPos(w - 3, h)
            term.write("[Q]")
        else
            term.setCursorPos(2, h)
            term.write("Arrows: Move/Rot | Space: Drop | [Q] Quit")
        end

        -- Game Over Modal
        if gameOver then
            local gW = math.min(w - 4, 22)
            local gX = math.floor((w - gW) / 2) + 1
            local gY = math.floor(h / 2) - 1

            term.setCursorPos(gX, gY)
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
            term.write("  === GAME OVER ===  ")

            term.setCursorPos(gX, gY + 1)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.yellow)
            term.write(string.format("  Score: %-10d  ", score))

            term.setCursorPos(gX, gY + 2)
            term.setTextColor(colors.white)
            term.write("  [Space/Tap] Restart ")
        end
    end

    local function getDropInterval()
        return math.max(0.08, 0.55 - (level - 1) * 0.05)
    end

    initGame()
    dropTimer = os.startTimer(getDropInterval())

    while true do
        drawGame()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == dropTimer then
            if not gameOver then
                if isValid(currentPiece, currentPiece.x, currentPiece.y + 1) then
                    currentPiece.y = currentPiece.y + 1
                else
                    lockPiece()
                    clearLines()
                    spawnNextPiece()
                end
                dropTimer = os.startTimer(getDropInterval())
            end

        elseif event == "key" then
            local key = p1
            if key == keys.q or key == keys.tab then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
            elseif gameOver then
                if key == keys.space or key == keys.enter or key == keys.r then
                    initGame()
                    dropTimer = os.startTimer(getDropInterval())
                end
            else
                if key == keys.left or key == keys.a then
                    moveHorizontal(-1)
                elseif key == keys.right or key == keys.d then
                    moveHorizontal(1)
                elseif key == keys.up or key == keys.w then
                    rotatePiece()
                elseif key == keys.down or key == keys.s then
                    softDrop()
                elseif key == keys.space then
                    hardDrop()
                end
            end

        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3

            -- Title Bar [X] to quit
            if cy == 1 and cx >= w - 3 then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
            end

            -- Restart on Game Over
            if gameOver then
                initGame()
                dropTimer = os.startTimer(getDropInterval())
            elseif isPocket and cy == h then
                -- Pocket on-screen touch buttons: "[<] [Rot] [>] [Drop]   [Q]"
                if cx >= 2 and cx <= 4 then
                    moveHorizontal(-1)
                elseif cx >= 6 and cx <= 10 then
                    rotatePiece()
                elseif cx >= 12 and cx <= 14 then
                    moveHorizontal(1)
                elseif cx >= 16 and cx <= 21 then
                    hardDrop()
                elseif cx >= w - 3 then
                    if score > 0 then scoreCache.recordScore(gameName, score, username) end
                    break
                end
            else
                -- Tap zones on playfield:
                -- Upper half: rotate
                -- Left side: move left
                -- Right side: move right
                -- Lower center: drop
                if cy < math.floor(h * 0.4) then
                    rotatePiece()
                elseif cy >= math.floor(h * 0.7) then
                    hardDrop()
                elseif cx < math.floor(w / 2) then
                    moveHorizontal(-1)
                else
                    moveHorizontal(1)
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
    print("Tetris Error: " .. tostring(err))
    print("Press any key to return...")
    pcall(os.pullEvent)
end
