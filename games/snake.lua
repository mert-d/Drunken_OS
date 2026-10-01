--[[
    Retro Snake (v2.0)
    Windows 95 Arcade Edition for Drunken OS
    by MuhendizBey & Antigravity
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
local gameName = "Snake"

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
    local cBoardBg = colors.black
    local cTitleBg = safeColor("blue", colors.gray)
    local cTitleText = colors.white
    local cBorder = safeColor("gray", colors.gray)
    local cSnakeHead = safeColor("lime", colors.white)
    local cSnakeBody = safeColor("green", colors.lightGray)
    local cFruit = safeColor("red", colors.white)
    local cGoldenFruit = safeColor("yellow", colors.white)

    -- Playfield Boundaries (enclosed in Win95 frame)
    local minX, maxX = 2, w - 1
    local minY, maxY = 4, h - 2
    local playW = maxX - minX + 1
    local playH = maxY - minY + 1

    -- Game State
    local snake = {}
    local fruit = { x = 0, y = 0, isGold = false }
    local dir = { x = 1, y = 0 }
    local nextDir = { x = 1, y = 0 }
    local score = 0
    local fruitsEaten = 0
    local speed = 0.16
    local gameOver = false
    local gameTimer = nil
    local personalBest = scoreCache.getPersonalBest(gameName)

    local function spawnFruit()
        local valid = false
        local rx, ry
        local attempts = 0
        while not valid and attempts < 200 do
            attempts = attempts + 1
            rx = math.random(minX, maxX)
            ry = math.random(minY, maxY)
            valid = true
            for _, seg in ipairs(snake) do
                if seg.x == rx and seg.y == ry then
                    valid = false
                    break
                end
            end
        end
        local isGold = (fruitsEaten > 0 and (fruitsEaten % 5 == 0))
        fruit = { x = rx, y = ry, isGold = isGold }
    end

    local function initGame()
        w, h = term.getSize()
        minX, maxX = 2, w - 1
        minY, maxY = 4, h - 2
        playW = maxX - minX + 1
        playH = maxY - minY + 1

        local startX = math.floor(minX + playW / 3)
        local startY = math.floor(minY + playH / 2)
        snake = {
            { x = startX,     y = startY },
            { x = startX - 1, y = startY },
            { x = startX - 2, y = startY }
        }
        dir = { x = 1, y = 0 }
        nextDir = { x = 1, y = 0 }
        score = 0
        fruitsEaten = 0
        speed = isPocket and 0.18 or 0.15
        gameOver = false
        personalBest = scoreCache.getPersonalBest(gameName)
        spawnFruit()
    end

    local function changeDirection(dx, dy)
        -- Prevent 180-degree immediate reversal into own neck
        if (dx ~= 0 and dir.x == 0) or (dy ~= 0 and dir.y == 0) then
            nextDir = { x = dx, y = dy }
        end
    end

    local function update()
        if gameOver then return end
        dir = nextDir

        local head = snake[1]
        local newHead = { x = head.x + dir.x, y = head.y + dir.y }

        -- Wall Collision
        if newHead.x < minX or newHead.x > maxX or newHead.y < minY or newHead.y > maxY then
            gameOver = true
            Sound.playNote("bass", 1.5, 4)
            return
        end

        -- Self Collision
        for i = 1, #snake - 1 do
            if newHead.x == snake[i].x and newHead.y == snake[i].y then
                gameOver = true
                Sound.playNote("bass", 1.5, 4)
                return
            end
        end

        table.insert(snake, 1, newHead)

        -- Fruit Collision
        if newHead.x == fruit.x and newHead.y == fruit.y then
            fruitsEaten = fruitsEaten + 1
            if fruit.isGold then
                score = score + 300
                Sound.playNote("pling", 1.2, 22)
            else
                score = score + 100
                Sound.playNote("pling", 1.0, 16)
            end

            -- Gradually increase speed
            speed = math.max(0.08, speed - 0.003)
            spawnFruit()
        else
            table.remove(snake)
        end
    end

    local function drawGame()
        w, h = term.getSize()
        minX, maxX = 2, w - 1
        minY, maxY = 4, h - 2

        -- Background Frame (Windows 95 Light Gray)
        term.setBackgroundColor(cWinBg)
        term.clear()

        -- Title Bar
        term.setCursorPos(1, 1)
        term.setBackgroundColor(cTitleBg)
        term.setTextColor(cTitleText)
        term.clearLine()
        term.write(" Retro Snake")
        term.setCursorPos(w - 2, 1)
        term.write("[X]")

        -- Top Stats Bar
        term.setCursorPos(2, 2)
        term.setBackgroundColor(cWinBg)
        term.setTextColor(colors.black)
        term.write(string.format("Score: %05d", score))

        local pbStr = string.format("Best: %d", math.max(score, personalBest))
        term.setCursorPos(math.max(16, w - #pbStr - 2), 2)
        term.setTextColor(colors.blue)
        term.write(pbStr)

        -- Playfield Border (Beveled Dark Frame)
        term.setCursorPos(minX - 1, minY - 1)
        term.setBackgroundColor(cBorder)
        term.write(string.rep("-", maxX - minX + 3))

        term.setCursorPos(minX - 1, maxY + 1)
        term.write(string.rep("-", maxX - minX + 3))

        for y = minY, maxY do
            term.setCursorPos(minX - 1, y)
            term.write("|")
            term.setCursorPos(maxX + 1, y)
            term.write("|")
        end

        -- Black Playfield Interior
        term.setBackgroundColor(cBoardBg)
        for y = minY, maxY do
            term.setCursorPos(minX, y)
            term.write(string.rep(" ", maxX - minX + 1))
        end

        -- Draw Fruit
        if fruit.x >= minX and fruit.x <= maxX and fruit.y >= minY and fruit.y <= maxY then
            term.setCursorPos(fruit.x, fruit.y)
            if fruit.isGold then
                term.setBackgroundColor(cBoardBg)
                term.setTextColor(cGoldenFruit)
                term.write("$")
            else
                term.setBackgroundColor(cBoardBg)
                term.setTextColor(cFruit)
                term.write("@")
            end
        end

        -- Draw Snake
        for idx, seg in ipairs(snake) do
            if seg.x >= minX and seg.x <= maxX and seg.y >= minY and seg.y <= maxY then
                term.setCursorPos(seg.x, seg.y)
                if idx == 1 then
                    term.setBackgroundColor(cSnakeHead)
                    term.setTextColor(colors.black)
                    -- Head directional character
                    local hChar = (dir.x == 1 and ">") or (dir.x == -1 and "<") or (dir.y == -1 and "^") or "v"
                    term.write(hChar)
                else
                    term.setBackgroundColor(cSnakeBody)
                    term.setTextColor(colors.white)
                    term.write("o")
                end
            end
        end

        -- Bottom Hint
        term.setCursorPos(1, h)
        term.setBackgroundColor(cBorder)
        term.setTextColor(colors.white)
        term.clearLine()
        if isPocket then
            term.setCursorPos(2, h)
            term.write("Tap sides to turn | [Q:Quit]")
        else
            term.setCursorPos(2, h)
            term.write("Arrows/WASD or Click/Tap to Turn | [Q:Quit]")
        end

        -- Game Over Banner
        if gameOver then
            local boxW = math.min(w - 4, 24)
            local boxX = math.floor((w - boxW) / 2) + 1
            local boxY = math.floor(h / 2) - 1

            term.setCursorPos(boxX, boxY)
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
            term.write("   === GAME OVER ===   ")

            term.setCursorPos(boxX, boxY + 1)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.yellow)
            term.write(string.format("  Final Score: %-6d  ", score))

            term.setCursorPos(boxX, boxY + 2)
            term.setTextColor(colors.white)
            term.write("  [Space/Tap] Restart  ")
        end
    end

    local function handlePointerClick(cx, cy)
        -- Title bar [X]
        if cy == 1 and cx >= w - 3 then
            return "exit"
        end

        if gameOver then
            -- Restart
            scoreCache.recordScore(gameName, score, username)
            initGame()
            gameTimer = os.startTimer(speed)
            return "continue"
        end

        -- Touch-to-turn logic based on snake head position
        local head = snake[1]
        local dx = cx - head.x
        local dy = cy - head.y

        if math.abs(dx) > math.abs(dy) then
            -- Horizontal turn
            if dx > 0 then changeDirection(1, 0)
            else changeDirection(-1, 0) end
        else
            -- Vertical turn
            if dy > 0 then changeDirection(0, 1)
            else changeDirection(0, -1) end
        end
        return "continue"
    end

    initGame()
    gameTimer = os.startTimer(speed)

    while true do
        drawGame()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == gameTimer then
            if not gameOver then
                update()
                gameTimer = os.startTimer(speed)
            end

        elseif event == "key" then
            local key = p1
            if key == keys.q or key == keys.tab then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
            elseif gameOver then
                if key == keys.space or key == keys.enter or key == keys.r then
                    scoreCache.recordScore(gameName, score, username)
                    initGame()
                    gameTimer = os.startTimer(speed)
                end
            else
                if key == keys.up or key == keys.w then changeDirection(0, -1)
                elseif key == keys.down or key == keys.s then changeDirection(0, 1)
                elseif key == keys.left or key == keys.a then changeDirection(-1, 0)
                elseif key == keys.right or key == keys.d then changeDirection(1, 0)
                end
            end

        elseif event == "mouse_click" or event == "mouse_drag" then
            local btn, cx, cy = p1, p2, p3
            local act = handlePointerClick(cx, cy)
            if act == "exit" then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
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
    print("Snake Error: " .. tostring(err))
    print("Press any key to return...")
    pcall(os.pullEvent)
end
