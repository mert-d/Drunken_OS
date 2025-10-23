--[[
    Snake (v1.0)
    by MuhendizBey

    Purpose:
    A classic snake game for the Drunken OS.
]]

--==============================================================================
-- Main Game Function (to be run inside pcall)
--==============================================================================

local function mainGame(...)
    local args = {...}
    local username = args[1]
    if not username then
        print("This game must be launched from the mail client.")
        print("Please select 'Play Games' from the menu.")
        sleep(4)
        return
    end

    local gameName = "Snake"
    local arcadeServerId = nil

    local snake, fruit, direction, score, gameOver = {}, {}, {1, 0}, 0, false

    local hasColor = term.isColor and term.isColor()
    local function safeColor(colorName, fallbackColor)
        if hasColor and colors[colorName] ~= nil then return colors[colorName] end
        return fallbackColor
    end

    local theme = {
        bg = safeColor("black", colors.black),
        windowBg = safeColor("darkGray", colors.gray),
        snake = safeColor("lime", colors.white),
        fruit = safeColor("red", colors.white),
        text = safeColor("white", colors.white),
    }

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function newGame()
        local w, h = getSafeSize()
        snake = { {x = math.floor(w/2), y = math.floor(h/2)} }
        fruit = { x = math.random(2, w-1), y = math.random(2, h-1) }
        direction = {1, 0}
        score = 0
        gameOver = false
    end

    local function update()
        local w, h = getSafeSize()
        local head = { x = snake[1].x + direction[1], y = snake[1].y + direction[2] }

        if head.x < 1 or head.x > w or head.y < 1 or head.y > h then
            gameOver = true
            return
        end

        for i = 2, #snake do
            if head.x == snake[i].x and head.y == snake[i].y then
                gameOver = true
                return
            end
        end

        table.insert(snake, 1, head)

        if head.x == fruit.x and head.y == fruit.y then
            score = score + 100
            fruit = { x = math.random(2, w-1), y = math.random(2, h-1) }
        else
            table.remove(snake)
        end
    end

    local function draw()
        term.setBackgroundColor(theme.windowBg)
        term.clear()
        local w, h = getSafeSize()

        term.setBackgroundColor(theme.fruit)
        term.setCursorPos(fruit.x, fruit.y); term.write(" ")

        term.setBackgroundColor(theme.snake)
        for _, segment in ipairs(snake) do
            term.setCursorPos(segment.x, segment.y); term.write(" ")
        end

        term.setBackgroundColor(theme.windowBg)
        term.setTextColor(theme.text)
        local scoreText = "Score: " .. score
        term.setCursorPos(math.floor(w / 2 - #scoreText / 2), 1)
        term.write(scoreText)
    end

    local function submitScore() if arcadeServerId then rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = score}, "ArcadeGames") end end

    local function showGameOverScreen()
        submitScore()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.windowBg); term.clear()
        local scoreText = "Game Over! Final Score: " .. score
        term.setCursorPos(math.floor(w/2 - #scoreText/2), math.floor(h/2))
        term.write(scoreText)
        sleep(3)
    end

    rednet.open("back")
    arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

    newGame()
    local gameTimer = os.startTimer(0.2)

    while not gameOver do
        local event, p1 = os.pullEvent()
        if event == "key" then
            if p1 == keys.up and direction[2] == 0 then direction = {0, -1}
            elseif p1 == keys.down and direction[2] == 0 then direction = {0, 1}
            elseif p1 == keys.left and direction[1] == 0 then direction = {-1, 0}
            elseif p1 == keys.right and direction[1] == 0 then direction = {1, 0}
            elseif p1 == keys.q then gameOver = true
            end
        elseif event == "timer" and p1 == gameTimer then
            update()
            draw()
            gameTimer = os.startTimer(0.2)
        elseif event == "terminate" then
            break
        end
    end

    showGameOverScreen()
    term.clear()
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("A critical error occurred:")
    print(err)
    print("\nPress any key to exit.")
    os.pullEvent("key")
end
