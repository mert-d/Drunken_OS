--[[
    Drunken Sokoban (v1.1)
    by Gemini Gem

    Purpose:
    A classic box-pushing puzzle for Drunken OS.
    Push all crates onto the target spots to win!
]]

-- Load shared libraries
if package and package.path then package.path = "/?.lua;" .. package.path end
local sharedTheme = require("lib.theme")
local scoreCache = require("lib.score_cache")

local gameVersion = 1.3

---
-- Main application point for Drunken Sokoban. 
-- Handles level parsing, character movement, and the world builder editor.
local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenSokoban"
    local arcadeServerId = nil

    local sound = nil
    pcall(function() sound = require("lib.sound") end)
    local function playSfx(fn, ...)
        if sound and sound[fn] then pcall(sound[fn], ...) end
    end
    local function playTone(inst, pitch, vol)
        if sound and sound.playNote then pcall(sound.playNote, colors.white, inst, pitch, vol) end
    end

    -- Use shared theme colors with Win95 styling
    local theme = {
        bg = colors.lightGray,
        text = colors.black,
        border = colors.gray,
        player = colors.yellow,
        box = colors.orange,
        target = colors.lime,
        wall = colors.gray,
        boxOnTarget = colors.green,
        highlightBg = colors.blue,
        highlightText = colors.white,
        prompt = colors.blue,
    }

    -- Level Data (Simple 1st Level)
    local levels = {
        {
            map = {
                "  ##### ",
                "###   # ",
                "# .X  # ",
                "### X.# ",
                "# .X  # ",
                "# #   # ",
                "#   @ # ",
                "####### "
            },
            name = "Safe Storage"
        },
        {
            map = {
                "#######",
                "#     #",
                "# X . #",
                "# . X #",
                "#  @  #",
                "#######"
            },
            name = "The Lobby"
        },
        {
            map = {
                " ##### ",
                " # . # ",
                " # X # ",
                " # @ # ",
                " ##### "
            },
            name = "The Well"
        },
        {
            map = {
                "#######",
                "#.  X #",
                "#X  @ #",
                "#.  X #",
                "#######"
            },
            name = "The Corner"
        },
        {
            map = {
                "#######",
                "#@    #",
                "# X X #",
                "# X.X #",
                "# ... #",
                "#######"
            },
            name = "Push & Shove"
        },
        {
            map = {
                "  ####  ",
                "###  ###",
                "#@ X . #",
                "###  ###",
                "  ####  "
            },
            name = "Tunnel"
        },
        {
            map = {
                "#########",
                "#   #   #",
                "# X . X #",
                "#   @   #",
                "# . #   #",
                "#########"
            },
            name = "The Cross"
        },
        {
            map = {
                "##########",
                "#@       #",
                "#  X X X #",
                "#  . . . #",
                "#        #",
                "##########"
            },
            name = "Parallel Lines"
        },
        {
            map = {
                "  #####  ",
                " ##   ## ",
                "## X.X ##",
                "# @.X.X #",
                "## X.X ##",
                " ##   ## ",
                "  #####  "
            },
            name = "Diamond"
        },
        {
            map = {
                "##########",
                "#@       #",
                "#  X#X   #",
                "#  #.#   #",
                "#  X#X   #",
                "#.  .   .#",
                "##########"
            },
            name = "Interstices"
        },
        {
            map = {
                "####################",
                "#@                 #",
                "#  X X X X X X X X #",
                "#  . . . . . . . . #",
                "#                  #",
                "#  X X X X X X X X #",
                "#  . . . . . . . . #",
                "#                  #",
                "####################"
            },
            name = "The Warehouse"
        },
        {
            map = {
                "####################",
                "#@ #     # . . . . #",
                "#  # XXXX# . . . . #",
                "#  # XXXX# . . . . #",
                "#  # XXXX# . . . . #",
                "#  # XXXX# . . . . #",
                "#  #######         #",
                "#                  #",
                "####################"
            },
            name = "The Sorting Room"
        },
        {
            map = {
                "        ########    ",
                "        #      #    ",
                "######### X XX #    ",
                "#@      # X XX #    ",
                "#  X XX #  X XX #    ",
                "#  ...  #  ... #    ",
                "#  ...  #####  #    ",
                "#  ...      #  #    ",
                "#############  #    ",
                "    #          #    ",
                "    ############    "
            },
            name = "Complex Alpha"
        },
        {
            map = {
                "####################",
                "#@       #       . #",
                "#   X    #    X    #",
                "#        #       . #",
                "####  ########  ####",
                "#        #         #",
                "#   X    #    X    #",
                "#        #         #",
                "####  ########  ####",
                "#.       #       . #",
                "####################"
            },
            name = "Quadrants"
        },
        {
            map = {
                "      ########      ",
                "     ##      ##     ",
                "    ##  X  X  ##    ",
                "   ##  .    .  ##   ",
                "  ##   .    .   ##  ",
                " ##    .    .    ## ",
                "##      @  X      ##",
                " ##    X    X.    ## ",
                "  ##   X    X   ##  ",
                "   ##          ##   ",
                "    ##        ##    ",
                "     ##########     "
            },
            name = "Octagon"
        },
        {
            map = {
                "####################",
                "#  . . . . . . . . #",
                "#  X X X X X X X X #",
                "#                  #",
                "#                  #",
                "#                  #",
                "#  X X X X X X X X #",
                "#  . . . . . . . . #",
                "#@                 #",
                "####################"
            },
            name = "Dual Storage"
        },
        {
            map = {
                "####################",
                "#@       #       . #",
                "#   X    #    X    #",
                "#        #       . #",
                "####  ########  ####",
                "#        #         #",
                "#   X    #    X    #",
                "#        #         #",
                "####  ########  ####",
                "#.       #       X #",
                "####################"
            },
            name = "The Gauntlet"
        },
        {
            map = {
                "####################",
                "# . . . . . . . . .#",
                "#                  #",
                "# X X X X X X X X X#",
                "#                  #",
                "#@                 #",
                "####################"
            },
            name = "The Stripe"
        },
        {
            map = {
                "####################",
                "#.#.#.#.#.#.#.#.#.#",
                "#                 #",
                "# X X X X X X X X X#",
                "#                 #",
                "#@                #",
                "####################"
            },
            name = "The Grating"
        },
        {
            map = {
                "       #######      ",
                "      ##     ##     ",
                "     ## .X.X. ##    ",
                "    ##  X.X.X  ##   ",
                "   ##  .X.X.X.  ##  ",
                "    ##  X.X.X  ##   ",
                "     ## .X.X. ##    ",
                "      ##  @ X##     ",
                "       #######      "
            },
            name = "The Star"
        }
    }

    -- State
    local currentLevel = 1
    local board = {}
    local player = { x = 1, y = 1 }
    local moveCount = 0
    local history = {}
    local w, h = term.getSize()

    local function getSafeSize()
        local w, h = term.getSize()
        while not w or not h do sleep(0.05); w, h = term.getSize() end
        return w, h
    end

    local function loadLevel(num)
        local lvl = levels[num]
        board = {}
        for y, row in ipairs(lvl.map) do
            board[y] = {}
            for x = 1, #row do
                local char = row:sub(x, x)
                if char == "@" then
                    player.x, player.y = x, y
                    board[y][x] = " "
                else
                    board[y][x] = char
                end
            end
        end
        moveCount = 0
        history = {}
    end

    local function copyBoard(b)
        local newB = {}
        for y, row in ipairs(b) do
            newB[y] = {}
            for x, char in ipairs(row) do
                newB[y][x] = char
            end
        end
        return newB
    end

    local function pushHistory()
        table.insert(history, {
            board = copyBoard(board),
            px = player.x,
            py = player.y,
            moves = moveCount
        })
        if #history > 50 then table.remove(history, 1) end
    end

    local function undo()
        if #history > 0 then
            local last = table.remove(history)
            board = last.board
            player.x = last.px
            player.y = last.py
            moveCount = last.moves
            playTone("flute", 16, 0.8)
            return true
        end
        playTone("bass", 1, 0.4)
        return false
    end

    local function drawFrame(subTitle)
        local w, h = getSafeSize()
        term.setBackgroundColor(colors.lightGray)
        term.clear()
        
        -- Win95 Title Bar
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        local title = " Sokoban " .. (subTitle and ("- " .. subTitle) or ("v" .. gameVersion))
        if #title > w - 4 then title = title:sub(1, w - 4) end
        term.write(title .. string.rep(" ", math.max(0, w - #title - 3)))
        
        -- Win95 Close Button [X]
        term.setCursorPos(w - 2, 1)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write("[X]")
    end

    local function countBoxes()
        local placed, total = 0, 0
        for y, row in ipairs(board) do
            for x, char in ipairs(row) do
                if char == "." then total = total + 1
                elseif char == "Y" then total = total + 1; placed = placed + 1 end
            end
        end
        return placed, total
    end

    local function drawBoard()
        local w, h = getSafeSize()
        drawFrame("Level " .. currentLevel)
        
        -- Top Scoreboard / Status Strip
        term.setCursorPos(1, 2)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(string.rep(" ", w))
        
        local placed, total = countBoxes()
        term.setCursorPos(2, 2)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lime)
        term.write(string.format(" L:%02d ", currentLevel))
        
        term.setCursorPos(math.max(9, math.floor(w/2 - 5)), 2)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.yellow)
        term.write(string.format(" MOV:%03d ", moveCount))
        
        local boxStr = string.format(" BOX:%d/%d ", placed, total)
        term.setCursorPos(math.max(2, w - #boxStr), 2)
        term.setBackgroundColor(colors.black)
        term.setTextColor(placed == total and colors.lime or colors.cyan)
        term.write(boxStr)

        -- Playfield Area
        local mh = #board
        local mw = 0
        for _, r in ipairs(board) do mw = math.max(mw, #r) end

        local ox = math.max(2, math.floor((w - mw) / 2))
        local oy = math.max(4, math.floor((h - 3 - mh) / 2) + 2)

        for y, row in ipairs(board) do
            term.setCursorPos(ox, oy + y - 1)
            for x, char in ipairs(row) do
                local fg = colors.white
                local bg = colors.black
                local display = char

                if x == player.x and y == player.y then
                    display = "@"
                    fg = colors.yellow
                    bg = (char == "." or char == "Y") and colors.green or colors.black
                elseif char == "#" then
                    fg = colors.gray
                    bg = colors.lightGray
                    display = "#"
                elseif char == "X" then
                    fg = colors.orange
                    bg = colors.brown
                    display = "$"
                elseif char == "." then
                    fg = colors.lime
                    bg = colors.black
                    display = "."
                elseif char == "Y" then -- Box on target
                    display = "$"
                    fg = colors.yellow
                    bg = colors.green
                elseif char == " " then
                    display = " "
                    bg = colors.black
                end

                term.setTextColor(fg)
                term.setBackgroundColor(bg)
                term.write(display)
            end
        end

        -- Bottom Touch & Control Bar
        term.setCursorPos(1, h)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(string.rep(" ", w))
        
        if w >= 38 then
            term.setCursorPos(2, h)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write("[<][^][v][>]")
            
            term.setCursorPos(16, h)
            term.write("[Undo] [Reset] [Menu]")
        else
            term.setCursorPos(1, h)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write("[<][^][v][>] [U] [R] [M]")
        end
        return ox, oy
    end

    local function move(dx, dy)
        local nx, ny = player.x + dx, player.y + dy
        local target = board[ny] and board[ny][nx]

        if not target or target == "#" then
            playTone("bass", 1, 0.4)
            return false
        end

        if target == "X" or target == "Y" then
            -- Push logic
            local bx, by = nx + dx, ny + dy
            local boxTarget = board[by] and board[by][bx]
            if boxTarget == " " or boxTarget == "." then
                pushHistory()
                -- Move box
                board[ny][nx] = (target == "Y") and "." or " "
                board[by][bx] = (boxTarget == ".") and "Y" or "X"
                -- Move player
                player.x, player.y = nx, ny
                moveCount = moveCount + 1
                if boxTarget == "." then
                    playTone("chime", 14, 1.0)
                else
                    playTone("bass", 7, 0.8)
                end
                return true
            else
                playTone("bass", 1, 0.4)
                return false
            end
        else
            pushHistory()
            -- Normal move
            player.x, player.y = nx, ny
            moveCount = moveCount + 1
            playTone("hat", 12, 0.3)
            return true
        end
    end

    local function checkWin()
        for y, row in ipairs(board) do
            for x, char in ipairs(row) do
                if char == "X" then return false end
            end
        end
        return true
    end

    local function showMenu()
        local options = { "New Game", "Level Select", "Local Maps", "World Builder", "Community Maps", "Quit" }
        local selection = 1
        while true do
            drawFrame("Menu")
            local w, h = getSafeSize()
            
            -- Win95 Dialog Box
            local bw = math.min(w - 4, 30)
            local bh = #options + 4
            local bx = math.floor((w - bw) / 2)
            local by = math.floor((h - bh) / 2)
            
            term.setBackgroundColor(colors.gray)
            for y = by, by + bh do
                term.setCursorPos(bx, y)
                term.write(string.rep(" ", bw))
            end
            
            term.setCursorPos(bx + 2, by + 1)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.yellow)
            term.write("SELECT AN OPTION:")

            for i, opt in ipairs(options) do
                local oy = by + 2 + i
                term.setCursorPos(bx + 2, oy)
                if i == selection then
                    term.setBackgroundColor(colors.blue)
                    term.setTextColor(colors.white)
                    term.write(string.format(" > [%d] %-" .. (bw - 8) .. "s ", i, opt))
                else
                    term.setBackgroundColor(colors.lightGray)
                    term.setTextColor(colors.black)
                    term.write(string.format("   [%d] %-" .. (bw - 8) .. "s ", i, opt))
                end
            end

            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.up then selection = math.max(1, selection - 1); playSfx("playClick")
                elseif p1 == keys.down then selection = math.min(#options, selection + 1); playSfx("playClick")
                elseif p1 == keys.enter or p1 == keys.space then playSfx("playClick"); return options[selection]
                elseif p1 == keys.one then return options[1]
                elseif p1 == keys.two then return options[2]
                elseif p1 == keys.three then return options[3]
                elseif p1 == keys.four then return options[4]
                elseif p1 == keys.five then return options[5]
                elseif p1 == keys.six or p1 == keys.q then return "Quit" end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= w - 3 then
                    playSfx("playClick")
                    return "Quit"
                end
                for i, opt in ipairs(options) do
                    local oy = by + 2 + i
                    if my == oy and mx >= bx and mx <= bx + bw then
                        playSfx("playClick")
                        selection = i
                        return opt
                    end
                end
            elseif event == "mouse_scroll" then
                selection = math.max(1, math.min(#options, selection + p1))
                playSfx("playClick")
            end
        end
    end

    local function showLevelSelect()
        local selection = 1
        local scroll = 0
        while true do
            drawFrame("Level Select")
            local w, h = getSafeSize()
            local maxVisible = math.max(4, h - 7)

            term.setCursorPos(math.floor(w/2 - 6), 3)
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write("SELECT LEVEL")

            for i = 1, maxVisible do
                local idx = i + scroll
                if idx > #levels then break end
                local lvl = levels[idx]
                
                term.setCursorPos(3, 4 + i)
                if idx == selection then
                    term.setBackgroundColor(colors.blue)
                    term.setTextColor(colors.white)
                    term.write(string.format(" > %2d. %-" .. (w - 10) .. "s ", idx, lvl.name))
                else
                    term.setBackgroundColor(colors.lightGray)
                    term.setTextColor(colors.black)
                    term.write(string.format("   %2d. %-" .. (w - 10) .. "s ", idx, lvl.name))
                end
            end

            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.setCursorPos(1, h)
            term.write(string.rep(" ", w))
            term.setCursorPos(2, h)
            term.write("[Play] [Back] | Tap to select")

            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.up then 
                    selection = math.max(1, selection - 1)
                    if selection <= scroll then scroll = math.max(0, scroll - 1) end
                    playSfx("playClick")
                elseif p1 == keys.down then 
                    selection = math.min(#levels, selection + 1)
                    if selection > scroll + maxVisible then scroll = math.min(#levels - maxVisible, scroll + 1) end
                    playSfx("playClick")
                elseif p1 == keys.enter then
                    currentLevel = selection
                    playSfx("playClick")
                    return true
                elseif p1 == keys.backspace or p1 == keys.q then
                    playSfx("playClick")
                    return false
                end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= w - 3 then
                    playSfx("playClick")
                    return false
                elseif my == h then
                    if mx >= 2 and mx <= 7 then
                        currentLevel = selection
                        playSfx("playClick")
                        return true
                    elseif mx >= 9 and mx <= 15 then
                        playSfx("playClick")
                        return false
                    end
                elseif my >= 5 and my <= 4 + maxVisible then
                    local clickedIdx = (my - 4) + scroll
                    if clickedIdx <= #levels then
                        selection = clickedIdx
                        currentLevel = selection
                        playSfx("playClick")
                        return true
                    end
                end
            elseif event == "mouse_scroll" then
                scroll = math.max(0, math.min(math.max(0, #levels - maxVisible), scroll + p1))
                selection = math.max(1, math.min(#levels, selection + p1))
                playSfx("playClick")
            end
        end
    end

    local function worldBuilder()
        local w, h = getSafeSize()
        local sizes = {
            { name = "Small (10x10)", w = 10, h = 10 },
            { name = "Medium (16x12)", w = 16, h = 12 },
            { name = "Large (Max)", w = w - 2, h = h - 4 }
        }
        local sizeSelection = 1
        local ew, eh

        while true do
            drawFrame()
            term.setTextColor(theme.prompt)
            term.setCursorPos(math.floor(w/2 - 6), 5)
            term.write("SELECT SIZE")

            for i, s in ipairs(sizes) do
                if i == sizeSelection then
                    term.setBackgroundColor(theme.highlightBg); term.setTextColor(theme.highlightText)
                else
                    term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
                end
                term.setCursorPos(math.floor(w/2 - #s.name/2), 7 + i)
                term.write(s.name)
            end

            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.up then sizeSelection = math.max(1, sizeSelection - 1); playSfx("playClick")
                elseif p1 == keys.down then sizeSelection = math.min(#sizes, sizeSelection + 1); playSfx("playClick")
                elseif p1 == keys.enter then
                    ew, eh = sizes[sizeSelection].w, sizes[sizeSelection].h
                    break
                elseif p1 == keys.q or p1 == keys.backspace then return end
            elseif event == "mouse_click" then
                if p3 == 1 and p2 >= w - 3 then return end
                for i = 1, #sizes do
                    if p3 == 7 + i then
                        sizeSelection = i
                        ew, eh = sizes[sizeSelection].w, sizes[sizeSelection].h
                        playSfx("playClick")
                        break
                    end
                end
                if ew and eh then break end
            end
        end

        local editorBoard = {}
        local cx, cy = 1, 1
        local brush = "#" -- Default brush: Wall
        local brushes = { "#", "X", ".", "@", " " }
        local brushNames = { ["#"] = "Wall", ["X"] = "Box", ["."] = "Target", ["@"] = "Player", [" "] = "Empty" }

        for y = 1, eh do editorBoard[y] = {}; for x = 1, ew do editorBoard[y][x] = " " end end

        local function drawEditor()
            drawFrame("World Builder")
            local w, h = getSafeSize()
            local ox = math.floor((w - ew) / 2)
            local oy = math.floor((h - eh) / 2)

            for y, row in ipairs(editorBoard) do
                term.setCursorPos(ox, oy + y - 1)
                for x, char in ipairs(row) do
                    local fg, bg = colors.black, colors.white
                    if x == cx and y == cy then bg = colors.blue; fg = colors.white end
                    
                    if char == "#" then fg = colors.gray; if x ~= cx or y ~= cy then bg = colors.lightGray end
                    elseif char == "X" then fg = colors.orange; if x ~= cx or y ~= cy then bg = colors.brown end
                    elseif char == "." then fg = colors.lime; if x ~= cx or y ~= cy then bg = colors.black end
                    elseif char == "@" then fg = colors.yellow; if x ~= cx or y ~= cy then bg = colors.black end end

                    term.setTextColor(fg); term.setBackgroundColor(bg)
                    term.write(char)
                end
            end

            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
            term.setCursorPos(1, h-1); term.write(string.rep(" ", w))
            term.setCursorPos(2, h-1); term.write("Brush: [" .. (brushNames[brush] or brush) .. "] (1:Wall 2:Box 3:Tgt 4:Ply 5:Clr)")
            term.setCursorPos(1, h); term.write(string.rep(" ", w))
            term.setCursorPos(2, h); term.write(" [S:Save] [P:Publish] [Q:Exit] | Tap grid to paint ")
            return ox, oy
        end

        while true do
            local ox, oy = drawEditor()
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                local key = p1
                if key == keys.up then cy = math.max(1, cy - 1)
                elseif key == keys.down then cy = math.min(eh, cy + 1)
                elseif key == keys.left then cx = math.max(1, cx - 1)
                elseif key == keys.right then cx = math.min(ew, cx + 1)
                elseif key == keys.space then editorBoard[cy][cx] = brush
                elseif key == keys.one then brush = "#"
                elseif key == keys.two then brush = "X"
                elseif key == keys.three then brush = "."
                elseif key == keys.four then brush = "@"
                elseif key == keys.five then brush = " "
                elseif key == keys.s then
                    -- Named save to local file
                    term.setCursorPos(2, 2); term.setBackgroundColor(theme.bg); term.setTextColor(theme.prompt)
                    term.write("Enter Map Name: ")
                    term.setCursorBlink(true)
                    local mapName = read()
                    term.setCursorBlink(false)
                    if mapName and mapName ~= "" then
                        local mapData = {}
                        for _, row in ipairs(editorBoard) do table.insert(mapData, table.concat(row)) end
                        if not fs.exists("/data/sokoban") then fs.makeDir("/data/sokoban") end
                        local filename = mapName:gsub("[%s%c%p]", "_") .. ".map.lua"
                        local f = fs.open(fs.combine("/data/sokoban", filename), "w")
                        f.write(textutils.serialize({ name = mapName, data = mapData }))
                        f.close()
                        term.setCursorPos(2, 2); term.setTextColor(colors.lime); term.write("Saved as " .. filename)
                    else
                        term.setCursorPos(2, 2); term.setTextColor(colors.red); term.write("Save cancelled.")
                    end
                    sleep(1.5)
                elseif key == keys.p then
                    -- Publish to Arcade Server
                    term.setCursorPos(2, 2); term.setBackgroundColor(theme.bg); term.setTextColor(theme.prompt)
                    term.write("Enter Public Name: ")
                    term.setCursorBlink(true)
                    local pubName = read()
                    term.setCursorBlink(false)
                    if pubName and pubName ~= "" then
                        local mapData = {}
                        for _, row in ipairs(editorBoard) do table.insert(mapData, table.concat(row)) end
                        term.setCursorPos(2, 2); term.setTextColor(colors.lime); term.write("Publishing...")
                        arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
                        if arcadeServerId then
                            rednet.send(arcadeServerId, {
                                type = "upload_map",
                                game = gameName,
                                mapName = pubName,
                                creator = username,
                                mapData = mapData
                            }, "ArcadeGames")
                            local id, msg = rednet.receive("ArcadeGames", 2)
                            if msg and msg.success then
                                term.setCursorPos(2, 2); term.write("Published Successfully!")
                            else
                                term.setCursorPos(2, 2); term.setTextColor(colors.red); term.write("Publish Failed.")
                            end
                        else
                            term.setCursorPos(2, 2); term.setTextColor(colors.red); term.write("Server not found.")
                        end
                    else
                        term.setCursorPos(2, 2); term.setTextColor(colors.red); term.write("Publish cancelled.")
                    end
                elseif key == keys.q then return end
            elseif event == "mouse_click" or event == "mouse_drag" then
                local mx, my = p2, p3
                if my == 1 and mx >= w - 3 then
                    playSfx("playClick")
                    return
                elseif ox and oy and my >= oy and my < oy + eh then
                    local gx = mx - ox + 1
                    local gy = my - oy + 1
                    if gx >= 1 and gx <= ew and gy >= 1 and gy <= eh then
                        editorBoard[gy][gx] = brush
                        cx, cy = gx, gy
                        playTone("hat", 14, 0.4)
                    end
                elseif my == h - 1 then
                    -- Brush change via touch
                    if mx >= 10 and mx <= 15 then brush = "#"; playSfx("playClick")
                    elseif mx >= 16 and mx <= 20 then brush = "X"; playSfx("playClick")
                    elseif mx >= 21 and mx <= 26 then brush = "."; playSfx("playClick")
                    elseif mx >= 27 and mx <= 32 then brush = "@"; playSfx("playClick")
                    elseif mx >= 33 and mx <= 38 then brush = " "; playSfx("playClick")
                    end
                end
            end
        end
    end

    local function showLocalMaps()
        local w, h = getSafeSize()
        local localDir = "/data/sokoban/"
        if not fs.exists(localDir) then fs.makeDir(localDir) end

        local files = fs.list(localDir)
        local maps = {}
        for _, file in ipairs(files) do
            if file:match("%.map%.lua$") then
                local f = fs.open(fs.combine(localDir, file), "r")
                if f then
                    local data = textutils.unserialize(f.readAll())
                    f.close()
                    if data then
                        table.insert(maps, { filename = file, name = data.name, data = data.data })
                    end
                end
            end
        end

        if #maps == 0 then
            drawFrame()
            term.setTextColor(colors.red); term.setCursorPos(5, 5)
            term.write("No local maps found. Use World Builder to create one.")
            sleep(2); return
        end

        local selection = 1
        local scroll = 0
        local maxVisible = 10
        while true do
            drawFrame()
            term.setTextColor(theme.prompt)
            term.setCursorPos(math.floor(w/2 - 5), 3); term.write("LOCAL MAPS")

            for i = 1, maxVisible do
                local idx = i + scroll
                if idx > #maps then break end
                local map = maps[idx]
                
                if idx == selection then
                    term.setBackgroundColor(theme.highlightBg); term.setTextColor(theme.highlightText)
                else
                    term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
                end
                local label = string.format("%d. %s", idx, map.name)
                term.setCursorPos(math.floor(w/2 - #label/2), 5 + i)
                term.write(label)
            end

            term.setBackgroundColor(theme.bg); term.setTextColor(colors.gray)
            term.setCursorPos(2, h); term.write(" ENTER: Play | BACKSPACE: Back ")

            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then 
                if p1 == keys.up then 
                    selection = math.max(1, selection - 1)
                    if selection <= scroll then scroll = math.max(0, scroll - 1) end
                    playSfx("playClick")
                elseif p1 == keys.down then 
                    selection = math.min(#maps, selection + 1)
                    if selection > scroll + maxVisible then scroll = math.min(#maps - maxVisible, scroll + 1) end
                    playSfx("playClick")
                elseif p1 == keys.enter then
                    local selected = maps[selection]
                    local originalLevel = currentLevel
                    levels[100] = { map = selected.data, name = selected.name }
                    currentLevel = 100
                    gameLoop()
                    currentLevel = originalLevel
                elseif p1 == keys.backspace or p1 == keys.q then return end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= w - 3 then return end
                if my >= 6 and my <= 5 + maxVisible then
                    local clickedIdx = (my - 5) + scroll
                    if clickedIdx <= #maps then
                        selection = clickedIdx
                        local selected = maps[selection]
                        local originalLevel = currentLevel
                        levels[100] = { map = selected.data, name = selected.name }
                        currentLevel = 100
                        gameLoop()
                        currentLevel = originalLevel
                    end
                end
            elseif event == "mouse_scroll" then
                scroll = math.max(0, math.min(math.max(0, #maps - maxVisible), scroll + p1))
                selection = math.max(1, math.min(#maps, selection + p1))
                playSfx("playClick")
            end
        end
    end

    local function showCommunityMaps()
        drawFrame("Community Maps")
        local w, h = getSafeSize()

        arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
        if not arcadeServerId then
            term.setTextColor(colors.red)
            term.setCursorPos(5, 5); term.write("Server Offline.")
            sleep(1.5); return
        end

        rednet.send(arcadeServerId, { type = "list_community_maps", game = gameName }, "ArcadeGames")
        local id, msg = rednet.receive("ArcadeGames", 1.2)
        if not msg or not msg.maps then
            term.setTextColor(colors.red)
            term.setCursorPos(5, 5); term.write("No maps found.")
            sleep(1.5); return
        end

        local selection = 1
        while true do
            drawFrame("Community Maps")
            
            for i, map in ipairs(msg.maps) do
                if i == selection then
                    term.setBackgroundColor(theme.highlightBg); term.setTextColor(theme.highlightText)
                else
                    term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
                end
                local label = string.format("%d. %s by %s", i, map.name, map.creator)
                term.setCursorPos(math.floor(w/2 - #label/2), 5 + i)
                term.write(label)
            end

            term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
            term.setCursorPos(2, h); term.write(" ENTER: Play | BACKSPACE/Q: Back ")

            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                if p1 == keys.up then selection = math.max(1, selection - 1); playSfx("playClick")
                elseif p1 == keys.down then selection = math.min(#msg.maps, selection + 1); playSfx("playClick")
                elseif p1 == keys.enter then
                    local selectedMap = msg.maps[selection]
                    rednet.send(arcadeServerId, { type = "get_community_map", game = gameName, filename = selectedMap.filename }, "ArcadeGames")
                    local rid, rmsg = rednet.receive("ArcadeGames", 3)
                    if rmsg and rmsg.success then
                        local originalLevel = currentLevel
                        levels[99] = { map = rmsg.map.data, name = rmsg.map.name }
                        currentLevel = 99
                        gameLoop()
                        currentLevel = originalLevel
                    end
                elseif p1 == keys.backspace or p1 == keys.q then return end
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= w - 3 then return end
                if my >= 6 and my <= 5 + #msg.maps then
                    selection = my - 5
                    local selectedMap = msg.maps[selection]
                    if selectedMap then
                        rednet.send(arcadeServerId, { type = "get_community_map", game = gameName, filename = selectedMap.filename }, "ArcadeGames")
                        local rid, rmsg = rednet.receive("ArcadeGames", 3)
                        if rmsg and rmsg.success then
                            local originalLevel = currentLevel
                            levels[99] = { map = rmsg.map.data, name = rmsg.map.name }
                            currentLevel = 99
                            gameLoop()
                            currentLevel = originalLevel
                        end
                    end
                end
            elseif event == "mouse_scroll" then
                selection = math.max(1, math.min(#msg.maps, selection + p1))
                playSfx("playClick")
            end
        end
    end

    local function gameLoop()
        loadLevel(currentLevel)
        while true do
            local ox, oy = drawBoard()
            local event, p1, p2, p3 = os.pullEvent()
            local w, h = getSafeSize()
            
            if event == "key" then
                if p1 == keys.up or p1 == keys.w then move(0, -1)
                elseif p1 == keys.down or p1 == keys.s then move(0, 1)
                elseif p1 == keys.left or p1 == keys.a then move(-1, 0)
                elseif p1 == keys.right or p1 == keys.d then move(1, 0)
                elseif p1 == keys.u or p1 == keys.z then undo()
                elseif p1 == keys.r then loadLevel(currentLevel); playTone("snare", 8, 0.7)
                elseif p1 == keys.q or p1 == keys.tab or p1 == keys.backspace then return end
            elseif event == "mouse_click" or event == "mouse_drag" then
                local mx, my = p2, p3
                -- Title Bar Close [X]
                if my == 1 and mx >= w - 3 then
                    playSfx("playClick")
                    return
                -- Bottom Bar Buttons
                elseif my == h then
                    if w >= 38 then
                        if mx >= 2 and mx <= 4 then move(-1, 0) -- [<]
                        elseif mx >= 5 and mx <= 7 then move(0, -1) -- [^]
                        elseif mx >= 8 and mx <= 10 then move(0, 1) -- [v]
                        elseif mx >= 11 and mx <= 13 then move(1, 0) -- [>]
                        elseif mx >= 16 and mx <= 21 then undo() -- [Undo]
                        elseif mx >= 23 and mx <= 30 then loadLevel(currentLevel); playTone("snare", 8, 0.7) -- [Reset]
                        elseif mx >= 32 and mx <= 38 then return -- [Menu]
                        end
                    else
                        if mx >= 1 and mx <= 3 then move(-1, 0) -- [<]
                        elseif mx >= 4 and mx <= 6 then move(0, -1) -- [^]
                        elseif mx >= 7 and mx <= 9 then move(0, 1) -- [v]
                        elseif mx >= 10 and mx <= 12 then move(1, 0) -- [>]
                        elseif mx >= 14 and mx <= 16 then undo() -- [U]
                        elseif mx >= 18 and mx <= 20 then loadLevel(currentLevel); playTone("snare", 8, 0.7) -- [R]
                        elseif mx >= 22 and mx <= 24 then return -- [M]
                        end
                    end
                -- Board Tap-to-move
                elseif ox and oy and my >= oy and my < oy + #board then
                    local bx = mx - ox + 1
                    local by = my - oy + 1
                    local dx = bx - player.x
                    local dy = by - player.y
                    if math.abs(dx) > math.abs(dy) then
                        move(dx > 0 and 1 or -1, 0)
                    elseif math.abs(dy) > 0 then
                        move(0, dy > 0 and 1 or -1)
                    end
                end
            end

            if checkWin() then
                drawBoard()
                playTone("bell", 10, 1.0)
                sleep(0.08)
                playTone("bell", 14, 1.0)
                sleep(0.08)
                playTone("chime", 18, 1.0)
                
                term.setCursorPos(math.max(1, math.floor(w/2 - 7)), math.floor(h/2))
                term.setBackgroundColor(colors.green)
                term.setTextColor(colors.white)
                term.write(" LEVEL CLEAR! ")
                sleep(1.2)
                
                currentLevel = currentLevel + 1
                if currentLevel > #levels then
                    drawFrame("Victory!")
                    term.setCursorPos(math.floor(w/2 - 8), math.floor(h/2 - 1))
                    term.setBackgroundColor(colors.blue)
                    term.setTextColor(colors.yellow)
                    term.write(" GAME COMPLETE! ")
                    local finalScore = math.max(10, 1000 - moveCount)
                    scoreCache.recordScore(gameName, finalScore, username)
                    term.setCursorPos(math.floor(w/2 - 10), math.floor(h/2 + 1))
                    term.setBackgroundColor(colors.lightGray)
                    term.setTextColor(colors.black)
                    term.write("Personal Best: " .. scoreCache.getPersonalBest(gameName))
                    playSfx("playSuccess")
                    sleep(2)
                    return
                end
                loadLevel(currentLevel)
            end
        end
    end

    -- Main Switch
    while true do
        local choice = showMenu()
        if choice == "New Game" then
            currentLevel = 1
            gameLoop()
        elseif choice == "Level Select" then
            if showLevelSelect() then gameLoop() end
        elseif choice == "Local Maps" then
            showLocalMaps()
        elseif choice == "World Builder" then
            worldBuilder()
        elseif choice == "Community Maps" then
            showCommunityMaps()
        elseif choice == "Quit" then
            return
        end
    end
end

local ok, err = pcall(mainGame, ...)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Sokoban Error: " .. err)
    os.pullEvent("key")
end
