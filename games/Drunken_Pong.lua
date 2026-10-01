--[[
    Drunken Pong (v1.1)
    by Gemini Gem

    Purpose:
    A 1v1 P2P real-time arcade game for Drunken OS.
    Battle a friend over Rednet in a classic game of Pong!
]]

-- Load shared libraries
if package and package.path then package.path = "/?.lua;" .. package.path end
local sharedTheme = require("lib.theme")
local ok_sound, Sound = pcall(require, "lib.sound")
if not ok_sound or type(Sound) ~= "table" then
    Sound = { playClick = function() end, playNote = function() end, playSuccess = function() end }
end

local gameVersion = 2.2
local P2P_Socket = require("lib.p2p_socket")
local saveFile = ".pong_save"

local persist = { wins = 0 }
if fs.exists(saveFile) then
    local f = fs.open(saveFile, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    if data then persist = data end
end

local function saveGame()
    local f = fs.open(saveFile, "w")
    f.write(textutils.serialize(persist))
    f.close()
end

---
-- Main application entry point for Drunken Pong.
-- Manages P2P connections and synchronizes the ball and paddle states.
local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenPong"
    local socket = P2P_Socket.new(gameName, gameVersion, "DrunkenPong_Game")
    local isHost = false
    local isSolo = false

    -- Use shared theme colors
    local theme = {
        bg = sharedTheme.bg,
        text = sharedTheme.text,
        border = sharedTheme.prompt,
        player = sharedTheme.game.energy,
        opponent = sharedTheme.game.enemy,
        ball = sharedTheme.game.gold,
        trail = sharedTheme.game.wall,
        powerup = sharedTheme.game.charge
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
    local disconnected = false

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
        local titleText = isSolo and " [X] Drunken Pong (Solo) " or " [X] Drunken Pong "
        if #titleText > w then titleText = " [X] Pong " end
        term.setCursorPos(math.max(1, math.floor((w - #titleText)/2) + 1), 1)
        term.write(titleText)
        
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
        local safeMsg = tostring(msg or "")
        if #safeMsg > w - 2 then safeMsg = safeMsg:sub(1, w - 2) end
        term.setCursorPos(math.max(1, math.floor((w - #safeMsg)/2) + 1), math.floor(h/2))
        term.write(safeMsg)
        term.setCursorPos(math.max(1, math.floor((w - 12)/2) + 1), h)
        term.setBackgroundColor(theme.border)
        term.setTextColor(colors.white)
        term.write(" [TAB: Back] ")
    end

    -- Coordinate Scaling (Internal Grid 51x19)
    local INT_W, INT_H = 51, 19
    local function toScreen(ix, iy)
        local sw, sh = getSafeSize()
        local sx = math.floor((ix / INT_W) * (sw - 4)) + 2
        local sy = math.floor((iy / INT_H) * (sh - 4)) + 2
        return math.min(sw - 1, math.max(2, sx)), math.min(sh - 1, math.max(2, sy))
    end

    local function drawGame()
        drawFrame()
        local w, h = getSafeSize()
        
        -- Draw Scores cleanly on Row 2 (No term.blit mismatch possible)
        local myScore = string.format("%02d", score.me)
        local oppScore = string.format("%02d", score.opp)
        local totalScoreLen = 11 -- "[ 00 : 00 ]"
        local startX = math.max(1, math.floor((w - totalScoreLen) / 2) + 1)
        
        term.setCursorPos(startX, 2)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        term.write("[ ")
        term.setTextColor(colors.lime)
        term.write(myScore)
        term.setTextColor(colors.gray)
        term.write(" : ")
        term.setTextColor(colors.red)
        term.write(oppScore)
        term.setTextColor(colors.gray)
        term.write(" ]")

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
    
    local function drawModePicker()
        drawFrame()
        local w, h = getSafeSize()
        local dw = math.min(24, w - 2)
        local dh = 11
        local dx = math.floor((w - dw)/2) + 1
        local dy = math.max(2, math.floor((h - dh)/2) + 1)
        
        paintutils.drawFilledBox(dx, dy, dx + dw - 1, dy + dh - 1, colors.lightGray)
        paintutils.drawBox(dx, dy, dx + dw - 1, dy + dh - 1, colors.gray)
        
        term.setCursorPos(dx + 1, dy)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        local title = " [X] Drunken Pong"
        term.write(title .. string.rep(" ", math.max(0, dw - #title - 2)))
        
        local buttons = {
            { id = 1, text = "[ 1: Solo vs AI ]" },
            { id = 2, text = "[ 2: Host Game  ]" },
            { id = 3, text = "[ 3: Join Lobby ]" },
            { id = 4, text = "[ 4: Direct ID  ]" },
        }
        
        for i, b in ipairs(buttons) do
            local by = dy + 1 + (i * 2 - 1)
            term.setCursorPos(dx + math.floor((dw - #b.text)/2), by)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(b.text)
        end
        
        term.setCursorPos(dx + math.floor((dw - 13)/2), dy + dh - 1)
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.write("[ TAB: Exit ]")
        
        return dx, dy, dw, dh
    end

    local function findMatch()
        local dx, dy, dw, dh = drawModePicker()
        local key = nil
        while not key do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.one or p1 == keys.two or p1 == keys.three or p1 == keys.four or p1 == keys.q or p1 == keys.tab or p1 == keys.esc then
                    key = p1
                end
            elseif event == "mouse_click" then
                local btn, cx, cy = p1, p2, p3
                local sw, sh = getSafeSize()
                if cy == dy and cx >= dx and cx <= dx + 4 then
                    key = keys.q
                elseif cy == dy + dh - 1 then
                    key = keys.q
                else
                    for i = 1, 4 do
                        local by = dy + 1 + (i * 2 - 1)
                        if cy == by and cx >= dx and cx <= dx + dw then
                            if i == 1 then key = keys.one
                            elseif i == 2 then key = keys.two
                            elseif i == 3 then key = keys.three
                            elseif i == 4 then key = keys.four end
                            break
                        end
                    end
                end
            end
        end

        if key == keys.q or key == keys.tab or key == keys.esc then return false end

        if key == keys.one then
            isSolo = true
            isHost = true
            return true
        end

        local directTarget = nil
        if key == keys.four then
            drawLobby("Enter Host ID:")
            local sw, sh = getSafeSize()
            term.setCursorPos(math.max(1, math.floor(sw/2 - 5)), math.floor(sh/2) + 1)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            directTarget = tonumber(read())
            if not directTarget then return false end
        end

        if key == keys.two then
            -- HOSTING
            isHost = true
            socket.lobbyProtocol = "DrunkenPong_Lobby"
            socket:hostGame(username)
            drawLobby("Hosting... (Q: Cancel)")
            
            local success = false
            parallel.waitForAny(
                function()
                    while true do
                        local msg = socket:waitForJoin(0.2)
                        if msg then
                            opponentId = socket.peerId
                            success = true
                            break
                        end
                    end
                end,
                function()
                    while true do
                        local event, p1 = os.pullEventRaw("key")
                        if p1 == keys.q or p1 == keys.tab or p1 == keys.esc then
                            socket:stopHosting()
                            break
                        end
                    end
                end
            )
            return success
        else
            -- JOINING (key == keys.three or directTarget was entered)
            local targetId = nil
            if key == keys.three then
                drawLobby("Searching Lobbies...")
                local lobbies, err = socket:findLobbies()
                if not lobbies then
                    drawLobby(err or "Failed to list lobbies.")
                    sleep(1.5)
                    return false
                end

                if #lobbies == 0 then
                    drawLobby("No Pong hosts online.")
                    sleep(1.5)
                    return false
                end
                targetId = lobbies[1].id
            else
                targetId = directTarget
            end

            opponentId = targetId
            drawLobby("Connecting to ID " .. tostring(targetId) .. "...")
            
            socket.lobbyProtocol = "DrunkenPong_Lobby"
            local reply, err = socket:connect(targetId, {user=username})
            
            if reply then
                isHost = false
                return true
            else
                drawLobby(err or "Join Failed.")
                sleep(1.5)
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
                local event, p1, p2, p3 = os.pullEvent()
                if event == "key" then
                    local key = p1
                    if (key == keys.w or key == keys.up) and myY > 1 then myY = myY - 1
                    elseif (key == keys.s or key == keys.down) and myY < INT_H - PADDLE_HEIGHT then myY = myY + 1
                    elseif key == keys.q or key == keys.tab then 
                        matchActive = false
                        socket:send({type="disconnect"})
                        break
                    end
                    -- Immediate Sync on move
                    socket:send({type="move", y=myY})
                elseif event == "mouse_click" or event == "mouse_drag" then
                    local btn, cx, cy = p1, p2, p3
                    local sw, sh = getSafeSize()
                    local targetY = math.floor(((cy - 2) / math.max(1, sh - 2)) * INT_H)
                    myY = math.min(INT_H - myHeight, math.max(1, targetY))
                    if not isSolo then socket:send({type="move", y=myY}) end
                end
            end
        end,
        function() -- Ball Physics (Host Only) & Tick
            while matchActive do
                if isHost then
                    if isSolo then
                        -- Smart AI Opponent
                        for _, b in ipairs(balls) do
                            if b.dx > 0 and b.x > INT_W / 4 then
                                local targetOppY = b.y - math.floor(oppHeight / 2)
                                if oppY < targetOppY and oppY < INT_H - oppHeight then
                                    oppY = math.min(INT_H - oppHeight, oppY + 0.6)
                                elseif oppY > targetOppY and oppY > 1 then
                                    oppY = math.max(1, oppY - 0.6)
                                end
                            end
                        end
                    end

                    -- Ball Progression & Trail Logic
                    for bi, b in ipairs(balls) do
                        table.insert(trails, {x=b.x, y=b.y})
                        if #trails > 20 then table.remove(trails, 1) end

                        b.x = b.x + b.dx * ballSpeed
                        b.y = b.y + b.dy * ballSpeed
                        
                        if b.y <= 1 or b.y >= INT_H - 1 then 
                            b.dy = -b.dy
                            Sound.playNote("snare", 0.4, 12)
                            for i=1,3 do addParticle(b.x, b.y, theme.ball) end
                        end
                        
                        -- Paddle Hit - Local
                        if b.x <= 2 then
                            if b.y >= myY and b.y < myY + myHeight then
                                b.dx = math.abs(b.dx)
                                local hitOffset = (b.y - (myY + myHeight/2)) / (myHeight/2)
                                b.dy = b.dy + hitOffset * 0.5
                                ballSpeed = math.min(ballSpeed + 0.02, 1.5)
                                shake = 2
                                Sound.playNote("hat", 0.8, 18)
                                for i=1,5 do addParticle(b.x, b.y, theme.player, "*") end
                            else
                                score.opp = score.opp + 1
                                b.x, b.y = INT_W/2, INT_H/2
                                b.dx = -b.dx
                                ballSpeed = 0.5
                                flash = colors.red
                                shake = 5
                                Sound.playNote("bass", 1.2, 6)
                            end
                        elseif b.x >= INT_W - 1 then
                            -- Paddle Hit - Remote
                            if b.y >= oppY and b.y < oppY + oppHeight then
                                b.dx = -math.abs(b.dx)
                                local hitOffset = (b.y - (oppY + oppHeight/2)) / (oppHeight/2)
                                b.dy = b.dy + hitOffset * 0.5
                                ballSpeed = math.min(ballSpeed + 0.02, 1.5)
                                shake = 2
                                Sound.playNote("hat", 0.8, 18)
                                for i=1,5 do addParticle(b.x, b.y, theme.opponent, "*") end
                            else
                                score.me = score.me + 1
                                b.x, b.y = INT_W/2, INT_H/2
                                b.dx = math.abs(b.dx)
                                ballSpeed = 0.5
                                flash = colors.lime
                                shake = 5
                                Sound.playNote("pling", 1.2, 20)
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
                    
                    if not isSolo and os.epoch("utc") - lastSync > 50 then
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
            if isSolo then
                while matchActive do sleep(0.2) end
                return
            end
            local lastRecv = os.epoch("utc")
            while matchActive do
                local msg = socket:receive(0.5)
                if msg then
                    lastRecv = os.epoch("utc")
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
                    elseif msg.type == "disconnect" then
                        disconnected = true
                        matchActive = false
                        break
                    end
                else
                    -- 8 second timeout with no packets from peer
                    if os.epoch("utc") - lastRecv > 8000 then
                        disconnected = true
                        matchActive = false
                        break
                    end
                end
            end
        end
    )
    
    -- Match Results & Score Submission
    drawGame()
    if disconnected then
        term.setCursorPos(math.max(1, math.floor(w/2 - 14)), math.floor(h/2 + 2))
        term.setTextColor(colors.red)
        term.write("Opponent Disconnected / Left!")
    else
        term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2 + 2))
        term.setTextColor(colors.lime)
        term.write("Match Over!")

        -- Submit winners score
        if score.me > score.opp then
            persist.wins = persist.wins + 1
            saveGame()
            socket:submitScore(username, persist.wins)
        end
    end

    sleep(2)
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Pong Error: " .. tostring(err))
    pcall(os.pullEvent)
end
