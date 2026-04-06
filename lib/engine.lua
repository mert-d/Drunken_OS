--[[
    Drunken Engine (v1.0)
    A lightweight, tile-based rendering engine for ComputerCraft.
    
    Features:
    - TileMap management
    - Virtual Camera (scrolling)
    - High-performance Blit Renderer
]]

local Engine = { _VERSION = "1.0" }

--==============================================================================
-- TILEMAP
--==============================================================================
local TileMap = {}
TileMap.__index = TileMap

---
-- Instantiates a new 2D tile map data structure.
-- @param width number: Total columns in the map.
-- @param height number: Total rows in the map.
-- @param defaultTile table: The fallback tile definition to fill the board with.
-- @return table: The TileMap class instance.
function Engine.newMap(width, height, defaultTile)
    local self = setmetatable({}, TileMap)
    self.width = width
    self.height = height
    self.data = {}
    
    -- Initialize grid
    for y = 1, height do
        self.data[y] = {}
        for x = 1, width do
            self.data[y][x] = defaultTile or { char=" ", fg=colors.white, bg=colors.black }
        end
    end
    
    return self
end

---
-- Writes a tile definition into the grid at the specified coordinates safely.
-- @param x number: Target column.
-- @param y number: Target row.
-- @param tile table: The tile definition {char, fg, bg}.
function TileMap:set(x, y, tile)
    if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
        self.data[y][x] = tile
    end
end

---
-- Retrieves the tile definition at a given grid coordinate.
-- @param x number: Target column.
-- @param y number: Target row.
-- @return table|nil: The tile definition, or nil if coordinates are out-of-bounds.
function TileMap:get(x, y)
    if x >= 1 and x <= self.width and y >= 1 and y <= self.height then
        return self.data[y][x]
    end
    return nil -- Out of bounds
end

--==============================================================================
-- CAMERA
--==============================================================================
local Camera = {}
Camera.__index = Camera

---
-- Instantiates a new virtual Camera to govern rendering windows onto a TileMap.
-- @param x number: The left-most grid column the camera currently views.
-- @param y number: The top-most grid row the camera currently views.
-- @param viewWidth number: The width of the viewport constraint.
-- @param viewHeight number: The height of the viewport constraint.
-- @return table: The Camera class instance.
function Engine.newCamera(x, y, viewWidth, viewHeight)
    local self = setmetatable({}, Camera)
    self.x = x or 1
    self.y = y or 1
    self.w = viewWidth
    self.h = viewHeight
    return self
end

---
-- Shifts the camera view such that a given coordinate is directly in the center, 
-- clamped against the literal bounds of the given Map.
-- @param targetX number: Center focus column.
-- @param targetY number: Center focus row.
-- @param mapWidth number: Maximum column width constraint.
-- @param mapHeight number: Maximum row height constraint.
function Camera:centerOn(targetX, targetY, mapWidth, mapHeight)
    self.x = targetX - math.floor(self.w / 2)
    self.y = targetY - math.floor(self.h / 2)
    
    -- Clamp to bounds
    if self.x < 1 then self.x = 1 end
    if self.y < 1 then self.y = 1 end
    if self.x + self.w > mapWidth then self.x = mapWidth - self.w + 1 end
    if self.y + self.h > mapHeight then self.y = mapHeight - self.h + 1 end
end

--==============================================================================
-- RENDERER
--==============================================================================
local Renderer = {}

-- Helper for color conversion (hex char)
local colorToHex = {
    [1] = "0", [2] = "1", [4] = "2", [8] = "3",
    [16] = "4", [32] = "5", [64] = "6", [128] = "7",
    [256] = "8", [512] = "9", [1024] = "a", [2048] = "b",
    [4096] = "c", [8192] = "d", [16384] = "e", [32768] = "f"
}

--- Draws the map region visible to the camera
-- Constructs a large display buffer and batches colors together to render 
-- high framerate tiles without tearing using term.blit.
-- @param map table: The TileMap instance to render.
-- @param camera table: The Camera acting as the viewport mask.
-- @param offsetX number: Screen relative X coordinate to draw the output rect.
-- @param offsetY number: Screen relative Y coordinate to draw the output rect.
function Renderer.draw(map, camera, offsetX, offsetY)
    local offX = offsetX or 1
    local offY = offsetY or 1
    
    for scrY = 0, camera.h - 1 do
        local worldY = camera.y + scrY
        local lineTxt = {}
        local lineFg = {}
        local lineBg = {}
        
        for scrX = 0, camera.w - 1 do
            local worldX = camera.x + scrX
            local tile = map:get(worldX, worldY)
            
            if tile then
                table.insert(lineTxt, tile.char)
                table.insert(lineFg, colorToHex[tile.fg] or "0")
                table.insert(lineBg, colorToHex[tile.bg] or "f")
            else
                -- Out of bounds filler
                table.insert(lineTxt, " ")
                table.insert(lineFg, "0")
                table.insert(lineBg, "f")
            end
        end
        
        term.setCursorPos(offX, offY + scrY)
        term.blit(table.concat(lineTxt), table.concat(lineFg), table.concat(lineBg))
    end
end

Engine.Renderer = Renderer

return Engine
