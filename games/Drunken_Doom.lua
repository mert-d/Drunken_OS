--[[
    Drunken Doom (v1.0)
    by Antigravity & MuhendizBey

    Purpose:
    A pseudo-3D raycasting engine for Drunken OS.
    Navigate a 3D environment rendered in ASCII/Colors.
]]

local gameVersion = 1.0
local saveFile = ".doom_save"

-- Load arguments (username)
local args = {...}
local username = args[1] or "Guest"
local gameName = "DrunkenDoom"

-- Rendering Constants
local DISPLAY_W, DISPLAY_H = term.getSize()
local FOV = math.pi / 3
local DEPTH = 16

-- Map
local map = {
    "################",
    "#..............#",
    "#..............#",
    "#...########...#",
    "#...#......#...#",
    "#...#......#...#",
    "#...#......#...#",
    "#...#..##..#...#",
    "#...####.###...#",
    "#..............#",
    "#..............#",
    "################",
}
local MAP_H = #map
local MAP_W = #map[1]

-- Player State
local playerX, playerY = 2, 2
local playerA = 0

-- Theme & Colors
local hasColor = term.isColor and term.isColor()
local function safeColor(c, f) return (hasColor and colors[c]) and colors[c] or f end

-- Color mapping for term.blit
local colorToBlit = {
    [colors.white] = "0", [colors.orange] = "1", [colors.magenta] = "2", [colors.lightBlue] = "3",
    [colors.yellow] = "4", [colors.lime] = "5", [colors.pink] = "6", [colors.gray] = "7",
    [colors.lightGray] = "8", [colors.cyan] = "9", [colors.purple] = "a", [colors.blue] = "b",
    [colors.brown] = "c", [colors.green] = "d", [colors.red] = "e", [colors.black] = "f"
}

local theme = {
    bg = colors.black,
    wall_near = colors.white,
    wall_mid = colors.lightGray,
    wall_far = colors.gray,
    floor = colors.brown,
    ceiling = colors.blue,
    text = colors.yellow,
    minimap_wall = colors.white,
    minimap_player = colors.red,
}

local function getMapChar(x, y)
    x = math.floor(x)
    y = math.floor(y)
    if x < 1 or x > MAP_W or y < 1 or y > MAP_H then return "#" end
    return map[y]:sub(x, x)
end

-- Sprites
local objects = {
    {x = 4.5, y = 4.5, char = "G", color = colors.gold, active = true},
    {x = 10.5, y = 10.5, char = "E", color = colors.red, active = true},
    {x = 2.5, y = 10.5, char = "G", color = colors.gold, active = true},
}

-- View Bobbing
local bobOffset = 0
local bobDir = 1

-- Shooting State
local isFiring = 0

local function draw(score, hp, lastFrameTime)
    local screen_chars = {}
    local screen_text = {}
    local screen_bg = {}
    local depth_buffer = {}

    -- Initialize buffer
    for y = 1, DISPLAY_H do
        screen_chars[y] = {}
        screen_text[y] = {}
        screen_bg[y] = {}
    end

    -- Constants for DDA
    local planeX = math.cos(playerA + math.pi/2) * (FOV/2)
    local planeY = math.sin(playerA + math.pi/2) * (FOV/2)
    local dirX = math.sin(playerA)
    local dirY = math.cos(playerA)

    for x = 1, DISPLAY_W do
        local cameraX = 2 * x / DISPLAY_W - 1
        local rayDirX = dirX + planeX * cameraX
        local rayDirY = dirY + planeY * cameraX

        local mapX = math.floor(playerX)
        local mapY = math.floor(playerY)

        local deltaDistX = math.abs(1 / rayDirX)
        local deltaDistY = math.abs(1 / rayDirY)

        local stepX, stepY
        local sideDistX, sideDistY

        if rayDirX < 0 then
            stepX = -1
            sideDistX = (playerX - mapX) * deltaDistX
        else
            stepX = 1
            sideDistX = (mapX + 1.0 - playerX) * deltaDistX
        end

        if rayDirY < 0 then
            stepY = -1
            sideDistY = (playerY - mapY) * deltaDistY
        else
            stepY = 1
            sideDistY = (mapY + 1.0 - playerY) * deltaDistY
        end

        local hit = 0
        local side = 0
        local distanceToWall = 0

        while hit == 0 do
            if sideDistX < sideDistY then
                sideDistX = sideDistX + deltaDistX
                mapX = mapX + stepX
                side = 0
            else
                sideDistY = sideDistY + deltaDistY
                mapY = mapY + stepY
                side = 1
            end
            if getMapChar(mapX, mapY) == "#" then hit = 1 end
        end

        if side == 0 then distanceToWall = (sideDistX - deltaDistX)
        else distanceToWall = (sideDistY - deltaDistY) end

        depth_buffer[x] = distanceToWall
        local ceiling = (DISPLAY_H / 2) - (DISPLAY_H / distanceToWall)
        local floor = DISPLAY_H - ceiling
        
        local char = " "
        local wallColor = theme.wall_far
        if distanceToWall <= DEPTH / 4 then wallColor = theme.wall_near
        elseif distanceToWall < DEPTH / 2 then wallColor = theme.wall_mid
        end
        
        -- Side shading (gives depth)
        if side == 1 then
            if wallColor == theme.wall_near then wallColor = theme.wall_mid
            elseif wallColor == theme.wall_mid then wallColor = theme.wall_far
            end
        end

        for y = 1, DISPLAY_H do
            if y <= ceiling then
                screen_chars[y][x] = " "
                screen_text[y][x] = "f"
                screen_bg[y][x] = colorToBlit[theme.ceiling]
            elseif y > ceiling and y <= floor then
                screen_chars[y][x] = char
                screen_text[y][x] = "f"
                screen_bg[y][x] = colorToBlit[wallColor]
            else
                local b = 1 - (y - DISPLAY_H/2) / (DISPLAY_H/2)
                local fCol = theme.floor
                if b < 0.25 then fCol = colors.green
                elseif b < 0.5 then fCol = theme.floor
                elseif b < 0.75 then fCol = colors.gray
                else fCol = colors.black end
                
                screen_chars[y][x] = " "
                screen_text[y][x] = "f"
                screen_bg[y][x] = colorToBlit[fCol]
            end
        end
    end

    -- Sprite Rendering
    for _, obj in ipairs(objects) do
        if obj.active then
            local vecX = obj.x - playerX
            local vecY = obj.y - playerY
            local distance = math.sqrt(vecX*vecX + vecY*vecY)

            local objAngle = math.atan2(vecX, vecY) - playerA
            if objAngle < -math.pi then objAngle = objAngle + 2*math.pi end
            if objAngle > math.pi then objAngle = objAngle - 2*math.pi end

            local inView = math.abs(objAngle) < FOV / 2

            if inView and distance > 0.5 and distance < DEPTH then
                local objCeiling = (DISPLAY_H / 2) - (DISPLAY_H / distance)
                local objFloor = DISPLAY_H - objCeiling
                local objHeight = objFloor - objCeiling
                local objAspectRatio = 1.0
                local objWidth = objHeight / objAspectRatio

                local middleX = (0.5 * (objAngle / (FOV / 2)) + 0.5) * DISPLAY_W

                for lx = 0, objWidth - 1 do
                    local sx = math.floor(middleX + lx - (objWidth / 2))
                    if sx >= 1 and sx <= DISPLAY_W then
                        if depth_buffer[sx] > distance then
                            for ly = 0, objHeight - 1 do
                                local sy = math.floor(objCeiling + ly)
                                if sy >= 1 and sy <= DISPLAY_H then
                                    screen_chars[sy][sx] = obj.char
                                    screen_text[sy][sx] = colorToBlit[obj.color]
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Render loop
    for y = 1, DISPLAY_H do
        term.setCursorPos(1, y)
        term.blit(table.concat(screen_chars[y]), table.concat(screen_text[y]), table.concat(screen_bg[y]))
    end

    -- Bobbing Weapon Plot (Fake)
    local weaponY = DISPLAY_H - 1 + math.floor(math.abs(bobOffset) * 2) - (isFiring > 0 and 2 or 0)
    term.setCursorPos(math.floor(DISPLAY_W / 2) - 1, weaponY)
    term.setTextColor(isFiring > 0 and colors.yellow or colors.gray)
    term.setBackgroundColor(colors.black)
    term.write(isFiring > 0 and "\\XX/" or "/MM\\")
    if isFiring > 0 then
        term.setCursorPos(math.floor(DISPLAY_W / 2), weaponY - 1)
        term.write("*")
    end

    -- Draw Minimap
    local mmX, mmY = 2, 2
    for y = 1, MAP_H do
        for x = 1, MAP_W do
            term.setCursorPos(mmX + x - 1, mmY + y - 1)
            local char = getMapChar(x, y)
            if math.floor(playerX) == x and math.floor(playerY) == y then
                term.setBackgroundColor(theme.minimap_player); term.write("P")
            elseif char == "#" then
                term.setBackgroundColor(theme.minimap_wall); term.write(" ")
            else
                term.setBackgroundColor(colors.black); term.write(".")
            end
        end
    end

    -- HUD
    term.setCursorPos(1, DISPLAY_H)
    term.setBackgroundColor(colors.black)
    term.setTextColor(theme.text)
    local fps = lastFrameTime > 0 and math.floor(1 / lastFrameTime) or 0
    term.write(string.format(" HP: %d | Score: %d | FPS: %d | [Q] Quit", hp, score, fps))
end

local function main(...)
    local args = {...}
    local username = args[1] or "Guest"
    
    local modem = peripheral.find("modem")
    if modem then rednet.open(peripheral.getName(modem)) end
    local arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

    -- Title Screen
    term.setBackgroundColor(colors.black); term.clear()
    term.setCursorPos(math.floor((DISPLAY_W - 12)/2), math.floor(DISPLAY_H/2) - 1)
    term.setTextColor(colors.red); print("DRUNKEN DOOM")
    term.setCursorPos(math.floor((DISPLAY_W - 19)/2), math.floor(DISPLAY_H/2) + 1)
    term.setTextColor(colors.white); print("PRO VERSION (DDA)")
    term.setCursorPos(math.floor((DISPLAY_W - 18)/2), math.floor(DISPLAY_H/2) + 2)
    print("Press ANY KEY to START")
    os.pullEvent("key")

    local score = 0
    local hp = 100
    local running = true
    local lastFrame = os.epoch("utc") / 1000
    local frameTime = 0.05

    while running do
        local now = os.epoch("utc") / 1000
        frameTime = now - lastFrame
        lastFrame = now

        draw(score, hp, frameTime)
        
        local timer = os.startTimer(0.01) -- High frequency
        local event, p1, p2, p3 = os.pullEvent()
        
        local moved = false
        if isFiring > 0 then isFiring = isFiring - 1 end

        if event == "key" then
            if p1 == keys.w then
                local nextX = playerX + math.sin(playerA) * 0.4
                local nextY = playerY + math.cos(playerA) * 0.4
                if getMapChar(nextX, nextY) ~= "#" then playerX, playerY = nextX, nextY; moved = true end
            elseif p1 == keys.s then
                local nextX = playerX - math.sin(playerA) * 0.4
                local nextY = playerY - math.cos(playerA) * 0.4
                if getMapChar(nextX, nextY) ~= "#" then playerX, playerY = nextX, nextY; moved = true end
            elseif p1 == keys.a then
                playerA = playerA - 0.2
            elseif p1 == keys.d then
                playerA = playerA + 0.2
            elseif p1 == keys.space then
                isFiring = 3
                -- Shoot logic
                for _, obj in ipairs(objects) do
                    if obj.active and obj.char == "E" then
                        local vecX = obj.x - playerX
                        local vecY = obj.y - playerY
                        local objAngle = math.atan2(vecX, vecY) - playerA
                        if objAngle < -math.pi then objAngle = objAngle + 2*math.pi end
                        if objAngle > math.pi then objAngle = objAngle - 2*math.pi end
                        if math.abs(objAngle) < 0.1 then
                            obj.active = false
                            score = score + 500
                        end
                    end
                end
            elseif p1 == keys.q or p1 == keys.tab then
                running = false
            end
        end

        if moved then
            bobOffset = bobOffset + 0.15 * bobDir
            if math.abs(bobOffset) > 0.5 then bobDir = bobDir * -1 end
        else
            bobOffset = bobOffset * 0.8
        end

        -- AI & Collision
        for _, obj in ipairs(objects) do
            if obj.active then
                local d = math.sqrt((obj.x-playerX)^2 + (obj.y-playerY)^2)
                if obj.char == "G" and d < 0.8 then
                    obj.active = false
                    score = score + 100
                elseif obj.char == "E" then
                    if d < 8 then
                        obj.x = obj.x + (playerX - obj.x) * 0.03
                        obj.y = obj.y + (playerY - obj.y) * 0.03
                    end
                    if d < 0.8 then
                        hp = hp - 1
                        if hp <= 0 then running = false end
                    end
                end
            end
        end

        -- Win check
        local anyGold = false
        for _, obj in ipairs(objects) do if obj.active and obj.char == "G" then anyGold = true; break end end
        if not anyGold then
            term.setBackgroundColor(colors.black); term.clear()
            term.setCursorPos(math.floor((DISPLAY_W - 10)/2), math.floor(DISPLAY_H/2))
            term.setTextColor(colors.lime); print("YOU WIN!")
            sleep(2)
            break
        end

        if event == "timer" and p1 == timer then end
    end
    
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
    if hp <= 0 then term.setTextColor(colors.red); print("MISSION FAILED...") else print("Exiting Game...") end
    print("Final Score: " .. score)
    sleep(2)
    
    if arcadeServerId then
        rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = score}, "ArcadeGames")
    end
end

local ok, err = pcall(main)
if not ok then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print("Error: " .. err)
    os.pullEvent("key")
end
