--[[
    Drunken Doom (v2.1 PRO)
    by Antigravity & MuhendizBey
    Purpose:
    A pseudo-3D raycasting engine for Drunken OS.
    Navigate a 3D environment rendered in ASCII/Colors.
]]

-- Load shared libraries
package.path = "/?.lua;" .. package.path
local sharedTheme = require("lib.theme")

local gameVersion = 1.7
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
local keysDown = {} -- Track held keys
local rotSpeed = 3.0 -- Radians per second
local moveSpeed = 4.0 -- Units per second
local sprintMult = 2.0 -- Sprint multiplier
local showMinimap = false -- Toggle with 'M'

-- Color mapping for term.blit (use from shared theme)
local colorToBlit = sharedTheme.colorToBlit or {
    [colors.white] = "0", [colors.orange] = "1", [colors.magenta] = "2", [colors.lightBlue] = "3",
    [colors.yellow] = "4", [colors.lime] = "5", [colors.pink] = "6", [colors.gray] = "7",
    [colors.lightGray] = "8", [colors.cyan] = "9", [colors.purple] = "a", [colors.blue] = "b",
    [colors.brown] = "c", [colors.green] = "d", [colors.red] = "e", [colors.black] = "f"
}

-- Use shared theme colors
local theme = {
    bg = sharedTheme.bg,
    wall_near = sharedTheme.text,
    wall_mid = sharedTheme.game.floor,
    wall_far = sharedTheme.game.wall,
    floor = sharedTheme.game.box,
    ceiling = sharedTheme.highlightBg,
    text = sharedTheme.game.gold,
    minimap_wall = sharedTheme.text,
    minimap_player = sharedTheme.game.enemy,
}

local function getMapChar(x, y)
    x = math.floor(x)
    y = math.floor(y)
    if x < 1 or x > MAP_W or y < 1 or y > MAP_H then return "#" end
    return map[y]:sub(x, x)
end

-- Sprites
local objects = {
    {x = 4.5, y = 4.5, char = "G", color = colors.yellow, active = true, type = "gold"},
    {x = 10.5, y = 10.5, char = "E", color = colors.red, active = true, type = "enemy", hp = 100, pain = 0},
    {x = 2.5, y = 10.5, char = "G", color = colors.yellow, active = true, type = "gold"},
    {x = 14.5, y = 2.5, char = "E", color = colors.red, active = true, type = "enemy", hp = 100, pain = 0},
}

-- View Bobbing
local bobOffset = 0
local bobDir = 1

-- Visual Effects State
local isFiring = 0
local screenShake = 0
local damageFlash = 0

local function draw(score, hp, lastFrameTime)
    local screen_chars = {}
    local screen_text = {}
    local screen_bg = {}
    local depth_buffer = {}

    -- Initialize buffer with defaults
    for y = 1, DISPLAY_H do
        screen_chars[y] = {}
        screen_text[y] = {}
        screen_bg[y] = {}
        for x = 1, DISPLAY_W do
            screen_chars[y][x] = " "
            screen_text[y][x] = "f"
            screen_bg[y][x] = "f"
        end
    end

    -- Perpendicular plane for correct FOV perspective
    -- If Dir is (sin A, cos A), Plane is (cos A, -sin A)
    local dirX = math.sin(playerA)
    local dirY = math.cos(playerA)
    local planeX = math.cos(playerA) * (FOV/2)
    local planeY = -math.sin(playerA) * (FOV/2)

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
            local drawColor = wallColor
            if damageFlash > 0 and y > ceiling and y <= floor then
                drawColor = (y % 2 == 0) and colors.red or colors.brown
            end

            if y <= ceiling then
                screen_chars[y][x] = " "
                screen_text[y][x] = "f"
                screen_bg[y][x] = colorToBlit[theme.ceiling]
            elseif y > ceiling and y <= floor then
                screen_chars[y][x] = char
                screen_text[y][x] = "f"
                screen_bg[y][x] = colorToBlit[drawColor]
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
        if obj.active and obj.x and obj.y then
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
                            -- Crosshair interaction
                            if sx == math.floor(DISPLAY_W/2) and obj.type == "enemy" then
                                -- We'll set a flag to color crosshair later
                                obj.isTargeted = true
                            end

                            for ly = 0, objHeight - 1 do
                                local sy = math.floor(objCeiling + ly)
                                if sy >= 1 and sy <= DISPLAY_H then
                                    screen_chars[sy][sx] = obj.char
                                    local col = obj.color or colors.white
                                    if obj.pain and obj.pain > 0 then col = colors.white end
                                    screen_text[sy][sx] = colorToBlit[col] or "0"
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Render loop with screen shake
    local shakeX = math.random(-math.floor(screenShake), math.floor(screenShake))
    local shakeY = math.random(-math.floor(screenShake), math.floor(screenShake))
    
    for y = 1, DISPLAY_H do
        local drawY = y + shakeY
        if drawY >= 1 and drawY <= DISPLAY_H then
            term.setCursorPos(1 + shakeX, drawY)
            term.blit(table.concat(screen_chars[y]), table.concat(screen_text[y]), table.concat(screen_bg[y]))
        end
    end

    -- Weapon Rendering (Fleshed out)
    local weaponY = DISPLAY_H - 1 + math.floor(math.abs(bobOffset) * 2) - (isFiring > 0 and 1 or 0)
    local centerX = math.floor(DISPLAY_W / 2)
    
    term.setBackgroundColor(colors.black)
    
    -- Gun Body (More detailed)
    term.setTextColor(colors.gray)
    term.setCursorPos(centerX - 3, weaponY)
    term.write("[|#####|]")
    term.setCursorPos(centerX - 2, weaponY - 1)
    term.write("/ MMM \\")
    term.setCursorPos(centerX - 1, weaponY - 2)
    term.write("|H|")
    
    -- Muzzle Flash & Effects
    if isFiring > 0 then
        term.setTextColor(colors.yellow)
        term.setCursorPos(centerX - 1, weaponY - 2)
        term.write("/#\\")
        term.setCursorPos(centerX, weaponY - 3)
        term.write("*")
        screenShake = 1
    end

    -- Draw Minimap (if enabled)
    if showMinimap then
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
    end

    -- HUD
    term.setCursorPos(1, DISPLAY_H)
    term.setBackgroundColor(colors.black)
    term.setTextColor(theme.text)
    local fps = lastFrameTime > 0 and math.floor(1 / lastFrameTime) or 0
    term.write(string.format(" HP: %d | Score: %d | FPS: %d | [M] Map | [Q] Quit", hp, score, fps))
    
    -- Crosshair
    local crosshairX, crosshairY = math.floor(DISPLAY_W / 2), math.floor(DISPLAY_H / 2)
    term.setCursorPos(crosshairX, crosshairY)
    local isEnemyTargeted = false
    for _, obj in ipairs(objects) do
        if obj.isTargeted then isEnemyTargeted = true; obj.isTargeted = nil end
    end
    term.setTextColor(isEnemyTargeted and colors.red or colors.white)
    term.write("+")
end

local function main(...)
    local args = {...}
    local username = args[1] or "Guest"
    
    local modem = peripheral.find("modem")
    if modem then rednet.open(peripheral.getName(modem)) end
    local arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")

    -- Title Screen
    term.setBackgroundColor(colors.black); term.clear()
    local titleArt = {
        " ___  __  __  __  __ ",
        "|   \\|  ||  ||  \\/  |",
        "| |  |  ||  || |\\/| |",
        "|___/ \\__/ \\__/|_|  |_|",
        "                     ",
        "  --- DRUNKEN DOOM ---"
    }
    
    local startY = math.floor((DISPLAY_H - #titleArt) / 2) - 1
    for i, line in ipairs(titleArt) do
        term.setCursorPos(math.floor((DISPLAY_W - #line) / 2) + 1, startY + i)
        term.setTextColor(i < #titleArt and colors.red or colors.orange)
        term.write(line)
    end
    
    term.setCursorPos(math.floor((DISPLAY_W - 19) / 2) + 1, startY + #titleArt + 2)
    term.setTextColor(colors.white); term.write("PRO VERSION (DDA)")
    term.setCursorPos(math.floor((DISPLAY_W - 22) / 2) + 1, startY + #titleArt + 4)
    term.setTextColor(colors.gray); term.write("PRESS ANY KEY TO START")
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
        
        -- Non-blocking event pull
        local event, p1 = os.pullEvent()
        
        if event == "key" then
            keysDown[p1] = true
            if p1 == keys.q or p1 == keys.tab then running = false end
            if p1 == keys.m then showMinimap = not showMinimap end
            if p1 == keys.space then
                isFiring = 0.15
                -- Shoot logic
                for _, obj in ipairs(objects) do
                    if obj.active and obj.type == "enemy" then
                        local vecX = obj.x - playerX
                        local vecY = obj.y - playerY
                        local objAngle = math.atan2(vecX, vecY) - playerA
                        if objAngle < -math.pi then objAngle = objAngle + 2*math.pi end
                        if objAngle > math.pi then objAngle = objAngle - 2*math.pi end
                        
                        -- Tightened hitboxes for the gun
                        if math.abs(objAngle) < 0.15 then
                            local dist = math.sqrt(vecX*vecX + vecY*vecY)
                            if dist < 8 then
                                obj.hp = obj.hp - 35
                                obj.pain = 0.2
                                if obj.hp <= 0 then
                                    obj.active = false
                                    score = score + 500
                                end
                            end
                        end
                    end
                end
            end
        elseif event == "key_up" then
            keysDown[p1] = nil
        end

        local moved = false
        if isFiring > 0 then isFiring = isFiring - frameTime end
        if screenShake > 0 then screenShake = math.max(0, screenShake - 5 * frameTime) end
        if damageFlash > 0 then damageFlash = damageFlash - frameTime end

        -- Rotation wrapping
        if playerA > math.pi then playerA = playerA - 2*math.pi end
        if playerA < -math.pi then playerA = playerA + 2*math.pi end

        -- Rotation
        if keysDown[keys.a] then playerA = playerA - rotSpeed * frameTime end
        if keysDown[keys.d] then playerA = playerA + rotSpeed * frameTime end

        -- Movement with Collision Sliding
        local moveX, moveY = 0, 0
        local curSpeed = moveSpeed * (keysDown[keys.leftShift] and sprintMult or 1.0)
        
        if keysDown[keys.w] then
            moveX = moveX + math.sin(playerA) * curSpeed * frameTime
            moveY = moveY + math.cos(playerA) * curSpeed * frameTime
        end
        if keysDown[keys.s] then
            moveX = moveX - math.sin(playerA) * curSpeed * frameTime
            moveY = moveY - math.cos(playerA) * curSpeed * frameTime
        end

        if moveX ~= 0 or moveY ~= 0 then
            moved = true
            -- Sliding logic: Check X and Y separately
            local nextX = playerX + moveX
            if getMapChar(nextX, playerY) ~= "#" then
                playerX = nextX
            end
            local nextY = playerY + moveY
            if getMapChar(playerX, nextY) ~= "#" then
                playerY = nextY
            end
        end

        if moved then
            bobOffset = bobOffset + 5 * frameTime * bobDir
            if math.abs(bobOffset) > 0.3 then bobDir = bobDir * -1 end
        else
            bobOffset = bobOffset * 0.9
        end

        -- AI & Collision
        for _, obj in ipairs(objects) do
            if obj.active and obj.x and obj.y then
                if obj.pain and obj.pain > 0 then obj.pain = obj.pain - frameTime end
                
                local d = math.sqrt((obj.x-playerX)^2 + (obj.y-playerY)^2)
                if obj.type == "gold" and d < 0.8 then
                    obj.active = false
                    score = score + 100
                elseif obj.type == "enemy" then
                    -- Simple approach logic
                    if d < 10 and (obj.pain == nil or obj.pain <= 0) then
                        obj.x = obj.x + (playerX - obj.x) * 1.5 * frameTime
                        obj.y = obj.y + (playerY - obj.y) * 1.5 * frameTime
                    end
                    if d < 0.8 then
                        hp = hp - 15 * frameTime -- Continuous damage
                        damageFlash = 0.1 -- Keep flashing while hit
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

        -- Yield briefly to maintain responsiveness
        os.queueEvent("yield")
        os.pullEvent("yield")
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
