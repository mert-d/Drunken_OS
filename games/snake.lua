--[[
    Snake (v1.2)
    by MuhendizBey

    Purpose:
    A classic snake game for the Drunken OS.
    Updated for auto-updater compatibility.
]]

-- Load shared libraries
package.path = "/?.lua;" .. package.path
local sharedTheme = require("lib.theme")

local currentVersion = 7.2

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

    -- Use shared theme colors
    local theme = {
        bg = sharedTheme.bg,
        windowBg = sharedTheme.windowBg,
        snake = sharedTheme.game.snake,
        fruit = sharedTheme.game.fruit,
        text = sharedTheme.text,
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
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.windowBg)
        term.clear()
        
        -- Draw subtle frame/border
        term.setBackgroundColor(colors.cyan)
        term.setCursorPos(1, 1); term.write(string.rep(" ", w))
        term.setCursorPos(1, h); term.write(string.rep(" ", w))
        for i = 2, h - 1 do
            term.setCursorPos(1, i); term.write(" ")
            term.setCursorPos(w, i); term.write(" ")
        end

        term.setCursorPos(1, 1)
        term.setTextColor(theme.text)
        local titleText = " " .. (gameName or "Drunken OS Game") .. " "
        local titleStart = math.floor((w - #titleText) / 2) + 1
        term.setCursorPos(titleStart, 1)
        term.write(titleText)

        term.setBackgroundColor(theme.windowBg)
        term.setCursorPos(fruit.x, fruit.y)
        term.setBackgroundColor(theme.fruit)
        term.write(" ")

        for _, segment in ipairs(snake) do
            term.setCursorPos(segment.x, segment.y)
            term.setBackgroundColor(theme.snake)
            term.write(" ")
        end

        term.setBackgroundColor(theme.windowBg)
        term.setTextColor(theme.text)
        local scoreText = "Score: " .. score
        term.setCursorPos(math.floor(w / 2 - #scoreText / 2), h)
        term.setBackgroundColor(colors.cyan)
        term.write(" " .. scoreText .. " ")
    end

    local function submitScore() 
        if arcadeServerId then 
            rednet.send(arcadeServerId, {
                type = "submit_score", 
                game = gameName, 
                user = username, 
                score = score, 
                timestamp = os.epoch("utc")
            }, "ArcadeGames") 
        end 
    end

    local function showGameOverScreen()
        submitScore()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.windowBg); term.clear()
        local scoreText = "Game Over! Final Score: " .. score
        term.setCursorPos(math.floor(w/2 - #scoreText/2), math.floor(h/2))
        term.write(scoreText)
        sleep(3)
    end

    local modem = peripheral.find("modem")
    if modem then rednet.open(peripheral.getName(modem)) end
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
            elseif p1 == keys.q or p1 == keys.tab then gameOver = true
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
