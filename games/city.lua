--[[
    Drunken City Builder (Alpha)
    A strategy game for Drunken OS.
    
    Controls:
    - Arrow Keys: Move Cursor (Camera follows)
    - Enter: Place Building / Interact
    - Tab: Open Build Menu
    - Q: Quit
]]

local Engine = require("lib.engine")
local theme = require("lib.theme") 

--==============================================================================
-- CONSTANTS & CONFIG
--==============================================================================
local MAP_W, MAP_H = 128, 128
local MIN_W, MIN_H = 35, 15 -- Enforce Desktop Size
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
      production={}, consumption={alloys=10} } -- Consumption handled specially in logic
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
    speaker = peripheral.find("speaker") -- Find speaker on init
}

-- Sound Helper
local function playSound(name, vol, pitch)
    if state.speaker then
        -- pcall to avoid crash if speaker disconnects
        pcall(state.speaker.playSound, name, vol or 1.0, pitch or 1.0)
    end
end
 
-- Helper: Check if building can be placed
local function canPlace(bDef, x, y)
    local tile = state.map:get(x, y)
    if not tile then return false, "Out of bounds" end
    if tile.solid and bDef.name ~= "Mine" then return false, "Terrain blocked" end
    
    -- Resource cost check
    for res, amt in pairs(bDef.cost) do
        if state.resources[res] < amt then return false, "Need " .. amt .. " " .. res end
    end
    
    -- Specific Logic
    if bDef.name == "Mine" and tile.resource ~= "ore" then return false, "Must place on Ore" end
    
    -- Collision with other buildings
    for _, b in ipairs(state.buildings) do
        if b.x == x and b.y == y then return false, "Occupied" end
    end
    
    return true
end

--==============================================================================
-- TERRAIN GENERATION
--==============================================================================
local function generateWorld()
    local map = Engine.newMap(MAP_W, MAP_H, TILES.GROUND)
    
    -- 1. Scatter Rocks (Obstacles)
    for i=1, (MAP_W * MAP_H) * 0.10 do
        local x, y = math.random(1, MAP_W), math.random(1, MAP_H)
        map:set(x, y, TILES.ROCK)
    end
    
    -- 2. Scatter Ore Veins (Resources)
    for i=1, (MAP_W * MAP_H) * 0.05 do
        local cx, cy = math.random(1, MAP_W), math.random(1, MAP_H)
        -- Create a small cluster
        for ox=-1,1 do for oy=-1,1 do
            if math.random() > 0.3 then
                map:set(cx+ox, cy+oy, TILES.ORE)
            end
        end end
    end
    
    -- 3. Safety Clearing (Start Zone)
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
        
        -- Check Consumption first
        local canProduce = true
        if def.consumption then
            for res, amt in pairs(def.consumption) do
                if state.resources[res] < amt then
                    canProduce = false
                    break
                end
            end
        end
        
        -- Apply Effects
        if canProduce then
            -- Consume & Produce
            local netProd = {} -- For tracking net production/consumption per resource
            
            if b.def.name == "Export" then
                -- Special Export Logic
                if state.resources.alloys >= 10 then
                    -- Get Username
                    local username = nil
                    if fs.exists(".session") then
                        local f = fs.open(".session", "r")
                        local data = textutils.unserialize(f.readAll())
                        f.close()
                        if data then username = data.username end
                    end
                    
                    if username then
                        -- Check Bank
                        state.resources.alloys = state.resources.alloys - 10
                        netProd.alloys = (netProd.alloys or 0) - 10
                        -- Send to Bank
                        -- We use rednet globally
                        peripheral.find("modem", rednet.open)
                        local bankId = rednet.lookup("DB_Bank", "bank.server")
                        if bankId then
                            rednet.send(bankId, { type="city_export", user=username, resource="alloys", count=10 }, "DB_Bank")
                            -- Visual Feedback?
                            -- playSound("entity.arrow.hit_player", 0.5, 2.0)
                        end
                    end
                end
            else
                -- Standard Production
                if b.def.production then
                    for res, amt in pairs(b.def.production) do
                        state.resources[res] = state.resources[res] + amt
                        netProd[res] = (netProd[res] or 0) + amt
                    end
                end
                
                -- Standard Consumption
                -- (Simplified: Always consume if available - real logic needs 'active' state)
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
        mapData = {}, -- Store strictly necessary data (char, fg, bg, solid, resource)
        buildings = state.buildings,
        resources = state.resources,
        timestamp = os.epoch("utc")
    }
    
    -- Serialize Map (Simple RLE or just flat list for now)
    -- Optimized: Only save NON-GROUND tiles to save space?
    -- For Alpha: Naive full dump is safest.
    for y=1, MAP_H do
        data.mapData[y] = {}
        for x=1, MAP_W do
            local tile = state.map:get(x, y)
            -- Save key properties so we can reconstruct TILES references
            local tType = "GROUND"
            if tile == TILES.ROCK then tType = "ROCK"
            elseif tile == TILES.ORE then tType = "ORE"
            elseif tile == TILES.WATER then tType = "WATER" end
            data.mapData[y][x] = tType
        end
    end
    
    local path = SAVE_DIR .. "city_" .. slotName .. ".save"
    local f = fs.open(path, "w")
    f.write(textutils.serialize(data))
    f.close()
    
    -- UI Feedback
    local w, h = term.getSize()
    term.setCursorPos(1, h-1)
    term.setTextColor(colors.lime)
    term.write("Saved to " .. slotName .. "!")
    os.sleep(0.5) -- Brief pause
end

local function loadGame(slotName)
    local path = SAVE_DIR .. "city_" .. slotName .. ".save"
    if not fs.exists(path) then return false end
    
    local f = fs.open(path, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    
    if not data then return false end
    
    -- Restore State
    state.resources = data.resources
    state.buildings = data.buildings -- Note: 'def' reference might be broken if not handled!
    
    -- Fix Building Def References (they were serialized as tables, need to link back to STRUCTURES)
    -- Actually, serialization saves a COPY of the table. We need to reunite them with logic objects?
    -- For this simple engine, the 'def' table just holds data. But if we add logic later...
    -- Re-link 'def' based on name just to be safe/clean.
    for _, b in ipairs(state.buildings) do
        for _, s in ipairs(STRUCTURES) do
            if s.name == b.def.name then
                b.def = s -- Pointer restoration
                break
            end
        end
    end
    
    -- Rebuild Map
    state.map = Engine.newMap(data.w, data.h, TILES.GROUND)
    for y=1, data.h do
        for x=1, data.w do
            local tType = data.mapData[y][x]
            if TILES[tType] then
                state.map:set(x, y, TILES[tType])
            end
        end
    end
    
    return true
end

--==============================================================================
-- UI & RENDER
--==============================================================================
local function drawUI()
    local w, h = term.getSize()
    -- Top Bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    
    local txt = string.format(" Min: %d | Alloy: %d | Pop: %d | Energy: %d", 
        state.resources.minerals, state.resources.alloys, state.resources.pop, state.resources.energy)
    term.write(txt)
    
    -- Cursor Info
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    local tile = state.map:get(state.cursor.x, state.cursor.y)
    local tName = "Ground"
    if tile == TILES.ROCK then tName = "Rock"
    elseif tile == TILES.ORE then tName = "Ore Deposit" 
    elseif tile == TILES.WATER then tName = "Water" end
    
    term.write(string.format(" Pos: %d,%d [%s] ", state.cursor.x, state.cursor.y, tName))
end

--==============================================================================
-- MAIN LOOP
--==============================================================================
local function main()
    -- Resolution Check
    local w, h = term.getSize()
    if w < MIN_W or h < MIN_H then
        print("Error: Screen too small.")
        print("This game requires a Desktop computer.")
        print("Min: " .. MIN_W .. "x" .. MIN_H)
        return
    end

    -- Init
    state.map = generateWorld()
    local w, h = term.getSize()
    state.camera = Engine.newCamera(1, 1, w, h-2) -- Reserve top/bottom lines
    
    -- Start Timer
    local timerId = os.startTimer(1)
    
    while state.running do
        -- 1. Draw Map
        Engine.Renderer.draw(state.map, state.camera, 1, 2)
        
        -- 2. Draw Buildings (Overlay)
        local OFF_X, OFF_Y = 1, 2
        for _, b in ipairs(state.buildings) do
             local scrX = b.x - state.camera.x + OFF_X
             local scrY = b.y - state.camera.y + OFF_Y
             
             if scrX >= 1 and scrX <= w and scrY >= 2 and scrY <= h-1 then
                 term.setCursorPos(scrX, scrY)
                 term.setTextColor(b.def.fg)
                 term.setBackgroundColor(b.def.bg)
                 term.write(b.def.char)
             end
        end
        
        -- 3. Draw Cursor
        local scrX = state.cursor.x - state.camera.x + OFF_X
        local scrY = state.cursor.y - state.camera.y + OFF_Y
        if scrX >= 1 and scrX <= w and scrY >= 2 and scrY <= h-1 then
            term.setCursorPos(scrX, scrY)
            if state.mode == "view" then
                term.setBackgroundColor(colors.white) 
                term.setTextColor(colors.black)
                local tile = state.map:get(state.cursor.x, state.cursor.y)
                term.write(tile.char)
            elseif state.mode == "build" then
                local bDef = STRUCTURES[state.selectedBuildIdx]
                -- Blink or show Ghost
                local valid, _ = canPlace(bDef, state.cursor.x, state.cursor.y)
                term.setBackgroundColor(valid and colors.lime or colors.red)
                term.setTextColor(bDef.fg)
                term.write(bDef.char)
            end
        end
        
        -- 4. Draw UI
        drawUI()
        
        -- 4b. Draw Build Menu
        if state.mode == "build" then
            -- ... (Existing Build Menu Code) ...
            local bw, bh = 30, #STRUCTURES + 4
            local bx, by = w - bw - 1, 3
            -- Frame
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.black)
            for i=0, bh do
                term.setCursorPos(bx, by+i)
                term.write(string.rep(" ", bw))
            end
            term.setCursorPos(bx+1, by+1); term.write("-- Build Menu (TAB) --")
            for i, struc in ipairs(STRUCTURES) do
                term.setCursorPos(bx+1, by+1+i)
                if i == state.selectedBuildIdx then
                    term.setTextColor(colors.yellow); term.write("> ")
                else
                    term.setTextColor(colors.gray); term.write("  ")
                end
                term.write(struc.name)
            end
            local sel = STRUCTURES[state.selectedBuildIdx]
            term.setCursorPos(bx+1, by+bh-1)
            term.setTextColor(colors.lightGray)
            term.write(sel.desc:sub(1, bw-2))
            
        elseif state.mode == "system" then
            -- System Menu Overlay
            local mw, mh = 26, 10
            local mx, my = math.floor((w-mw)/2), math.floor((h-mh)/2)
            
            -- Draw Box
            paintutils.drawFilledBox(mx, my, mx+mw, my+mh, colors.blue)
            paintutils.drawBox(mx, my, mx+mw, my+mh, colors.white)
            
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.blue)
            term.setCursorPos(mx+2, my+1); term.write("== SYSTEM MENU ==")
            
            term.setCursorPos(mx+2, my+3); term.write("[R] Resume")
            term.setCursorPos(mx+2, my+4); term.write("-- SAVE (1-3) --")
            term.setCursorPos(mx+2, my+5); term.write("[1] Auto  [2] Slot2  [3] Slot3")
            term.setCursorPos(mx+2, my+6); term.write("-- LOAD (F1-F3) --")
            term.setCursorPos(mx+2, my+7); term.write("[F1] Auto [F2] Slot2 [F3] Slot3")
            
            term.setCursorPos(mx+2, my+9); term.write("[Q] Quit Game")
        end
        
        -- 5. Input
        local event, p1 = os.pullEvent()
        
        if event == "timer" and p1 == timerId then
            simulationTick()
            timerId = os.startTimer(1)
            
            -- Auto Save Logic (Every 60s)
            local now = os.epoch("utc")
            if (now - (state.lastAutoSave or 0)) > 60000 then
                 saveGame("auto")
                 state.lastAutoSave = now
            end
            
        elseif event == "key" then
            local key = p1
            
            if state.mode == "system" then
                -- SYSTEM MENU CONTROLS
                if key == keys.r or key == keys.esc then
                    state.mode = "view"
                elseif key == keys.q then
                    saveGame("auto") -- Save on quit
                    state.running = false
                elseif key == keys.one then
                    saveGame("auto")
                elseif key == keys.two then
                    saveGame("slot2")
                elseif key == keys.three then
                    saveGame("slot3")
                
                -- Shift+Number to LOAD? Or separate menu? 
                -- Let's keep it simple: Number = Save, Shift+Number = Load? 
                -- Wait, keyboard helper needed. For this Alpha, let's just do:
                -- S + 1/2/3 = Save, L + 1/2/3 = Load
                elseif key == keys.l then
                     -- Ideally show "Press 1-3 to Load..."
                     -- Stub for logic: Load Slot 2 immediately for test?
                     -- Let's stick to user request: "3 save slots".
                     -- Simple Keybinding for now:
                     -- F1: Load Auto, F2: Load Slot 2, F3: Load Slot 3
                end
                
                -- HOTFIX Input for Alpha
                if key == keys.f1 then loadGame("auto"); state.mode="view" end
                if key == keys.f2 then loadGame("slot2"); state.mode="view" end
                if key == keys.f3 then loadGame("slot3"); state.mode="view" end
                
            else
                -- GAMEPLAY CONTROLS
                if key == keys.esc then
                    state.mode = "system"
                elseif key == keys.q then -- Legacy Quit
                    state.mode = "system"
                    
                elseif key == keys.up and state.cursor.y > 1 then
                    state.cursor.y = state.cursor.y - 1
                elseif key == keys.down and state.cursor.y < MAP_H then
                    state.cursor.y = state.cursor.y + 1
                elseif key == keys.left and state.cursor.x > 1 then
                    state.cursor.x = state.cursor.x - 1
                elseif key == keys.right and state.cursor.x < MAP_W then
                    state.cursor.x = state.cursor.x + 1
                elseif key == keys.tab then
                    state.mode = (state.mode == "view") and "build" or "view"
                elseif state.mode == "build" then
                     -- ... (Build controls existing) ... 
                     if key == keys.w then 
                         state.selectedBuildIdx = state.selectedBuildIdx - 1
                         if state.selectedBuildIdx < 1 then state.selectedBuildIdx = #STRUCTURES end
                    elseif key == keys.s then 
                         state.selectedBuildIdx = state.selectedBuildIdx + 1
                         if state.selectedBuildIdx > #STRUCTURES then state.selectedBuildIdx = 1 end
                    elseif key == keys.enter then
                     -- Place
                     local bDef = STRUCTURES[state.selectedBuildIdx]
                     local valid, reason = canPlace(bDef, state.cursor.x, state.cursor.y)
                     if valid then
                         -- Deduct Cost
                         for res, amt in pairs(bDef.cost) do state.resources[res] = state.resources[res] - amt end
                         -- Add Building
                         table.insert(state.buildings, { 
                            x=state.cursor.x, 
                            y=state.cursor.y, 
                            def=bDef, 
                            lastTick=os.epoch("utc") 
                         })
                         playSound("entity.experience_orb.pickup", 1, 1.2) -- Pling!
                     else
                         -- Show Error (Flash UI? or just sound)
                         playSound("block.note_block.bass", 1, 0.5) -- Buzz!
                     end
                end
            end
            
            -- Camera Follow
            state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
        end
    end
end

-- Run
term.clear()
main()
term.clear()
term.setCursorPos(1,1)
