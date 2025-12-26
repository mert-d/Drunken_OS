--[[
    Drunken Pong (v1.0)
    by Gemini Gem

    Purpose:
    A 1v1 P2P real-time arcade game for Drunken OS.
    Battle a friend over Rednet in a classic game of Pong!
]]

local gameVersion = 2.0
local P2P_Socket = require("lib.p2p_socket")

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
        border = safeColor("cyan", colors.blue),
        player = safeColor("lime", colors.white),
        opponent = safeColor("red", colors.white),
        ball = safeColor("yellow", colors.white),
        trail = safeColor("gray", colors.lightGray),
        powerup = safeColor("purple", colors.magenta)
    }

    -- Visual Effects State
    local particles = {}
    local trails = {} -- { {x, y, age} }
    local shake = 0
    local flash = nil

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
        term.setBackgroundColor(flash or theme.bg); term.clear()
        
        -- Draw Neon Border with Shake
        local ox = math.random(-shake, shake)
        local oy = math.random(-shake, shake)
        
        term.setBackgroundColor(theme.border)
        term.setCursorPos(1+ox, 1+oy); term.write(string.rep(" ", w))
        term.setCursorPos(1+ox, h+oy); term.write(string.rep(" ", w))
        for i = 2, h - 1 do
            term.setCursorPos(1+ox, i+oy); term.write(" ")
            term.setCursorPos(w+ox, i+oy); term.write(" ")
        end

        term.setCursorPos(1, 1)
        term.setTextColor(theme.text)
        local titleText = " [ DRUNKEN PONG NEON ] "
        term.setCursorPos(math.floor((w - #titleText)/2), 1); term.write(titleText)
        
        if shake > 0 then shake = shake - 1 end
        if flash then flash = nil end
    end

    local function addParticle(x, y, color, char)
        table.insert(particles, {x = x, y = y, dx = math.random(-10, 10)/10, dy = math.random(-10, 10)/10, color = color, char = char or ".", life = 10})
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

    -- Coordinate Scaling (Internal Grid 51x19)
    local INT_W, INT_H = 51, 19
    local function toScreen(ix, iy)
        local sw, sh = getSafeSize()
        local sx = math.floor((ix / INT_W) * (sw - 2)) + 2
        local sy = math.floor((iy / INT_H) * (sh - 2)) + 2
        return sx, sy
    end

    local function drawGame()
        drawFrame()
        local w, h = getSafeSize()
        
        -- Draw Scores (Sleek Blit)
        local scoreMsg = string.format(" %s %02d | %02d %s ", username, score.me, score.opp, "Opponent")
        local scoreColor = string.rep("5", #username + 4) .. "f" .. string.rep("e", 11)
        term.setCursorPos(math.floor(w/2 - #scoreMsg/2), 2)
        term.blit(scoreMsg, scoreColor, string.rep("f", #scoreMsg))

        -- Draw Trails
        term.setBackgroundColor(theme.bg)
        for i, t in ipairs(trails) do
            local tx, ty = toScreen(t.x, t.y)
            term.setTextColor(theme.trail)
            term.setCursorPos(tx, ty); term.write(".")
        end

        -- Draw Paddles (Scaled)
        for i = 0, PADDLE_HEIGHT-1 do
            local sx, sy = toScreen(1, myY + i)
            term.setBackgroundColor(theme.player)
            term.setCursorPos(sx, sy); term.write(" ")
            
            local ox, oy = toScreen(INT_W - 1, oppY + i)
            term.setBackgroundColor(theme.opponent)
            term.setCursorPos(ox, oy); term.write(" ")
        end

        -- Draw Particles
        for i = #particles, 1, -1 do
            local p = particles[i]
            local px, py = toScreen(p.x, p.y)
            term.setTextColor(p.color)
            term.setCursorPos(px, py); term.write(p.char)
            p.x = p.x + p.dx; p.y = p.y + p.dy
            p.life = p.life - 1
            if p.life <= 0 then table.remove(particles, i) end
        end

        -- Draw Ball (Scaled)
        if ball.x > 0 and ball.y > 0 then
            local sx, sy = toScreen(ball.x, ball.y)
            term.setBackgroundColor(theme.bg)
            term.setTextColor(theme.ball)
            term.setCursorPos(sx, sy)
            term.write(BALL_CHAR)
        end
    end

    -- Networking
    local socket = P2P_Socket.new("DrunkenPong", gameVersion, "DrunkenPong_Game")
    
    local function findMatch()
        if not socket:checkArcade() then 
            drawLobby("Mainframe Arcade Server Offline!")
            sleep(2)
        end

        drawLobby("1: Host | 2: Join | 3: Direct Connect")
        local event, key
        repeat
            event, key = os.pullEvent("key")
        until key == keys.one or key == keys.two or key == keys.three or key == keys.q or key == keys.tab

        if key == keys.q or key == keys.tab then return false end

        local directTarget = nil
        if key == keys.three then
            drawLobby("Enter Host ID: ")
            term.setCursorPos(math.floor(getSafeSize()/2-5), math.floor(getSafeSize()/2)+1)
            term.setBackgroundColor(colors.gray)
            directTarget = tonumber(read())
            if not directTarget then return false end
        end

        if key == keys.one then
            -- HOSTING
            isHost = true
            socket.lobbyProtocol = "DrunkenPong_Lobby"
            socket:hostGame(username)
            drawLobby("Hosting... Waiting for Player...")
            
            while true do
                local msg = socket:waitForJoin(0.1)
                if msg then
                    opponentId = socket.peerId
                    -- Socket handles accept
                    return true
                end
                
                local tevt, tk = os.pullEventRaw()
                if tevt == "key" and (tk == keys.q or tk == keys.tab) then 
                    socket:stopHosting()
                    return false 
                end
            end
        else
            -- JOINING
            local targetId = nil
            if key == keys.two then
                drawLobby("Fetching Lobbies...")
                local lobbies, err = socket:findLobbies()
                if not lobbies then
                    drawLobby(err or "Failed to list lobbies.")
                    sleep(1)
                    return false
                end

                if #lobbies == 0 then
                    drawLobby("No " .. gameName .. " hosts online.")
                    sleep(1)
                    return false
                end
                targetId = lobbies[1].id
            else
                targetId = directTarget
            end

            opponentId = targetId
            drawLobby("Connecting to ID " .. targetId .. "...")
            
            socket.lobbyProtocol = "DrunkenPong_Lobby"
            local reply, err = socket:connect(targetId, {user=username})
            
            if reply then
                isHost = false
                return true
            else
                drawLobby(err or "Join Failed.")
                sleep(1)
                return false
            end
        end
    end

    if not findMatch() then return end
    
    -- Match Countdown
    for i = 3, 1, -1 do
        drawGame()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.bg)
        term.setCursorPos(math.floor(w/2), math.floor(h/2))
        term.setTextColor(colors.white); term.write(tostring(i))
        sleep(1)
    end

    -- Game Loop
    local w, h = getSafeSize()
    ball.x, ball.y = INT_W/2, INT_H/2
    local balls = {ball} -- Support for Multi-ball
    local ballSpeed = 0.5
    local powerups = {} -- { {x, y, type} }
    local myHeight = PADDLE_HEIGHT
    local oppHeight = PADDLE_HEIGHT

    matchActive = true
    local lastSync = os.epoch("utc")
    
    parallel.waitForAny(
        function() -- Input & Local Logic
            while matchActive do
                local event, key = os.pullEvent()
                if event == "key" then
                    if (key == keys.w or key == keys.up) and myY > 1 then myY = myY - 1
                    elseif (key == keys.s or key == keys.down) and myY < INT_H - PADDLE_HEIGHT then myY = myY + 1
                    elseif key == keys.q or key == keys.tab then matchActive = false end
                    
                    -- Immediate Sync on move
                    socket:send({type="move", y=myY})
                end
            end
        end,
        function() -- Ball Physics (Host Only) & Tick
            while matchActive do
                if isHost then
                    -- Ball Progression & Trail Logic
                    for bi, b in ipairs(balls) do
                        table.insert(trails, {x=b.x, y=b.y})
                        if #trails > 20 then table.remove(trails, 1) end

                        b.x = b.x + b.dx * ballSpeed
                        b.y = b.y + b.dy * ballSpeed
                        
                        if b.y <= 1 or b.y >= INT_H - 1 then 
                            b.dy = -b.dy 
                            for i=1,3 do addParticle(b.x, b.y, theme.ball) end
                        end
                        
                        -- Paddle Hit - Local
                        if b.x <= 2 then
                            if b.y >= myY and b.y < myY + myHeight then
                                b.dx = math.abs(b.dx)
                                -- Curved Shot
                                local hitOffset = (b.y - (myY + myHeight/2)) / (myHeight/2)
                                b.dy = b.dy + hitOffset * 0.5
                                ballSpeed = math.min(ballSpeed + 0.02, 1.5)
                                shake = 2
                                for i=1,5 do addParticle(b.x, b.y, theme.player, "*") end
                            else
                                score.opp = score.opp + 1
                                b.x, b.y = INT_W/2, INT_H/2
                                b.dx = -b.dx
                                ballSpeed = 0.5
                                flash = colors.red
                                shake = 5
                            end
                        elseif b.x >= INT_W - 1 then
                            -- Paddle Hit - Remote
                            if b.y >= oppY and b.y < oppY + oppHeight then
                                b.dx = -math.abs(b.dx)
                                local hitOffset = (b.y - (oppY + oppHeight/2)) / (oppHeight/2)
                                b.dy = b.dy + hitOffset * 0.5
                                ballSpeed = math.min(ballSpeed + 0.02, 1.5)
                                shake = 2
                                for i=1,5 do addParticle(b.x, b.y, theme.opponent, "*") end
                            else
                                score.me = score.me + 1
                                b.x, b.y = INT_W/2, INT_H/2
                                b.dx = math.abs(b.dx)
                                ballSpeed = 0.5
                                flash = colors.lime
                                shake = 5
                            end
                        end
                    end

                    -- Power-up Logic (Host Only)
                    if math.random(1, 200) == 1 then
                        local types = {"large", "multi"}
                        table.insert(powerups, {x=math.random(10, INT_W-10), y=math.random(3, INT_H-3), type=types[math.random(1, #types)]})
                    end

                    for pi = #powerups, 1, -1 do
                        local pu = powerups[pi]
                        for bi, b in ipairs(balls) do
                            local dist = math.sqrt((b.x-pu.x)^2 + (b.y-pu.y)^2)
                            if dist < 2 then
                                if pu.type == "large" then
                                    if b.dx > 0 then myHeight = 5 else oppHeight = 5 end
                                elseif pu.type == "multi" then
                                    table.insert(balls, {x=b.x, y=b.y, dx=-b.dx, dy=-b.dy})
                                end
                                table.remove(powerups, pi)
                                break
                            end
                        end
                    end
                    
                    if os.epoch("utc") - lastSync > 50 then
                        socket:send({
                            type="sync", 
                            balls=balls, 
                            score=score, 
                            powerups=powerups,
                            myH = myHeight,
                            oppH = oppHeight,
                            speed = ballSpeed
                        })
                        lastSync = os.epoch("utc")
                    end
                end
                
                drawGame()
                -- Draw Powerups (Local Client Side)
                for _, pu in ipairs(powerups) do
                    local px, py = toScreen(pu.x, pu.y)
                    term.setCursorPos(px, py); term.setTextColor(theme.powerup); term.write("?")
                end

                sleep(0.05)
                if score.me >= 10 or score.opp >= 10 then matchActive = false end
            end
        end,
        function() -- Receiving
            while matchActive do
                local msg = socket:receive(0.5)
                if msg then
                    if msg.type == "move" then
                        oppY = msg.y
                    elseif msg.type == "sync" then
                        -- Non-host mirrors host state
                        if not isHost then
                            balls = msg.balls
                            -- Inversion of coordinate for mirrored view (X ONLY)
                            for _, b in ipairs(balls) do b.x = INT_W - b.x end
                            score.me, score.opp = msg.score.opp, msg.score.me
                            powerups = msg.powerups
                            for _, pu in ipairs(powerups) do pu.x = INT_W - pu.x end
                            myHeight = msg.oppH
                            oppHeight = msg.myH
                            ballSpeed = msg.speed
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
