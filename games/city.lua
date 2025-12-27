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
local TILES = {
    GROUND = { char=".", fg=colors.lightGray, bg=colors.black, solid=false },
    ROCK   = { char="#", fg=colors.gray, bg=colors.black, solid=true },
    ORE    = { char="%", fg=colors.yellow, bg=colors.black, solid=true, resource="ore" },
    WATER  = { char="~", fg=colors.blue, bg=colors.lightBlue, solid=true }
}

--==============================================================================
-- GAME STATE
--==============================================================================
local state = {
    map = nil,
    camera = nil,
    cursor = { x=10, y=10 },
    resources = { 
        minerals = 0, 
        alloys = 0, 
        energy = 100,
        pop = 5 
    },
    buildings = {}, -- List of {x, y, type, lastTick}
    running = true,
    mode = "view" -- view, build
}

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
    -- Init
    state.map = generateWorld()
    local w, h = term.getSize()
    state.camera = Engine.newCamera(1, 1, w, h-2) -- Reserve top/bottom lines
    
    while state.running do
        -- 1. Draw Map
        Engine.Renderer.draw(state.map, state.camera, 1, 2)
        
        -- 2. Draw Buildings (Overlay)
        -- TODO: Optimized way? For now, manual draw on screen pos
        for _, b in ipairs(state.buildings) do
             -- If b is visible... draw it.
             -- (Ideally this logic belongs in Engine, but overlay support is next)
        end
        
        -- 3. Draw Cursor
        local scrX = state.cursor.x - state.camera.x + 1
        local scrY = state.cursor.y - state.camera.y + 2
        if scrX >= 1 and scrX <= w and scrY >= 2 and scrY <= h-1 then
            term.setCursorPos(scrX, scrY)
            term.setBackgroundColor(colors.white) 
            term.setTextColor(colors.black)
            local tile = state.map:get(state.cursor.x, state.cursor.y)
            term.write(tile.char)
        end
        
        -- 4. Draw UI
        drawUI()
        
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
        end
        
        -- 6. Logic (Camera Follow)
        state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
    end
end

-- Run
term.clear()
main()
term.clear()
term.setCursorPos(1,1)
