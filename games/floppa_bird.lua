--[[
    Floppa Bird (v2.0)
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
local gameName = "FloppaBird"

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
    local cSkyBg = safeColor("lightBlue", colors.black)
    local cTitleBg = safeColor("blue", colors.gray)
    local cTitleText = colors.white
    local cPipe = safeColor("green", colors.gray)
    local cBird = safeColor("yellow", colors.white)
    local cGround = safeColor("brown", colors.gray)

    -- Boundaries
    local minY = 3
    local maxY = h - 2
    local skyH = maxY - minY + 1

    -- Physics State
    local player = { x = 6, y = math.floor(h / 2), dy = 0 }
    local gravity = 0.45
    local flapStrength = -1.8
    local pipes = {}
    local score = 0
    local gameOver = false
    local gameTimer = nil
    local personalBest = scoreCache.getPersonalBest(gameName)

    local function createPipe()
        local gapSize = isPocket and 5 or 6
        local minPipe = 2
        local maxGapY = skyH - gapSize - minPipe
        local gapY = math.random(minPipe, math.max(minPipe, maxGapY))

        table.insert(pipes, {
            x = w,
            gapTop = minY + gapY,
            gapBottom = minY + gapY + gapSize,
            width = isPocket and 3 or 4,
            scored = false
        })
    end

    local function initGame()
        w, h = term.getSize()
        isPocket = (w <= 30)
        minY = 3
        maxY = h - 2
        skyH = maxY - minY + 1

        player = { x = isPocket and 5 or 8, y = math.floor((minY + maxY) / 2), dy = 0 }
        pipes = {}
        score = 0
        gameOver = false
        personalBest = scoreCache.getPersonalBest(gameName)
        createPipe()
    end

    local function flap()
        if gameOver then return end
        player.dy = flapStrength
        Sound.playNote("hat", 0.5, 18)
    end

    local function update()
        if gameOver then return end

        -- Apply gravity
        player.dy = player.dy + gravity
        player.y = player.y + player.dy

        -- Ceiling / Floor collision
        if player.y < minY or player.y > maxY then
            gameOver = true
            Sound.playNote("bass", 1.5, 4)
            scoreCache.recordScore(gameName, score, username)
            return
        end

        -- Update pipes
        for i = #pipes, 1, -1 do
            local p = pipes[i]
            p.x = p.x - 1

            -- Check scoring
            if not p.scored and (p.x + p.width) < player.x then
                p.scored = true
                score = score + 1
                Sound.playNote("pling", 1.0, 18)
            end

            -- Collision detection
            local playerIntY = math.floor(player.y + 0.5)
            if player.x >= p.x and player.x < (p.x + p.width) then
                if playerIntY < p.gapTop or playerIntY >= p.gapBottom then
                    gameOver = true
                    Sound.playNote("bass", 1.5, 4)
                    scoreCache.recordScore(gameName, score, username)
                    return
                end
            end

            -- Remove off-screen pipes
            if p.x + p.width < 1 then
                table.remove(pipes, i)
            end
        end

        -- Spawn new pipes
        if #pipes == 0 or pipes[#pipes].x <= (w - (isPocket and 12 or 16)) then
            createPipe()
        end
    end

    local function drawGame()
        w, h = term.getSize()
        isPocket = (w <= 30)

        -- Windows 95 Window Frame
        term.setBackgroundColor(cWinBg)
        term.clear()

        -- Title Bar
        term.setCursorPos(1, 1)
        term.setBackgroundColor(cTitleBg)
        term.setTextColor(cTitleText)
        term.clearLine()
        term.write(" Floppa Bird")
        term.setCursorPos(w - 2, 1)
        term.write("[X]")

        -- Top Score LCD
        term.setCursorPos(2, 2)
        term.setBackgroundColor(cWinBg)
        term.setTextColor(colors.black)
        term.write(string.format("Score: %03d", score))

        local bestStr = string.format("Best: %d", math.max(score, personalBest))
        term.setCursorPos(math.max(14, w - #bestStr - 2), 2)
        term.setTextColor(colors.blue)
        term.write(bestStr)

        -- Sky Canvas Interior
        term.setBackgroundColor(cSkyBg)
        for y = minY, maxY do
            term.setCursorPos(1, y)
            term.write(string.rep(" ", w))
        end

        -- Draw Pipes
        for _, p in ipairs(pipes) do
            for y = minY, maxY do
                if y < p.gapTop or y >= p.gapBottom then
                    for px = 0, p.width - 1 do
                        local drawX = p.x + px
                        if drawX >= 1 and drawX <= w then
                            term.setCursorPos(drawX, y)
                            term.setBackgroundColor(cPipe)
                            term.setTextColor(colors.black)
                            term.write(px == 0 and "[" or (px == p.width - 1 and "]" or "#"))
                        end
                    end
                end
            end
        end

        -- Draw Player (Floppa Bird)
        local py = math.floor(player.y + 0.5)
        if py >= minY and py <= maxY and player.x >= 1 and player.x <= w then
            term.setCursorPos(player.x - 1, py)
            term.setBackgroundColor(cBird)
            term.setTextColor(colors.black)
            term.write("(o>")
        end

        -- Ground Bar
        term.setCursorPos(1, maxY + 1)
        term.setBackgroundColor(cGround)
        term.setTextColor(colors.yellow)
        term.write(string.rep("^", w))

        -- Bottom Hint
        term.setCursorPos(1, h)
        term.setBackgroundColor(cWinBg)
        term.setTextColor(colors.gray)
        term.clearLine()
        if isPocket then
            term.setCursorPos(2, h)
            term.write("Tap to flap | [Q:Quit]")
        else
            term.setCursorPos(2, h)
            term.write("Space/Tap to Flap | [Q] Quit")
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

    -- Initial Start Screen
    initGame()
    drawGame()

    local startMsg = "Tap or Space to start"
    term.setCursorPos(math.floor((w - #startMsg) / 2) + 1, math.floor(h / 2))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.write(" " .. startMsg .. " ")

    while true do
        local e, p1 = os.pullEvent()
        if e == "key" then
            if p1 == keys.q or p1 == keys.tab then return end
            flap()
            break
        elseif e == "mouse_click" then
            if p1 == 1 and p2 and p3 and p3 == 1 and p2 >= w - 3 then return end
            flap()
            break
        end
    end

    gameTimer = os.startTimer(0.12)

    while true do
        drawGame()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == gameTimer then
            if not gameOver then
                update()
                gameTimer = os.startTimer(0.12)
            end

        elseif event == "key" then
            local key = p1
            if key == keys.q or key == keys.tab then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
            elseif gameOver then
                if key == keys.space or key == keys.enter or key == keys.r then
                    initGame()
                    gameTimer = os.startTimer(0.12)
                end
            else
                if key == keys.space or key == keys.up or key == keys.w then
                    flap()
                end
            end

        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            if cy == 1 and cx >= w - 3 then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
            end

            if gameOver then
                initGame()
                gameTimer = os.startTimer(0.12)
            else
                flap()
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
    print("Floppa Bird Error: " .. tostring(err))
    print("Press any key to return...")
    pcall(os.pullEvent)
end
