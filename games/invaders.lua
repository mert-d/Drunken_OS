--[[
    Invaders (Gem Standard v1.7)
    by Gemini Gem

    Purpose:
    Updated for Drunken OS v12.0 distribution.
]]

local currentVersion = 1.7
-- ... rest of the floppa bird game code

--==============================================================================
-- Main Game Function (to be run inside pcall)
--==============================================================================

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest" -- Fallback to Guest
    -- if not username then ... (removed check)

    local gameName = "Invaders"
    local arcadeServerId = nil

    local player, aliens, bullets, bombs = {}, {}, {}, {}
    local score, lives, gameOver, level = 0, 3, false, 1 -- **NEW**: Added level
 tracking
    local alienDirection, alienMoveTimer, alienDropTimer = 1, 0, 0

    local hasColor = term.isColor and term.isColor()
    local function safeColor(colorName, fallbackColor)
        if hasColor and colors[colorName] ~= nil then return colors[colorName] end
        return fallbackColor
    end

    local theme = {
        bg = safeColor("black", colors.black),
        windowBg = safeColor("darkGray", colors.gray),
        title = safeColor("green", colors.lime),
        prompt = safeColor("cyan", colors.cyan),
        player = safeColor("lime", colors.white),
        alien = safeColor("red", colors.white),
        bullet = safeColor("yellow", colors.white),
        bomb = safeColor("orange", colors.white),
        text = safeColor("white", colors.white),
    }

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function createAliens()
        aliens = {}
        for r = 1, 4 do
            for c = 1, 8 do
                table.insert(aliens, { x = c * 3, y = r * 2 + 1, alive = true })
            end
        end
    end

    local function updateAliens()
        -- **NEW**: Alien speed increases with each level.
        local alienSpeed = 10 - level
        if alienSpeed < 2 then alienSpeed = 2 end -- Set a max speed

        alienMoveTimer = alienMoveTimer + 1
        if alienMoveTimer < alienSpeed then return end
        alienMoveTimer = 0

        local w, h = getSafeSize()
        local drop = false
        for _, alien in ipairs(aliens) do
            if alien.alive then
                if (alien.x >= w and alienDirection == 1) or (alien.x <= 1 and a
lienDirection == -1) then
                    drop = true
                    break
                end
            end
        end

        if drop then
            alienDirection = -alienDirection
            for _, alien in ipairs(aliens) do
                alien.y = alien.y + 1
                if alien.alive and alien.y >= player.y then
                    gameOver = true
                end
            end
        else
            for _, alien in ipairs(aliens) do
                alien.x = alien.x + alienDirection
            end
        end
    end

    local function updateBullets()
        for i = #bullets, 1, -1 do
            local bullet = bullets[i]
            bullet.y = bullet.y - 1
            if bullet.y < 1 then
                table.remove(bullets, i)
            else
                for j, alien in ipairs(aliens) do
                    if alien.alive and bullet.x == alien.x and bullet.y == alien
.y then
                        alien.alive = false
                        score = score + 100
                        table.remove(bullets, i)
                        break
                    end
                end
            end
        end
    end

    local function updateBombs()
        -- **NEW**: Bomb drop speed increases with each level.
        local bombSpeed = 20 - level
        if bombSpeed < 5 then bombSpeed = 5 end

        alienDropTimer = alienDropTimer + 1
        if alienDropTimer > bombSpeed and #aliens > 0 then
            alienDropTimer = 0
            local aliveAliens = {}
            for _, alien in ipairs(aliens) do
                if alien.alive then table.insert(aliveAliens, alien) end
            end
            if #aliveAliens > 0 then
                local shooter = aliveAliens[math.random(#aliveAliens)]
                table.insert(bombs, { x = shooter.x, y = shooter.y + 1 })
            end
        end

        local _, h = getSafeSize()
        for i = #bombs, 1, -1 do
            local bomb = bombs[i]
            bomb.y = bomb.y + 1
            if bomb.y > h then
                table.remove(bombs, i)
            elseif bomb.x == player.x and bomb.y == player.y then
                lives = lives - 1
                if lives <= 0 then gameOver = true end
                table.remove(bombs, i)
            end
        end
    end

    -- **NEW**: A function to check if all aliens are defeated.
    local function checkLevelComplete()
        for _, alien in ipairs(aliens) do
            if alien.alive then
                return false -- Found a live alien, level is not complete
            end
        end
        return true -- No live aliens found
    end

    local function draw()
        term.setBackgroundColor(theme.windowBg)
        term.clear()
        local w, h = getSafeSize()

        term.setTextColor(theme.player)
        term.setCursorPos(player.x, player.y); term.write("^")

        term.setTextColor(theme.alien)
        for _, alien in ipairs(aliens) do
            if alien.alive then
                term.setCursorPos(alien.x, alien.y); term.write("V")
            end
        end

        term.setTextColor(theme.bullet)
        for _, bullet in ipairs(bullets) do
            term.setCursorPos(bullet.x, bullet.y); term.write("l")
        end

        term.setTextColor(theme.bomb)
        for _, bomb in ipairs(bombs) do
            term.setCursorPos(bomb.x, bomb.y); term.write("*")
        end

        term.setTextColor(theme.text)
        local scoreText = "Score: " .. score
        local livesText = "Lives: " .. lives
        local levelText = "Level: " .. level
        term.setCursorPos(2, 1); term.write(scoreText)
        term.setCursorPos(w - #livesText, 1); term.write(livesText)
        term.setCursorPos(math.floor(w/2 - #levelText/2), 1); term.write(levelTe
xt)
    end

    local function submitScore() if arcadeServerId then rednet.send(arcadeServer
Id, {type = "submit_score", game = gameName, user = username, score = score}, "A
rcadeGames") end end

    local function showGameOverScreen()
        submitScore()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.windowBg); term.clear()
        local boxWidth = 32; local boxHeight = 18
        local boxX = math.floor((w - boxWidth) / 2); local boxY = math.floor((h
- boxHeight) / 2)
        for y = 0, boxHeight - 1 do term.setCursorPos(boxX, boxY + y); term.writ
e(string.rep(" ", boxWidth)) end
        local title = "Game Over"
        term.setCursorPos(boxX + math.floor((w - #title) / 2), boxY + 1); term.s
etTextColor(colors.red); term.write(title)
        local scoreText = "Final Score: " .. score
        term.setCursorPos(boxX + math.floor((w - #scoreText) / 2), boxY + 3); te
rm.setTextColor(theme.text); term.write(scoreText)
        if arcadeServerId then
            rednet.send(arcadeServerId, {type = "get_leaderboard", game = gameNa
me}, "ArcadeGames")
            local _, response = rednet.receive("ArcadeGames", 3)
            if response and response.leaderboard then
                local sortedScores = {}; for user, s in pairs(response.leaderboa
rd) do table.insert(sortedScores, {user = user, score = s}) end
                table.sort(sortedScores, function(a,b) return a.score > b.score
end)
                local lbTitle = "--- Leaderboard ---"
                term.setCursorPos(boxX + math.floor((boxWidth - #lbTitle) / 2),
boxY + 5); term.setTextColor(theme.title); term.write(lbTitle)
                term.setTextColor(theme.text)
                for i = 1, math.min(10, #sortedScores) do
                    local entry = string.format("%2d. %-15s %d", i, sortedScores
[i].user, sortedScores[i].score)
                    term.setCursorPos(boxX + 2, boxY + 6 + i); term.write(entry)
                end
            end
        end
        local prompt = "Press any key to exit..."
        term.setCursorPos(boxX + math.floor((boxWidth - #prompt) / 2), boxY + bo
xHeight - 2); term.setTextColor(theme.prompt); term.write(prompt)

        sleep(2)
        os.pullEvent("key")
    end

    rednet.open("back")
    arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

    local w, h = getSafeSize()

    term.setBackgroundColor(theme.windowBg)
    term.clear()
    local startMsg = "Press any key to start"
    term.setCursorPos(math.floor(w/2 - #startMsg/2), math.floor(h/2))
    term.setTextColor(theme.prompt)
    term.write(startMsg)
    os.pullEvent("key")

    player.x = math.floor(w / 2)
    player.y = h - 1
    createAliens()

    local gameTimer = os.startTimer(0.1)

    while not gameOver do
        local event, p1 = os.pullEvent()

        if event == "key" then
            local w, h = getSafeSize()
            if p1 == keys.left and player.x > 1 then
                player.x = player.x - 1
            elseif p1 == keys.right and player.x < w then
                player.x = player.x + 1
            elseif p1 == keys.space then
                if #bullets < 3 then
                    table.insert(bullets, { x = player.x, y = player.y - 1 })
                end
            elseif p1 == keys.q then
                gameOver = true
            end
        elseif event == "timer" and p1 == gameTimer then
            updateAliens()
            updateBullets()
            updateBombs()

            if checkLevelComplete() then
                level = level + 1
                score = score + 1000 -- Level clear bonus
                createAliens()
                term.setBackgroundColor(theme.windowBg); term.clear()
                local levelMsg = "Level " .. level
                term.setCursorPos(math.floor(w/2 - #levelMsg/2), math.floor(h/2)
)
                term.setTextColor(theme.title); term.write(levelMsg)
                sleep(2)
            end

            draw()
            gameTimer = os.startTimer(0.1)
        elseif event == "terminate" then
            break
        end
    end

    showGameOverScreen()
    term.clear()
end

--==============================================================================
-- Protected Call Wrapper
--==============================================================================

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
