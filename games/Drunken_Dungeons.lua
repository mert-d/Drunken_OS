--[[
    Drunken Dungeons (v1.0)
    by Gemini Gem & MuhendizBey

    Purpose:
    A turn-based ASCII roguelike for Drunken OS.
    Explore procedural dungeons, fight monsters, and collect gold.
]]

local gameVersion = 2.1 -- Version: 2.1
local saveFile = ".dungeon_save"

-- Color mapping for term.blit
local colorToBlit = {
    [colors.white] = "0", [colors.orange] = "1", [colors.magenta] = "2", [colors.lightBlue] = "3",
    [colors.yellow] = "4", [colors.lime] = "5", [colors.pink] = "6", [colors.gray] = "7",
    [colors.lightGray] = "8", [colors.cyan] = "9", [colors.purple] = "a", [colors.blue] = "b",
    [colors.brown] = "c", [colors.green] = "d", [colors.red] = "e", [colors.black] = "f"
}

---
-- Persists player data (gold, upgrades) to a local sidecar file.
-- @param data {table} The persistence table containing gold and upgrade levels.
local function saveGame(data)
    local f = fs.open(saveFile, "w")
    f.write(textutils.serialize(data))
    f.close()
end

---
-- Loads the player's persistent data from disk.
-- Returns default values if no save file exists.
-- @return {table} The persistence data.
local function loadGame()
    if not fs.exists(saveFile) then
        -- Default starting stats for new players
        return { gold = 0, upgrades = { hp = 0, dmg = 0, luck = 0 } }
    end
    local f = fs.open(saveFile, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data
end

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenDungeons"
    local arcadeServerId = nil
    local opponentId = nil
    local isMultiplayer = false
    local sharedSeed = os.time()

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local w, h = getSafeSize()
    local MAP_W = math.min(w - 6, 40)
    local MAP_H = math.min(h - 9, 15)

    -- Theme & Colors
    local hasColor = term.isColor and term.isColor()
    local function safeColor(c, f) return (hasColor and colors[c]) and colors[c] or f end

    local theme = {
        bg = colors.black,
        wall = safeColor("gray", colors.white),
        floor = safeColor("lightGray", colors.gray),
        player = safeColor("yellow", colors.white),
        enemy = safeColor("red", colors.white),
        gold = safeColor("gold", colors.white),
        text = colors.white,
        border = colors.cyan,
    }

    -- Game Constants
    local TILE_WALL = "#"
    local TILE_FLOOR = "."
    local TILE_PLAYER = "@"
    local TILE_ENEMY = "E"
    local TILE_GOLD = "$"
    local TILE_STAIRS = ">"

    -- Load Persistent Data
    local persist = loadGame()

    -- Game State
    local player = { 
        x = 2, y = 2, hp = 10, maxHp = 10, gold = 0, level = 1, xp = 0, dmg = 1,
        equipment = { weapon = nil, armor = nil, trinket = nil }
    }
    local map = {}
    local visibility = {} -- 0: hidden, 1: explored, 2: visible
    local entities = {}
    local dungeonLevel = 1
    local gameOver = false
    local logs = {{ text = "Welcome to Drunken Dungeons!", color = colors.yellow }}
    local class = "Brawler"
    local otherPlayer = { x = 0, y = 0, hp = 10, active = false }

    -- Item Templates
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

---
-- Procedural Level Generation using a Drunkard's Walk algorithm.
-- Generates floor tiles from a central point and populates the level
-- with gold and enemies based on the current shared seed.
local function generateMap()
    math.randomseed(sharedSeed + dungeonLevel)
    -- Initialize the map with solid walls
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

    -- Starting position for the 'drunkard'
    local cx, cy = math.random(5, MAP_W-5), math.random(5, MAP_H-5)
    player.x, player.y = cx, cy

    -- Carve out tiles in random directions
    for i = 1, 300 do
        map[cy][cx] = TILE_FLOOR
        local dir = math.random(1, 4)
        if dir == 1 and cx > 2 then cx = cx - 1
        elseif dir == 2 and cx < MAP_W - 1 then cx = cx + 1
        elseif dir == 3 and cy > 2 then cy = cy - 1
        elseif dir == 4 and cy < MAP_H - 1 then cy = cy + 1 end
    end
    
    -- Populate the level with interactable entities
    entities = {}
    local count = 0
    local target = 5 + (dungeonLevel * 2)
    while count < target do
        local sx, sy = math.random(2, MAP_W-1), math.random(2, MAP_H-1)
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

    -- Spawn Stairs (always at least one)
    local sx, sy = math.random(2, MAP_W-1), math.random(2, MAP_H-1)
    while map[sy][sx] ~= TILE_FLOOR or (sx == player.x and sy == player.y) do
        sx, sy = math.random(2, MAP_W-1), math.random(2, MAP_H-1)
    end
    table.insert(entities, {x = sx, y = sy, type = "stairs", hp = 0})
end

---
-- Updates the visibility map based on player position.
-- Implements a simple Raycast or Radius-based vision.
local function updateVisibility()
    -- Set all currently visible to explored
    for y = 1, MAP_H do
        for x = 1, MAP_W do
            if visibility[y][x] == 2 then visibility[y][x] = 1 end
        end
    end

    local radius = 5
    for dy = -radius, radius do
        for dx = -radius, radius do
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist <= radius then
                local vx, vy = player.x + dx, player.y + dy
                if vx >= 1 and vx <= MAP_W and vy >= 1 and vy <= MAP_H then
                    -- Simple Line of Sight check
                    local blocked = false
                    local steps = math.max(math.abs(dx), math.abs(dy))
                    for i = 1, steps - 1 do
                        local tx = math.floor(player.x + (dx * i / steps) + 0.5)
                        local ty = math.floor(player.y + (dy * i / steps) + 0.5)
                        if map[ty][tx] == TILE_WALL then
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
        local w, h = getSafeSize()
        updateVisibility()
        
        -- Draw Border & Header/Footer
        term.setBackgroundColor(theme.bg); term.clear()
        term.setBackgroundColor(theme.border)
        term.setCursorPos(1, 1); term.write(string.rep(" ", w))
        term.setCursorPos(1, h); term.write(string.rep(" ", w))
        term.setCursorPos(1, 1); term.setTextColor(colors.white)
        local titleText = " DRUNKEN DUNGEONS Lv" .. dungeonLevel .. " "
        term.setCursorPos(math.floor((w - #titleText)/2), 1); term.write(titleText)
        
        for i = 2, h - 1 do
            term.setCursorPos(1, i); term.write(" ")
            term.setCursorPos(w, i); term.write(" ")
        end

        local ox, oy = math.floor((w - MAP_W)/2), 3
        
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
                    -- Hidden
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
                                if v == 2 then -- Only see entities in direct vision
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
                        -- Explored but not visible (Dimmed)
                        fg = colors.gray
                        if char == TILE_ENEMY or char == TILE_GOLD then char = TILE_FLOOR end -- Hide dynamic entities in FOW
                    end
                end
                
                table.insert(row_chars, char)
                table.insert(row_fg, colorToBlit[fg] or "0")
                table.insert(row_bg, colorToBlit[bg] or "f")
            end
            
            term.setCursorPos(ox, oy + y - 1)
            term.blit(table.concat(row_chars), table.concat(row_fg), table.concat(row_bg))
        end

        -- Draw HUD (Status Bars)
        term.setBackgroundColor(theme.bg)
        
        -- HP Bar
        local barLen = 15
        local hpFill = math.floor((player.hp / player.maxHp) * barLen)
        term.setCursorPos(2, h-4)
        term.setTextColor(colors.white); term.write("HP: ")
        term.blit(string.rep("|", hpFill) .. string.rep(".", barLen - hpFill), 
                  string.rep("e", hpFill) .. string.rep("7", barLen - hpFill),
                  string.rep("f", barLen))
        
        -- Gold & XP
        term.setCursorPos(20, h-4)
        term.setTextColor(theme.gold); term.write(" Gold: " .. player.gold)
        term.setTextColor(colors.lime); term.write(" XP: " .. player.xp)
        
        -- Logs
        for i, log in ipairs(logs) do
            term.setCursorPos(2, h - 3 + i)
            if type(log) == "table" then
                term.setTextColor(log.color or colors.lightGray)
                term.write("> " .. (log.text or "???"))
            else
                term.setTextColor(colors.lightGray)
                term.write("> " .. tostring(log))
            end
        end
        
        term.setCursorPos(math.floor(w/2 - 10), h)
        term.setBackgroundColor(theme.border); term.setTextColor(colors.white); term.write(" WASD to Move | TAB: Back ")
    end

    local function showInventory()
        local w, h = getSafeSize()
        term.setBackgroundColor(colors.black); term.clear()
        term.setTextColor(colors.cyan)
        term.setCursorPos(math.floor(w/2 - 5), 2); term.write(" INVENTORY ")
        
        local items = {
            { slot = "Weapon", item = player.equipment.weapon },
            { slot = "Armor", item = player.equipment.armor },
            { slot = "Trinket", item = player.equipment.trinket },
        }
        
        for i, entry in ipairs(items) do
            term.setCursorPos(4, 5 + (i * 2))
            term.setTextColor(colors.white); term.write(entry.slot .. ": ")
            if entry.item then
                term.setTextColor(entry.item.rarity or colors.white)
                term.write(entry.item.name)
                term.setTextColor(colors.gray)
                if entry.item.dmg then term.write(" (+" .. entry.item.dmg .. " DMG)")
                elseif entry.item.defense then term.write(" (+" .. entry.item.defense .. " DEF)")
                elseif entry.item.luck then term.write(" (+" .. entry.item.luck .. " LUCK)")
                elseif entry.item.vision then term.write(" (+" .. entry.item.vision .. " VISION)") end
            else
                term.setTextColor(colors.gray); term.write("Empty")
            end
        end
        
        term.setCursorPos(math.floor(w/2 - 10), h-2)
        term.setTextColor(colors.yellow); term.write(" Press any key to return ")
        os.pullEvent("key")
    end

---
-- Handles player movement and collision with walls/entities.
-- Triggers combat, item pickup, and multiplayer sync.
-- @param dx {number} Change in X direction.
-- @param dy {number} Change in Y direction.
local function movePlayer(dx, dy)
    local nx, ny = player.x + dx, player.y + dy
    if nx < 1 or nx > MAP_W or ny < 1 or ny > MAP_H then return end
    
    if map[ny][nx] == TILE_WALL then
        addLog("Ouch! You bumped into a wall.")
        return
    end

    -- Dynamic Entity Interaction (Gold, Items, Enemies, etc.)
    for i = #entities, 1, -1 do
        local ent = entities[i]
        if ent.x == nx and ent.y == ny then
                if ent.type == "gold" then
                    -- Random loot drop: Gold or Item
                    if math.random(1, 10) > 8 then
                        -- Drop Item
                        local slots = {"weapon", "armor", "trinket"}
                        local slot = slots[math.random(1, #slots)]
                        local pool = itemPool[slot]
                        local item = pool[math.random(1, #pool)]
                        
                        addLog("Found " .. item.name .. "!", item.rarity or colors.yellow)
                        player.equipment[slot] = item
                    else
                        -- Drop Gold
                        local amt = math.random(10, 50) + (persist.upgrades.luck * 2)
                        player.gold = player.gold + amt
                        addLog("Found " .. amt .. " gold!", colors.gold)
                    end
                table.remove(entities, i)
            elseif ent.type == "enemy" then
                -- Combat Calculation
                local bonusDmg = (player.equipment.weapon and player.equipment.weapon.dmg or 0)
                local damage = player.dmg + (class == "Brawler" and 1 or 0) + bonusDmg
                -- Critical hit check based on Luck upgrade + Trinket
                local bonusLuck = (player.equipment.trinket and player.equipment.trinket.luck or 0)
                if math.random(1, 100) <= (5 + persist.upgrades.luck + bonusLuck) then
                    damage = damage * 2
                    addLog("CRITICAL HIT!", colors.orange)
                end
                ent.hp = ent.hp - damage
                addLog("You hit the enemy for " .. damage .. "!", colors.red)
                
                if ent.hp <= 0 then
                    addLog("Enemy defeated!", colors.lime)
                    -- Class-specific bonuses
                    local xpGain = 20 + (class == "Nerd" and 10 or 0)
                    player.xp = player.xp + xpGain
                    table.remove(entities, i)
                else
                    -- Counter-attack logic
                    local bonusDef = (player.equipment.armor and player.equipment.armor.defense or 0)
                    local edmg = math.max(1, 2 + math.floor(dungeonLevel/3) - bonusDef)
                    
                    if class == "Rogue" and math.random(1, 10) <= 3 then
                        addLog("You dodged the attack!", colors.cyan)
                    else
                        player.hp = player.hp - edmg
                        addLog("Enemy hits for " .. edmg .. "!", colors.magenta)
                    end
                end
                return -- Attack ends the movement sequence for this turn
            elseif ent.type == "stairs" then
                dungeonLevel = dungeonLevel + 1
                addLog("You descend to level " .. dungeonLevel .. "!", colors.yellow)
                generateMap()
                return
            end
        end
    end

    -- Update position and sync in multiplayer sessions
    player.x, player.y = nx, ny
    if isMultiplayer then
        rednet.send(opponentId, {
            type="sync", 
            x=player.x, 
            y=player.y, 
            hp=player.hp, 
            gold=player.gold, 
            xp=player.xp,
            lvl=dungeonLevel
        }, "Dungeon_Coop_v2")
    end
    
    -- Partner Revival Mechanic
    if isMultiplayer and otherPlayer.active and otherPlayer.hp <= 0 then
        local dist = math.sqrt((player.x - otherPlayer.x)^2 + (player.y - otherPlayer.y)^2)
        if dist <= 1.5 then
            if player.gold >= 100 then
                player.gold = player.gold - 100
                otherPlayer.hp = 5
                addLog("You revived your partner! (-100g)", colors.lime)
                rednet.send(opponentId, {type="revive", hp=5}, "Dungeon_Coop_v2")
            else
                addLog("Not enough gold to revive partner (100g)", colors.orange)
            end
        end
    end
    
    -- Advanced AI: Smarter movement
    for _, ent in ipairs(entities) do
        if ent.type == "enemy" then
            local dist = math.sqrt((player.x - ent.x)^2 + (player.y - ent.y)^2)
            local moveProb = 0.5 -- 50% chance to act
            
            if math.random() <= moveProb then
                local edx, edy = 0, 0
                if dist < 6 then
                    -- Aggressive/Survival Behavior
                    if ent.hp <= 1 then
                        -- Flee if low HP
                        edx = (player.x > ent.x) and -1 or (player.x < ent.x and 1 or 0)
                        edy = (player.y > ent.y) and -1 or (player.y < ent.y and 1 or 0)
                    else
                        -- Approach
                        edx = (player.x > ent.x) and 1 or (player.x < ent.x and -1 or 0)
                        edy = (player.y > ent.y) and 1 or (player.y < ent.y and -1 or 0)
                    end
                else
                    -- Wander
                    local r = math.random(1, 4)
                    if r == 1 then edx = 1 elseif r == 2 then edx = -1 elseif r == 3 then edy = 1 elseif r == 4 then edy = -1 end
                end
                
                local tx, ty = ent.x + edx, ent.y + edy
                if tx >= 1 and tx <= MAP_W and ty >= 1 and ty <= MAP_H and map[ty][tx] == TILE_FLOOR then
                    -- Check if position is occupied by another entity
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

    -- Menu Logic
    local function drawMenu(selectedOpt)
        local w, h = getSafeSize()
        term.setBackgroundColor(colors.black); term.clear()
        
        -- Responsive Header
        local statsBoxY = 10
        if w > 45 then
             local titleLines = {
                "  ____   _____  _    _  _   _  _  __ ______  _   _ ",
                " |  _ \\ |  __ \\| |  | || \\ | || |/ /|  ____|| \\ | |",
                " | | | || |__) | |  | ||  \\| || ' / | |__   |  \\| |",
                " | | | ||  _  /| |  | || . ` ||  <  |  __|  | . ` |",
                " | |_| || | \\ \\| |__| || |\\  || . \\ | |____ | |\\  |",
                " |____/ |_|  \\_\\\\____/ |_| \\_||_|\\_\\|______||_| \\_|",
                "         D  U  N  G  E  O  N  S  (v2.1)"
            }
            for i, line in ipairs(titleLines) do
                local color = (i < 7) and "9" or "3"
                term.setCursorPos(math.floor(w/2 - #line/2), i + 1)
                term.blit(line, string.rep(color, #line), string.rep("f", #line))
            end
            statsBoxY = 10
        else
            -- Mobile/Compact Header
            term.setCursorPos(math.floor(w/2 - 8), 2)
            term.setTextColor(colors.cyan)
            term.write("DRUNKEN DUNGEONS")
            term.setCursorPos(math.floor(w/2 - 2), 3)
            term.setTextColor(colors.gray)
            term.write("v2.1")
            statsBoxY = 5
        end

        -- Stats Box
        term.setCursorPos(math.floor(w/2 - 10), statsBoxY)
        term.setTextColor(colors.gray); term.write("╔═══════════════════╗")
        term.setCursorPos(math.floor(w/2 - 10), statsBoxY + 1)
        term.write("║ "); term.setTextColor(theme.gold); term.write("Gold: " .. persist.gold); term.setCursorPos(math.floor(w/2 + 9), statsBoxY + 1); term.setTextColor(colors.gray); term.write("║")
        term.setCursorPos(math.floor(w/2 - 10), statsBoxY + 2)
        term.write("║ "); term.setTextColor(colors.cyan); term.write("Class: " .. (class or "None")); term.setCursorPos(math.floor(w/2 + 9), statsBoxY + 2); term.setTextColor(colors.gray); term.write("║")
        term.setCursorPos(math.floor(w/2 - 10), statsBoxY + 3)
        term.write("╚═══════════════════╝")

        -- Options
        local opts = {
            "Enter Dungeon",
            "Upgrade Hero",
            "Join Party (Co-op)",
            "Exit Game"
        }
        
        for i, opt in ipairs(opts) do
            term.setCursorPos(math.floor(w/2 - #opt/2) - 2, statsBoxY + 4 + i)
            if i == selectedOpt then
                 term.setTextColor(colors.yellow)
                 term.write("> " .. opt .. " <")
            else
                 term.setTextColor(colors.white)
                 term.write("  " .. opt .. "  ")
            end
        end
    end
    


    local function upgradeShop()
        while true do
            local w, h = getSafeSize()
            term.setBackgroundColor(colors.black); term.clear()
            print("=== UPGRADES SHOP ===")
            print("Gold: " .. persist.gold)
            print("\n[1] Vitality (HP) - Lvl " .. persist.upgrades.hp .. " ($100)")
            print("[2] Sharpness (DMG) - Lvl " .. persist.upgrades.dmg .. " ($250)")
            print("[3] Luck (Crit/Loot) - Lvl " .. persist.upgrades.luck .. " ($150)")
            print("[TAB] Back")
            
            local _, k = os.pullEvent("key")
            if k == keys.one and persist.gold >= 100 then
                persist.gold = persist.gold - 100
                persist.upgrades.hp = persist.upgrades.hp + 1
            elseif k == keys.two and persist.gold >= 250 then
                persist.gold = persist.gold - 250
                persist.upgrades.dmg = persist.upgrades.dmg + 1
            elseif k == keys.three and persist.gold >= 150 then
                persist.gold = persist.gold - 150
                persist.upgrades.luck = persist.upgrades.luck + 1
            elseif k == keys.q or k == keys.tab then return end
            saveGame(persist)
        end
    end

    local function selectClass()
        term.clear(); term.setCursorPos(1,1)
        print("Select Class:")
        print("[1] Brawler (+HP, +DMG)")
        print("[2] Rogue (High Dodge, More Gold)")
        print("[3] Nerd (Faster XP)")
        while true do
            local _, k = os.pullEvent("key")
            if k == keys.one then class = "Brawler"; break
            elseif k == keys.two then class = "Rogue"; break
            elseif k == keys.three then class = "Nerd"; break end
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
            local _, k = os.pullEvent("key")
            
            -- Selection Logic
            if k == keys.up then
                menuSelected = (menuSelected == 1) and 4 or menuSelected - 1
            elseif k == keys.down then
                menuSelected = (menuSelected == 4) and 1 or menuSelected + 1
            
            -- Activation Logic
            elseif k == keys.enter or k == keys.space or k == keys.one or (k == keys.two and menuSelected==2) or (k == keys.three and menuSelected==3) then
                if k == keys.one then menuSelected = 1 end
                if k == keys.two then menuSelected = 2 end
                if k == keys.three then menuSelected = 3 end
                
                -- Route Selection
                if menuSelected == 1 then
                    -- Play
                    selectClass() -- Ask for class before map gen
                    -- Wait, old code called selectClass inside loop only for [1]?
                    -- Old code: [1]->selectClass->break loop->generateMap
                    break
                elseif menuSelected == 2 then
                    upgradeShop()
                elseif menuSelected == 3 then
                    -- Multiplayer Setup
                    menuSelected = 3 -- Visual stickiness
                    term.clear(); term.setCursorPos(1,1)
                    local arcadeId = rednet.lookup("ArcadeGames_Internal", "arcade.server.internal")
                    if not arcadeId then 
                        print("Mainframe Arcade Server Offline!")
                        sleep(2)
                    else
                        print("1: Host | 2: Join | 3: Direct Connect")
                        print("[TAB] Back")
                        local _, lobbyKey = os.pullEvent("key")
                        
                        if lobbyKey == keys.tab or lobbyKey == keys.q then
                             -- Back to menu
                        else
                            local directTarget = nil
                            if lobbyKey == keys.three then
                                print("Enter Host ID: ")
                                directTarget = tonumber(read())
                                if not directTarget then lobbyKey = nil end -- Cancel
                            end

                            if lobbyKey == keys.one then
                                rednet.send(arcadeId, {type="host_game", user=username, game=gameName}, "ArcadeGames")
                                print("Hosting... Waiting for Partner...")
                                while true do
                                    local id, msg = rednet.receive("Dungeon_Coop_v2", 2)
                                    if id and msg.type == "match_join" then
                                        opponentId = id
                                        isMultiplayer = true
                                        rednet.send(id, {type="match_accept", user=username, seed=sharedSeed, version=gameVersion}, "Dungeon_Coop_v2")
                                        rednet.send(arcadeId, {type="close_lobby"}, "ArcadeGames")
                                        addLog("Partner Joined!", colors.lime)
                                        selectClass()
                                        break -- Break wait loop
                                    end
                                    local e, ek = os.pullEventRaw()
                                    if e == "key" and ek == keys.q then 
                                        rednet.send(arcadeId, {type="close_lobby"}, "ArcadeGames")
                                        break -- Cancel host
                                    end
                                end
                                if isMultiplayer then break end -- Break Menu Loop
                            
                            elseif lobbyKey == keys.two or directTarget then
                                -- JOIN Logic
                                local target = nil
                                if lobbyKey == keys.two then
                                    rednet.send(arcadeId, {type="list_lobbies"}, "ArcadeGames")
                                    local _, reply = rednet.receive("ArcadeGames", 3)
                                    if reply and reply.lobbies then
                                        local options = {}
                                        for id, lob in pairs(reply.lobbies) do
                                            if lob.game == gameName then table.insert(options, {id=id, user=lob.user}) end
                                        end
                                        if #options > 0 then target = options[1]
                                        else print("No Co-op hosts online."); sleep(1) end
                                    end
                                else
                                    target = {id = directTarget, user = "ID "..directTarget}
                                end

                                if target then
                                    print("Connecting to " .. target.user .. "...")
                                    rednet.send(target.id, {type="match_join", user=username, version=gameVersion}, "Dungeon_Coop_v2")
                                    local sid, smsg = rednet.receive("Dungeon_Coop_v2", 5)
                                    if sid == target.id and smsg.type == "match_accept" then
                                        if smsg.version ~= gameVersion then
                                            print("Ver: " .. (smsg.version or "?") .. " != Local: " .. gameVersion)
                                            sleep(2)
                                        else
                                            opponentId = target.id
                                            isMultiplayer = true
                                            sharedSeed = smsg.seed
                                            addLog("Joined " .. target.user, colors.lime)
                                            selectClass()
                                            break -- Break Menu Loop
                                        end
                                    end
                                end
                            end
                        end
                    end
                elseif menuSelected == 4 then
                    return -- Exit
                end
            elseif k == keys.tab or k == keys.q then
                return -- Exit
            end
        end

        -- Initialize Network (Existing)
        local modem = peripheral.find("modem")
        if modem then rednet.open(peripheral.getName(modem)) end
        arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

        generateMap()

        while not gameOver do
            draw()
            local event, p1, p2, p3 = os.pullEvent()

            if event == "key" then
                if p1 == keys.w or p1 == keys.up then movePlayer(0, -1)
                elseif p1 == keys.s or p1 == keys.down then movePlayer(0, 1)
                elseif p1 == keys.a or p1 == keys.left then movePlayer(-1, 0)
                elseif p1 == keys.d or p1 == keys.right then movePlayer(1, 0)
                elseif p1 == keys.i then showInventory()
                elseif p1 == keys.q or p1 == keys.tab then gameOver = true end
            elseif event == "rednet_message" and p3 == "Dungeon_Coop_v2" then
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
                addLog("You died...")
                gameOver = true
            end
        end

        -- Update persistent gold
        persist.gold = persist.gold + player.gold
        saveGame(persist)

        -- High Score Submit
        if arcadeServerId then rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = player.gold + player.xp}, "ArcadeGames") end
        
        term.setBackgroundColor(colors.black); term.clear()
        local w, h = getSafeSize()
        local resLines = {
            "G A M E   O V E R",
            "-----------------",
            "Gold Found: " .. player.gold,
            "XP Earned: " .. player.xp,
            "Total Score: " .. (player.gold + player.xp),
            "",
            "Press any key to return to menu"
        }
        for i, line in ipairs(resLines) do
            term.setCursorPos(math.floor(w/2 - #line/2), h/2 - 4 + i)
            term.setTextColor(i == 1 and colors.red or colors.white)
            term.write(line)
        end
        os.pullEvent("key")
    end
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    term.setTextColor(colors.red); print("Dungeon Error: " .. err)
    os.pullEvent("key")
end
