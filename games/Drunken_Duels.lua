--[[
    Drunken Duels (v1.1)
    by Gemini Gem

    Purpose:
    A 1v1 P2P combat game for Drunken OS.
    Challenge a friend over Rednet and battle for dominance!
]]

-- Load shared libraries
if package and package.path then package.path = "/?.lua;" .. package.path end
local sharedTheme = require("lib.theme")

local gameVersion = 2.2
local P2P_Socket = require("lib.p2p_socket")
local saveFile = ".duels_save"

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

local classes = {
    Warrior = {
        hp = 120, energy = 10, 
        passive = "Tenacity: -20% Dmg taken",
        color = colors.orange,
        portrait = {
            "  [==]  ",
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

---
-- Main application entry point for Drunken Duels.
-- Initializes P2P sockets and handles multiplayer matchups.
local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"


    local gameName = "DrunkenDuels"
    local socket = P2P_Socket.new(gameName, gameVersion, "DrunkenDuels_Game")
    local isSpectator = false
    local isSolo = false

    local sound = nil
    pcall(function() sound = require("lib.sound") end)
    local function playSfx(fn, ...)
        if sound and sound[fn] then pcall(sound[fn], ...) end
    end
    local function playTone(inst, pitch, vol)
        if sound and sound.playNote then pcall(sound.playNote, colors.white, inst, pitch, vol) end
    end

    -- Win95 Theme colors
    local theme = {
        bg = colors.lightGray,
        text = colors.black,
        border = colors.gray,
        player = colors.blue,
        opponent = colors.red,
        header = colors.blue,
        hp = colors.red,
        en = colors.lightBlue,
        charge = colors.yellow,
        active = colors.blue
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
        table.insert(logs, {text = msg, color = color or colors.white})
        if #logs > 5 then table.remove(logs, 1) end
    end

    local function addParticle(text, x, y, color)
        table.insert(particles, {text = text, x = x, y = y, color = color, life = 10})
    end

    local function drawBar(x, y, width, val, max, color, label)
        term.setCursorPos(x, y)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(string.format("%-3s: ", label))
        
        local barX = x + 5
        local fillWidth = math.max(0, math.min(width, math.floor(((val or 0) / math.max(1, max or 1)) * width)))
        
        term.setCursorPos(barX, y)
        term.setBackgroundColor(colors.black)
        term.setTextColor(color)
        term.write(string.rep("=", fillWidth))
        term.setTextColor(colors.gray)
        term.write(string.rep("-", width - fillWidth))
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(string.format(" %d/%d", val or 0, max or 1))
    end

    local function screenShake()
        shakeDir = math.random(-1, 1)
        flashCol = colors.red
        sleep(0.05)
        shakeDir = 0
        flashCol = nil
    end

    local function drawFrame(subTitle)
        local w, h = getSafeSize()
        term.setBackgroundColor(flashCol or colors.lightGray); term.clear()
        
        -- Win95 Title Bar
        local offset = shakeDir
        term.setCursorPos(1 + offset, 1)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        local title = " Drunken Duels " .. (subTitle and ("- " .. subTitle) or ("v" .. gameVersion))
        if #title > w - 4 then title = title:sub(1, w - 4) end
        term.write(title .. string.rep(" ", math.max(0, w - #title - 3)))
        
        term.setCursorPos(w - 2 + offset, 1)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write("[X]")
    end

    local function drawLobby(msg)
        drawFrame("Lobby")
        local w, h = getSafeSize()
        
        -- Win95 Dialog
        local bw = math.min(w - 4, 34)
        local bh = 11
        local bx = math.floor((w - bw) / 2)
        local by = math.floor((h - bh) / 2)
        
        term.setBackgroundColor(colors.gray)
        for y = by, by + bh do
            term.setCursorPos(bx, y)
            term.write(string.rep(" ", bw))
        end
        
        term.setCursorPos(bx + 2, by + 1)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.yellow)
        term.write("SELECT MATCH MODE:")

        local lobbyOpts = {
            "[1] Solo (vs AI Bot)",
            "[2] Host Match (P2P)",
            "[3] Join Match (Lobby)",
            "[4] Direct ID Connect",
            "[5] Spectate Match",
            "[Q] Exit Duel"
        }
        for i, opt in ipairs(lobbyOpts) do
            term.setCursorPos(bx + 2, by + 2 + i)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(string.format(" %-" .. (bw - 6) .. "s ", opt))
        end

        if msg then
            term.setCursorPos(bx + 2, by + bh)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.lime)
            local cleanMsg = #msg > bw - 4 and msg:sub(1, bw - 7) .. "..." or msg
            term.write(cleanMsg)
        end
        
        return bx, by, bw, bh
    end

    local function drawStats()
        local w, h = getSafeSize()
        local half = math.floor(w / 2)
        
        -- My Stats (Left)
        term.setTextColor(colors.blue)
        term.setBackgroundColor(colors.lightGray)
        local leftLabel = isSpectator and "P2 (" .. (myStats.username or "Player 2") .. ")" or "YOU (" .. username .. ")"
        term.setCursorPos(3, 3); term.write(leftLabel .. " [" .. (myStats.class or "?") .. "]")
        drawBar(3, 4, 10, myStats.hp, myStats.maxHp, theme.hp, "HP")
        drawBar(3, 5, 10, myStats.energy, myStats.maxEnergy or 10, theme.en, "EN")
        drawBar(3, 6, 5, myStats.charge, 3, theme.charge, "ULT")
        
        -- Portrait Player
        if myStats.class and classes[myStats.class] then
            term.setTextColor(classes[myStats.class].color)
            term.setBackgroundColor(colors.lightGray)
            for i, line in ipairs(classes[myStats.class].portrait) do
                term.setCursorPos(3, 7 + i); term.write(line)
            end
        end

        -- Opponent Stats (Right)
        term.setTextColor(colors.red)
        term.setBackgroundColor(colors.lightGray)
        local oppName = oppStats.username or (isSolo and "ShadowBot" or "Opponent")
        local rightLabel = isSpectator and "P1 (" .. oppName .. ")" or "OP (" .. oppName .. ")"
        term.setCursorPos(math.max(half, w - 25), 3); term.write(rightLabel .. " [" .. (oppStats.class or "?") .. "]")
        drawBar(math.max(half, w - 25), 4, 10, oppStats.hp, oppStats.maxHp, theme.hp, "HP")
        drawBar(math.max(half, w - 25), 5, 10, oppStats.energy, oppStats.maxEnergy or 10, theme.en, "EN")
        drawBar(math.max(half, w - 25), 6, 5, oppStats.charge, 3, theme.charge, "ULT")

        -- Portrait Opponent
        if oppStats.class and classes[oppStats.class] then
            term.setTextColor(classes[oppStats.class].color)
            term.setBackgroundColor(colors.lightGray)
            for i, line in ipairs(classes[oppStats.class].portrait) do
                term.setCursorPos(math.max(half + 10, w - 12), 7 + i); term.write(line)
            end
        end
        
        -- Recessed Battle Log Box
        local logBoxY = math.max(11, h - 7)
        term.setBackgroundColor(colors.black)
        for y = logBoxY, h - 2 do
            term.setCursorPos(2, y)
            term.write(string.rep(" ", w - 2))
        end
        for i, log in ipairs(logs) do
            if logBoxY + i - 1 <= h - 2 then
                term.setCursorPos(3, logBoxY + i - 1)
                term.setBackgroundColor(colors.black)
                term.setTextColor(log.color or colors.white)
                term.write("> " .. log.text)
            end
        end

        -- Particles
        for i = #particles, 1, -1 do
            local p = particles[i]
            term.setTextColor(p.color)
            term.setBackgroundColor(colors.lightGray)
            term.setCursorPos(p.x, p.y)
            term.write(p.text)
            p.life = p.life - 1
            p.y = p.y - 1 -- Float up
            if p.life <= 0 then table.remove(particles, i) end
        end
    end

    local function drawClassSelection()
        local w, h = getSafeSize()
        drawFrame("Class Selection")
        term.setTextColor(colors.black)
        term.setBackgroundColor(colors.lightGray)
        local title = "CHOOSE YOUR FIGHTER"
        term.setCursorPos(math.floor(w/2 - #title/2), 3); term.write(title)

        local classOrder = { "Warrior", "Mage", "Rogue" }
        for i, name in ipairs(classOrder) do
            local data = classes[name]
            local x = 3 + ((i - 1) * 16)
            
            -- Win95 Card Bevel
            term.setBackgroundColor(colors.gray)
            for cy = 5, 13 do
                term.setCursorPos(x, cy); term.write(string.rep(" ", 15))
            end
            
            term.setTextColor(data.color)
            term.setBackgroundColor(colors.gray)
            term.setCursorPos(x + 1, 6); term.write("[" .. i .. "] " .. name)
            for j, line in ipairs(data.portrait) do
                term.setCursorPos(x + 2, 7 + j); term.write(line)
            end
            term.setTextColor(colors.white)
            term.setCursorPos(x + 2, 11); term.write("HP: " .. data.hp)
            term.setCursorPos(x + 2, 12); term.write("EN: " .. data.energy)
        end
        
        term.setCursorPos(1, h)
        term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
        term.write(string.rep(" ", w))
        term.setCursorPos(2, h)
        term.write("Tap card or press 1-3 to pick")
    end

    local function drawGame()
        drawFrame("Combat Arena")
        drawStats()
        local w, h = getSafeSize()
        
        term.setCursorPos(1, h)
        term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
        term.write(string.rep(" ", w))

        if turn == 1 then
            local spec = "Special"
            if myStats.class == "Warrior" then spec = "Bash"
            elseif myStats.class == "Mage" then spec = "Fire"
            elseif myStats.class == "Rogue" then spec = "Pois" end
            
            local ult = "ULT:Lock"
            if myStats.charge >= 3 then
                if myStats.class == "Warrior" then ult = "EXECUTE"
                elseif myStats.class == "Mage" then ult = "ARCANE"
                elseif myStats.class == "Rogue" then ult = "ASSASSIN" end
            end

            term.setCursorPos(2, h)
            term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
            term.write("[1:Atk] [2:" .. spec .. "] [3:" .. ult .. "] [4:Def] [5:Rest] [Q:Quit]")
        elseif isSpectator then
            term.setCursorPos(math.floor(w/2 - 10), h)
            term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
            term.write(" [ SPECTATING MATCH ] ")
        elseif turn == 0 or turn == 2 then
            term.setCursorPos(math.floor(w/2 - 12), h)
            term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
            term.write(" [ Waiting for Opponent... ] ")
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
        local modeChoice = nil
        while not modeChoice do
            local bx, by, bw, bh = drawLobby()
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.one then modeChoice = 1; playSfx("playClick")
                elseif p1 == keys.two then modeChoice = 2; playSfx("playClick")
                elseif p1 == keys.three then modeChoice = 3; playSfx("playClick")
                elseif p1 == keys.four then modeChoice = 4; playSfx("playClick")
                elseif p1 == keys.five then modeChoice = 5; playSfx("playClick")
                elseif p1 == keys.q or p1 == keys.tab then return false end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                local w, h = getSafeSize()
                if my == 1 and mx >= w - 3 then return false end
                for i = 1, 6 do
                    if my == by + 2 + i and mx >= bx and mx <= bx + bw then
                        playSfx("playClick")
                        if i == 6 then return false else modeChoice = i end
                        break
                    end
                end
            end
        end

        local directTarget = nil
        if modeChoice == 4 or modeChoice == 5 then
            drawLobby("Enter Host ID: ")
            local w, h = getSafeSize()
            term.setCursorPos(math.floor(w/2 - 5), math.floor(h/2) + 1)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.setCursorBlink(true)
            directTarget = tonumber(read())
            term.setCursorBlink(false)
            if not directTarget then return false end
        end

        if modeChoice == 5 then
            -- SPECTATING
            opponentId = directTarget
            drawLobby("Spectating Host ID " .. directTarget .. "...")
            socket.lobbyProtocol = "DrunkenDuels_Lobby"
            local reply, err = socket:spectate(directTarget)
            if reply then
                isSpectator = true
                isHost = false
                return true
            else
                drawLobby(err or "Spectate Failed.")
                sleep(2)
                return false
            end
        end

        -- Class Selection before match
        local chosenClass = nil
        while not chosenClass do
            drawClassSelection()
            local event, p1, p2, p3 = os.pullEvent()
            local w, h = getSafeSize()
            if event == "key" then
                if p1 == keys.one then chosenClass = "Warrior"; playSfx("playClick")
                elseif p1 == keys.two then chosenClass = "Mage"; playSfx("playClick")
                elseif p1 == keys.three then chosenClass = "Rogue"; playSfx("playClick")
                elseif p1 == keys.q or p1 == keys.tab or p1 == keys.backspace then return false end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= w - 3 then return false end
                for i, cName in ipairs({"Warrior", "Mage", "Rogue"}) do
                    local cx = 3 + ((i - 1) * 16)
                    if mx >= cx and mx <= cx + 15 and my >= 5 and my <= 13 then
                        chosenClass = cName
                        playSfx("playClick")
                        break
                    end
                end
            end
        end

        local classData = classes[chosenClass]
        myStats.class = chosenClass
        myStats.hp = classData.hp
        myStats.maxHp = classData.hp
        myStats.energy = classData.energy
        myStats.maxEnergy = classData.energy
        myStats.charge = 0
        myStats.username = username
        myStats.status = {}

        if modeChoice == 1 then
            -- SOLO MODE (VS AI BOT)
            isSolo = true
            isHost = true
            local botPool = {"Warrior", "Mage", "Rogue"}
            local botClass = botPool[math.random(1, 3)]
            local bData = classes[botClass]
            oppStats.username = "ShadowBot"
            oppStats.class = botClass
            oppStats.hp = bData.hp
            oppStats.maxHp = bData.hp
            oppStats.energy = bData.energy
            oppStats.maxEnergy = bData.energy
            oppStats.charge = 0
            oppStats.status = {}
            addLog("Duelling " .. oppStats.username .. " (" .. botClass .. ")!", colors.yellow)
            return true
        end

        if modeChoice == 2 then
            -- HOSTING
            isHost = true
            socket.lobbyProtocol = "DrunkenDuels_Lobby" -- Ensure specific lobby protocol
            socket:hostGame(username)
            drawLobby("Hosting... Waiting for Player...")
            
            local success = false
            parallel.waitForAny(
                function()
                    while true do
                        local msg = socket:waitForJoin(0.2)
                        if msg then
                            opponentId = socket.peerId
                            oppStats.username = msg.user
                            oppStats.class = msg.class
                            local oData = classes[msg.class] or classes.Warrior
                            oppStats.hp = oData.hp
                            oppStats.maxHp = oData.hp
                            oppStats.energy = oData.energy
                            oppStats.maxEnergy = oData.energy
                            oppStats.charge = 0
                            oppStats.status = {}
                            success = true
                            break
                        end
                        socket:acceptSpectator(0.1)
                    end
                end,
                function()
                    while true do
                        local event, p1 = os.pullEventRaw("key")
                        if p1 == keys.q or p1 == keys.tab then
                            socket:stopHosting()
                            break
                        end
                    end
                end
            )
            return success
        else
            -- JOINING (Standard or Direct)
            local targetId = nil
            if modeChoice == 3 then
                drawLobby("Fetching Lobbies...")
                local lobbies, err = socket:findLobbies()
                if not lobbies or #lobbies == 0 then
                    drawLobby(err or "No " .. gameName .. " hosts online.")
                    sleep(1.5)
                    return false
                end
                targetId = lobbies[1].id
            else
                targetId = directTarget
            end

            opponentId = targetId
            drawLobby("Connecting to ID " .. targetId .. "...")
            socket.lobbyProtocol = "DrunkenDuels_Lobby"
            local reply, err = socket:connect(targetId, {
                user=username, 
                class=chosenClass 
            })
            
            if reply then
                isHost = false
                oppStats.username = reply.user
                oppStats.class = reply.class
                local oData = classes[reply.class] or classes.Warrior
                oppStats.hp = oData.hp
                oppStats.maxHp = oData.hp
                oppStats.energy = oData.energy
                oppStats.maxEnergy = oData.energy
                oppStats.charge = 0
                oppStats.status = {}
                return true
            else
                drawLobby(err or "Connection Failed.")
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
                playTone("hat", 16, 0.5)
                return 0
            end
            
            target.hp = math.max(0, target.hp - final)
            addParticle("-" .. final, source == "p1" and (getSafeSize() - 10) or 5, 4, colors.red)
            playTone("bass", 2, 0.8)
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
            
            if m.ult then
                me.charge = 0
                playTone("bell", 18, 1.0)
                playTone("chime", 12, 1.0)
            else
                me.charge = math.min(3, me.charge + 1)
                if move == "attack" then playTone("snare", 8, 0.9)
                elseif move == "defend" then playTone("bass", 10, 0.8)
                elseif move == "rest" then playTone("chime", 8, 0.7)
                else playTone("flute", 12, 0.9) end
            end
            me.energy = math.max(0, me.energy - m.cost)
            
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
    local waitStart = os.epoch("utc")
    
    while matchActive do
        drawGame()
        local w, h = getSafeSize()
        
        local canMove = (turn == 1 and not isSpectator)
        if myStats.status.stun and not isSpectator then
            addLog("STUNNED! Skipping turn...", colors.yellow)
            myStats.status.stun = nil
            if isSolo or isHost then myMove = "rest" else socket:send({type="move", move="rest"}) end
            canMove = false
            turn = 0
        end

        if canMove then
            local timer = os.startTimer(30)
            local move = nil
            
            while not move do
                local event, p1, p2, p3 = os.pullEvent()
                if event == "key" then
                    local key = p1
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
                            playTone("bass", 1, 0.4)
                        end
                    elseif key == keys.four then move = "defend"
                    elseif key == keys.five then move = "rest"
                    elseif key == keys.q or key == keys.tab then move = "forfeit" end
                elseif event == "mouse_click" then
                    local mx, my = p2, p3
                    if my == 1 and mx >= w - 3 then
                        move = "forfeit"
                    elseif my == h then
                        if mx >= 2 and mx <= 8 then move = "attack"
                        elseif mx >= 10 and mx <= 18 then
                            if myStats.class == "Warrior" then move = "shield_bash"
                            elseif myStats.class == "Mage" then move = "fireball"
                            elseif myStats.class == "Rogue" then move = "poison_stab" end
                        elseif mx >= 20 and mx <= 30 then
                            if myStats.charge >= 3 then
                                if myStats.class == "Warrior" then move = "execute"
                                elseif myStats.class == "Mage" then move = "arcane_nova"
                                elseif myStats.class == "Rogue" then move = "assassinate" end
                            else
                                addLog("Ultimate NOT READY!", colors.red)
                                playTone("bass", 1, 0.4)
                            end
                        elseif mx >= 32 and mx <= 39 then move = "defend"
                        elseif mx >= 41 and mx <= 48 then move = "rest"
                        elseif mx >= 50 and mx <= 58 then move = "forfeit" end
                    end
                elseif event == "timer" and p1 == timer then
                    addLog("Time out! Automatically resting.", colors.gray)
                    move = "rest"
                end
                
                if move then
                    local mPrices = {
                        attack = 2, shield_bash = 4, fireball = 5, poison_stab = 3,
                        execute = 0, arcane_nova = 0, assassinate = 0,
                        defend = 1, rest = 0, forfeit = 0
                    }
                    if myStats.energy < (mPrices[move] or 0) then
                        addLog("Not enough energy!", colors.red)
                        playTone("bass", 1, 0.4)
                        move = nil
                    end
                end
            end
            
            if isSolo then
                myMove = move
                turn = 0
            elseif isHost then
                myMove = move
                turn = 0
            else
                socket:send({type="move", move=move})
                turn = 0
            end
            waitStart = os.epoch("utc")
        elseif turn == 0 or turn == 2 then
            if isSolo then
                -- Smart AI Opponent Turn
                sleep(0.4)
                local oppM = "attack"
                if oppStats.charge >= 3 then
                    if oppStats.class == "Warrior" then oppM = "execute"
                    elseif oppStats.class == "Mage" then oppM = "arcane_nova"
                    elseif oppStats.class == "Rogue" then oppM = "assassinate" end
                elseif oppStats.hp < 25 and oppStats.energy >= 1 and math.random(1, 10) <= 5 then
                    oppM = "defend"
                elseif oppStats.energy >= 4 and math.random(1, 10) <= 6 then
                    if oppStats.class == "Warrior" then oppM = "shield_bash"
                    elseif oppStats.class == "Mage" then oppM = "fireball"
                    elseif oppStats.class == "Rogue" then oppM = "poison_stab" end
                elseif oppStats.energy >= 2 then
                    oppM = "attack"
                else
                    oppM = "rest"
                end
                
                oppMove = oppM
                processTurn(myMove, oppMove)
                screenShake()
                
                local ended = (myMove == "forfeit" or oppMove == "forfeit" or myStats.hp <= 0 or oppStats.hp <= 0)
                if ended then
                    matchActive = false
                else
                    myMove = nil
                    oppMove = nil
                    turn = 1
                end
            elseif isHost then
                local msg = socket:receive(0.5)
                socket:acceptSpectator(0)

                if msg and msg.type == "move" then
                    oppMove = msg.move
                    processTurn(myMove, oppMove)
                    
                    local ended = (myMove == "forfeit" or oppMove == "forfeit" or myStats.hp <= 0 or oppStats.hp <= 0)
                    screenShake()
                    socket:send({type="sync", myStats=oppStats, oppStats=myStats, logs=logs, ended=ended})
                    
                    if ended then matchActive = false end
                    myMove = nil
                    oppMove = nil
                    turn = 1
                elseif msg and msg.type == "forfeit" then
                    addLog("Opponent Forfeited!", colors.red)
                    matchActive = false
                elseif not msg then
                    if os.epoch("utc") - waitStart > 45000 then
                        addLog("Opponent Timed Out!", colors.red)
                        matchActive = false
                    end
                end
            else
                local msg = socket:receive(1)
                if msg then
                    if msg.type == "sync" then
                        myStats = msg.myStats
                        oppStats = msg.oppStats
                        logs = msg.logs
                        screenShake()
                        if msg.ended then matchActive = false end
                        if not isSpectator then turn = 1 end
                    elseif msg.type == "forfeit" then
                        addLog("Opponent Forfeited!", colors.red)
                        matchActive = false
                    end
                else
                    if os.epoch("utc") - waitStart > 45000 then
                        addLog("Host Timed Out!", colors.red)
                        matchActive = false
                    end
                end
            end
        end
        
        if myStats.hp <= 0 or oppStats.hp <= 0 then
            addLog("Match Ended!")
            matchActive = false
            
            if oppStats.hp <= 0 then
                persist.wins = persist.wins + 1
                saveGame()
                pcall(function() socket:submitScore(username, persist.wins) end)
                addLog("VICTORY! You won the duel!", colors.lime)
                playSfx("playSuccess")
            else
                addLog("DEFEAT! You were slain!", colors.red)
                playTone("bass", 6, 1.0)
                sleep(0.1)
                playTone("bass", 2, 1.0)
            end
        end
    end
    
    drawGame()
    local w, h = getSafeSize()
    term.setCursorPos(math.floor(w/2 - 14), h - 1)
    term.setBackgroundColor(colors.blue); term.setTextColor(colors.yellow)
    term.write(" PRESS ANY KEY OR TAP TO EXIT ")
    while true do
        local e = os.pullEvent()
        if e == "key" or e == "mouse_click" then break end
    end
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Duels Error: " .. err)
    os.pullEvent("key")
end
