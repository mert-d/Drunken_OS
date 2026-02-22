--[[
    Drunken Sudoku
    Version: 1.0
    A classic puzzle game.
]]
local gameVersion = 1.0

local args = {...}
local username = args[1] or "Player"

local w, h = term.getSize()

-- Colors (fallback if no theme)
local bgCol = colors.black
local fgCol = colors.yellow
local fixCol = colors.lightGray
local curCol = colors.white
local hlBgCol = colors.blue
local lineCol = colors.gray
local winCol = colors.lime

-- Attempt to load theme
pcall(function()
    local theme = require("lib.theme")
    if theme then
        bgCol = theme.bg or colors.black
        fgCol = theme.prompt or colors.yellow
        fixCol = theme.text or colors.lightGray
        hlBgCol = theme.highlightBg or colors.blue
        curCol = theme.highlightText or colors.white
        lineCol = theme.mutedText or colors.gray
        winCol = theme.successText or colors.lime
    end
end)

local state = {
    grid = {},
    fixed = {}, 
    cursorX = 1,
    cursorY = 1,
    won = false,
}

local function generateGrid()
    local base = {
      {1,2,3, 4,5,6, 7,8,9},
      {4,5,6, 7,8,9, 1,2,3},
      {7,8,9, 1,2,3, 4,5,6},
      
      {2,3,4, 5,6,7, 8,9,1},
      {5,6,7, 8,9,1, 2,3,4},
      {8,9,1, 2,3,4, 5,6,7},
      
      {3,4,5, 6,7,8, 9,1,2},
      {6,7,8, 9,1,2, 3,4,5},
      {9,1,2, 3,4,5, 6,7,8}
    }
    
    local map = {1,2,3,4,5,6,7,8,9}
    for i=9, 2, -1 do
        local j = math.random(1, i)
        map[i], map[j] = map[j], map[i]
    end
    
    for r=1, 9 do
        state.grid[r] = {}
        state.fixed[r] = {}
        for c=1, 9 do
            state.grid[r][c] = map[base[r][c]]
            state.fixed[r][c] = true
        end
    end
    
    for band=0, 2 do
        local r1, r2, r3 = band*3+1, band*3+2, band*3+3
        if math.random()>0.5 then state.grid[r1], state.grid[r2] = state.grid[r2], state.grid[r1] end
        if math.random()>0.5 then state.grid[r2], state.grid[r3] = state.grid[r3], state.grid[r2] end
        if math.random()>0.5 then state.grid[r1], state.grid[r3] = state.grid[r3], state.grid[r1] end
    end
    
    for stack=0, 2 do
        local c1, c2, c3 = stack*3+1, stack*3+2, stack*3+3
        local function swapCol(ca, cb)
            for r=1, 9 do
                state.grid[r][ca], state.grid[r][cb] = state.grid[r][cb], state.grid[r][ca]
            end
        end
        if math.random()>0.5 then swapCol(c1, c2) end
        if math.random()>0.5 then swapCol(c2, c3) end
        if math.random()>0.5 then swapCol(c1, c3) end
    end
    
    local holes = 45 
    while holes > 0 do
        local r = math.random(1, 9)
        local c = math.random(1, 9)
        if state.grid[r][c] ~= 0 then
            state.grid[r][c] = 0
            state.fixed[r][c] = false
            holes = holes - 1
        end
    end
end

local function drawGrid()
    local ox = math.floor((w - 25) / 2)
    local oy = math.floor((h - 13) / 2)
    
    local function drawHoriz(y)
        term.setCursorPos(ox, oy + y)
        term.setTextColor(lineCol)
        term.setBackgroundColor(bgCol)
        term.write("+-------+-------+-------+")
    end
    
    for r=1, 9 do
        if r % 3 == 1 then drawHoriz(r-1 + math.floor((r-1)/3)) end
        
        term.setCursorPos(ox, oy + r - 1 + math.floor((r-1)/3) + 1)
        for c=1, 9 do
            if c % 3 == 1 then
                term.setTextColor(lineCol)
                term.setBackgroundColor(bgCol)
                term.write("| ")
            end
            
            local val = state.grid[r][c]
            local isFixed = state.fixed[r][c]
            
            if r == state.cursorY and c == state.cursorX then
                term.setBackgroundColor(hlBgCol)
                term.setTextColor(curCol)
            else
                term.setBackgroundColor(bgCol)
                if isFixed then
                    term.setTextColor(fixCol)
                else
                    term.setTextColor(fgCol)
                end
            end
            
            if val == 0 then
                term.write(".")
            else
                term.write(tostring(val))
            end
            
            term.setBackgroundColor(bgCol)
            term.setTextColor(lineCol)
            term.write(" ")
            
            if c == 9 then
                term.write("|")
            end
        end
    end
    drawHoriz(13-1)
    
    term.setCursorPos(math.max(1, ox - 3), oy + 14)
    term.setBackgroundColor(bgCol)
    term.clearLine()
    
    if state.won then
        term.setTextColor(winCol)
        term.setCursorPos(math.max(1, ox - 3), oy + 14)
        term.write("Puzzle Solved! Press Q to quit ")
    else
        term.setTextColor(fgCol)
        term.setCursorPos(math.max(1, ox - 3), oy + 14)
        term.write("Arrows: Move | 1-9: Set | 0: Clear")
        term.setCursorPos(math.max(1, ox - 3), oy + 15)
        term.clearLine()
        term.setCursorPos(math.max(1, ox - 3), oy + 15)
        term.write("Q: Quit ")
    end
end

local function checkWin()
    for r=1,9 do
        for c=1,9 do
            if state.grid[r][c] == 0 then return false end
        end
    end
    
    for i=1,9 do
        local rSet, cSet = {}, {}
        for j=1,9 do
            rSet[state.grid[i][j]] = true
            cSet[state.grid[j][i]] = true
        end
        local rCount, cCount = 0, 0
        for _ in pairs(rSet) do rCount = rCount + 1 end
        for _ in pairs(cSet) do cCount = cCount + 1 end
        if rCount < 9 or cCount < 9 then return false end
    end
    
    for br=0,2 do
        for bc=0,2 do
            local bSet = {}
            for r=1,3 do
                for c=1,3 do
                    bSet[state.grid[br*3+r][bc*3+c]] = true
                end
            end
            local bCount = 0
            for _ in pairs(bSet) do bCount = bCount + 1 end
            if bCount < 9 then return false end
        end
    end
    
    return true
end

math.randomseed(os.epoch("utc"))
generateGrid()
state.won = false

term.setBackgroundColor(bgCol)
term.clear()

local run = true
while run do
    -- Header
    term.setBackgroundColor(lineCol)
    term.setTextColor(bgCol)
    term.setCursorPos(1,1)
    term.clearLine()
    term.write(" DRUNKEN SUDOKU - Player: " .. username)

    drawGrid()
    
    local evt, key = os.pullEvent("key")
    if evt == "key" then
        if key == keys.q then
            run = false
        elseif not state.won then
            if key == keys.up and state.cursorY > 1 then state.cursorY = state.cursorY - 1
            elseif key == keys.down and state.cursorY < 9 then state.cursorY = state.cursorY + 1
            elseif key == keys.left and state.cursorX > 1 then state.cursorX = state.cursorX - 1
            elseif key == keys.right and state.cursorX < 9 then state.cursorX = state.cursorX + 1
            elseif key >= keys.one and key <= keys.nine then
                if not state.fixed[state.cursorY][state.cursorX] then
                    state.grid[state.cursorY][state.cursorX] = key - keys.one + 1
                    if checkWin() then state.won = true end
                end
            elseif key >= keys.numPad1 and key <= keys.numPad9 then
                if not state.fixed[state.cursorY][state.cursorX] then
                    state.grid[state.cursorY][state.cursorX] = key - keys.numPad1 + 1
                    if checkWin() then state.won = true end
                end
            elseif key == keys.zero or key == keys.backspace or key == keys.delete or key == keys.space or key == keys.numPad0 then
                if not state.fixed[state.cursorY][state.cursorX] then
                    state.grid[state.cursorY][state.cursorX] = 0
                end
            end
        end
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
