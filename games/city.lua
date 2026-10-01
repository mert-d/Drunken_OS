--[[
    Drunken City Builder (v2.2 - Enterprise Edition)
    A strategy and simulation game for Drunken OS.
    Windows 95 aesthetic, full Pocket (26x20) and Desktop support,
    touchscreen/mouse building, auto-saving, and live economic simulation.
    
    Controls:
    - Tap Map: Move Cursor / Target tile
    - Tap [PLACE] or Double-tap tile: Construct selected building
    - Tap [PICK] or [BUILD]: Open structure selector
    - Arrow Keys / WASD: Move Cursor
    - Enter / Space: Construct building
    - Tab: Toggle Build Mode
    - Esc / Q / [X]: System Menu / Exit
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
local SAVE_FILE = ".city_save"

local TILES = {
    GROUND = { char=".", fg=colors.lightGray, bg=colors.black, solid=false },
    ROCK   = { char="#", fg=colors.gray, bg=colors.black, solid=true },
    ORE    = { char="%", fg=colors.yellow, bg=colors.black, solid=true, resource="ore" },
    WATER  = { char="~", fg=colors.blue, bg=colors.lightBlue, solid=true }
}

-- Building Definitions
local STRUCTURES = {
    { name="Road",    char="+", fg=colors.lightGray, bg=colors.gray, cost={minerals=1}, desc="Connects city areas." },
    { name="Mine",    char="M", fg=colors.black, bg=colors.yellow, cost={minerals=10}, desc="Produces +1 Min/s (Ore only)",
      production={minerals=1}, consumption={energy=1} },
      
    { name="Factory", char="F", fg=colors.orange, bg=colors.gray, cost={minerals=50, energy=10}, desc="Refines 2 Min -> 1 Alloy/s",
      production={alloys=1}, consumption={minerals=2, energy=2} },
      
    { name="House",   char="H", fg=colors.white, bg=colors.brown, cost={alloys=10}, desc="Workers (+1 Pop). Consumes Energy.",
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
    seed = 12345,
    cursor = { x=10, y=10 },
    resources = { 
        minerals = 100, 
        alloys = 50, 
        energy = 100,
        pop = 5 
    },
    buildings = {}, 
    running = true,
    mode = "view", -- view, build, pick, system
    selectedBuildIdx = 1,
    statusMsg = "Welcome, Mayor!",
    statusColor = colors.yellow,
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
        if (state.resources[res] or 0) < amt then 
            return false, "Need " .. amt .. " " .. res 
        end
    end
    
    if bDef.name == "Mine" and tile.resource ~= "ore" then 
        return false, "Must place on Ore (%)" 
    end
    
    for _, b in ipairs(state.buildings) do
        if b.x == x and b.y == y then return false, "Occupied" end
    end
    
    return true
end

-- Forward declaration of saveGame
local saveGame = nil

local function placeBuildingAtCursor()
    local bDef = STRUCTURES[state.selectedBuildIdx]
    local valid, reason = canPlace(bDef, state.cursor.x, state.cursor.y)
    if valid then
        for res, amt in pairs(bDef.cost) do 
            state.resources[res] = state.resources[res] - amt 
        end
        table.insert(state.buildings, { 
            x = state.cursor.x, 
            y = state.cursor.y, 
            def = bDef, 
            lastTick = os.epoch("utc") 
        })
        state.statusMsg = "[+] Built " .. bDef.name .. "!"
        state.statusColor = colors.lime
        playSnd("playNote", "pling", 1.2, 18)
        playSound("entity.experience_orb.pickup", 1, 1.2)
        if saveGame then saveGame("auto", true) end
        return true
    else
        state.statusMsg = "[X] " .. reason
        state.statusColor = colors.orange
        playSnd("playError")
        playSound("block.note_block.bass", 1, 0.5)
        return false, reason
    end
end

--==============================================================================
-- TERRAIN GENERATION
--==============================================================================
local function generateWorld(seed)
    local s = tonumber(seed) or math.random(10000, 999999)
    math.randomseed(s)
    local map = Engine.newMap(MAP_W, MAP_H, TILES.GROUND)
    
    -- 1. Scatter Rocks (Obstacles)
    for i=1, math.floor((MAP_W * MAP_H) * 0.10) do
        local x, y = math.random(1, MAP_W), math.random(1, MAP_H)
        map:set(x, y, TILES.ROCK)
    end
    
    -- 2. Scatter Ore Veins (Resources)
    for i=1, math.floor((MAP_W * MAP_H) * 0.05) do
        local cx, cy = math.random(1, MAP_W), math.random(1, MAP_H)
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
    
    return map, s
end

--==============================================================================
-- SIMULATION (ECONOMY)
--==============================================================================
local function simulationTick()
    local powerShortage = false
    
    for _, b in ipairs(state.buildings) do
        local def = b.def
        
        local canProduce = true
        if def.consumption then
            for res, amt in pairs(def.consumption) do
                if (state.resources[res] or 0) < amt then
                    canProduce = false
                    if res == "energy" then powerShortage = true end
                    break
                end
            end
        end
        
        if canProduce then
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
                        state.resources[res] = (state.resources[res] or 0) + amt
                    end
                end
                
                if b.def.consumption then
                    for res, amt in pairs(b.def.consumption) do
                        if (state.resources[res] or 0) >= amt then
                            state.resources[res] = state.resources[res] - amt
                        end
                    end
                end
            end
        end
    end
    
    if powerShortage and state.resources.energy <= 0 then
        state.statusMsg = "[!] LOW POWER: Build Solar (+5E)!"
        state.statusColor = colors.red
    end
end

--==============================================================================
-- PERSISTENCE
--==============================================================================
local function getSavePath(slotName)
    if slotName == "auto" or not slotName then
        return SAVE_FILE
    else
        return ".city_save_" .. slotName
    end
end

saveGame = function(slotName, silent)
    local data = {
        version = 2.2,
        seed = state.seed,
        buildings = {},
        resources = state.resources,
        cursor = state.cursor,
        timestamp = os.epoch("utc")
    }
    
    for _, b in ipairs(state.buildings) do
        table.insert(data.buildings, {
            x = b.x,
            y = b.y,
            name = (b.def and b.def.name) or "Road",
            lastTick = b.lastTick or os.epoch("utc")
        })
    end
    
    local path = getSavePath(slotName)
    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serialize(data))
        f.close()
    end
    
    if not silent then
        playSnd("playSuccess")
        state.statusMsg = "[Saved to " .. (slotName or "auto") .. "!]"
        state.statusColor = colors.lime
    end
    return true
end

local function loadGame(slotName)
    local path = getSavePath(slotName)
    if not fs.exists(path) then return false end
    
    local f = fs.open(path, "r")
    if not f then return false end
    local data = textutils.unserialize(f.readAll())
    f.close()
    
    if not data or type(data) ~= "table" then return false end
    
    state.resources = data.resources or state.resources
    state.seed = tonumber(data.seed) or state.seed
    state.map = generateWorld(state.seed)
    state.cursor = data.cursor or { x=10, y=10 }
    
    state.buildings = {}
    if data.buildings then
        for _, b in ipairs(data.buildings) do
            local bName = b.name or (b.def and b.def.name)
            for _, s in ipairs(STRUCTURES) do
                if s.name == bName then
                    table.insert(state.buildings, {
                        x = b.x,
                        y = b.y,
                        def = s,
                        lastTick = b.lastTick or os.epoch("utc")
                    })
                    break
                end
            end
        end
    end
    
    if state.camera then
        state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
    end
    
    playSnd("playToast", "default")
    state.statusMsg = string.format("City Loaded! (%d buildings)", #state.buildings)
    state.statusColor = colors.lime
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
    
    if state.mode == "build" then
        local bDef = STRUCTURES[state.selectedBuildIdx]
        local titleStr = " [X] Build: " .. bDef.name
        if w >= 40 then
            titleStr = " [X] City Builder  [Mode: " .. bDef.name .. "]"
            term.write(titleStr)
            local right = "[PICK] [DONE]"
            term.setCursorPos(w - #right, 1)
            term.write(right)
        else
            term.write(titleStr)
            local right = "[DONE]"
            term.setCursorPos(w - #right, 1)
            term.write(right)
        end
    else
        term.write(" [X] Drunken City")
        if w >= 45 then
            local rightBtns = "[BUILD] [SAVE] [MENU]"
            term.setCursorPos(w - #rightBtns, 1)
            term.write(rightBtns)
        elseif w >= 34 then
            local rightBtns = "[BUILD] [MENU]"
            term.setCursorPos(w - #rightBtns, 1)
            term.write(rightBtns)
        end
    end
    
    -- Row 2: Win95 Resource Status Bar
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.clearLine()
    
    local resStr = ""
    if w >= 45 then
        resStr = string.format(" Min:[%04d]  Alloy:[%04d]  Pop:[%03d]  Energy:[%04d]", 
            state.resources.minerals, state.resources.alloys, state.resources.pop, state.resources.energy)
    else
        local eStr = (state.resources.energy <= 0) and "0!" or tostring(state.resources.energy)
        resStr = string.format(" M:%d A:%d P:%d E:%s", 
            state.resources.minerals, state.resources.alloys, state.resources.pop, eStr)
    end
    term.write(resStr)
    
    -- Row h - 1: Status / Feedback Bar
    term.setCursorPos(1, h - 1)
    term.setBackgroundColor(colors.black)
    term.clearLine()
    
    if state.mode == "build" then
        local bDef = STRUCTURES[state.selectedBuildIdx]
        local valid, reason = canPlace(bDef, state.cursor.x, state.cursor.y)
        if valid then
            term.setTextColor(colors.lime)
            term.write(" [OK] Tap tile or [PLACE]!")
        else
            term.setTextColor(colors.orange)
            local msg = " [X] " .. reason
            if #msg > w then msg = msg:sub(1, w) end
            term.write(msg)
        end
    else
        term.setTextColor(state.statusColor or colors.yellow)
        local msg = " " .. (state.statusMsg or "")
        if #msg > w then msg = msg:sub(1, w) end
        term.write(msg)
    end
    
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
    
    local posTxt = string.format(" %03d,%03d [%s]", state.cursor.x, state.cursor.y, tName)
    term.write(posTxt)
    
    if state.mode == "build" then
        local btmBtns = (w >= 36) and "[PICK] [PLACE] [DONE]" or "[PICK] [PLACE]"
        term.setCursorPos(w - #btmBtns, h)
        term.write(btmBtns)
    else
        local btmBtns = ""
        if w >= 48 then
            btmBtns = "[BUILD] [SAVE] [MENU] [QUIT]"
        elseif w >= 36 then
            btmBtns = "[BUILD] [SAVE] [MENU]"
        elseif w >= 26 then
            btmBtns = "[BUILD] [MENU]"
        end
        term.setCursorPos(w - #btmBtns, h)
        term.write(btmBtns)
    end
end

--==============================================================================
-- STRUCTURE PICKER MODAL (Fits all screens including Pocket 26x20)
--==============================================================================
local function drawStructurePicker()
    local w, h = term.getSize()
    local pw = math.min(24, w - 2)
    local ph = #STRUCTURES + 4
    local px = math.floor((w - pw)/2) + 1
    local py = math.max(3, math.floor((h - ph)/2))
    
    paintutils.drawFilledBox(px, py, px + pw - 1, py + ph - 1, colors.lightGray)
    paintutils.drawBox(px, py, px + pw - 1, py + ph - 1, colors.gray)
    
    term.setCursorPos(px + 1, py)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    local title = " [X] Select Building"
    term.write(title .. string.rep(" ", math.max(0, pw - #title - 2)))
    
    for i, struc in ipairs(STRUCTURES) do
        local sy = py + 1 + i
        term.setCursorPos(px + 1, sy)
        if i == state.selectedBuildIdx then
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.yellow)
            term.write(string.format(" > %d:%-7s ", i, struc.name))
        else
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(string.format("   %d:%-7s ", i, struc.name))
        end
        
        term.setTextColor(colors.gray)
        local cstr = ""
        for res, amt in pairs(struc.cost) do
            cstr = cstr .. amt .. res:sub(1,1):upper() .. " "
        end
        term.write(cstr)
    end
    
    local closeBtn = "[ Close / Build ]"
    term.setCursorPos(px + math.floor((pw - #closeBtn)/2), py + ph - 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(closeBtn)
    
    return px, py, pw, ph
end

--==============================================================================
-- SYSTEM MENU MODAL
--==============================================================================
local function drawSystemMenu()
    local w, h = term.getSize()
    local mw = math.min(24, w - 2)
    local mh = 11
    local mx = math.floor((w - mw)/2) + 1
    local my = math.max(3, math.floor((h - mh)/2))
    
    paintutils.drawFilledBox(mx, my, mx + mw - 1, my + mh - 1, colors.lightGray)
    paintutils.drawBox(mx, my, mx + mw - 1, my + mh - 1, colors.gray)
    
    term.setCursorPos(mx + 1, my)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    local mTitle = " [X] System Menu"
    term.write(mTitle .. string.rep(" ", math.max(0, mw - #mTitle - 2)))
    
    local items = {
        { id=1, text="[ 1: Resume Game ]" },
        { id=2, text="[ 2: Save City   ]" },
        { id=3, text="[ 3: Load City   ]" },
        { id=4, text="[ 4: New City    ]" },
        { id=5, text="[ 5: Exit to OS  ]" },
    }
    
    for i, it in ipairs(items) do
        local iy = my + 1 + i * 2 - 1
        term.setCursorPos(mx + math.floor((mw - #it.text)/2), iy)
        if i == 5 then
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
        end
        term.write(it.text)
    end
    
    return mx, my, mw, mh
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

    -- Auto-load or generate initial world
    if fs.exists(SAVE_FILE) then
        local ok = loadGame("auto")
        if not ok then
            state.map, state.seed = generateWorld()
        end
    else
        state.map, state.seed = generateWorld()
    end
    
    w, h = term.getSize()
    local OFF_X, OFF_Y = 1, 3
    state.camera = Engine.newCamera(1, 1, w, h - 4)
    state.camera:centerOn(state.cursor.x, state.cursor.y, MAP_W, MAP_H)
    
    local timerId = os.startTimer(1)
    
    while state.running do
        w, h = term.getSize()
        local viewBottom = h - 2
        
        -- 1. Draw Map (FORCE = TRUE to prevent delta-cache ghost cursor bugs)
        Engine.Renderer.draw(state.map, state.camera, OFF_X, OFF_Y, true)
        
        -- 2. Draw Buildings (Overlay)
        for _, b in ipairs(state.buildings) do
             local scrX = b.x - state.camera.x + OFF_X
             local scrY = b.y - state.camera.y + OFF_Y
             
             if scrX >= 1 and scrX <= w and scrY >= OFF_Y and scrY <= viewBottom then
                  term.setCursorPos(scrX, scrY)
                  term.setTextColor(b.def.fg)
                  term.setBackgroundColor(b.def.bg)
                  term.write(b.def.char)
             end
        end
        
        -- 3. Draw Cursor
        local scrX = state.cursor.x - state.camera.x + OFF_X
        local scrY = state.cursor.y - state.camera.y + OFF_Y
        if scrX >= 1 and scrX <= w and scrY >= OFF_Y and scrY <= viewBottom then
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
        
        -- 4. Draw Header, Status, and Footer UI
        drawUI()
        
        -- 5. Draw Active Modals (Pick Structure or System Menu)
        local px, py, pw, ph = nil, nil, nil, nil
        local mx0, my0, mw0, mh0 = nil, nil, nil, nil
        
        if state.mode == "pick" then
            px, py, pw, ph = drawStructurePicker()
        elseif state.mode == "system" then
            mx0, my0, mw0, mh0 = drawSystemMenu()
        end
        
        -- 6. Unified Input Handling
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == timerId then
            simulationTick()
            timerId = os.startTimer(1)
            
            local now = os.epoch("utc")
            if (now - (state.lastAutoSave or 0)) > 30000 then
                 saveGame("auto", true)
                 state.lastAutoSave = now
            end
            
        elseif event == "key" then
            local key = p1
            
            if state.mode == "system" then
                if key == keys.r or key == keys.esc or key == keys.space or key == keys.enter or key == keys.one then
                    state.mode = "view"
                    playSnd("playClick")
                elseif key == keys.two then
                    saveGame("auto")
                elseif key == keys.three then
                    loadGame("auto"); state.mode = "view"
                elseif key == keys.four then
                    -- New City
                    state.buildings = {}
                    state.resources = { minerals=100, alloys=50, energy=100, pop=5 }
                    state.map, state.seed = generateWorld()
                    state.mode = "view"
                    saveGame("auto")
                    state.statusMsg = "Brand new city founded!"
                    state.statusColor = colors.yellow
                elseif key == keys.q or key == keys.five then
                    saveGame("auto", true)
                    state.running = false
                end
                
            elseif state.mode == "pick" then
                if key >= keys.one and key <= keys.six then
                    state.selectedBuildIdx = (key - keys.one) + 1
                    state.mode = "build"
                    playSnd("playClick")
                elseif key == keys.esc or key == keys.q or key == keys.enter or key == keys.space then
                    state.mode = "build"
                    playSnd("playClick")
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
                    if state.mode == "view" then
                        state.mode = "build"
                    else
                        state.mode = "view"
                    end
                    playSnd("playClick")
                elseif state.mode == "build" then
                    if key >= keys.one and key <= keys.six then
                        state.selectedBuildIdx = (key - keys.one) + 1
                        playSnd("playClick")
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
            
            -- Modal: Structure Picker Interception
            if state.mode == "pick" and px then
                if my == py and mx >= px and mx <= px + 4 then
                    state.mode = "view"
                    playSnd("playClick")
                elseif my >= py + 2 and my <= py + 1 + #STRUCTURES then
                    state.selectedBuildIdx = my - (py + 1)
                    state.mode = "build"
                    playSnd("playClick")
                elseif my == py + ph - 1 then
                    state.mode = "build"
                    playSnd("playClick")
                else
                    state.mode = "build"
                    playSnd("playClick")
                end
                
            -- Modal: System Menu Interception
            elseif state.mode == "system" and mx0 then
                if my == my0 and mx >= mx0 and mx <= mx0 + 4 then
                    state.mode = "view"
                    playSnd("playClick")
                elseif my == my0 + 2 then
                    state.mode = "view"
                    playSnd("playClick")
                elseif my == my0 + 4 then
                    saveGame("auto")
                elseif my == my0 + 6 then
                    loadGame("auto"); state.mode = "view"
                elseif my == my0 + 8 then
                    state.buildings = {}
                    state.resources = { minerals=100, alloys=50, energy=100, pop=5 }
                    state.map, state.seed = generateWorld()
                    state.mode = "view"
                    saveGame("auto")
                    state.statusMsg = "Brand new city founded!"
                    state.statusColor = colors.yellow
                elseif my == my0 + 10 then
                    saveGame("auto", true)
                    state.running = false
                end
                
            -- Row 1: Title Bar Clicks
            elseif my == 1 then
                if mx >= 2 and mx <= 4 then
                    state.mode = (state.mode == "system") and "view" or "system"
                    playSnd("playClick")
                elseif state.mode == "build" then
                    if mx >= w - 6 and mx <= w then
                        state.mode = "view"
                        playSnd("playClick")
                    elseif w >= 40 and mx >= w - 13 and mx <= w - 8 then
                        state.mode = "pick"
                        playSnd("playClick")
                    end
                else
                    if w >= 45 then
                        if mx >= w - 21 and mx <= w - 15 then
                            state.mode = "build"
                            playSnd("playClick")
                        elseif mx >= w - 13 and mx <= w - 8 then
                            saveGame("auto")
                        elseif mx >= w - 6 and mx <= w then
                            state.mode = "system"
                            playSnd("playClick")
                        end
                    elseif w >= 34 then
                        if mx >= w - 14 and mx <= w - 8 then
                            state.mode = "build"
                            playSnd("playClick")
                        elseif mx >= w - 6 and mx <= w then
                            state.mode = "system"
                            playSnd("playClick")
                        end
                    end
                end
                
            -- Row h: Bottom Action Bar Clicks
            elseif my == h then
                if state.mode == "build" then
                    if mx >= w - 7 and mx <= w then
                        -- [PLACE]
                        placeBuildingAtCursor()
                    elseif mx >= w - 14 and mx <= w - 8 then
                        -- [PICK]
                        state.mode = "pick"
                        playSnd("playClick")
                    elseif w >= 36 and mx >= w - 6 and mx <= w then
                        state.mode = "view"
                        playSnd("playClick")
                    end
                else
                    if mx >= w - 14 and mx <= w - 8 then
                        state.mode = "build"
                        playSnd("playClick")
                    elseif mx >= w - 6 and mx <= w then
                        state.mode = "system"
                        playSnd("playClick")
                    end
                end
                
            -- Map Clicks (Viewport Rows OFF_Y to viewBottom)
            elseif my >= OFF_Y and my <= viewBottom then
                local worldX = mx + state.camera.x - OFF_X
                local worldY = my + state.camera.y - OFF_Y
                if worldX >= 1 and worldX <= MAP_W and worldY >= 1 and worldY <= MAP_H then
                    if state.mode == "build" then
                        if state.cursor.x == worldX and state.cursor.y == worldY then
                            -- Double tap same tile: place!
                            placeBuildingAtCursor()
                        else
                            -- Move cursor & preview
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
            if my >= OFF_Y and my <= viewBottom then
                if state.mode == "view" or state.mode == "build" then
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
