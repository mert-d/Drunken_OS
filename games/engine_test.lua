--[[
    Engine Verification Script
    Tests the Performance and API of lib/engine.lua
]]

local Engine = require("lib.engine")
local width, height = 100, 100
local map = Engine.newMap(width, height)    
local theme = require("lib.theme") 

-- Generate Random Terrain
print("Generating Terrain...")
for y=1, height do
    for x=1, width do
        local r = math.random()
        if r < 0.1 then
            map:set(x, y, { char="#", fg=colors.gray, bg=colors.black }) -- Rock
        elseif r < 0.15 then
            map:set(x, y, { char="%", fg=colors.yellow, bg=colors.black }) -- Ore
        elseif r < 0.2 then
             map:set(x, y, { char="~", fg=colors.blue, bg=colors.lightBlue }) -- Water
        else
            map:set(x, y, { char=".", fg=colors.lightGray, bg=colors.black }) -- Ground
        end
    end
end

-- Camera Setup
local w, h = term.getSize()
local camera = Engine.newCamera(1, 1, w, h)

-- Main Loop
local running = true
while running do
    -- Render
    Engine.Renderer.draw(map, camera)
    
    -- Debug Info
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.write("Cam: " .. camera.x .. "," .. camera.y)
    
    local event, key = os.pullEvent("key")
    if key == keys.q then
        running = false
    elseif key == keys.up then
        camera:centerOn(camera.x + camera.w/2, camera.y + camera.h/2 - 1, map.width, map.height)
    elseif key == keys.down then
        camera:centerOn(camera.x + camera.w/2, camera.y + camera.h/2 + 1, map.width, map.height)
    elseif key == keys.left then
        camera:centerOn(camera.x + camera.w/2 - 1, camera.y + camera.h/2, map.width, map.height)
    elseif key == keys.right then
        camera:centerOn(camera.x + camera.w/2 + 1, camera.y + camera.h/2, map.width, map.height)
    end
end

term.clear()
term.setCursorPos(1,1)
print("Engine Test Complete.")
