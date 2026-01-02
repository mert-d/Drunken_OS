--[[
    Floppa Bird (Gem Standard v1.7)
    by Gemini Gem

    Purpose:
    Updated for Drunken OS v12.0 distribution.
]]

-- Load shared libraries
package.path = "/?.lua;" .. package.path
local sharedTheme = require("lib.theme")

local currentVersion = 7.2
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

    -- Use shared theme colors
    local theme = {
        bg = sharedTheme.bg,
        windowBg = sharedTheme.windowBg,
        title = sharedTheme.game.target,
        prompt = sharedTheme.prompt,
        player = sharedTheme.game.gold,
        pipe = sharedTheme.game.target,
        text = sharedTheme.text,
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

        table.insert(pipes, { x = w, y = gapY, width = 5, gap = gapSize, scored = false })
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

        term.setBackgroundColor(theme.pipe)
        for _, pipe in ipairs(pipes) do
            for y = 2, h - 1 do -- Limit to inside frame
                if y < pipe.y or y > pipe.y + pipe.gap then
                    if pipe.x > 1 and pipe.x + pipe.width - 1 < w then
                        term.setCursorPos(pipe.x, y)
                        term.write(string.rep(" ", pipe.width))
                    end
                end
            end
        end

        term.setBackgroundColor(theme.player)
        term.setCursorPos(player.x, math.floor(player.y))
        term.write(" ")

        term.setBackgroundColor(theme.windowBg)
        term.setTextColor(theme.text)
        local scoreText = "Score: " .. score
        term.setCursorPos(math.floor(w / 2 - #scoreText / 2), h)
        term.setBackgroundColor(colors.cyan)
        term.write(" " .. scoreText .. " ")
    end

    local function submitScore() if arcadeServerId then rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = score}, "ArcadeGames") end end

    local function showGameOverScreen()
        submitScore()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.windowBg); term.clear()
        local boxWidth = 32; local boxHeight = 18
        local boxX = math.floor((w - boxWidth) / 2); local boxY = math.floor((h - boxHeight) / 2)
        for y = 0, boxHeight - 1 do term.setCursorPos(boxX, boxY + y); term.write(string.rep(" ", boxWidth)) end
        local title = "Game Over"
        term.setCursorPos(boxX + math.floor((w - #title) / 2), boxY + 1); term.setTextColor(colors.red); term.write(title)
        local scoreText = "Final Score: " .. score
        term.setCursorPos(boxX + math.floor((w - #scoreText) / 2), boxY + 3); term.setTextColor(theme.text); term.write(scoreText)
        if arcadeServerId then
            rednet.send(arcadeServerId, {type = "get_leaderboard", game = gameName}, "ArcadeGames")
            local _, response = rednet.receive("ArcadeGames", 3)
            if response and response.leaderboard then
                local sortedScores = {}; for user, s in pairs(response.leaderboard) do table.insert(sortedScores, {user = user, score = s}) end
                table.sort(sortedScores, function(a,b) return a.score > b.score end)
                local lbTitle = "--- Leaderboard ---"
                term.setCursorPos(boxX + math.floor((boxWidth - #lbTitle) / 2), boxY + 5); term.setTextColor(theme.title); term.write(lbTitle)
                term.setTextColor(theme.text)
                for i = 1, math.min(10, #sortedScores) do
                    local entry = string.format("%2d. %-15s %d", i, sortedScores[i].user, sortedScores[i].score)
                    term.setCursorPos(boxX + 2, boxY + 6 + i); term.write(entry)
                end
            end
        end
        local prompt = "Press any key to exit..."
        term.setCursorPos(boxX + math.floor((boxWidth - #prompt) / 2), boxY + boxHeight - 2); term.setTextColor(theme.prompt); term.write(prompt)

        -- **NEW**: Add a delay before listening for the exit key.
        sleep(2)
        os.pullEvent("key")
    end

    local modem = peripheral.find("modem")
    if modem then rednet.open(peripheral.getName(modem)) end
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
            if p1 == keys.q or p1 == keys.tab then
                gameOver = true
            else
                player.dy = flapStrength
            end
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
