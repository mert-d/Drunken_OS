--[[
    Drunken Dungeons (v1.0)
    by Gemini Gem & MuhendizBey

    Purpose:
    A turn-based ASCII roguelike for Drunken OS.
    Explore procedural dungeons, fight monsters, and collect gold.
]]

local gameVersion = 1.0

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenDungeons"
    local arcadeServerId = nil

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
    local MAP_W = 40
    local MAP_H = 15
    local TILE_WALL = "#"
    local TILE_FLOOR = "."
    local TILE_PLAYER = "@"
    local TILE_ENEMY = "E"
    local TILE_GOLD = "$"

    -- Game State
    local player = { x = 2, y = 2, hp = 10, maxHp = 10, gold = 0, level = 1, xp = 0 }
    local map = {}
    local entities = {}
    local dungeonLevel = 1
    local gameOver = false
    local logs = {"Welcome to Drunken Dungeons!"}

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function addLog(msg)
        table.insert(logs, msg)
        if #logs > 3 then table.remove(logs, 1) end
    end

    -- Procedural Generation (Simple Random Walk for now)
    local function generateMap()
        map = {}
        for y = 1, MAP_H do
            map[y] = {}
            for x = 1, MAP_W do map[y][x] = TILE_WALL end
        end

        local cx, cy = math.random(5, MAP_W-5), math.random(5, MAP_H-5)
        player.x, player.y = cx, cy

        for i = 1, 300 do
            map[cy][cx] = TILE_FLOOR
            local dir = math.random(1, 4)
            if dir == 1 and cx > 2 then cx = cx - 1
            elseif dir == 2 and cx < MAP_W - 1 then cx = cx + 1
            elseif dir == 3 and cy > 2 then cy = cy - 1
            elseif dir == 4 and cy < MAP_H - 1 then cy = cy + 1 end
        end
        
        -- Spawn Gold and Enemies
        entities = {}
        for i = 1, 5 do
            local sx, sy = math.random(2, MAP_W-1), math.random(2, MAP_H-1)
            if map[sy][sx] == TILE_FLOOR then
                table.insert(entities, {x = sx, y = sy, type = math.random(1,2) == 1 and "gold" or "enemy", hp = 3})
            end
        end
    end

    local function draw()
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
        local titleText = " Drunken Dungeons Lvl: "..dungeonLevel.." "
        term.setCursorPos(math.floor((w - #titleText)/2), 1); term.write(titleText)

        -- Draw Map (Offcentered)
        local ox, oy = math.floor((w - MAP_W)/2), 3
        for y = 1, MAP_H do
            term.setCursorPos(ox, oy + y - 1)
            for x = 1, MAP_W do
                local t = map[y][x]
                if x == player.x and y == player.y then
                    term.setTextColor(theme.player); term.write(TILE_PLAYER)
                else
                    local entFound = false
                    for _, ent in ipairs(entities) do
                        if ent.x == x and ent.y == y then
                            term.setTextColor(ent.type == "gold" and theme.gold or theme.enemy)
                            term.write(ent.type == "gold" and TILE_GOLD or TILE_ENEMY)
                            entFound = true; break
                        end
                    end
                    if not entFound then
                        term.setTextColor(t == TILE_WALL and theme.wall or theme.floor)
                        term.write(t)
                    end
                end
            end
        end

        -- Draw HUD
        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.text)
        term.setCursorPos(2, h-4); term.write(string.format("HP: %d/%d | Gold: %d | XP: %d", player.hp, player.maxHp, player.gold, player.xp))
        
        -- Logs
        for i, log in ipairs(logs) do
            term.setCursorPos(2, h - 4 + i)
            term.write("> " .. log)
        end
        
        term.setCursorPos(math.floor(w/2 - 10), h)
        term.setBackgroundColor(theme.border); term.write(" WASD to Move | Q: Quit ")
    end

    local function movePlayer(dx, dy)
        local nx, ny = player.x + dx, player.y + dy
        if nx < 1 or nx > MAP_W or ny < 1 or ny > MAP_H then return end
        
        if map[ny][nx] == TILE_WALL then
            addLog("Ouch! You bumped into a wall.")
            return
        end

        -- Check Entities
        for i = #entities, 1, -1 do
            local ent = entities[i]
            if ent.x == nx and ent.y == ny then
                if ent.type == "gold" then
                    local amt = math.random(10, 50)
                    player.gold = player.gold + amt
                    addLog("Found " .. amt .. " gold!")
                    table.remove(entities, i)
                elseif ent.type == "enemy" then
                    ent.hp = ent.hp - 1
                    addLog("You hit the enemy!")
                    if ent.hp <= 0 then
                        addLog("Enemy defeated!")
                        player.xp = player.xp + 20
                        table.remove(entities, i)
                    else
                        player.hp = player.hp - 1
                        addLog("Enemy hits back!")
                    end
                    return -- Don't move into enemy tile
                end
            end
        end

        player.x, player.y = nx, ny
        
        -- Enemies move? (Simple)
        for _, ent in ipairs(entities) do
            if ent.type == "enemy" and math.random(1, 4) == 1 then
                local edx = (player.x > ent.x) and 1 or (player.x < ent.x and -1 or 0)
                local edy = (player.y > ent.y) and 1 or (player.y < ent.y and -1 or 0)
                if map[ent.y + edy][ent.x + edx] == TILE_FLOOR then
                    ent.x, ent.y = ent.x + edx, ent.y + edy
                end
            end
        end
    end

    -- Initialize Network
    local modem = peripheral.find("modem")
    if modem then rednet.open(peripheral.getName(modem)) end
    arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

    generateMap()

    while not gameOver do
        draw()
        local _, key = os.pullEvent("key")

        if key == keys.w or key == keys.up then movePlayer(0, -1)
        elseif key == keys.s or key == keys.down then movePlayer(0, 1)
        elseif key == keys.a or key == keys.left then movePlayer(-1, 0)
        elseif key == keys.d or key == keys.right then movePlayer(1, 0)
        elseif key == keys.q then gameOver = true end

        if player.hp <= 0 then
            addLog("You died...")
            gameOver = true
        end
    end

    -- High Score Submit
    if arcadeServerId then rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = player.gold + player.xp}, "ArcadeGames") end
    
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Game Over. Final Score: " .. (player.gold + player.xp))
    sleep(2)
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    term.setTextColor(colors.red); print("Dungeon Error: " .. err)
    os.pullEvent("key")
end
