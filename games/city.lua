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
    { name="Mine",    char="M", fg=colors.black, bg=colors.yellow, cost={minerals=10}, desc="Produces Minerals on [Ore]." },
    { name="Factory", char="F", fg=colors.orange, bg=colors.gray, cost={minerals=50, energy=10}, desc="Refines Minerals -> Alloys." },
    { name="House",   char="H", fg=colors.white, bg=colors.brown, cost={alloys=10, energy=5}, desc="Housing for workers." },
    { name="Solar",   char="S", fg=colors.cyan, bg=colors.gray, cost={alloys=20}, desc="Generates Energy." }
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
    mode = "view", -- view, build
    selectedBuildIdx = 1
}

-- Helper: Check if building can be placed
-- Returns: boolean, reason_string
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
                -- Cost display?
            end
            
            -- Desc
            local sel = STRUCTURES[state.selectedBuildIdx]
            term.setCursorPos(bx+1, by+bh-1)
            term.setTextColor(colors.lightGray)
            term.write(sel.desc:sub(1, bw-2))
        end
        
        -- 5. Input
        local event, key = os.pullEvent("key")
        if key == keys.q then
            state.running = false
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
            -- Build Controls
            if key == keys.w then -- Cycle up
                 state.selectedBuildIdx = state.selectedBuildIdx - 1
                 if state.selectedBuildIdx < 1 then state.selectedBuildIdx = #STRUCTURES end
            elseif key == keys.s then -- Cycle down
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
                     -- Reset ground if needed (e.g. Road overrides Rock... wait, checks prevent that)
                 else
                     -- Show Error (Flash UI?)
                 end
            end
        end
    end
end

-- Run
term.clear()
main()
term.clear()
term.setCursorPos(1,1)
