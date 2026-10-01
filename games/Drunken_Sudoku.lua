--[[
    Sudoku Master (v2.0)
    Windows 95 Arcade Edition for Drunken OS
    by Antigravity & MuhendizBey
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
local gameName = "Drunken_Sudoku"

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

    -- Windows 95 Theme Palette
    local cWinBg = safeColor("lightGray", colors.black)
    local cTitleBg = safeColor("blue", colors.gray)
    local cTitleText = colors.white
    local cGridBg = colors.black
    local cLine = safeColor("gray", colors.lightGray)
    local cFixed = colors.white
    local cUser = safeColor("cyan", colors.yellow)
    local cCursor = safeColor("yellow", colors.white)
    local cMatch = safeColor("brown", colors.gray)
    local cError = colors.red

    local state = {
        grid = {},
        fixed = {},
        cursorX = 1,
        cursorY = 1,
        won = false,
        mistakes = 0
    }

    local function generateGrid()
        local base = {
            {1,2,3, 4,5,6, 7,8,9},
            {4,5,6, 7,8,9, 1,2,3},
            {7,8,9, 1,2,3, 4,5,6},
            {2,3,4, 5,6,7, 8,9,1},
            {5,6,7, 8,9,1, 2,3,4},
            {8,9,1, 2,3,4, 5,6,7},
            {3,4,5, 6,7,8, 9,1,2},
            {6,7,8, 9,1,2, 3,4,5},
            {9,1,2, 3,4,5, 6,7,8}
        }
        
        local map = {1,2,3,4,5,6,7,8,9}
        for i = 9, 2, -1 do
            local j = math.random(1, i)
            map[i], map[j] = map[j], map[i]
        end
        
        for r = 1, 9 do
            state.grid[r] = {}
            state.fixed[r] = {}
            for c = 1, 9 do
                state.grid[r][c] = map[base[r][c]]
                state.fixed[r][c] = true
            end
        end
        
        for band = 0, 2 do
            local r1, r2, r3 = band*3+1, band*3+2, band*3+3
            if math.random() > 0.5 then state.grid[r1], state.grid[r2] = state.grid[r2], state.grid[r1] end
            if math.random() > 0.5 then state.grid[r2], state.grid[r3] = state.grid[r3], state.grid[r2] end
            if math.random() > 0.5 then state.grid[r1], state.grid[r3] = state.grid[r3], state.grid[r1] end
        end
        
        for stack = 0, 2 do
            local c1, c2, c3 = stack*3+1, stack*3+2, stack*3+3
            local function swapCol(ca, cb)
                for r = 1, 9 do
                    state.grid[r][ca], state.grid[r][cb] = state.grid[r][cb], state.grid[r][ca]
                end
            end
            if math.random() > 0.5 then swapCol(c1, c2) end
            if math.random() > 0.5 then swapCol(c2, c3) end
            if math.random() > 0.5 then swapCol(c1, c3) end
        end
        
        -- Carve out holes
        local holes = isPocket and 36 or 42
        while holes > 0 do
            local r = math.random(1, 9)
            local c = math.random(1, 9)
            if state.grid[r][c] ~= 0 then
                state.grid[r][c] = 0
                state.fixed[r][c] = false
                holes = holes - 1
            end
        end
    end

    local function checkWin()
        for r = 1, 9 do
            for c = 1, 9 do
                if state.grid[r][c] == 0 then return false end
            end
        end
        
        for i = 1, 9 do
            local rSet, cSet = {}, {}
            for j = 1, 9 do
                rSet[state.grid[i][j]] = true
                cSet[state.grid[j][i]] = true
            end
            local rCount, cCount = 0, 0
            for _ in pairs(rSet) do rCount = rCount + 1 end
            for _ in pairs(cSet) do cCount = cCount + 1 end
            if rCount < 9 or cCount < 9 then return false end
        end
        
        for br = 0, 2 do
            for bc = 0, 2 do
                local bSet = {}
                for r = 1, 3 do
                    for c = 1, 3 do
                        bSet[state.grid[br*3+r][bc*3+c]] = true
                    end
                end
                local bCount = 0
                for _ in pairs(bSet) do bCount = bCount + 1 end
                if bCount < 9 then return false end
            end
        end
        
        return true
    end

    local function handleWin()
        state.won = true
        Sound.playSuccess()
        local pts = math.max(100, 1000 - state.mistakes * 50)
        scoreCache.recordScore(gameName, pts, username)
    end

    local function initGame()
        math.randomseed(os.epoch("utc"))
        generateGrid()
        state.won = false
        state.mistakes = 0
        state.cursorX = 5
        state.cursorY = 5
    end

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
        term.write(" Sudoku Master")
        term.setCursorPos(w - 2, 1)
        term.write("[X]")

        -- Top Stats Bar
        term.setCursorPos(2, 2)
        term.setBackgroundColor(cWinBg)
        term.setTextColor(colors.black)
        term.write(string.format("Player: %s", username:sub(1, 10)))

        local bestScore = scoreCache.getPersonalBest(gameName)
        local pbStr = string.format("Best: %d", bestScore)
        term.setCursorPos(math.max(16, w - #pbStr - 2), 2)
        term.setTextColor(colors.blue)
        term.write(pbStr)

        -- Grid Layout
        local ox = math.floor((w - 25) / 2) + 1
        local oy = 3
        if h >= 19 then oy = 4 end

        local curVal = state.grid[state.cursorY][state.cursorX]

        local function drawHoriz(rowIdx)
            term.setCursorPos(ox, oy + rowIdx)
            term.setTextColor(cLine)
            term.setBackgroundColor(cGridBg)
            term.write("+-------+-------+-------+")
        end

        for r = 1, 9 do
            if r % 3 == 1 then
                drawHoriz(r - 1 + math.floor((r - 1) / 3))
            end

            local drawY = oy + r - 1 + math.floor((r - 1) / 3) + 1
            term.setCursorPos(ox, drawY)

            for c = 1, 9 do
                if c % 3 == 1 then
                    term.setTextColor(cLine)
                    term.setBackgroundColor(cGridBg)
                    term.write("| ")
                end

                local val = state.grid[r][c]
                local isFixed = state.fixed[r][c]
                local isCursor = (r == state.cursorY and c == state.cursorX)
                local isSameNum = (val > 0 and val == curVal and not isCursor)

                local bg = cGridBg
                local fg = isFixed and cFixed or cUser

                if isCursor then
                    bg = cCursor
                    fg = colors.black
                elseif isSameNum then
                    bg = cMatch
                end

                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                local char = (val == 0) and "." or tostring(val)
                term.write(char .. " ")
            end

            term.setTextColor(cLine)
            term.setBackgroundColor(cGridBg)
            term.write("|")
        end
        drawHoriz(12)

        -- Interactive Touch Number Keypad
        local keypadY = oy + 13
        if keypadY <= h - 1 then
            term.setCursorPos(1, keypadY)
            term.setBackgroundColor(cWinBg)
            term.clearLine()
            
            -- Draw Keypad Buttons [1][2][3][4][5][6][7][8][9][X]
            local keypadStr = "[1][2][3][4][5][6][7][8][9][X]"
            local kx = math.floor((w - #keypadStr) / 2) + 1
            term.setCursorPos(kx, keypadY)
            term.setTextColor(colors.blue)
            term.write(keypadStr)
        end

        -- Footer Bar
        term.setCursorPos(1, h)
        term.setBackgroundColor(cLine)
        term.setTextColor(colors.white)
        term.clearLine()
        if isPocket then
            term.setCursorPos(2, h)
            term.write("Tap Cell & Num | [Q:Quit]")
        else
            term.setCursorPos(2, h)
            term.write("Arrows: Move | 1-9: Enter | Space: Clear | [Q] Quit")
        end

        -- Win Banner
        if state.won then
            local gW = math.min(w - 4, 22)
            local gX = math.floor((w - gW) / 2) + 1
            local gY = math.floor(h / 2) - 1

            term.setCursorPos(gX, gY)
            term.setBackgroundColor(colors.lime)
            term.setTextColor(colors.black)
            term.write("  === PUZZLE SOLVED! ===  ")

            term.setCursorPos(gX, gY + 1)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.yellow)
            term.write("   Congratulations!       ")

            term.setCursorPos(gX, gY + 2)
            term.setTextColor(colors.white)
            term.write("   [Space/Tap] New Game   ")
        end
    end

    local function setCellValue(n)
        if state.won then return end
        if not state.fixed[state.cursorY][state.cursorX] then
            state.grid[state.cursorY][state.cursorX] = n
            if n > 0 then
                Sound.playClick()
            else
                Sound.playNote("hat", 0.5, 10)
            end
            if checkWin() then
                handleWin()
            end
        end
    end

    initGame()

    while true do
        drawGame()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "key" then
            local key = p1
            if key == keys.q or key == keys.tab then
                break
            elseif state.won then
                if key == keys.space or key == keys.enter or key == keys.r then
                    initGame()
                end
            else
                if key == keys.up and state.cursorY > 1 then
                    state.cursorY = state.cursorY - 1
                elseif key == keys.down and state.cursorY < 9 then
                    state.cursorY = state.cursorY + 1
                elseif key == keys.left and state.cursorX > 1 then
                    state.cursorX = state.cursorX - 1
                elseif key == keys.right and state.cursorX < 9 then
                    state.cursorX = state.cursorX + 1
                elseif key >= keys.one and key <= keys.nine then
                    setCellValue(key - keys.one + 1)
                elseif key >= keys.numPad1 and key <= keys.numPad9 then
                    setCellValue(key - keys.numPad1 + 1)
                elseif key == keys.zero or key == keys.numPad0 or key == keys.backspace or key == keys.delete or key == keys.space then
                    setCellValue(0)
                elseif key == keys.r then
                    initGame()
                end
            end

        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3

            -- Title bar [X] to quit
            if cy == 1 and cx >= w - 3 then
                break
            end

            -- Restart on Win click
            if state.won then
                initGame()
            else
                local ox = math.floor((w - 25) / 2) + 1
                local oy = (h >= 19) and 4 or 3
                local keypadY = oy + 13

                -- Check Keypad click: "[1][2][3][4][5][6][7][8][9][X]"
                if cy == keypadY then
                    local keypadStr = "[1][2][3][4][5][6][7][8][9][X]"
                    local kx = math.floor((w - #keypadStr) / 2) + 1
                    local rel = cx - kx
                    if rel >= 0 and rel < #keypadStr then
                        local btnIdx = math.floor(rel / 3) + 1
                        if btnIdx >= 1 and btnIdx <= 9 then
                            setCellValue(btnIdx)
                        elseif btnIdx == 10 then
                            setCellValue(0)
                        end
                    end
                end

                -- Check Grid click
                -- Grid rows occupy:
                -- r=1..3 -> drawY = oy + 1, 2, 3
                -- r=4..6 -> drawY = oy + 5, 6, 7
                -- r=7..9 -> drawY = oy + 9, 10, 11
                for r = 1, 9 do
                    local drawY = oy + r - 1 + math.floor((r - 1) / 3) + 1
                    if cy == drawY then
                        -- Check X coordinate for col 1..9
                        local relX = cx - ox
                        if relX >= 2 and relX <= 24 then
                            -- Block 0: relX 2..7 (c=1,2,3)
                            -- Block 1: relX 10..15 (c=4,5,6)
                            -- Block 2: relX 18..23 (c=7,8,9)
                            local block = math.floor(relX / 8)
                            local inBlock = relX % 8
                            if inBlock >= 2 and inBlock <= 7 then
                                local c = block * 3 + math.floor((inBlock - 2) / 2) + 1
                                if c >= 1 and c <= 9 then
                                    state.cursorX = c
                                    state.cursorY = r
                                    Sound.playClick()
                                end
                            end
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
    print("Sudoku Error: " .. tostring(err))
    print("Press any key to return...")
    pcall(os.pullEvent)
end
