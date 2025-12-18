--[[
    Floppa Bird (Gem Standard v1.6)
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

    local gameName = "FloppaBird"
    local arcadeServerId = nil

    local player, pipes = {}, {}
    local score, gameOver = 0, false
    local gravity, flapStrength, pipeSpeed = 0.5, -2, 1

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
        player = safeColor("yellow", colors.white),
        pipe = safeColor("green", colors.white),
        text = safeColor("white", colors.white),
    }

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function createPipe()
        local w, h = getSafeSize()
        local gapSize = 6
        local gapY = math.random(3, h - gapSize - 2)

        table.insert(pipes, { x = w, y = gapY, width = 5, gap = gapSize, scored
= false })
    end

    local function updatePlayer()
        local w, h = getSafeSize()
        player.dy = player.dy + gravity
        player.y = player.y + player.dy

        if player.y < 1 or player.y > h then
            gameOver = true
        end
    end

    local function updatePipes()
        local w, h = getSafeSize()
        for i = #pipes, 1, -1 do
            local pipe = pipes[i]
            pipe.x = pipe.x - pipeSpeed

            if not pipe.scored and pipe.x + pipe.width < player.x then
                pipe.scored = true
                score = score + 1
            end

            if pipe.x + pipe.width < 1 then
                table.remove(pipes, i)
            end

            if player.x >= pipe.x and player.x < pipe.x + pipe.width then
                if player.y < pipe.y or player.y > pipe.y + pipe.gap then
                    gameOver = true
                end
            end
        end

        if #pipes == 0 or pipes[#pipes].x < w - 20 then
            createPipe()
        end
    end

    local function draw()
        term.setBackgroundColor(theme.windowBg)
        term.clear()
        local w, h = getSafeSize()

        term.setBackgroundColor(theme.player)
        term.setCursorPos(player.x, math.floor(player.y))
        term.write(" ")

        term.setBackgroundColor(theme.pipe)
        for _, pipe in ipairs(pipes) do
            for y = 1, h do
                if y < pipe.y or y > pipe.y + pipe.gap then
                    if pipe.x > 0 and pipe.x + pipe.width -1 <= w then
                        term.setCursorPos(pipe.x, y)
                        term.write(string.rep(" ", pipe.width))
                    end
                end
            end
        end

        term.setBackgroundColor(theme.windowBg)
        term.setTextColor(theme.text)
        local scoreText = "Score: " .. score
        term.setCursorPos(math.floor(w / 2 - #scoreText / 2), 1)
        term.write(scoreText)
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

        -- **NEW**: Add a delay before listening for the exit key.
        sleep(2)
        os.pullEvent("key")
    end

    rednet.open("back")
    arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

    local w, h = getSafeSize()
    term.setBackgroundColor(theme.windowBg)
    term.clear()
    local startMsg = "Press any key to flap"
    term.setCursorPos(math.floor(w/2 - #startMsg/2), math.floor(h/2))
    term.setTextColor(theme.prompt)
    term.write(startMsg)
    os.pullEvent("key")

    player.x = math.floor(w / 4)
    player.y = math.floor(h / 2)
    player.dy = 0
    pipes = {}
    score = 0
    player.dy = flapStrength

    local gameTimer = os.startTimer(0.1)

    while not gameOver do
        local event, p1 = os.pullEvent()

        if event == "key" then
            player.dy = flapStrength
        elseif event == "timer" and p1 == gameTimer then
            updatePlayer()
            updatePipes()
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
