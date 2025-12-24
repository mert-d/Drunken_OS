--[[
    Drunken Duels (v1.0)
    by Gemini Gem

    Purpose:
    A 1v1 P2P combat game for Drunken OS.
    Challenge a friend over Rednet and battle for dominance!
]]

local gameVersion = 1.2

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenDuels"
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
        header = safeColor("blue", colors.gray),
    }

    -- Game State
    local myStats = { hp = 100, maxHp = 100, energy = 10, charge = 0 }
    local oppStats = { hp = 100, maxHp = 100, energy = 10, charge = 0 }
    local logs = {"Welcome to the Arena!"}
    local turn = 0 -- 1 = My Turn, 2 = Opponent Turn, 0 = Waiting/Sync
    local myMove = nil
    local oppMove = nil

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function addLog(msg)
        table.insert(logs, msg)
        if #logs > 4 then table.remove(logs, 1) end
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
        local titleText = " Drunken Duels v" .. gameVersion .. " "
        term.setCursorPos(math.floor((w - #titleText)/2), 1); term.write(titleText)
    end

    local function drawLobby(msg)
        drawFrame()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.text)
        
        msg = msg or (isHost and "Waiting for player..." or "Searching for match...")
        if #msg > w - 4 then msg = msg:sub(1, w - 7) .. "..." end
        term.setCursorPos(math.floor(w/2 - #msg/2), math.floor(h/2))
        term.write(msg)
        
        term.setCursorPos(math.floor(w/2 - 10), h)
        term.setBackgroundColor(theme.border); term.write(" TAB: Back ")
    end

    local function drawStats()
        local w, h = getSafeSize()
        -- Split Screen Stats
        local half = math.floor(w / 2)
        
        -- My Stats (Left)
        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.player)
        term.setCursorPos(3, 3); term.write("YOU (" .. username .. ")")
        term.setCursorPos(3, 4); term.write("HP: " .. myStats.hp .. "/" .. myStats.maxHp)
        term.setCursorPos(3, 5); term.write("EN: " .. myStats.energy)
        
        -- Opponent Stats (Right)
        term.setTextColor(theme.opponent)
        local oppLabel = "OPPONENT"
        term.setCursorPos(w - #oppLabel - 2, 3); term.write(oppLabel)
        local hpLabel = "HP: " .. oppStats.hp .. "/" .. oppStats.maxHp
        term.setCursorPos(w - #hpLabel - 2, 4); term.write(hpLabel)
        local enLabel = "EN: " .. oppStats.energy
        term.setCursorPos(w - #enLabel - 2, 5); term.write(enLabel)
        
        -- Logs
        term.setTextColor(theme.text)
        for i, log in ipairs(logs) do
            term.setCursorPos(3, h - 6 + i)
            term.write("> " .. log)
        end
    end

    local function drawGame()
        drawFrame()
        drawStats()
        local w, h = getSafeSize()
        
        if turn == 1 then
            term.setCursorPos(2, h)
            term.setBackgroundColor(theme.border)
            term.write(" [1]Atk [2]Def [3]Heal [4]Rest [TAB]Back ")
        elseif turn == 2 then
            term.setCursorPos(math.floor(w/2 - 10), h)
            term.setBackgroundColor(theme.border)
            term.write(" Waiting for Opponent... ")
        end
    end

    -- Networking
    local modem = peripheral.find("modem")
    if not modem then
        error("Drunken Duels requires a Modem to play!")
    end
    rednet.open(peripheral.getName(modem))
    
    -- Negotiation
---
-- Negotiates a 1v1 match over the Rednet network.
-- Broadcasts a match request and waits for an acceptance. 
-- Determines host status based on Computer ID.
-- @return {boolean} True if a match was successfully found.
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
            local id, msg = rednet.receive("DrunkenDuels_Lobby", 2)
            if id and msg.type == "match_join" then
                opponentId = id
                rednet.send(id, {type="match_accept", user=username}, "DrunkenDuels_Lobby")
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

        -- Pick the first available host for now (can expand to a menu later)
        local target = options[1]
        opponentId = target.id
        drawLobby("Joining " .. target.user .. "...")
        rednet.send(target.id, {type="match_join", user=username}, "DrunkenDuels_Lobby")
        
        local sid, smsg = rednet.receive("DrunkenDuels_Lobby", 5)
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
    
    -- Start Match
    turn = isHost and 1 or 2
    local matchActive = true
    
    while matchActive do
        drawGame()
        
        if turn == 1 then
            local event, key = os.pullEvent("key")
            local move = nil
            if key == keys.one then move = "attack"
            elseif key == keys.two then move = "defend"
            elseif key == keys.three then move = "heal"
            elseif key == keys.four then move = "rest"
            elseif key == keys.q or key == keys.tab then move = "forfeit" end
            
            if move then
                local cost = {attack=2, defend=1, heal=5, rest=0, forfeit=0}
                if myStats.energy < (cost[move] or 0) then
                    addLog("Not enough energy for " .. move .. "!")
                else
                    rednet.send(opponentId, {type="move", move=move}, "DrunkenDuels_Game")
                    myMove = move
                    turn = 0
                end
            end
        elseif turn == 2 or turn == 0 then
            -- Waiting for the opponent to send their move
            local id, msg = rednet.receive("DrunkenDuels_Game", 5)
            if id == opponentId and msg.type == "move" then
                oppMove = msg.move
                
                -- Turn Resolution Logic: Compare both moves and calculate outcome
                if myMove == "attack" then
                    if oppMove == "defend" then
                        oppStats.hp = oppStats.hp - 5
                        myStats.energy = myStats.energy - 2
                        addLog("You attacked, but they defended (-5 HP)")
                    elseif oppMove == "rest" then
                        oppStats.hp = oppStats.hp - 20
                        myStats.energy = myStats.energy - 2
                        addLog("Critical Hit! They were resting (-20 HP)")
                    else
                        oppStats.hp = oppStats.hp - 15
                        myStats.energy = myStats.energy - 2
                        addLog("You landed a solid hit! (-15 HP)")
                    end
                elseif myMove == "heal" then
                    myStats.hp = math.min(myStats.maxHp, myStats.hp + 25)
                    myStats.energy = myStats.energy - 5
                    addLog("You focused and healed +25 HP.")
                elseif myMove == "rest" then
                    myStats.energy = myStats.energy + 3
                    addLog("You rested and gained energy.")
                end
                
                -- Check the relative outcome of the opponent's move
                if oppMove == "attack" then
                    if myMove == "defend" then
                        myStats.hp = myStats.hp - 5
                        addLog("Opponent attacked! You blocked (-5 HP)")
                    elseif myMove == "rest" then
                        myStats.hp = myStats.hp - 20
                        addLog("Ouch! You were caught resting (-20 HP)")
                    else
                        myStats.hp = myStats.hp - 15
                        addLog("Opponent hit you! (-15 HP)")
                    end
                end

                -- Edge Case: Forfeiting ends the match immediately
                if myMove == "forfeit" or oppMove == "forfeit" then
                    addLog("A player forfeited.")
                    matchActive = false
                end

                -- Swap turns based on host synchronization
                turn = isHost and 1 or 2
                if turn == 1 then turn = 2 else turn = 1 end -- Swap
                myMove = nil
                oppMove = nil
            end
        end
        
        if myStats.hp <= 0 or oppStats.hp <= 0 then
            addLog("Match Ended!")
            matchActive = false
        end
    end
    
    drawGame()
    print("\nPress any key to return.")
    os.pullEvent("key")
end

mainGame(...)
