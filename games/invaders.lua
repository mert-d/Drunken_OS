--[[
    Space Invaders (v2.0)
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
local gameName = "Invaders"

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
    local cPlayer = safeColor("lime", colors.white)
    local cAlien = safeColor("yellow", colors.white)
    local cAlienAlt = safeColor("purple", colors.white)
    local cBullet = safeColor("cyan", colors.white)
    local cBomb = safeColor("red", colors.white)
    local cShield = safeColor("lightBlue", colors.white)

    -- Boundaries
    local minY = 3
    local maxY = h - 2
    local playW = w - 2

    -- Game State
    local player = { x = math.floor(w / 2), y = maxY - 1 }
    local aliens = {}
    local bullets = {}
    local bombs = {}
    local shields = {}
    local score = 0
    local lives = 3
    local wave = 1
    local gameOver = false
    local victory = false
    local gameTimer = nil
    local alienDir = 1
    local alienTick = 0
    local personalBest = scoreCache.getPersonalBest(gameName)

    local function createShields()
        shields = {}
        local shieldCount = isPocket and 3 or 4
        local spacing = math.floor(w / (shieldCount + 1))
        local shieldY = maxY - 3

        for i = 1, shieldCount do
            local sx = i * spacing
            for dx = -1, 1 do
                table.insert(shields, { x = sx + dx, y = shieldY, hp = 3 })
            end
        end
    end

    local function createAliens()
        aliens = {}
        local rows = isPocket and 3 or 4
        local cols = isPocket and 6 or 8
        local startX = math.floor((w - cols * 3) / 2) + 1

        for r = 1, rows do
            for c = 1, cols do
                table.insert(aliens, {
                    x = startX + (c - 1) * 3,
                    y = minY + (r - 1) * 2,
                    alive = true,
                    row = r
                })
            end
        end
        alienDir = 1
        alienTick = 0
    end

    local function initGame()
        w, h = term.getSize()
        isPocket = (w <= 30)
        minY = 3
        maxY = h - 2
        playW = w - 2

        player = { x = math.floor(w / 2), y = maxY - 1 }
        bullets = {}
        bombs = {}
        score = 0
        lives = 3
        wave = 1
        gameOver = false
        victory = false
        personalBest = scoreCache.getPersonalBest(gameName)

        createAliens()
        createShields()
    end

    local function fireBullet()
        if gameOver then return end
        if #bullets < 2 then
            table.insert(bullets, { x = player.x, y = player.y - 1 })
            Sound.playNote("chime", 0.5, 20)
        end
    end

    local function update()
        if gameOver then return end

        -- 1. Move Player Bullets
        for i = #bullets, 1, -1 do
            local b = bullets[i]
            b.y = b.y - 1

            -- Check Collision with Shields
            local hitShield = false
            for si = #shields, 1, -1 do
                local s = shields[si]
                if s.x == b.x and s.y == b.y then
                    s.hp = s.hp - 1
                    if s.hp <= 0 then table.remove(shields, si) end
                    hitShield = true
                    break
                end
            end

            -- Check Collision with Aliens
            local hitAlien = false
            if not hitShield then
                for _, a in ipairs(aliens) do
                    if a.alive and a.y == b.y and (b.x >= a.x and b.x <= a.x + 1) then
                        a.alive = false
                        hitAlien = true
                        score = score + (5 - a.row) * 20
                        Sound.playNote("hat", 0.8, 16)
                        break
                    end
                end
            end

            if hitShield or hitAlien or b.y < minY then
                table.remove(bullets, i)
            end
        end

        -- 2. Move Alien Bombs
        for i = #bombs, 1, -1 do
            local bm = bombs[i]
            bm.y = bm.y + 1

            -- Check Shield Collision
            local hitShield = false
            for si = #shields, 1, -1 do
                local s = shields[si]
                if s.x == bm.x and s.y == bm.y then
                    s.hp = s.hp - 1
                    if s.hp <= 0 then table.remove(shields, si) end
                    hitShield = true
                    break
                end
            end

            -- Check Player Collision
            local hitPlayer = false
            if not hitShield and bm.y == player.y and (math.abs(bm.x - player.x) <= 1) then
                hitPlayer = true
                lives = lives - 1
                Sound.playNote("bass", 1.5, 4)
                if lives <= 0 then
                    gameOver = true
                    scoreCache.recordScore(gameName, score, username)
                end
            end

            if hitShield or hitPlayer or bm.y > maxY then
                table.remove(bombs, i)
            end
        end

        -- 3. Move Aliens Formation
        alienTick = alienTick + 1
        local aliveCount = 0
        for _, a in ipairs(aliens) do if a.alive then aliveCount = aliveCount + 1 end end

        if aliveCount == 0 then
            -- Wave Complete!
            wave = wave + 1
            score = score + 500
            Sound.playSuccess()
            createAliens()
            createShields()
            return
        end

        local speedTicks = math.max(1, math.floor(aliveCount / 4) + 1)
        if alienTick >= speedTicks then
            alienTick = 0
            local shouldDrop = false

            for _, a in ipairs(aliens) do
                if a.alive then
                    if (alienDir == 1 and a.x >= w - 3) or (alienDir == -1 and a.x <= 2) then
                        shouldDrop = true
                        break
                    end
                end
            end

            if shouldDrop then
                alienDir = -alienDir
                for _, a in ipairs(aliens) do
                    a.y = a.y + 1
                    if a.alive and a.y >= player.y then
                        gameOver = true
                        Sound.playNote("bass", 1.5, 4)
                        scoreCache.recordScore(gameName, score, username)
                    end
                end
            else
                for _, a in ipairs(aliens) do
                    a.x = a.x + alienDir
                end
            end

            -- Random alien bomb drop
            if #bombs < 3 and math.random(1, 4) == 1 then
                local shooter = nil
                local aliveAliens = {}
                for _, a in ipairs(aliens) do if a.alive then table.insert(aliveAliens, a) end end
                if #aliveAliens > 0 then
                    local sel = aliveAliens[math.random(#aliveAliens)]
                    table.insert(bombs, { x = sel.x, y = sel.y + 1 })
                end
            end
        end
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
        term.write(" Space Invaders")
        term.setCursorPos(w - 2, 1)
        term.write("[X]")

        -- Top Score & Lives Bar
        term.setCursorPos(2, 2)
        term.setBackgroundColor(cWinBg)
        term.setTextColor(colors.black)
        term.write(string.format("Score: %05d", score))

        local livesStr = "Lives: " .. string.rep("<3 ", math.max(0, lives))
        term.setCursorPos(math.max(16, w - #livesStr - 2), 2)
        term.setTextColor(colors.red)
        term.write(livesStr)

        -- Black Space Canvas
        term.setBackgroundColor(cBoardBg)
        for y = minY, maxY do
            term.setCursorPos(1, y)
            term.write(string.rep(" ", w))
        end

        -- Draw Shields
        for _, s in ipairs(shields) do
            if s.y >= minY and s.y <= maxY and s.x >= 1 and s.x <= w then
                term.setCursorPos(s.x, s.y)
                term.setBackgroundColor(cBoardBg)
                term.setTextColor(s.hp == 3 and colors.lightBlue or (s.hp == 2 and colors.cyan or colors.gray))
                term.write("#")
            end
        end

        -- Draw Aliens
        for _, a in ipairs(aliens) do
            if a.alive and a.y >= minY and a.y <= maxY and a.x >= 1 and a.x <= w - 1 then
                term.setCursorPos(a.x, a.y)
                term.setBackgroundColor(cBoardBg)
                term.setTextColor((a.row % 2 == 1) and cAlien or cAlienAlt)
                term.write("}{")
            end
        end

        -- Draw Player Bullets
        for _, b in ipairs(bullets) do
            if b.y >= minY and b.y <= maxY and b.x >= 1 and b.x <= w then
                term.setCursorPos(b.x, b.y)
                term.setBackgroundColor(cBoardBg)
                term.setTextColor(cBullet)
                term.write("|")
            end
        end

        -- Draw Alien Bombs
        for _, bm in ipairs(bombs) do
            if bm.y >= minY and bm.y <= maxY and bm.x >= 1 and bm.x <= w then
                term.setCursorPos(bm.x, bm.y)
                term.setBackgroundColor(cBoardBg)
                term.setTextColor(cBomb)
                term.write("v")
            end
        end

        -- Draw Player Cannon
        if player.y >= minY and player.y <= maxY then
            term.setCursorPos(math.max(1, player.x - 1), player.y)
            term.setBackgroundColor(cBoardBg)
            term.setTextColor(cPlayer)
            term.write("/^\\")
        end

        -- Bottom Hint / Touch Buttons
        term.setCursorPos(1, h)
        term.setBackgroundColor(cWinBg)
        term.setTextColor(colors.black)
        term.clearLine()
        if isPocket then
            term.setCursorPos(2, h)
            term.write("[<] [FIRE] [>]")
            term.setCursorPos(w - 3, h)
            term.write("[Q]")
        else
            term.setCursorPos(2, h)
            term.write("Left/Right: Move | Space/Click: Fire | [Q] Quit")
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
            break
        elseif e == "mouse_click" then
            if p1 == 1 and p2 and p3 and p3 == 1 and p2 >= w - 3 then return end
            break
        end
    end

    gameTimer = os.startTimer(0.08)

    while true do
        drawGame()

        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == gameTimer then
            if not gameOver then
                update()
                gameTimer = os.startTimer(0.08)
            end

        elseif event == "key" then
            local key = p1
            if key == keys.q or key == keys.tab then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
            elseif gameOver then
                if key == keys.space or key == keys.enter or key == keys.r then
                    initGame()
                    gameTimer = os.startTimer(0.08)
                end
            else
                if (key == keys.left or key == keys.a) and player.x > 2 then
                    player.x = player.x - 1
                elseif (key == keys.right or key == keys.d) and player.x < w - 2 then
                    player.x = player.x + 1
                elseif key == keys.space or key == keys.up or key == keys.w then
                    fireBullet()
                end
            end

        elseif event == "mouse_click" or event == "mouse_drag" then
            local btn, cx, cy = p1, p2, p3

            -- Title Bar [X] to quit
            if cy == 1 and cx >= w - 3 then
                if score > 0 then scoreCache.recordScore(gameName, score, username) end
                break
            end

            -- Restart on Game Over
            if gameOver then
                initGame()
                gameTimer = os.startTimer(0.08)
            elseif isPocket and cy == h then
                -- Pocket on-screen touch buttons: "[<] [FIRE] [>]   [Q]"
                if cx >= 2 and cx <= 4 and player.x > 2 then
                    player.x = player.x - 1
                elseif cx >= 6 and cx <= 11 then
                    fireBullet()
                elseif cx >= 13 and cx <= 15 and player.x < w - 2 then
                    player.x = player.x + 1
                elseif cx >= w - 3 then
                    if score > 0 then scoreCache.recordScore(gameName, score, username) end
                    break
                end
            else
                -- Click on screen to direct Cannon and Fire
                if cx < player.x and player.x > 2 then
                    player.x = player.x - 1
                elseif cx > player.x and player.x < w - 2 then
                    player.x = player.x + 1
                end
                if event == "mouse_click" then
                    fireBullet()
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
    print("Space Invaders Error: " .. tostring(err))
    print("Press any key to return...")
    pcall(os.pullEvent)
end
