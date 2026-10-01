--[[
    Drunken City Builder (v2.0)
    A strategy and simulation game for Drunken OS.
    Windows 95 aesthetic, full mouse/touch controls, and audio effects.
    
    Controls:
    - Mouse / Touch: Tap map to target/preview, tap targeted tile to build!
    - Tap on Build Menu to select structures or Place.
    - Arrow Keys / WASD: Move Cursor
    - Enter / Space: Place Building
    - Tab: Toggle Build Menu
    - Esc / Q: System Menu
]]

if package and package.path then package.path = "/?.lua;" .. package.path end
local Engine = require("lib.engine")
local theme = require("lib.theme") 

local Sound = nil
pcall(function() Sound = require("lib.sound") end)

local function playSnd(fn, ...)
    if Sound and Sound[fn] then
        pcall(Sound[fn], ...)
    end
end

--==============================================================================
-- CONSTANTS & CONFIG
--==============================================================================
local MAP_W, MAP_H = 128, 128
local MIN_W, MIN_H = 26, 12
local TILES = {
    GROUND = { char=".", fg=colors.lightGray, bg=colors.black, solid=false },
    ROCK   = { char="#", fg=colors.gray, bg=colors.black, solid=true },
    ORE    = { char="%", fg=colors.yellow, bg=colors.black, solid=true, resource="ore" },
    WATER  = { char="~", fg=colors.blue, bg=colors.lightBlue, solid=true }
}

-- Building Definitions
local STRUCTURES = {
    { name="Road",    char="+", fg=colors.lightGray, bg=colors.gray, cost={minerals=1}, desc="Connects buildings." },
    { name="Mine",    char="M", fg=colors.black, bg=colors.yellow, cost={minerals=10}, desc="Produces +1 Mineral/s",
      production={minerals=1}, consumption={energy=1} },
      
    { name="Factory", char="F", fg=colors.orange, bg=colors.gray, cost={minerals=50, energy=10}, desc="Refines 2 Min -> 1 Alloy/s",
      production={alloys=1}, consumption={minerals=2, energy=2} },
      
    { name="House",   char="H", fg=colors.white, bg=colors.brown, cost={alloys=10}, desc="Workers. Consumes Energy.",
      production={pop=1}, consumption={energy=1} }, 
      
    { name="Solar",   char="S", fg=colors.cyan, bg=colors.gray, cost={alloys=20}, desc="Generates +5 Energy/s",
      production={energy=5}, consumption={} },
      
    { name="Export",  char="E", fg=colors.lime, bg=colors.black, cost={alloys=200}, desc="Sells 10 Alloys -> $1 Bank Credit",
      production={}, consumption={alloys=10} }
}

--==============================================================================
-- GAME STATE
--==============================================================================
local state = {
    map = nil,
    camera = nil,
    cursor = { x=10, y=10 },
    resources = { 
        minerals = 100, 
        alloys = 50, 
        energy = 100,
        pop = 5 
    },
    buildings = {}, 
    running = true,
    mode = "view", -- view, build, system
    selectedBuildIdx = 1,
    lastAutoSave = os.epoch("utc"),
    speaker = peripheral.find("speaker")
}

local function playSound(name, vol, pitch)
    if state.speaker and state.speaker.playSound then
        pcall(state.speaker.playSound, name, vol or 1.0, pitch or 1.0)
    end
end
 
local function canPlace(bDef, x, y)
    local tile = state.map:get(x, y)
    if not tile then return false, "Out of bounds" end
    if tile.solid and bDef.name ~= "Mine" then return false, "Terrain blocked" end
    
    for res, amt in pairs(bDef.cost) do
        if state.resources[res] < amt then return false, "Need " .. amt .. " " .. res end
    end
    
    if bDef.name == "Mine" and tile.resource ~= "ore" then return false, "Must place on Ore" end
    
    for _, b in ipairs(state.buildings) do
        if b.x == x and b.y == y then return false, "Occupied" end
    end
    
    return true
end

local function placeBuildingAtCursor()
    local bDef = STRUCTURES[state.selectedBuildIdx]
    local valid, reason = canPlace(bDef, state.cursor.x, state.cursor.y)
    if valid then
        for res, amt in pairs(bDef.cost) do 
            state.resources[res] = state.resources[res] - amt 
        end
        table.insert(state.buildings, { 
            x=state.cursor.x, 
            y=state.cursor.y, 
            def=bDef, 
            lastTick=os.epoch("utc") 
        })
        playSnd("playNote", "pling", 1.2, 18)
        playSound("entity.experience_orb.pickup", 1, 1.2)
        return true
    else
        playSnd("playError")
        playSound("block.note_block.bass", 1, 0.5)
        return false, reason
    end
end

--==============================================================================
-- TERRAIN GENERATION
--==============================================================================
local function generateWorld()
    local map = Engine.newMap(MAP_W, MAP_H, TILES.GROUND)
    
    for i=1, (MAP_W * MAP_H) * 0.10 do
        local x, y = math.random(1, MAP_W), math.random(1, MAP_H)
        map:set(x, y, TILES.ROCK)
    end
    
    for i=1, (MAP_W * MAP_H) * 0.05 do
        local cx, cy = math.random(1, MAP_W), math.random(1, MAP_H)
        for ox=-1,1 do for oy=-1,1 do
            if math.random() > 0.3 then
                map:set(cx+ox, cy+oy, TILES.ORE)
            end
        end end
    end
    
    for x=5,15 do for y=5,15 do
        map:set(x, y, TILES.GROUND)
    end end
    
    return map
end

--==============================================================================
-- SIMULATION (ECONOMY)
--==============================================================================
local function simulationTick()
    for _, b in ipairs(state.buildings) do
        local def = b.def
        
        local canProduce = true
        if def.consumption then
            for res, amt in pairs(def.consumption) do
                if state.resources[res] < amt then
                    canProduce = false
                    break
                end
            end
        end
        
        if canProduce then
            local netProd = {}
            
            if b.def.name == "Export" then
                if state.resources.alloys >= 10 then
                    local username, token = nil, nil
                    if fs.exists(".session") then
                        local f = fs.open(".session", "r")
                        if f then
                            local data = textutils.unserialize(f.readAll())
                            f.close()
                            if data then 
                                username = data.username 
                                token = data.session_token
                            end
                        end
                    end
                    
                    if username and token then
                        state.resources.alloys = state.resources.alloys - 10
                        netProd.alloys = (netProd.alloys or 0) - 10
                        pcall(function()
                            peripheral.find("modem", rednet.open)
                            local bankId = rednet.lookup("DB_Bank", "bank.server")
                            if bankId then
                                rednet.send(bankId, { type="city_export", user=username, session_token=token, resource="alloys", count=10 }, "DB_Bank")
                            end
                        end)
                    end
                end
            else
                if b.def.production then
                    for res, amt in pairs(b.def.production) do
                        state.resources[res] = state.resources[res] + amt
                        netProd[res] = (netProd[res] or 0) + amt
                    end
                end
                
                if b.def.consumption then
                    for res, amt in pairs(b.def.consumption) do
                        if state.resources[res] and state.resources[res] >= amt then
                            state.resources[res] = state.resources[res] - amt
                            netProd[res] = (netProd[res] or 0) - amt
                        end
                    end
                end
            end
        end
    end
end

--==============================================================================
-- PERSISTENCE
--==============================================================================
local SAVE_DIR = "games/saves/"

local function saveGame(slotName)
    if not fs.exists(SAVE_DIR) then fs.makeDir(SAVE_DIR) end
    
    local data = {
        w = MAP_W, h = MAP_H,
        mapData = {},
        buildings = state.buildings,
        resources = state.resources,
        timestamp = os.epoch("utc")
    }
    
    for y=1, MAP_H do
        data.mapData[y] = {}
        for x=1, MAP_W do
            local tile = state.map:get(x, y)
            local tType = "GROUND"
            if tile == TILES.ROCK then tType = "ROCK"
            elseif tile == TILES.ORE then tType = "ORE"
            elseif tile == TILES.WATER then tType = "WATER" end
            data.mapData[y][x] = tType
        end
    end
    
    local path = SAVE_DIR .. "city_" .. slotName .. ".save"
    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serialize(data))
        f.close()
    end
    
    playSnd("playSuccess")
    
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.lime)
    term.setTextColor(colors.black)
    term.write(" [Saved to " .. slotName .. "!] ")
    sleep(0.3)
end

local function loadGame(slotName)
    local path = SAVE_DIR .. "city_" .. slotName .. ".save"
    if not fs.exists(path) then return false end
    
    local f = fs.open(path, "r")
    if not f then return false end
    local data = textutils.unserialize(f.readAll())
    f.close()
    
    if not data then return false end
    
    state.resources = data.resources
    state.buildings = data.buildings
    
    for _, b in ipairs(state.buildings) do
        for _, s in ipairs(STRUCTURES) do
            if s.name == b.def.name then
                b.def = s
                break
            end
        end
    end
    
    state.map = Engine.newMap(data.w, data.h, TILES.GROUND)
    for y=1, data.h do
        for x=1, data.w do
            local tType = data.mapData[y][x]
            if TILES[tType] then
                state.map:set(x, y, TILES[tType])
            end
        end
    end
    
    playSnd("playToast", "default")
    return true
end

--==============================================================================
-- UI & RENDER
--==============================================================================
local function drawUI()
    local w, h = term.getSize()
    
    -- Row 1: Win95 Navy Title Bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" [X] Drunken City Builder")
    if w >= 45 then
        local rightBtns = "[Build] [Save] [Menu]"
        term.setCursorPos(w - #rightBtns, 1)
        term.write(rightBtns)
    end
    
    -- Row 2: Win95 Resource Status Bar
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.clearLine()
    local resStr = string.format(" Min:[%04d]  Alloy:[%04d]  Pop:[%03d]  Energy:[%04d]", 
        state.resources.minerals, state.resources.alloys, state.resources.pop, state.resources.energy)
    if #resStr > w then
        resStr = string.format(" M:%d A:%d P:%d E:%d", 
            state.resources.minerals, state.resources.alloys, state.resources.pop, state.resources.energy)
    end
    term.write(resStr)
    
    -- Row h: Bottom Status & Control Bar
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    local tile = state.map:get(state.cursor.x, state.cursor.y)
    local tName = "Ground"
    if tile == TILES.ROCK then tName = "Rock"
    elseif tile == TILES.ORE then tName = "Ore" 
    elseif tile == TILES.WATER then tName = "Water" end
    
    local posTxt = string.format(" Pos: %03d,%03d [%s] ", state.cursor.x, state.cursor.y, tName)
    term.write(posTxt)
    
    if w >= 48 then
        local btmBtns = "[TAB:Build] [Save] [Menu] [Quit]"
        term.setCursorPos(w - #btmBtns, h)
        term.write(btmBtns)
    elseif w >= 36 then
        local btmBtns = "[Build] [Menu] [Quit]"
        term.setCursorPos(w - #btmBtns, h)
        term.write(btmBtns)
    end
end

--==============================================================================
-- MAIN LOOP
--==============================================================================
local function main(...)
    local args = {...}
    local username = args[1] or "Guest"

    local w, h = term.getSize()
    if w < MIN_W or h < MIN_H then
        print("Error: Screen too small.")
        print("Min: " .. MIN_W .. "x" .. MIN_H)
        return
    end

    state.map = generateWorld()
    w, h = term.getSize()
    state.camera = Engine.newCamera(1, 1, w, h - 3)
    
    local timerId = os.startTimer(1)
    local OFF_X, OFF_Y = 1, 3
    
    while state.running do
        w, h = term.getSize()
        
        -- 1. Draw Map
        Engine.Renderer.draw(state.map, state.camera, OFF_X, OFF_Y)
        
        -- 2. Draw Buildings (Overlay)
        for _, b in ipairs(state.buildings) do
             local scrX = b.x - state.camera.x + OFF_X
             local scrY = b.y - state.camera.y + OFF_Y
             
             if scrX >= 1 and scrX <= w and scrY >= OFF_Y and scrY <= h - 1 then
                  term.setCursorPos(scrX, scrY)
                  term.setTextColor(b.def.fg)
                  term.setBackgroundColor(b.def.bg)
                  term.write(b.def.char)
             end
        end
        
        -- 3. Draw Cursor
        local scrX = state.cursor.x - state.camera.x + OFF_X
        local scrY = state.cursor.y - state.camera.y + OFF_Y
        if scrX >= 1 and scrX <= w and scrY >= OFF_Y and scrY <= h - 1 then
            term.setCursorPos(scrX, scrY)
            if state.mode == "view" then
                term.setBackgroundColor(colors.white) 
                term.setTextColor(colors.black)
                local tile = state.map:get(state.cursor.x, state.cursor.y)
                term.write(tile and tile.char or " ")
            elseif state.mode == "build" then
                local bDef = STRUCTURES[state.selectedBuildIdx]
                local valid, _ = canPlace(bDef, state.cursor.x, state.cursor.y)
                term.setBackgroundColor(valid and colors.lime or colors.red)
                term.setTextColor(bDef.fg)
                term.write(bDef.char)
            end
        end
        
        -- 4. Draw Header/Footer UI
        drawUI()
        
        -- 4b. Draw Build Menu
        local bw = math.min(28, math.floor(w * 0.55))
        local bh = #STRUCTURES + 4
        local bx = w - bw - 1
        local by = 3
        
        if state.mode == "build" then
            paintutils.drawFilledBox(bx, by, bx + bw, by + bh, colors.lightGray)
            paintutils.drawBox(bx, by, bx + bw, by + bh, colors.gray)
            
            term.setCursorPos(bx + 1, by)
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            local bTitle = " [X] Build Structure"
            term.write(bTitle .. string.rep(" ", math.max(0, bw - #bTitle)))
            
            for i, struc in ipairs(STRUCTURES) do
                local sy = by + 1 + i
                term.setCursorPos(bx + 1, sy)
                if i == state.selectedBuildIdx then
                    term.setBackgroundColor(colors.blue)
                    term.setTextColor(colors.yellow)
                    term.write(string.format(" > %-8s ", struc.name))
                else
                    term.setBackgroundColor(colors.lightGray)
                    term.setTextColor(colors.black)
                    term.write(string.format("   %-8s ", struc.name))
                end
                
                term.setTextColor(colors.gray)
                local cstr = ""
                for res, amt in pairs(struc.cost) do
                    cstr = cstr .. amt .. res:sub(1,1):upper() .. " "
                end
                term.write(cstr)
            end
            
            local sel = STRUCTURES[state.selectedBuildIdx]
            term.setCursorPos(bx + 1, by + bh - 1)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            local dtxt = sel.desc
            if #dtxt > bw - 2 then dtxt = dtxt:sub(1, bw - 5) .. "..." end
            term.write(dtxt)
            
            term.setCursorPos(bx + 2, by + bh)
            term.setBackgroundColor(colors.green)
            term.setTextColor(colors.white)
            term.write(" [ Place at Cursor ] ")
            
        elseif state.mode == "system" then
            local mw, mh = math.min(34, w - 2), 10
            local mx, my = math.floor((w - mw)/2), math.floor((h - mh)/2)
            
            paintutils.drawFilledBox(mx, my, mx + mw, my + mh, colors.lightGray)
            paintutils.drawBox(mx, my, mx + mw, my + mh, colors.gray)
            
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.blue)
            term.setCursorPos(mx + 1, my)
            local mTitle = " [X] System Menu"
            term.write(mTitle .. string.rep(" ", math.max(0, mw - #mTitle)))
            
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            
            term.setCursorPos(mx + 2, my + 2)
            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
            term.write(" [R: Resume] ")
            
            term.setCursorPos(mx + 2, my + 4)
            term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
            term.write("SAVE: ")
            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
            term.write("[1:Auto] [2:Slot2] [3:Slot3]")
            
            term.setCursorPos(mx + 2, my + 6)
            term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
            term.write("LOAD: ")
            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
            term.write("[F1:Auto] [F2:Slot2]")
            
            term.setCursorPos(mx + 2, my + 8)
            term.setBackgroundColor(colors.red); term.setTextColor(colors.white)
            term.write(" [Q: Quit Game] ")
        end
        
        -- 5. Unified Input Handling (Keyboard, Mouse Click, Drag, Scroll)
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == timerId then
            simulationTick()
            timerId = os.startTimer(1)
            
            local now = os.epoch("utc")
            if (now - (state.lastAutoSave or 0)) > 60000 then
                 saveGame("auto")
                 state.lastAutoSave = now
            end
            
        elseif event == "key" then
            local key = p1
            
            if state.mode == "system" then
                if key == keys.r or key == keys.esc or key == keys.space or key == keys.enter then
                    state.mode = "view"
                    playSnd("playClick")
                elseif key == keys.q then
                    saveGame("auto")
                    state.running = false
                elseif key == keys.one then
                    saveGame("auto")
                elseif key == keys.two then
                    saveGame("slot2")
                elseif key == keys.three then
                    saveGame("slot3")
                elseif key == keys.f1 then
                    loadGame("auto"); state.mode = "view"
                elseif key == keys.f2 then
                    loadGame("slot2"); state.mode = "view"
                end
                
            else
                if key == keys.esc or key == keys.q then
                    state.mode = "system"
                    playSnd("playClick")
                elseif key == keys.up or key == keys.w then
                    if state.cursor.y > 1 then state.cursor.y = state.cursor.y - 1 end
                elseif key == keys.down or key == keys.s then
                    if state.cursor.y < MAP_H then state.cursor.y = state.cursor.y + 1 end
                elseif key == keys.left or key == keys.a then
                    if state.cursor.x > 1 then state.cursor.x = state.cursor.x - 1 end
                elseif key == keys.right or key == keys.d then
                    if state.cursor.x < MAP_W then state.cursor.x = state.cursor.x + 1 end
                elseif key == keys.tab then
                    state.mode = (state.mode == "view") and "build" or "view"
                    playSnd("playClick")
                elseif state.mode == "build" then
                    if key == keys.one then state.selectedBuildIdx = 1; playSnd("playClick")
                    elseif key == keys.two then state.selectedBuildIdx = 2; playSnd("playClick")
                    elseif key == keys.three then state.selectedBuildIdx = 3; playSnd("playClick")
                    elseif key == keys.four then state.selectedBuildIdx = 4; playSnd("playClick")
                    elseif key == keys.five then state.selectedBuildIdx = 5; playSnd("playClick")
                    elseif key == keys.six then state.selectedBuildIdx = 6; playSnd("playClick")
                    elseif key == keys.enter or key == keys.space then
                        placeBuildingAtCursor()
                    end
                elseif state.mode == "view" then
                    if key == keys.enter or key == keys.space then
                        state.mode = "build"
                        playSnd("playClick")
                    end
                end
                
                state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
            end
            
        elseif event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Row 1: Title bar
            if my == 1 then
                if mx >= 2 and mx <= 4 then
                    state.mode = (state.mode == "system") and "view" or "system"
                    playSnd("playClick")
                elseif w >= 45 then
                    if mx >= w - 21 and mx <= w - 15 then
                        state.mode = (state.mode == "build") and "view" or "build"
                        playSnd("playClick")
                    elseif mx >= w - 13 and mx <= w - 8 then
                        saveGame("auto")
                    elseif mx >= w - 6 and mx <= w then
                        state.mode = (state.mode == "system") and "view" or "system"
                        playSnd("playClick")
                    end
                end
                
            -- Row h: Bottom bar
            elseif my == h then
                if mx >= w - 25 and mx <= w - 18 then
                    state.mode = (state.mode == "build") and "view" or "build"
                    playSnd("playClick")
                elseif mx >= w - 16 and mx <= w - 12 then
                    saveGame("auto")
                elseif mx >= w - 10 and mx <= w - 6 then
                    state.mode = (state.mode == "system") and "view" or "system"
                    playSnd("playClick")
                elseif mx >= w - 5 and mx <= w then
                    saveGame("auto")
                    state.running = false
                end
                
            -- System Menu Interactions
            elseif state.mode == "system" then
                local mw, mh = math.min(34, w - 2), 10
                local mx0, my0 = math.floor((w - mw)/2), math.floor((h - mh)/2)
                if my == my0 and mx >= mx0 + 1 and mx <= mx0 + 4 then
                    state.mode = "view"
                    playSnd("playClick")
                elseif my == my0 + 2 and mx >= mx0 + 2 and mx <= mx0 + 14 then
                    state.mode = "view"
                    playSnd("playClick")
                elseif my == my0 + 4 then
                    if mx >= mx0 + 8 and mx <= mx0 + 16 then saveGame("auto")
                    elseif mx >= mx0 + 17 and mx <= mx0 + 26 then saveGame("slot2")
                    elseif mx >= mx0 + 27 and mx <= mx0 + 36 then saveGame("slot3") end
                elseif my == my0 + 6 then
                    if mx >= mx0 + 8 and mx <= mx0 + 16 then loadGame("auto"); state.mode = "view"
                    elseif mx >= mx0 + 17 and mx <= mx0 + 26 then loadGame("slot2"); state.mode = "view" end
                elseif my == my0 + 8 and mx >= mx0 + 2 and mx <= mx0 + 17 then
                    saveGame("auto")
                    state.running = false
                end
                
            -- Build Menu Interactions
            elseif state.mode == "build" and mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then
                if my == by and mx >= bx + 1 and mx <= bx + 4 then
                    state.mode = "view"
                    playSnd("playClick")
                elseif my >= by + 2 and my <= by + 1 + #STRUCTURES then
                    state.selectedBuildIdx = my - (by + 1)
                    playSnd("playClick")
                elseif my == by + bh then
                    placeBuildingAtCursor()
                end
                
            -- Map Clicks (Viewport Rows OFF_Y to h - 1)
            elseif my >= OFF_Y and my <= h - 1 then
                local worldX = mx + state.camera.x - OFF_X
                local worldY = my + state.camera.y - OFF_Y
                if worldX >= 1 and worldX <= MAP_W and worldY >= 1 and worldY <= MAP_H then
                    if state.mode == "build" then
                        if state.cursor.x == worldX and state.cursor.y == worldY then
                            placeBuildingAtCursor()
                        else
                            state.cursor.x = worldX
                            state.cursor.y = worldY
                            state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
                            playSnd("playClick")
                        end
                    else
                        state.cursor.x = worldX
                        state.cursor.y = worldY
                        state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
                        playSnd("playClick")
                    end
                end
            end
            
        elseif event == "mouse_drag" then
            local btn, mx, my = p1, p2, p3
            if my >= OFF_Y and my <= h - 1 then
                if state.mode ~= "system" then
                    local worldX = mx + state.camera.x - OFF_X
                    local worldY = my + state.camera.y - OFF_Y
                    if worldX >= 1 and worldX <= MAP_W and worldY >= 1 and worldY <= MAP_H then
                        state.cursor.x = worldX
                        state.cursor.y = worldY
                        state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
                    end
                end
            end
            
        elseif event == "mouse_scroll" then
            local dir = p1
            if state.mode == "build" then
                if dir > 0 then
                    state.selectedBuildIdx = state.selectedBuildIdx + 1
                    if state.selectedBuildIdx > #STRUCTURES then state.selectedBuildIdx = 1 end
                else
                    state.selectedBuildIdx = state.selectedBuildIdx - 1
                    if state.selectedBuildIdx < 1 then state.selectedBuildIdx = #STRUCTURES end
                end
                playSnd("playClick")
            else
                local newY = state.cursor.y + dir * 2
                if newY >= 1 and newY <= MAP_H then
                    state.cursor.y = newY
                    state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
                end
            end
        end
    end
end

-- Run
term.clear()
main(...)
term.clear()
term.setCursorPos(1,1)
