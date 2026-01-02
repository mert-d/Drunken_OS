--[[
    Drunken Sweeper (v1.1)
    by Gemini Gem

    Purpose:
    A classic minesweeper puzzle for Drunken OS.
    Clear the board without hitting any mines!
]]

-- Load shared libraries
package.path = "/?.lua;" .. package.path
local sharedTheme = require("lib.theme")

local gameVersion = 1.2

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"
    local w, h = term.getSize()

    local gameName = "DrunkenSweeper"
    local arcadeServerId = nil

    -- Use shared theme colors
    local theme = {
        bg = sharedTheme.bg,
        text = sharedTheme.text,
        border = sharedTheme.prompt,
        hidden = sharedTheme.game.wall,
        revealed = sharedTheme.game.floor,
        mine = sharedTheme.game.enemy,
        flag = sharedTheme.game.charge,
        cursor = sharedTheme.game.gold,
    }

    local numColors = {
        [1] = colors.blue,
        [2] = colors.green,
        [3] = colors.red,
        [4] = colors.purple,
        [5] = colors.maroon,
        [6] = colors.cyan,
        [7] = colors.black,
        [8] = colors.gray
    }

    -- Board Configuration
    local w, h = term.getSize()
    local BOARD_W = 10
    local BOARD_H = 10
    local MINE_COUNT = 15

    -- Board State
    local board = {}
    local revealed = {}
    local flagged = {}
    local cursor = { x = 1, y = 1 }
    local gameState = "playing" -- playing, won, lost
    local score = 0
    local startTime = os.time()

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

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

        local placed = 0
        while placed < MINE_COUNT do
            local rx = math.random(1, BOARD_W)
            local ry = math.random(1, BOARD_H)
            if board[ry][rx] ~= -1 then
                board[ry][rx] = -1
                placed = placed + 1
            end
        end

        -- Calculate counts
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

    local function drawFrame()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.bg); term.clear()
        term.setBackgroundColor(theme.border)
        term.setCursorPos(1, 1); term.write(string.rep(" ", w))
        term.setCursorPos(1, h); term.write(string.rep(" ", w))
        for i = 2, h - 1 do
            term.setCursorPos(1, i); term.write(" ")
            term.setCursorPos(w, i); term.write(" ")
        end
        term.setCursorPos(1, 1); term.setTextColor(theme.text)
        local title = " Drunken Sweeper v" .. gameVersion .. " "
        term.setCursorPos(math.floor((w - #title)/2), 1); term.write(title)
    end

    local function drawBoard()
        drawFrame()
        local w, h = getSafeSize()
        local ox = math.floor((w - (BOARD_W * 3)) / 2)
        local oy = math.floor((h - BOARD_H) / 2)

        for y = 1, BOARD_H do
            term.setCursorPos(ox, oy + y - 1)
            for x = 1, BOARD_W do
                local char = "[ ]"
                local fg = theme.hidden
                local bg = theme.bg

                if cursor.x == x and cursor.y == y then
                    bg = theme.cursor
                    fg = colors.black
                end

                if revealed[y][x] then
                    bg = theme.revealed
                    if board[y][x] == -1 then
                        char = "[*]"
                        fg = theme.mine
                    elseif board[y][x] == 0 then
                        char = "   "
                    else
                        char = " " .. board[y][x] .. " "
                        fg = safeColor(numColors[board[y][x]] or colors.white, colors.white)
                    end
                elseif flagged[y][x] then
                    char = "[F]"
                    fg = theme.flag
                end

                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(char)
            end
        end

        -- HUD
        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.text)
        local status = " Mines: " .. MINE_COUNT .. " | Flags: " .. 0
        local fCount = 0
        for y=1, BOARD_H do for x=1, BOARD_W do if flagged[y][x] then fCount = fCount + 1 end end end
        term.setCursorPos(2, h-2); term.write("Mines: " .. MINE_COUNT .. " | Flags: " .. fCount)
        
        term.setCursorPos(math.floor(w/2 - 12), h)
        term.setBackgroundColor(theme.border); term.write(" ARROWS: Move | ENTER: Reveal | SPACE: Flag ")
    end

    local function floodFill(x, y)
        if x < 1 or x > BOARD_W or y < 1 or y > BOARD_H or revealed[y][x] or flagged[y][x] then return end
        revealed[y][x] = true
        if board[y][x] == 0 then
            for dy = -1, 1 do
                for dx = -1, 1 do
                    floodFill(x + dx, y + dy)
                end
            end
        end
    end

    local function checkWin()
        local count = 0
        for y = 1, BOARD_H do
            for x = 1, BOARD_W do
                if revealed[y][x] then count = count + 1 end
            end
        end
        if count == (BOARD_W * BOARD_H) - MINE_COUNT then
            gameState = "won"
            return true
        end
        return false
    end

    initBoard()

    while gameState == "playing" do
        drawBoard()
        local event, key = os.pullEvent("key")
        if key == keys.up and cursor.y > 1 then cursor.y = cursor.y - 1
        elseif key == keys.down and cursor.y < BOARD_H then cursor.y = cursor.y + 1
        elseif key == keys.left and cursor.x > 1 then cursor.x = cursor.x - 1
        elseif key == keys.right and cursor.x < BOARD_W then cursor.x = cursor.x + 1
        elseif key == keys.space then
            if not revealed[cursor.y][cursor.x] then
                flagged[cursor.y][cursor.x] = not flagged[cursor.y][cursor.x]
            end
        elseif key == keys.enter then
            if not flagged[cursor.y][cursor.x] then
                if board[cursor.y][cursor.x] == -1 then
                    gameState = "lost"
                    -- Reveal all mines
                    for y=1, BOARD_H do for x=1, BOARD_W do if board[y][x] == -1 then revealed[y][x] = true end end end
                else
                    floodFill(cursor.x, cursor.y)
                    checkWin()
                end
            end
        elseif key == keys.q then
            return
        end
    end

    drawBoard()
    local w, h = getSafeSize()
    term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2 + 2))
    term.setBackgroundColor(colors.black)
    if gameState == "won" then
        term.setTextColor(colors.lime); term.write("YOU WON!")
        local score = 1000 -- Basic score for now
        local arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
        if arcadeServerId then
            rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = score}, "ArcadeGames")
        end
    else
        term.setTextColor(colors.red); term.write("GAME OVER")
    end
    sleep(2)
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Sweeper Error: " .. err)
    os.pullEvent("key")
end
