--[[
    Drunken Dungeons (v2.5)
    by Gemini Gem & MuhendizBey

    Purpose:
    A turn-based ASCII roguelike for Drunken OS.
    Windows 95 aesthetic, touch controls, sound effects, and co-op multiplayer.
]]

-- Load shared libraries
if package and package.path then package.path = "/?.lua;" .. package.path end
local sharedTheme = require("lib.theme")
local P2P_Socket = require("lib.p2p_socket")

local Sound = nil
pcall(function() Sound = require("lib.sound") end)

local function playSnd(fn, ...)
    if Sound and Sound[fn] then
        pcall(Sound[fn], ...)
    end
end

local gameVersion = 2.5
local saveFile = ".dungeon_save"

local colorToBlit = sharedTheme.colorToBlit or {
    [colors.white] = "0", [colors.orange] = "1", [colors.magenta] = "2", [colors.lightBlue] = "3",
    [colors.yellow] = "4", [colors.lime] = "5", [colors.pink] = "6", [colors.gray] = "7",
    [colors.lightGray] = "8", [colors.cyan] = "9", [colors.purple] = "a", [colors.blue] = "b",
    [colors.brown] = "c", [colors.green] = "d", [colors.red] = "e", [colors.black] = "f"
}

local function saveGame(data)
    local f = fs.open(saveFile, "w")
    if f then
        f.write(textutils.serialize(data))
        f.close()
    end
end

local function loadGame()
    if not fs.exists(saveFile) then
        return { gold = 0, upgrades = { hp = 0, dmg = 0, luck = 0 } }
    end
    local f = fs.open(saveFile, "r")
    if not f then
        return { gold = 0, upgrades = { hp = 0, dmg = 0, luck = 0 } }
    end
    local data = textutils.unserialize(f.readAll())
    f.close()
    if type(data) ~= "table" then
        return { gold = 0, upgrades = { hp = 0, dmg = 0, luck = 0 } }
    end
    data.upgrades = data.upgrades or { hp = 0, dmg = 0, luck = 0 }
    data.gold = data.gold or 0
    return data
end

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenDungeons"
    local socket = P2P_Socket.new(gameName, gameVersion, "DrunkenDungeons_Game")
    local isMultiplayer = false
    local sharedSeed = os.time()

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local w, h = getSafeSize()
    local MAP_W = math.min(w - 6, 40)
    local MAP_H = math.min(h - 8, 14)

    local theme = {
        bg = colors.black,
        wall = sharedTheme.game.wall or colors.gray,
        floor = sharedTheme.game.floor or colors.lightGray,
        player = colors.yellow,
        enemy = colors.red,
        gold = colors.yellow,
        text = colors.white,
        border = colors.lightGray,
    }

    local TILE_WALL = "#"
    local TILE_FLOOR = "."
    local TILE_PLAYER = "@"
    local TILE_ENEMY = "E"
    local TILE_GOLD = "$"
    local TILE_STAIRS = ">"

    local persist = loadGame()

    local player = { 
        x = 2, y = 2, hp = 10, maxHp = 10, gold = 0, level = 1, xp = 0, dmg = 1,
        equipment = { weapon = nil, armor = nil, trinket = nil }
    }
    local map = {}
    local visibility = {}
    local entities = {}
    local dungeonLevel = 1
    local gameOver = false
    local logs = {{ text = "Welcome to Drunken Dungeons!", color = colors.yellow }}
    local class = "Brawler"
    local otherPlayer = { x = 0, y = 0, hp = 10, active = false }

    local itemPool = {
        weapon = {
            { name = "Rusty Dagger", dmg = 1, rarity = colors.lightGray },
            { name = "Iron Sword", dmg = 3, rarity = colors.white },
            { name = "Great Axe", dmg = 5, rarity = colors.orange },
        },
        armor = {
            { name = "Cloth Tunic", defense = 1, rarity = colors.lightGray },
            { name = "Leather Armor", defense = 2, rarity = colors.white },
            { name = "Plate Mail", defense = 4, rarity = colors.orange },
        },
        trinket = {
            { name = "Lucky Coin", luck = 5, rarity = colors.yellow },
            { name = "Owl Eye", vision = 2, rarity = colors.cyan },
        }
    }

    local function addLog(msg, color)
        table.insert(logs, { text = msg, color = color or colors.lightGray })
        if #logs > 3 then table.remove(logs, 1) end
    end

    local function generateMap()
        math.randomseed(sharedSeed + dungeonLevel)
        map = {}
        visibility = {}
        for y = 1, MAP_H do
            map[y] = {}
            visibility[y] = {}
            for x = 1, MAP_W do 
                map[y][x] = TILE_WALL 
                visibility[y][x] = 0
            end
        end

        local cx, cy = math.random(3, MAP_W - 3), math.random(3, MAP_H - 3)
        player.x, player.y = cx, cy

        for i = 1, 300 do
            map[cy][cx] = TILE_FLOOR
            local dir = math.random(1, 4)
            if dir == 1 and cx > 2 then cx = cx - 1
            elseif dir == 2 and cx < MAP_W - 1 then cx = cx + 1
            elseif dir == 3 and cy > 2 then cy = cy - 1
            elseif dir == 4 and cy < MAP_H - 1 then cy = cy + 1 end
        end
        
        entities = {}
        local count = 0
        local target = 5 + (dungeonLevel * 2)
        while count < target do
            local sx, sy = math.random(2, MAP_W - 1), math.random(2, MAP_H - 1)
            if map[sy][sx] == TILE_FLOOR and (sx ~= player.x or sy ~= player.y) then
                local isOccupied = false
                for _, e in ipairs(entities) do
                    if e.x == sx and e.y == sy then isOccupied = true; break end
                end
                
                if not isOccupied then
                    local eType = (count % 2 == 0) and "gold" or "enemy"
                    table.insert(entities, {
                        x = sx, 
                        y = sy, 
                        type = eType, 
                        hp = 2 + math.floor(dungeonLevel / 2)
                    })
                    count = count + 1
                end
            end
        end

        local sx, sy = math.random(2, MAP_W - 1), math.random(2, MAP_H - 1)
        while map[sy][sx] ~= TILE_FLOOR or (sx == player.x and sy == player.y) do
            sx, sy = math.random(2, MAP_W - 1), math.random(2, MAP_H - 1)
        end
        table.insert(entities, {x = sx, y = sy, type = "stairs", hp = 0})
    end

    local function updateVisibility()
        for y = 1, MAP_H do
            for x = 1, MAP_W do
                if visibility[y][x] == 2 then visibility[y][x] = 1 end
            end
        end

        local radius = 5
        if player.equipment.trinket and player.equipment.trinket.vision then
            radius = radius + player.equipment.trinket.vision
        end

        for dy = -radius, radius do
            for dx = -radius, radius do
                local dist = math.sqrt(dx*dx + dy*dy)
                if dist <= radius then
                    local vx, vy = player.x + dx, player.y + dy
                    if vx >= 1 and vx <= MAP_W and vy >= 1 and vy <= MAP_H then
                        local blocked = false
                        local steps = math.max(math.abs(dx), math.abs(dy))
                        for i = 1, steps - 1 do
                            local tx = math.floor(player.x + (dx * i / steps) + 0.5)
                            local ty = math.floor(player.y + (dy * i / steps) + 0.5)
                            if map[ty] and map[ty][tx] == TILE_WALL then
                                blocked = true; break
                            end
                        end
                        if not blocked then visibility[vy][vx] = 2 end
                    end
                end
            end
        end
    end

    local function draw()
        local curW, curH = getSafeSize()
        updateVisibility()
        
        -- Win95 Blue Title Bar
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.clearLine()
        local titleStr = " [X] Drunken Dungeons Lv." .. dungeonLevel .. (isMultiplayer and " (CO-OP)" or "")
        term.write(titleStr)

        -- Dungeon Viewport Background
        term.setBackgroundColor(theme.bg)
        for i = 2, curH - 4 do
            term.setCursorPos(1, i)
            term.write(string.rep(" ", curW))
        end

        local ox = math.max(2, math.floor((curW - MAP_W)/2) + 1)
        local oy = 3
        
        for y = 1, MAP_H do
            local row_chars = {}
            local row_fg = {}
            local row_bg = {}
            
            for x = 1, MAP_W do
                local v = visibility[y][x]
                local char = " "
                local fg = theme.text
                local bg = theme.bg
                
                if v == 0 then
                    char = " "
                    fg = colors.black
                    bg = colors.black
                else
                    local t = map[y][x]
                    if x == player.x and y == player.y then
                        char = TILE_PLAYER
                        fg = theme.player
                    elseif otherPlayer.active and x == otherPlayer.x and y == otherPlayer.y then
                        char = TILE_PLAYER
                        fg = colors.purple
                    else
                        local entFound = false
                        for _, ent in ipairs(entities) do
                            if ent.x == x and ent.y == y then
                                if v == 2 then
                                    char = (ent.type == "gold" and TILE_GOLD or (ent.type == "stairs" and TILE_STAIRS or TILE_ENEMY))
                                    fg = (ent.type == "gold" and theme.gold or (ent.type == "stairs" and colors.white or theme.enemy))
                                    entFound = true; break
                                end
                            end
                        end
                        if not entFound then
                            char = t
                            fg = (t == TILE_WALL and theme.wall or theme.floor)
                        end
                    end
                    
                    if v == 1 then
                        fg = colors.gray
                        if char == TILE_ENEMY or char == TILE_GOLD then char = TILE_FLOOR end
                    end
                end
                
                table.insert(row_chars, char)
                table.insert(row_fg, colorToBlit[fg] or "0")
                table.insert(row_bg, colorToBlit[bg] or "f")
            end
            
            term.setCursorPos(ox, oy + y - 1)
            term.blit(table.concat(row_chars), table.concat(row_fg), table.concat(row_bg))
        end

        -- Win95 Status Bar (Line curH - 3)
        term.setCursorPos(1, curH - 3)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.clearLine()
        
        local barLen = math.min(10, math.max(6, math.floor(curW * 0.16)))
        local hpFill = math.floor((math.max(0, player.hp) / player.maxHp) * barLen)
        term.setCursorPos(2, curH - 3)
        term.write("HP:[")
        term.blit(string.rep("|", hpFill) .. string.rep(".", barLen - hpFill), 
                  string.rep("e", hpFill) .. string.rep("7", barLen - hpFill),
                  string.rep("8", barLen))
        term.setCursorPos(2 + 4 + barLen, curH - 3)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(string.format("] %d/%d", player.hp, player.maxHp))
        
        local goldPos = math.min(curW - 20, 23)
        term.setCursorPos(goldPos, curH - 3)
        term.setTextColor(colors.brown)
        term.write(string.format("Gold:[%04d]", player.gold))
        
        if curW >= 42 then
            term.setCursorPos(goldPos + 12, curH - 3)
            term.setTextColor(colors.blue)
            term.write(string.format("XP:[%03d]", player.xp))
        end
        
        -- Win95 Combat / Action Logs (Lines curH - 2 and curH - 1)
        term.setCursorPos(1, curH - 2)
        term.setBackgroundColor(colors.lightGray)
        term.clearLine()
        if #logs >= 2 then
            local prevLog = logs[#logs - 1]
            term.setCursorPos(2, curH - 2)
            term.setTextColor(colors.gray)
            local ptxt = prevLog.text or tostring(prevLog)
            if #ptxt > curW - 4 then ptxt = ptxt:sub(1, curW - 7) .. "..." end
            term.write("  " .. ptxt)
        end

        term.setCursorPos(1, curH - 1)
        term.setBackgroundColor(colors.lightGray)
        term.clearLine()
        if #logs >= 1 then
            local latestLog = logs[#logs]
            term.setCursorPos(2, curH - 1)
            term.setTextColor(latestLog.color or colors.black)
            local ltxt = latestLog.text or tostring(latestLog)
            if #ltxt > curW - 4 then ltxt = ltxt:sub(1, curW - 7) .. "..." end
            term.write("> " .. ltxt)
        end
        
        -- Win95 Touch Button Bar (Line curH)
        term.setCursorPos(1, curH)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.clearLine()
        
        if curW < 35 then
            term.setCursorPos(2, curH)
            term.write("[I] [.] [<] [^] [v] [>] [X]")
        else
            term.setCursorPos(2, curH)
            term.write("[Inv] [Wait] [<] [^] [v] [>] [Quit]")
        end
    end

    local function handleHudClick(mx, curW)
        if curW < 35 then
            if mx >= 2 and mx <= 4 then return "inv" end
            if mx >= 6 and mx <= 8 then return "wait" end
            if mx >= 10 and mx <= 12 then return "left" end
            if mx >= 14 and mx <= 16 then return "up" end
            if mx >= 18 and mx <= 20 then return "down" end
            if mx >= 22 and mx <= 24 then return "right" end
            if mx >= 26 and mx <= 28 then return "quit" end
        else
            if mx >= 2 and mx <= 6 then return "inv" end
            if mx >= 8 and mx <= 13 then return "wait" end
            if mx >= 15 and mx <= 17 then return "left" end
            if mx >= 19 and mx <= 21 then return "up" end
            if mx >= 23 and mx <= 25 then return "down" end
            if mx >= 27 and mx <= 29 then return "right" end
            if mx >= 31 and mx <= 36 then return "quit" end
        end
        return nil
    end

    local function showInventory()
        local curW, curH = getSafeSize()
        term.setBackgroundColor(colors.lightGray)
        term.clear()
        
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.clearLine()
        term.write(" [X] Hero Equipment & Inventory")
        
        local items = {
            { slot = "Weapon", item = player.equipment.weapon },
            { slot = "Armor",  item = player.equipment.armor },
            { slot = "Trinket",item = player.equipment.trinket },
        }
        
        local startY = 3
        for i, entry in ipairs(items) do
            term.setCursorPos(4, startY + (i - 1) * 3)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(entry.slot .. ": ")
            
            term.setCursorPos(4, startY + (i - 1) * 3 + 1)
            if entry.item then
                term.setTextColor(entry.item.rarity or colors.blue)
                local desc = entry.item.name
                if entry.item.dmg then desc = desc .. " (+" .. entry.item.dmg .. " DMG)"
                elseif entry.item.defense then desc = desc .. " (+" .. entry.item.defense .. " DEF)"
                elseif entry.item.luck then desc = desc .. " (+" .. entry.item.luck .. " LUCK)"
                elseif entry.item.vision then desc = desc .. " (+" .. entry.item.vision .. " VISION)" end
                term.write("[ " .. desc .. " ]")
            else
                term.setTextColor(colors.gray)
                term.write("[ (Empty Slot) ]")
            end
        end
        
        local btnText = "[ Close Inventory ]"
        local btnX = math.floor((curW - #btnText)/2)
        local btnY = curH - 2
        term.setCursorPos(btnX, btnY)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(btnText)
        
        playSnd("playClick")
        
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.enter or p1 == keys.space or p1 == keys.q or p1 == keys.tab or p1 == keys.i or p1 == keys.esc then
                    playSnd("playClick")
                    break
                end
            elseif event == "mouse_click" then
                playSnd("playClick")
                break
            end
        end
    end

    local function movePlayer(dx, dy)
        if dx ~= 0 or dy ~= 0 then
            local nx, ny = player.x + dx, player.y + dy
            if nx < 1 or nx > MAP_W or ny < 1 or ny > MAP_H then return end
            
            if map[ny][nx] == TILE_WALL then
                addLog("Ouch! You bumped into a wall.", colors.orange)
                playSnd("playError")
                return
            end

            for i = #entities, 1, -1 do
                local ent = entities[i]
                if ent.x == nx and ent.y == ny then
                    if ent.type == "gold" then
                        if math.random(1, 10) > 8 then
                            local slots = {"weapon", "armor", "trinket"}
                            local slot = slots[math.random(1, #slots)]
                            local pool = itemPool[slot]
                            local item = pool[math.random(1, #pool)]
                            
                            addLog("Found " .. item.name .. "!", item.rarity or colors.yellow)
                            player.equipment[slot] = item
                            playSnd("playSuccess")
                        else
                            local amt = math.random(10, 50) + (persist.upgrades.luck * 2)
                            player.gold = player.gold + amt
                            addLog("Found " .. amt .. " gold!", colors.yellow)
                            playSnd("playCoin")
                        end
                        table.remove(entities, i)
                    elseif ent.type == "enemy" then
                        local bonusDmg = (player.equipment.weapon and player.equipment.weapon.dmg or 0)
                        local damage = player.dmg + (class == "Brawler" and 1 or 0) + bonusDmg
                        local bonusLuck = (player.equipment.trinket and player.equipment.trinket.luck or 0)
                        if math.random(1, 100) <= (5 + persist.upgrades.luck + bonusLuck) then
                            damage = damage * 2
                            addLog("CRITICAL HIT!", colors.orange)
                        end
                        ent.hp = ent.hp - damage
                        addLog("You hit enemy for " .. damage .. "!", colors.red)
                        playSnd("playGameBeep", "hit")
                        
                        if ent.hp <= 0 then
                            addLog("Enemy defeated!", colors.lime)
                            playSnd("playNote", "harp", 1.2, 16)
                            local xpGain = 20 + (class == "Nerd" and 10 or 0)
                            player.xp = player.xp + xpGain
                            table.remove(entities, i)
                        else
                            local bonusDef = (player.equipment.armor and player.equipment.armor.defense or 0)
                            local edmg = math.max(1, 2 + math.floor(dungeonLevel/3) - bonusDef)
                            
                            if class == "Rogue" and math.random(1, 10) <= 3 then
                                addLog("You dodged the attack!", colors.cyan)
                                playSnd("playNote", "flute", 1.0, 18)
                            else
                                player.hp = player.hp - edmg
                                addLog("Enemy hits for " .. edmg .. "!", colors.magenta)
                                playSnd("playError")
                            end
                        end
                        return
                    elseif ent.type == "stairs" then
                        dungeonLevel = dungeonLevel + 1
                        addLog("Descended to level " .. dungeonLevel .. "!", colors.yellow)
                        playSnd("playNote", "chime", 1.2, 12)
                        playSnd("playNote", "chime", 1.2, 16)
                        generateMap()
                        return
                    end
                end
            end

            player.x, player.y = nx, ny
            playSnd("playClick")
        else
            addLog("You catch your breath.", colors.yellow)
            playSnd("playClick")
        end

        if isMultiplayer then
            socket:send({
                type="sync", 
                x=player.x, 
                y=player.y, 
                hp=player.hp, 
                gold=player.gold, 
                xp=player.xp,
                lvl=dungeonLevel
            })
        end
        
        if isMultiplayer and otherPlayer.active and otherPlayer.hp <= 0 then
            local dist = math.sqrt((player.x - otherPlayer.x)^2 + (player.y - otherPlayer.y)^2)
            if dist <= 1.5 then
                if player.gold >= 100 then
                    player.gold = player.gold - 100
                    otherPlayer.hp = 5
                    addLog("You revived your partner! (-100g)", colors.lime)
                    playSnd("playSuccess")
                    socket:send({type="revive", hp=5})
                else
                    addLog("Not enough gold to revive partner (100g)", colors.orange)
                end
            end
        end
        
        for _, ent in ipairs(entities) do
            if ent.type == "enemy" then
                local dist = math.sqrt((player.x - ent.x)^2 + (player.y - ent.y)^2)
                local moveProb = 0.5
                
                if math.random() <= moveProb then
                    local edx, edy = 0, 0
                    if dist < 6 then
                        if ent.hp <= 1 then
                            edx = (player.x > ent.x) and -1 or (player.x < ent.x and 1 or 0)
                            edy = (player.y > ent.y) and -1 or (player.y < ent.y and 1 or 0)
                        else
                            edx = (player.x > ent.x) and 1 or (player.x < ent.x and -1 or 0)
                            edy = (player.y > ent.y) and 1 or (player.y < ent.y and -1 or 0)
                        end
                    else
                        local r = math.random(1, 4)
                        if r == 1 then edx = 1 elseif r == 2 then edx = -1 elseif r == 3 then edy = 1 elseif r == 4 then edy = -1 end
                    end
                    
                    local tx, ty = ent.x + edx, ent.y + edy
                    if tx >= 1 and tx <= MAP_W and ty >= 1 and ty <= MAP_H and map[ty][tx] == TILE_FLOOR then
                        local occ = false
                        for _, other in ipairs(entities) do
                            if other ~= ent and other.x == tx and other.y == ty then occ = true; break end
                        end
                        if tx == player.x and ty == player.y then occ = true end
                        
                        if not occ then
                            ent.x, ent.y = tx, ty
                        end
                    end
                end
            end
        end
    end

    local function drawMenu(selectedOpt)
        local curW, curH = getSafeSize()
        term.setBackgroundColor(colors.lightGray); term.clear()
        
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.clearLine()
        term.write(" [X] Drunken Dungeons v" .. gameVersion)
        
        local startY = 3
        if curW > 45 and curH >= 18 then
            local titleLines = {
                "  ____   _____  _    _  _   _  _  __ ______  _   _ ",
                " |  _ \\ |  __ \\| |  | || \\ | || |/ /|  ____|| \\ | |",
                " | | | || |__) | |  | ||  \\| || ' / | |__   |  \\| |",
                " | | | ||  _  /| |  | || . ` ||  <  |  __|  | . ` |",
                " | |_| || | \\ \\| |__| || |\\  || . \\ | |____ | |\\  |",
                " |____/ |_|  \\_\\\\____/ |_| \\_||_|\\_\\|______||_| \\_|",
                "         D  U  N  G  E  O  N  S  (v" .. gameVersion .. ")"
            }
            for i, line in ipairs(titleLines) do
                local color = (i < 7) and "9" or "3"
                term.setCursorPos(math.floor(curW/2 - #line/2), i + 1)
                term.blit(line, string.rep(color, #line), string.rep("8", #line))
            end
            startY = 10
        else
            term.setCursorPos(math.floor(curW/2 - 8), 3)
            term.setTextColor(colors.blue)
            term.write("DRUNKEN DUNGEONS")
            startY = 5
        end

        term.setCursorPos(math.floor(curW/2 - 13), startY)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.yellow)
        term.write(string.format(" [ Gold: $%04d ] [ Class: %-7s ] ", persist.gold, class or "Brawler"))

        local opts = {
            "Enter Dungeon",
            "Upgrade Hero",
            "Join Party (Co-op)",
            "Exit Game"
        }
        
        for i, opt in ipairs(opts) do
            local oy = startY + 1 + i
            local btnText = " [ " .. i .. ": " .. opt .. " ] "
            term.setCursorPos(math.floor(curW/2 - #btnText/2), oy)
            if i == selectedOpt then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.yellow)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            term.write(btnText)
        end
    end

    local function upgradeShop()
        while true do
            local curW, curH = getSafeSize()
            term.setBackgroundColor(colors.lightGray)
            term.clear()
            
            term.setCursorPos(1, 1)
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            term.clearLine()
            term.write(" [X] Blacksmith - Hero Upgrades")
            
            term.setCursorPos(3, 3)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.yellow)
            term.write(string.format(" Available Gold: $%04d ", persist.gold))
            
            local upgrades = {
                { id = 1, name = "Vitality (+2 HP)",     lvl = persist.upgrades.hp,   cost = 100, field = "hp" },
                { id = 2, name = "Sharpness (+1 DMG)",   lvl = persist.upgrades.dmg,  cost = 250, field = "dmg" },
                { id = 3, name = "Luck (+Crit/Loot)",    lvl = persist.upgrades.luck, cost = 150, field = "luck" },
            }
            
            local cardY = 5
            for i, u in ipairs(upgrades) do
                local cy = cardY + (i - 1) * 3
                term.setCursorPos(3, cy)
                term.setBackgroundColor(colors.lightGray)
                term.setTextColor(colors.black)
                term.write(string.format("[%d] %s (Lv.%d)", u.id, u.name, u.lvl))
                
                term.setCursorPos(3, cy + 1)
                local canAfford = persist.gold >= u.cost
                if canAfford then
                    term.setBackgroundColor(colors.green)
                    term.setTextColor(colors.white)
                    term.write(string.format(" [ BUY: $%d ] ", u.cost))
                else
                    term.setBackgroundColor(colors.gray)
                    term.setTextColor(colors.lightGray)
                    term.write(string.format(" [ NEED: $%d ] ", u.cost))
                end
            end
            
            local doneBtn = "[ Done / Back ]"
            local doneX = math.floor((curW - #doneBtn) / 2)
            local doneY = curH - 2
            term.setCursorPos(doneX, doneY)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(doneBtn)
            
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.one and persist.gold >= 100 then
                    persist.gold = persist.gold - 100
                    persist.upgrades.hp = persist.upgrades.hp + 1
                    playSnd("playCoin")
                elseif p1 == keys.two and persist.gold >= 250 then
                    persist.gold = persist.gold - 250
                    persist.upgrades.dmg = persist.upgrades.dmg + 1
                    playSnd("playCoin")
                elseif p1 == keys.three and persist.gold >= 150 then
                    persist.gold = persist.gold - 150
                    persist.upgrades.luck = persist.upgrades.luck + 1
                    playSnd("playCoin")
                elseif p1 == keys.q or p1 == keys.tab or p1 == keys.esc or p1 == keys.enter or p1 == keys.space then
                    playSnd("playClick")
                    return
                else
                    playSnd("playError")
                end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= 2 and mx <= 4 then
                    playSnd("playClick")
                    return
                end
                if my == doneY and mx >= doneX and mx <= doneX + #doneBtn then
                    playSnd("playClick")
                    return
                end
                for i, u in ipairs(upgrades) do
                    local cy = cardY + (i - 1) * 3
                    if (my == cy or my == cy + 1) and mx >= 3 and mx <= 30 then
                        if persist.gold >= u.cost then
                            persist.gold = persist.gold - u.cost
                            persist.upgrades[u.field] = persist.upgrades[u.field] + 1
                            playSnd("playCoin")
                        else
                            playSnd("playError")
                        end
                        break
                    end
                end
            end
            saveGame(persist)
        end
    end

    local function selectClass()
        local curW, curH = getSafeSize()
        term.setBackgroundColor(colors.lightGray)
        term.clear()
        
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.clearLine()
        term.write(" [X] Select Hero Class")
        
        local classes = {
            { name = "Brawler", desc = "Heavy Hitter (+HP, +DMG)" },
            { name = "Rogue",   desc = "Agile Thief (Dodge, Gold)" },
            { name = "Nerd",    desc = "Tactician (Faster XP)" },
        }
        
        local startY = 4
        for i, c in ipairs(classes) do
            local cy = startY + (i - 1) * 3
            term.setCursorPos(3, cy)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.yellow)
            term.write(string.format(" [%d] %-8s ", i, c.name))
            
            term.setCursorPos(17, cy)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(c.desc)
            
            term.setCursorPos(3, cy + 1)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.gray)
            term.write("Click or press [" .. i .. "] to select")
        end
        
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.one then class = "Brawler"; playSnd("playClick"); break
                elseif p1 == keys.two then class = "Rogue"; playSnd("playClick"); break
                elseif p1 == keys.three then class = "Nerd"; playSnd("playClick"); break end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                for i, c in ipairs(classes) do
                    local cy = startY + (i - 1) * 3
                    if my >= cy and my <= cy + 1 then
                        class = c.name
                        playSnd("playClick")
                        return
                    end
                end
            end
        end
    end

    while true do
        gameOver = false
        player.hp = 10 + (persist.upgrades.hp * 2)
        player.maxHp = player.hp
        player.gold = 0
        player.xp = 0
        dungeonLevel = 1
        isMultiplayer = false
        otherPlayer.active = false
        
        local menuSelected = 1
        while true do
            drawMenu(menuSelected)
            local event, p1, p2, p3 = os.pullEvent()
            local selectedAndTriggered = false
            
            if event == "key" then
                local k = p1
                if k == keys.up then
                    menuSelected = (menuSelected == 1) and 4 or menuSelected - 1
                    playSnd("playClick")
                elseif k == keys.down then
                    menuSelected = (menuSelected == 4) and 1 or menuSelected + 1
                    playSnd("playClick")
                elseif k == keys.one then menuSelected = 1; selectedAndTriggered = true
                elseif k == keys.two then menuSelected = 2; selectedAndTriggered = true
                elseif k == keys.three then menuSelected = 3; selectedAndTriggered = true
                elseif k == keys.four then menuSelected = 4; selectedAndTriggered = true
                elseif k == keys.enter or k == keys.space then
                    selectedAndTriggered = true
                elseif k == keys.tab or k == keys.q or k == keys.esc then
                    return
                end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= 2 and mx <= 4 then
                    playSnd("playClick")
                    return
                end
                
                local curW, curH = getSafeSize()
                local startY = (curW > 45 and curH >= 18) and 10 or 5
                for i = 1, 4 do
                    local oy = startY + 1 + i
                    if my == oy then
                        menuSelected = i
                        selectedAndTriggered = true
                        playSnd("playClick")
                        break
                    end
                end
            end
            
            if selectedAndTriggered then
                playSnd("playClick")
                if menuSelected == 1 then
                    selectClass()
                    break
                elseif menuSelected == 2 then
                    upgradeShop()
                elseif menuSelected == 3 then
                    menuSelected = 3
                    local curW, curH = getSafeSize()
                    term.setBackgroundColor(colors.lightGray); term.clear()
                    term.setCursorPos(1, 1); term.setBackgroundColor(colors.blue); term.setTextColor(colors.white); term.clearLine()
                    term.write(" [X] Drunken Dungeons - Co-op Lobby")
                    
                    if not socket:checkArcade() then 
                        term.setCursorPos(3, 4); term.setTextColor(colors.red); term.setBackgroundColor(colors.lightGray)
                        term.write("Mainframe Arcade Server Offline!")
                        sleep(2)
                    else
                        local lobbyOpts = {
                            "[ 1: Host Game ]",
                            "[ 2: Join Lobby ]",
                            "[ 3: Direct Connect ]",
                            "[ Back to Menu ]"
                        }
                        for i, opt in ipairs(lobbyOpts) do
                            term.setCursorPos(math.floor((curW - #opt)/2), 3 + i * 2)
                            term.setBackgroundColor(colors.gray)
                            term.setTextColor(colors.white)
                            term.write(opt)
                        end
                        
                        local lobbyChoice = nil
                        while not lobbyChoice do
                            local ev, lp1, lp2, lp3 = os.pullEvent()
                            if ev == "key" then
                                if lp1 == keys.one then lobbyChoice = 1
                                elseif lp1 == keys.two then lobbyChoice = 2
                                elseif lp1 == keys.three then lobbyChoice = 3
                                elseif lp1 == keys.tab or lp1 == keys.q or lp1 == keys.esc then lobbyChoice = 4 end
                            elseif ev == "mouse_click" then
                                local mx, my = lp2, lp3
                                if my == 1 and mx >= 2 and mx <= 4 then lobbyChoice = 4 end
                                for i = 1, #lobbyOpts do
                                    if my == 3 + i * 2 then lobbyChoice = i; break end
                                end
                            end
                        end
                        
                        if lobbyChoice == 1 then
                            term.setCursorPos(3, 12); term.setTextColor(colors.black); term.setBackgroundColor(colors.lightGray)
                            term.write("Hosting... Waiting for Partner (Q to cancel)...")
                            if socket:hostGame(username) then
                                local success = false
                                parallel.waitForAny(
                                    function()
                                        while true do
                                            local msg = socket:waitForJoin(0.2, {seed = sharedSeed})
                                            if msg then
                                                isMultiplayer = true
                                                addLog("Partner Joined!", colors.lime)
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
                                if success then
                                    selectClass()
                                    break
                                end
                            else
                                term.setCursorPos(3, 13); term.setTextColor(colors.red); term.write("Failed to host game.")
                                sleep(1.5)
                            end
                        elseif lobbyChoice == 2 then
                            term.setCursorPos(3, 12); term.setTextColor(colors.black); term.setBackgroundColor(colors.lightGray)
                            term.write("Searching for lobbies...")
                            local lobbies = socket:findLobbies()
                            if lobbies and #lobbies > 0 then
                                local target = lobbies[1]
                                term.setCursorPos(3, 13); term.write("Connecting to " .. target.user .. "...")
                                local msg, err = socket:connect(target.id, {user=username})
                                if msg then
                                    isMultiplayer = true
                                    sharedSeed = msg.seed
                                    addLog("Joined " .. target.user, colors.lime)
                                    selectClass()
                                    break
                                else
                                    term.setCursorPos(3, 14); term.setTextColor(colors.red); term.write("Connection Failed: " .. (err or "Timeout"))
                                    sleep(1.5)
                                end
                            else
                                term.setCursorPos(3, 13); term.setTextColor(colors.red); term.write("No open lobbies found.")
                                sleep(1.5)
                            end
                        elseif lobbyChoice == 3 then
                            term.setCursorPos(3, 12); term.setTextColor(colors.black); term.setBackgroundColor(colors.lightGray)
                            term.write("Enter Host ID: ")
                            local directTarget = tonumber(read())
                            if directTarget then
                                local msg, err = socket:connect(directTarget, {user=username})
                                if msg then
                                    isMultiplayer = true
                                    sharedSeed = msg.seed
                                    addLog("Connected to Host!", colors.lime)
                                    selectClass()
                                    break
                                else
                                    term.setCursorPos(3, 14); term.setTextColor(colors.red); term.write("Connection Failed: " .. (err or "Timeout"))
                                    sleep(1.5)
                                end
                            end
                        end
                    end
                elseif menuSelected == 4 then
                    return
                end
            end
        end

        local modem = peripheral.find("modem")
        if modem then rednet.open(peripheral.getName(modem)) end

        generateMap()

        while not gameOver do
            draw()
            local event, p1, p2, p3 = os.pullEvent()

            if event == "key" then
                if p1 == keys.w or p1 == keys.up then movePlayer(0, -1)
                elseif p1 == keys.s or p1 == keys.down then movePlayer(0, 1)
                elseif p1 == keys.a or p1 == keys.left then movePlayer(-1, 0)
                elseif p1 == keys.d or p1 == keys.right then movePlayer(1, 0)
                elseif p1 == keys.space or p1 == keys.period then movePlayer(0, 0)
                elseif p1 == keys.i then showInventory()
                elseif p1 == keys.q or p1 == keys.tab or p1 == keys.esc then gameOver = true end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                local curW, curH = getSafeSize()
                if my == 1 and mx >= 2 and mx <= 4 then
                    gameOver = true
                elseif my == curH then
                    local act = handleHudClick(mx, curW)
                    if act == "inv" then showInventory()
                    elseif act == "wait" then movePlayer(0, 0)
                    elseif act == "left" then movePlayer(-1, 0)
                    elseif act == "up" then movePlayer(0, -1)
                    elseif act == "down" then movePlayer(0, 1)
                    elseif act == "right" then movePlayer(1, 0)
                    elseif act == "quit" then gameOver = true end
                else
                    local ox = math.max(2, math.floor((curW - MAP_W)/2) + 1)
                    local oy = 3
                    if mx >= ox and mx < ox + MAP_W and my >= oy and my < oy + MAP_H then
                        local tx = mx - ox + 1
                        local ty = my - oy + 1
                        if tx == player.x and ty == player.y then
                            movePlayer(0, 0)
                        elseif math.abs(tx - player.x) <= 1 and math.abs(ty - player.y) <= 1 then
                            movePlayer(tx - player.x, ty - player.y)
                        else
                            local dx = tx - player.x
                            local dy = ty - player.y
                            if math.abs(dx) >= math.abs(dy) then
                                movePlayer(dx > 0 and 1 or -1, 0)
                            else
                                movePlayer(0, dy > 0 and 1 or -1)
                            end
                        end
                    end
                end
            elseif event == "rednet_message" and p3 == socket.protocol then
                if p2.type == "sync" then
                    otherPlayer.x, otherPlayer.y, otherPlayer.hp = p2.x, p2.y, p2.hp
                    if p2.lvl > dungeonLevel then
                        dungeonLevel = p2.lvl
                        addLog("Partner descended! Syncing level...", colors.yellow)
                        generateMap()
                    end
                    otherPlayer.active = true
                elseif p2.type == "revive" then
                    player.hp = p2.hp
                    addLog("Partner revived you!", colors.lime)
                end
            end

            if player.hp <= 0 then
                addLog("You died...", colors.red)
                gameOver = true
            end
        end

        persist.gold = persist.gold + player.gold
        saveGame(persist)

        socket:submitScore(username, player.gold + player.xp)
        playSnd("playGameBeep", "gameover")
        
        term.setBackgroundColor(colors.lightGray); term.clear()
        local curW, curH = getSafeSize()
        term.setCursorPos(1, 1); term.setBackgroundColor(colors.blue); term.setTextColor(colors.white); term.clearLine()
        term.write(" [X] Drunken Dungeons - Fallen Hero")
        
        local resLines = {
            "=== G A M E   O V E R ===",
            "",
            "Gold Found: $" .. player.gold,
            "XP Earned: " .. player.xp,
            "Final Floor: " .. dungeonLevel,
            "Total Score: " .. (player.gold + player.xp),
            "",
            "[ Return to Menu ]"
        }
        for i, line in ipairs(resLines) do
            term.setCursorPos(math.floor(curW/2 - #line/2), curH/2 - 4 + i)
            if i == 1 then
                term.setTextColor(colors.red)
                term.setBackgroundColor(colors.lightGray)
            elseif i == #resLines then
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            else
                term.setTextColor(colors.black)
                term.setBackgroundColor(colors.lightGray)
            end
            term.write(line)
        end
        
        while true do
            local ev = os.pullEvent()
            if ev == "key" or ev == "mouse_click" then
                playSnd("playClick")
                break
            end
        end
    end
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    term.setTextColor(colors.red); print("Dungeon Error: " .. err)
    pcall(os.pullEvent)
end
