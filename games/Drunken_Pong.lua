--[[
    Drunken Pong (v1.0)
    by Gemini Gem

    Purpose:
    A 1v1 P2P real-time arcade game for Drunken OS.
    Battle a friend over Rednet in a classic game of Pong!
]]

local gameVersion = 1.2

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenPong"
    local arcadeServerId = nil
    local opponentId = nil
    local isHost = false

    -- Theme & Colors
    local hasColor = term.isColor and term.isColor()
    local function safeColor(c, f) return (hasColor and colors[c]) and colors[c] or f end

    local theme = {
        bg = colors.black,
        text = colors.white,
        border = colors.cyan,
        player = safeColor("lime", colors.white),
        opponent = safeColor("red", colors.white),
        ball = safeColor("yellow", colors.white),
    }

    -- Game Constants
    local PADDLE_HEIGHT = 3
    local BALL_CHAR = "O"

    -- Game State
    local myY = 5
    local oppY = 5
    local ball = { x = 0, y = 0, dx = 1, dy = 1 }
    local score = { me = 0, opp = 0 }
    local matchActive = false

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function drawFrame()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.bg); term.clear()
        
        -- Draw Border
        term.setBackgroundColor(theme.border)
        term.setCursorPos(1, 1); term.write(string.rep(" ", w))
        term.setCursorPos(1, h); term.write(string.rep(" ", w))
        for i = 2, h - 1 do
            term.setCursorPos(1, i); term.write(" ")
            term.setCursorPos(w, i); term.write(" ")
        end

        term.setCursorPos(1, 1)
        term.setTextColor(theme.text)
        local titleText = " Drunken Pong v" .. gameVersion .. " "
        term.setCursorPos(math.floor((w - #titleText)/2), 1); term.write(titleText)
    end

    local function drawLobby(msg)
        drawFrame()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.text)
        term.setCursorPos(math.floor(w/2 - #msg/2), math.floor(h/2))
        term.write(msg)
        term.setCursorPos(math.floor(w/2 - 10), h)
        term.setBackgroundColor(theme.border); term.write(" TAB: Back ")
    end

    local function drawGame()
        drawFrame()
        local w, h = getSafeSize()
        
        -- Draw Scores
        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.player)
        term.setCursorPos(3, 2); term.write(username .. ": " .. score.me)
        term.setTextColor(theme.opponent)
        local oppScoreText = "Opponent: " .. score.opp
        term.setCursorPos(w - #oppScoreText - 2, 2); term.write(oppScoreText)

        -- Draw Paddles
        term.setBackgroundColor(theme.player)
        for i = 0, PADDLE_HEIGHT-1 do
            term.setCursorPos(2, math.floor(myY + i))
            term.write(" ")
        end

        term.setBackgroundColor(theme.opponent)
        for i = 0, PADDLE_HEIGHT-1 do
            term.setCursorPos(w-1, math.floor(oppY + i))
            term.write(" ")
        end

        -- Draw Ball
        if ball.x > 0 and ball.y > 0 then
            term.setBackgroundColor(theme.bg)
            term.setTextColor(theme.ball)
            term.setCursorPos(math.floor(ball.x), math.floor(ball.y))
            term.write(BALL_CHAR)
        end
    end

    -- Networking
    local modem = peripheral.find("modem")
    if not modem then error("Drunken Pong requires a Modem!") end
    rednet.open(peripheral.getName(modem))
    
    local function findMatch()
        local arcadeId = rednet.lookup("ArcadeGames_Internal", "arcade.server.internal")
        if not arcadeId then 
            drawLobby("Mainframe Arcade Server Offline!")
            sleep(2)
            return false
        end

        drawLobby("1: Host Match | 2: Join Match")
        local event, key
        repeat
            event, key = os.pullEvent("key")
        until key == keys.one or key == keys.two or key == keys.q or key == keys.tab

        if key == keys.q or key == keys.tab then return false end

        if key == keys.one then
            -- HOSTING
            isHost = true
            rednet.send(arcadeId, {type="host_game", user=username, game=gameName}, "ArcadeGames")
            drawLobby("Hosting... Waiting for Player...")
            
            while true do
                local id, msg = rednet.receive("DrunkenPong_Lobby", 2)
                if id and msg.type == "match_join" then
                    opponentId = id
                    rednet.send(id, {type="match_accept", user=username}, "DrunkenPong_Lobby")
                    rednet.send(arcadeId, {type="close_lobby"}, "ArcadeGames")
                    return true
                end
                local tevt, tk = os.pullEventRaw()
                if tevt == "key" and (tk == keys.q or tk == keys.tab) then 
                    rednet.send(arcadeId, {type="close_lobby"}, "ArcadeGames")
                    return false 
                end
            end
        else
            -- JOINING
            rednet.send(arcadeId, {type="list_lobbies"}, "ArcadeGames")
            local _, reply = rednet.receive("ArcadeGames", 3)
            if not reply or not reply.lobbies then
                drawLobby("No Lobbies Found.")
                sleep(1)
                return false
            end

            local options = {}
            for id, lob in pairs(reply.lobbies) do
                if lob.game == gameName then table.insert(options, {id=id, user=lob.user}) end
            end

            if #options == 0 then
                drawLobby("No " .. gameName .. " hosts online.")
                sleep(1)
                return false
            end

            -- Pick the first available host
            local target = options[1]
            opponentId = target.id
            drawLobby("Joining " .. target.user .. "...")
            rednet.send(target.id, {type="match_join", user=username}, "DrunkenPong_Lobby")
            
            local sid, smsg = rednet.receive("DrunkenPong_Lobby", 5)
            if sid == opponentId and smsg.type == "match_accept" then
                isHost = false
                return true
            else
                drawLobby("Join Failed/Timed Out.")
                sleep(1)
                return false
            end
        end
    end

    if not findMatch() then return end
    
    -- Game Loop
    local w, h = getSafeSize()
    ball.x, ball.y = w/2, h/2
    matchActive = true
    local lastSync = os.epoch("utc")
    
    parallel.waitForAny(
        function() -- Input & Local Logic
            while matchActive do
                local event, key = os.pullEvent()
                if event == "key" then
                    if (key == keys.w or key == keys.up) and myY > 2 then myY = myY - 1
                    elseif (key == keys.s or key == keys.down) and myY < h - PADDLE_HEIGHT then myY = myY + 1
                    elseif key == keys.q or key == keys.tab then matchActive = false end
                    
                    -- Immediate Sync on move
                    rednet.send(opponentId, {type="move", y=myY}, "DrunkenPong_Game")
                end
            end
        end,
        function() -- Ball Physics (Host Only) & Tick
            while matchActive do
                if isHost then
                    ball.x = ball.x + ball.dx
                    ball.y = ball.y + ball.dy
                    
                    if ball.y <= 2 or ball.y >= h - 1 then ball.dy = -ball.dy end
                    
                    -- Paddle Hit - Local
                    if ball.x <= 3 then
                        if ball.y >= myY and ball.y < myY + PADDLE_HEIGHT then
                            ball.dx = math.abs(ball.dx)
                        else
                            score.opp = score.opp + 1
                            ball.x, ball.y = w/2, h/2
                            ball.dx = -ball.dx
                        end
                    elseif ball.x >= w - 2 then
                        -- Paddle Hit - Remote (approximate based on last sync)
                        if ball.y >= oppY and ball.y < oppY + PADDLE_HEIGHT then
                            ball.dx = -math.abs(ball.dx)
                        else
                            score.me = score.me + 1
                            ball.x, ball.y = w/2, h/2
                            ball.dx = math.abs(ball.dx)
                        end
                    end
                    
                    if os.epoch("utc") - lastSync > 50 then
                        rednet.send(opponentId, {type="sync", ball=ball, score=score}, "DrunkenPong_Game")
                        lastSync = os.epoch("utc")
                    end
                end
                
                drawGame()
                sleep(0.05)
                if score.me >= 10 or score.opp >= 10 then matchActive = false end
            end
        end,
        function() -- Receiving
            while matchActive do
                local id, msg = rednet.receive("DrunkenPong_Game", 0.5)
                if id == opponentId then
                    if msg.type == "move" then
                        oppY = msg.y
                    elseif msg.type == "sync" then
                        -- Non-host mirrors host state
                        if not isHost then
                            ball = msg.ball
                            -- Inversion of coordinate for mirrored view
                            ball.x = w - ball.x
                            score.me, score.opp = msg.score.opp, msg.score.me
                        end
                    end
                end
            end
        end
    )
    
    -- Match Results & Score Submission
    drawGame()
    term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2 + 2))
    print("Match Over!")

    -- Submit winners score
    if score.me > score.opp then
        arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
        if arcadeServerId then
            rednet.send(arcadeServerId, {
                type = "submit_score", 
                game = gameName, 
                user = username, 
                score = score.me * 100 -- Bonus for winning
            }, "ArcadeGames")
        end
    end

    sleep(2)
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Pong Error: " .. err)
    os.pullEvent("key")
end
