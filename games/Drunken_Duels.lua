--[[
    Drunken Duels (v1.0)
    by Gemini Gem

    Purpose:
    A 1v1 P2P combat game for Drunken OS.
    Challenge a friend over Rednet and battle for dominance!
]]

local gameVersion = 2.0
local P2P_Socket = require("lib.p2p_socket")

local classes = {
    Warrior = {
        hp = 120, energy = 10, 
        passive = "Tenacity: -20% Dmg taken",
        color = colors.orange,
        portrait = {
            "  [══]  ",
            " /[||]\\ ",
            "  /  \\  "
        }
    },
    Mage = {
        hp = 80, energy = 25, 
        passive = "Mana Flow: +2 EN/Turn",
        color = colors.purple,
        portrait = {
            "   /\\   ",
            "  (oo)  ",
            "  /--\\  "
        }
    },
    Rogue = {
        hp = 100, energy = 15, 
        passive = "Evasion: 15% Dodge",
        color = colors.lime,
        portrait = {
            "   __   ",
            "  (XX)  ",
            "  /  \\  "
        }
    }
}

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
        border = colors.lightGray,
        player = safeColor("lime", colors.white),
        opponent = safeColor("red", colors.white),
        header = safeColor("blue", colors.gray),
        hp = colors.red,
        en = colors.blue,
        charge = colors.yellow,
        active = colors.cyan
    }

    local particles = {}
    local shakeDir = 0
    local flashCol = nil

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

    local function addLog(msg, color)
        table.insert(logs, {text = msg, color = color or theme.text})
        if #logs > 5 then table.remove(logs, 1) end
    end

    local function addParticle(text, x, y, color)
        table.insert(particles, {text = text, x = x, y = y, color = color, life = 10})
    end

    local function drawBar(x, y, width, val, max, color, label)
        term.setCursorPos(x, y)
        term.setTextColor(theme.text)
        term.write(label .. ": ")
        
        local barX = x + #label + 2
        local fillWidth = math.floor((val / max) * width)
        
        term.setCursorPos(barX, y)
        term.setTextColor(color)
        term.write("[")
        term.write(string.rep("█", fillWidth))
        term.setTextColor(colors.gray)
        term.write(string.rep("-", width - fillWidth))
        term.setTextColor(color)
        term.write("] " .. val .. "/" .. max)
    end

    local function screenShake()
        shakeDir = math.random(-1, 1)
        flashCol = colors.red
        sleep(0.05)
        shakeDir = 0
        flashCol = nil
    end

    local function drawFrame()
        local w, h = getSafeSize()
        term.setBackgroundColor(flashCol or theme.bg); term.clear()
        
        -- Draw Border with Shake
        local offset = shakeDir
        term.setBackgroundColor(theme.border)
        term.setCursorPos(1 + offset, 1); term.write(string.rep(" ", w))
        term.setCursorPos(1 + offset, h); term.write(string.rep(" ", w))
        for i = 2, h - 1 do
            term.setCursorPos(1 + offset, i); term.write(" ")
            term.setCursorPos(w + offset, i); term.write(" ")
        end

        term.setCursorPos(1 + offset, 1)
        term.setTextColor(theme.text)
        local titleText = " Drunken Duels v" .. gameVersion .. " "
        term.setCursorPos(math.floor((w - #titleText)/2) + offset, 1); term.write(titleText)
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
        local half = math.floor(w / 2)
        
        -- My Stats (Left)
        term.setTextColor(theme.player)
        term.setCursorPos(3, 3); term.write("YOU (" .. username .. ") [" .. (myStats.class or "?") .. "]")
        drawBar(3, 4, 10, myStats.hp, myStats.maxHp, theme.hp, "HP")
        drawBar(3, 5, 10, myStats.energy, myStats.maxEnergy or 10, theme.en, "EN")
        drawBar(3, 6, 5, myStats.charge, 3, theme.charge, "ULT")
        
        -- Portrait Player
        if myStats.class then
            term.setTextColor(classes[myStats.class].color)
            for i, line in ipairs(classes[myStats.class].portrait) do
                term.setCursorPos(3, 7 + i); term.write(line)
            end
        end

        -- Opponent Stats (Right)
        term.setTextColor(theme.opponent)
        local oppLabel = "OP (" .. (oppStats.username or "Opponent") .. ") [" .. (oppStats.class or "?") .. "]"
        term.setCursorPos(w - #oppLabel - 2, 3); term.write(oppLabel)
        drawBar(w - 25, 4, 10, oppStats.hp, oppStats.maxHp, theme.hp, "HP")
        drawBar(w - 25, 5, 10, oppStats.energy, oppStats.maxEnergy or 10, theme.en, "EN")
        drawBar(w - 25, 6, 5, oppStats.charge, 3, theme.charge, "ULT")

        -- Portrait Opponent
        if oppStats.class then
            term.setTextColor(classes[oppStats.class].color)
            for i, line in ipairs(classes[oppStats.class].portrait) do
                term.setCursorPos(w - 10, 7 + i); term.write(line)
            end
        end
        
        -- Logs
        for i, log in ipairs(logs) do
            term.setCursorPos(3, h - 7 + i)
            term.setTextColor(log.color)
            term.write("> " .. log.text)
        end

        -- Particles
        for i = #particles, 1, -1 do
            local p = particles[i]
            term.setTextColor(p.color)
            term.setCursorPos(p.x, p.y)
            term.write(p.text)
            p.life = p.life - 1
            p.y = p.y - 1 -- Float up
            if p.life <= 0 then table.remove(particles, i) end
        end
    end

    local function drawClassSelection()
        local w, h = getSafeSize()
        drawFrame()
        term.setTextColor(theme.text)
        local title = "SELECT YOUR CLASS"
        term.setCursorPos(math.floor(w/2 - #title/2), 3); term.write(title)

        local i = 0
        for name, data in pairs(classes) do
            local x = 5 + (i * 15)
            term.setTextColor(data.color)
            term.setCursorPos(x, 6); term.write("[" .. (i+1) .. "] " .. name)
            for j, line in ipairs(data.portrait) do
                term.setCursorPos(x + 2, 7 + j); term.write(line)
            end
            term.setTextColor(theme.text)
            term.setCursorPos(x, 11); term.write("HP: " .. data.hp)
            term.setCursorPos(x, 12); term.write("EN: " .. data.energy)
            i = i + 1
        end
        
        term.setCursorPos(2, h)
        term.setBackgroundColor(theme.border); term.write(" Press 1-3 to pick ")
    end

    local function drawGame()
        drawFrame()
        drawStats()
        local w, h = getSafeSize()
        
        if turn == 1 then
            term.setCursorPos(2, h)
            term.setBackgroundColor(theme.border)
            local spec = "Special"
            if myStats.class == "Warrior" then spec = "ShieldBash"
            elseif myStats.class == "Mage" then spec = "Fireball"
            elseif myStats.class == "Rogue" then spec = "PoisonStab" end
            
            local ult = "ULT (Locked)"
            if myStats.charge >= 3 then
                if myStats.class == "Warrior" then ult = "EXECUTE"
                elseif myStats.class == "Mage" then ult = "ARCANE"
                elseif myStats.class == "Rogue" then ult = "ASSASSIN" end
            end

            term.write(" [1]Atk [2]" .. spec .. " [3]" .. ult .. " [4]Def [5]Rest [TAB]Quit ")
        elseif turn == 0 or turn == 2 then
            term.setCursorPos(math.floor(w/2 - 10), h)
            term.setBackgroundColor(theme.border)
            term.write(" Waiting for Opponent... ")
        end
    end

    -- Networking
    local socket = P2P_Socket.new("DrunkenDuels", gameVersion, "DrunkenDuels_Game")
    
    -- Negotiation
---
    -- Negotiates a 1v1 match over the Rednet network.
    -- Broadcasts a match request and waits for an acceptance. 
    -- Determines host status based on Computer ID.
    -- @return {boolean} True if a match was successfully found.
    local function findMatch()
        if not socket:checkArcade() then 
            drawLobby("Mainframe Arcade Server Offline!")
            sleep(2)
            -- We can allow direct connect even if arcade is offline, but listing won't work
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

        -- Class Selection before match
        drawClassSelection()
        local cKey
        repeat
            _, cKey = os.pullEvent("key")
        until cKey == keys.one or cKey == keys.two or cKey == keys.three
        
        local classNames = {"Warrior", "Mage", "Rogue"}
        local myClass = classNames[cKey == keys.one and 1 or (cKey == keys.two and 2 or 3)]
        local classData = classes[myClass]
        
        myStats.class = myClass
        myStats.hp = classData.hp
        myStats.maxHp = classData.hp
        myStats.energy = classData.energy
        myStats.maxEnergy = classData.energy
        myStats.charge = 0
        myStats.username = username
        myStats.status = {}

        if key == keys.one then
            -- HOSTING
            isHost = true
            socket.lobbyProtocol = "DrunkenDuels_Lobby" -- Ensure specific lobby protocol
            socket:hostGame(username)
            drawLobby("Hosting... Waiting for Player...")
            
            while true do
                -- Listen using socket
                local msg = socket:waitForJoin(0.1)
                if msg then
                    opponentId = socket.peerId
                    
                    -- Process handshake data
                    oppStats.username = msg.user
                    oppStats.class = msg.class
                    local oData = classes[msg.class]
                    oppStats.hp = oData.hp
                    oppStats.maxHp = oData.hp
                    oppStats.energy = oData.energy
                    oppStats.maxEnergy = oData.energy
                    oppStats.charge = 0
                    oppStats.status = {}
                    
                    -- Socket handles the accept reply internally in waitForJoin
                    return true
                end
                
                local tevt, tk = os.pullEventRaw()
                if tevt == "key" and (tk == keys.q or tk == keys.tab) then 
                    socket:stopHosting()
                    return false 
                end
            end
        else
            -- JOINING (Standard or Direct)
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
                
                -- Simple selection: just pick the first for now (as in original)
                -- Ideally we'd show a menu, but sticking to original flow
                targetId = lobbies[1].id
            else
                targetId = directTarget
            end

            opponentId = targetId
            drawLobby("Connecting to ID " .. targetId .. "...")
            
            -- Use socket to connect
            socket.lobbyProtocol = "DrunkenDuels_Lobby"
            local reply, err = socket:connect(targetId, {
                user=username, 
                class=myClass 
                -- socket adds version automatically
            })
            
            if reply then
                isHost = false
                -- Process Accept data
                oppStats.username = reply.user
                oppStats.class = reply.class
                local oData = classes[reply.class]
                oppStats.hp = oData.hp
                oppStats.maxHp = oData.hp
                oppStats.energy = oData.energy
                oppStats.maxEnergy = oData.energy
                oppStats.charge = 0
                oppStats.status = {}
                return true
            else
                drawLobby(err or "Join Failed.")
                sleep(2)
                return false
            end
        end
    end

    -- Combat Resolution (Host Only)
    local function processTurn(p1Move, p2Move)
        local results = {}
        
        -- Helper for damage
        local function applyDamage(target, amt, targetMove, source)
            local final = amt
            -- Defend reduction
            if targetMove == "defend" then final = math.floor(final * 0.4) end
            -- Warrior Passive
            if target.class == "Warrior" then final = math.floor(final * 0.8) end
            -- Rogue Passive
            if target.class == "Rogue" and math.random(1, 100) <= 15 then
                addLog(target.username .. " DODGED!", colors.lime)
                addParticle("MISS", source == "p1" and 5 or (getSafeSize() - 10), 5, colors.white)
                return 0
            end
            
            target.hp = math.max(0, target.hp - final)
            addParticle("-" .. final, source == "p1" and (getSafeSize() - 10) or 5, 4, colors.red)
            return final
        end

        -- Move definitions
        local moveData = {
            attack = {cost=2, dmg={10, 15}, name="Attack"},
            defend = {cost=1, name="Defend"},
            rest = {cost=0, name="Rest"},
            -- Warrior
            shield_bash = {cost=4, dmg={8, 12}, effect="stun", name="Shield Bash"},
            execute = {cost=0, ult=true, dmg={20, 30}, name="EXECUTE"},
            -- Mage
            fireball = {cost=5, dmg={15, 20}, effect="burn", name="Fireball"},
            arcane_nova = {cost=0, ult=true, dmg={30, 40}, name="ARCANE NOVA"},
            -- Rogue
            poison_stab = {cost=3, dmg={5, 10}, effect="poison", name="Poison Stab"},
            assassinate = {cost=0, ult=true, dmg={25, 35}, crit=true, name="ASSASSINATE"}
        }

        -- Handle Moves
        local function handlePlayerMove(me, opp, move, id, oppMove)
            local m = moveData[move]
            if not m then return end
            
            if m.ult then me.charge = 0 else me.charge = math.min(3, me.charge + 1) end
            me.energy = me.energy - m.cost
            
            if m.dmg then
                local d = math.random(m.dmg[1], m.dmg[2])
                if m.crit then d = d * 2; addLog("CRITICAL!", colors.yellow) end
                local taken = applyDamage(opp, d, oppMove, id)
                addLog(me.username .. " used " .. m.name .. " (" .. taken .. " dmg)", classes[me.class].color)
            else
                addLog(me.username .. " used " .. m.name, classes[me.class].color)
            end
            
            if m.effect == "stun" and math.random(1, 100) <= 40 then
                opp.status.stun = 1
                addLog(opp.username .. " is STUNNED!", colors.yellow)
            elseif m.effect == "burn" then
                opp.status.burn = 3
                addLog(opp.username .. " is BURNING!", colors.orange)
            elseif m.effect == "poison" then
                opp.status.poison = 5
                addLog(opp.username .. " is POISONED!", colors.green)
            end
            
            if move == "rest" then
                me.energy = math.min(me.maxEnergy, me.energy + 5)
            end
        end

        handlePlayerMove(myStats, oppStats, p1Move, "p1", p2Move)
        handlePlayerMove(oppStats, myStats, p2Move, "p2", p1Move)
        
        -- Start of Turn Regeneration & Status
        local function handleStatus(p)
            if p.class == "Mage" then p.energy = math.min(p.maxEnergy, p.energy + 2) end
            if p.status.burn then
                p.hp = math.max(0, p.hp - 5)
                p.status.burn = p.status.burn - 1
                if p.status.burn <= 0 then p.status.burn = nil end
                addLog(p.username .. " took burn damage", colors.orange)
            end
            if p.status.poison then
                p.hp = math.max(0, p.hp - 3)
                p.status.poison = p.status.poison - 1
                if p.status.poison <= 0 then p.status.poison = nil end
                addLog(p.username .. " took poison damage", colors.green)
            end
        end
        
        handleStatus(myStats)
        handleStatus(oppStats)
        
        return results
    end
    
    if not findMatch() then return end
    
    -- Start Match
    turn = isHost and 1 or 2
    local matchActive = true
    
    while matchActive do
        drawGame()
        
        local canMove = (turn == 1)
        if myStats.status.stun then
            addLog("STUNNED! Skipping turn...", colors.yellow)
            myStats.status.stun = nil
            if isHost then myMove = "rest" else socket:send({type="move", move="rest"}) end
            canMove = false
            turn = 0
        end

        if canMove then
            local timer = os.startTimer(30)
            local move = nil
            
            while not move do
                local event, p1, p2 = os.pullEvent()
                if event == "key" then
                    local key = p1
                    -- Move selection based on Class
                    if key == keys.one then move = "attack"
                    elseif key == keys.two then
                        if myStats.class == "Warrior" then move = "shield_bash"
                        elseif myStats.class == "Mage" then move = "fireball"
                        elseif myStats.class == "Rogue" then move = "poison_stab" end
                    elseif key == keys.three then
                        if myStats.charge >= 3 then
                            if myStats.class == "Warrior" then move = "execute"
                            elseif myStats.class == "Mage" then move = "arcane_nova"
                            elseif myStats.class == "Rogue" then move = "assassinate" end
                        else
                            addLog("Ultimate NOT READY!", colors.red)
                        end
                    elseif key == keys.four then move = "defend"
                    elseif key == keys.five then move = "rest"
                    elseif key == keys.q or key == keys.tab then move = "forfeit" end
                    
                    if move then
                        local mPrices = {
                            attack = 2, shield_bash = 4, fireball = 5, poison_stab = 3,
                            execute = 0, arcane_nova = 0, assassinate = 0,
                            defend = 1, rest = 0, forfeit = 0
                        }
                        if myStats.energy < (mPrices[move] or 0) then
                            addLog("Not enough energy!", colors.red)
                            move = nil -- Reset to keep loop going
                        end
                    end
                elseif event == "timer" and p1 == timer then
                    addLog("Time out! Automatically resting.", colors.gray)
                    move = "rest"
                end
            end
            
            if isHost then
                myMove = move
            else
                socket:send({type="move", move=move})
            end
            turn = 0
        elseif turn == 0 or turn == 2 then
            -- Waiting logic
            if isHost then
                -- Wait for guest move
                -- Wait for guest move
                local msg = socket:receive(1)
                if msg and msg.type == "move" then
                    oppMove = msg.move
                    processTurn(myMove, oppMove)
                    
                    local ended = (myMove == "forfeit" or oppMove == "forfeit" or myStats.hp <= 0 or oppStats.hp <= 0)
                    
                    -- Shake if anyone took dmg
                    screenShake()

                    -- Sync state to guest
                    -- Sync state to guest
                    socket:send({type="sync", myStats=oppStats, oppStats=myStats, logs=logs, ended=ended})
                    
                    if ended then matchActive = false end
                    
                    myMove = nil
                    oppMove = nil
                    turn = 1
                end
            else
                -- Wait for sync from host
                -- Wait for sync from host
                local msg = socket:receive(1)
                if msg then
                    if msg.type == "sync" then
                        myStats = msg.myStats
                        oppStats = msg.oppStats
                        logs = msg.logs
                        screenShake()
                        if msg.ended then matchActive = false end
                        turn = 1
                    elseif msg.type == "forfeit" then
                        addLog("Opponent Forfeited!", colors.red)
                        matchActive = false
                    end
                end
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
