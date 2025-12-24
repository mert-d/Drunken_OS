--[[
    Drunken Sokoban (v1.0)
    by Gemini Gem

    Purpose:
    A classic box-pushing puzzle for Drunken OS.
    Push all crates onto the target spots to win!
]]

local gameVersion = 1.0

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenSokoban"
    local arcadeServerId = nil

    -- Theme & Colors
    local hasColor = term.isColor and term.isColor()
    local function safeColor(c, f) return (hasColor and colors[c]) and colors[c] or f end

    local theme = {
        bg = colors.black,
        text = colors.white,
        border = colors.cyan,
        player = safeColor("yellow", colors.white),
        box = safeColor("orange", colors.brown),
        target = safeColor("lime", colors.green),
        wall = safeColor("gray", colors.lightGray),
        boxOnTarget = safeColor("green", colors.lime),
    }

    -- Level Data (Simple 1st Level)
    local levels = {
        {
            map = {
                "  ##### ",
                "###   # ",
                "# .X  # ",
                "### X.# ",
                "# .X  # ",
                "# #   # ",
                "#   @ # ",
                "####### "
            },
            name = "Safe Storage"
        },
        {
            map = {
                "#######",
                "#     #",
                "# X . #",
                "# . X #",
                "#  @  #",
                "#######"
            },
            name = "The Lobby"
        }
    }

    -- State
    local currentLevel = 1
    local board = {}
    local player = { x = 1, y = 1 }
    local moveCount = 0

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function loadLevel(num)
        local lvl = levels[num]
        board = {}
        for y, row in ipairs(lvl.map) do
            board[y] = {}
            for x = 1, #row do
                local char = row:sub(x, x)
                if char == "@" then
                    player.x, player.y = x, y
                    board[y][x] = " "
                else
                    board[y][x] = char
                end
            end
        end
        moveCount = 0
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
        local title = " Drunken Sokoban v" .. gameVersion .. " "
        term.setCursorPos(math.floor((w - #title)/2), 1); term.write(title)
    end

    local function drawBoard()
        drawFrame()
        local w, h = getSafeSize()
        local lvl = levels[currentLevel]
        local mh = #board
        local mw = 0
        for _, r in ipairs(board) do mw = math.max(mw, #r) end

        local ox = math.floor((w - mw) / 2)
        local oy = math.floor((h - mh) / 2)

        for y, row in ipairs(board) do
            term.setCursorPos(ox, oy + y - 1)
            for x, char in ipairs(row) do
                local fg = theme.text
                local bg = theme.bg
                local display = char

                if x == player.x and y == player.y then
                    display = "@"
                    fg = theme.player
                elseif char == "#" then
                    fg = theme.wall
                elseif char == "X" then
                    fg = theme.box
                elseif char == "." then
                    fg = theme.target
                elseif char == "Y" then -- Box on target
                    display = "X"
                    fg = theme.boxOnTarget
                end

                term.setTextColor(fg)
                term.write(display)
            end
        end

        term.setTextColor(theme.text)
        term.setCursorPos(2, h-2); term.write("Level: " .. currentLevel .. " | Moves: " .. moveCount)
        term.setCursorPos(math.floor(w/2 - 10), h)
        term.setBackgroundColor(theme.border); term.write(" ARROWS: Move | R: Restart | Q: Quit ")
    end

    local function move(dx, dy)
        local nx, ny = player.x + dx, player.y + dy
        local target = board[ny][nx]

        if target == "#" then return end -- Wall

        if target == "X" or target == "Y" then
            -- Push logic
            local bx, by = nx + dx, ny + dy
            local boxTarget = board[by][bx]
            if boxTarget == " " or boxTarget == "." then
                -- Move box
                board[ny][nx] = (target == "Y") and "." or " "
                board[by][bx] = (boxTarget == ".") and "Y" or "X"
                -- Move player
                player.x, player.y = nx, ny
                moveCount = moveCount + 1
            end
        else
            -- Normal move
            player.x, player.y = nx, ny
            moveCount = moveCount + 1
        end
    end

    local function checkWin()
        for y, row in ipairs(board) do
            for x, char in ipairs(row) do
                if char == "X" then return false end
            end
        end
        return true
    end

    loadLevel(currentLevel)

    while true do
        drawBoard()
        local event, key = os.pullEvent("key")
        if key == keys.up then move(0, -1)
        elseif key == keys.down then move(0, 1)
        elseif key == keys.left then move(-1, 0)
        elseif key == keys.right then move(1, 0)
        elseif key == keys.r then loadLevel(currentLevel)
        elseif key == keys.q then return end

        if checkWin() then
            drawBoard()
            term.setCursorPos(1, h-1); print("Level Clear!")
            sleep(1)
            currentLevel = currentLevel + 1
            if currentLevel > #levels then
                print("Game Complete!")
                score = moveCount -- In Sokoban lower is better, but arcade server usually expects higher. 
                -- We'll submit a inverted score or just the count.
                arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
                if arcadeServerId then
                    rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = 1000 - moveCount}, "ArcadeGames")
                end
                sleep(2)
                return
            end
            loadLevel(currentLevel)
        end
    end
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Sokoban Error: " .. err)
    os.pullEvent("key")
end
