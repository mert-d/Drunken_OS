--[[
    Drunken Sokoban (v1.0)
    by Gemini Gem

    Purpose:
    A classic box-pushing puzzle for Drunken OS.
    Push all crates onto the target spots to win!
]]

local gameVersion = 1.2

local function mainGame(...)
    local args = {...}
    local username = args[1] or "Guest"

    local gameName = "DrunkenSokoban"
    local arcadeServerId = nil

    -- Theme & Colors
    local hasColor = term.isColor and term.isColor()
    local function safeColor(c, f) return (hasColor and colors[c]) and colors[c] or f end

    local theme = {
        bg = colors.black,
        text = colors.white,
        border = colors.cyan,
        player = safeColor("yellow", colors.white),
        box = safeColor("orange", colors.brown),
        target = safeColor("lime", colors.green),
        wall = safeColor("gray", colors.lightGray),
        boxOnTarget = safeColor("green", colors.lime),
        highlightBg = colors.blue,
        highlightText = colors.white,
        prompt = colors.yellow,
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
            return true
        end
        return false
    end

    local function drawFrame()
        local w, h = getSafeSize()
        term.setBackgroundColor(theme.bg); term.clear()
        term.setBackgroundColor(theme.border)
        term.setCursorPos(1, 1); term.write(string.rep(" ", w))
        term.setCursorPos(1, h); term.write(string.rep(" ", w))
        for i = 2, h - 1 do
            term.setCursorPos(1, i); term.write(" ")
            term.setCursorPos(w, i); term.write(" ")
        end
        term.setCursorPos(1, 1); term.setTextColor(theme.text)
        local title = " Drunken Sokoban v" .. gameVersion .. " "
        term.setCursorPos(math.floor((w - #title)/2), 1); term.write(title)
    end

    local function drawBoard()
        drawFrame()
        local w, h = getSafeSize()
        local lvl = levels[currentLevel]
        local mh = #board
        local mw = 0
        for _, r in ipairs(board) do mw = math.max(mw, #r) end

        local ox = math.floor((w - mw) / 2)
        local oy = math.floor((h - mh) / 2)

        for y, row in ipairs(board) do
            term.setCursorPos(ox, oy + y - 1)
            for x, char in ipairs(row) do
                local fg = theme.text
                local bg = theme.bg
                local display = char

                if x == player.x and y == player.y then
                    display = "@"
                    fg = theme.player
                elseif char == "#" then
                    fg = theme.wall
                elseif char == "X" then
                    fg = theme.box
                elseif char == "." then
                    fg = theme.target
                elseif char == "Y" then -- Box on target
                    display = "X"
                    fg = theme.boxOnTarget
                end

                term.setTextColor(fg)
                term.write(display)
            end
        end

        term.setTextColor(theme.text)
        term.setCursorPos(2, h-2); term.write("Level: " .. currentLevel .. " | Moves: " .. moveCount)
        term.setCursorPos(math.floor(w/2 - 15), h)
        term.setBackgroundColor(theme.border); term.write(" ARROWS: Move | U: Undo | R: Restart | Q: Quit ")
    end

    local function move(dx, dy)
        local nx, ny = player.x + dx, player.y + dy
        local target = board[ny] and board[ny][nx]

        if not target or target == "#" then return end -- Wall or OOB

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
            end
        else
            pushHistory()
            -- Normal move
            player.x, player.y = nx, ny
            moveCount = moveCount + 1
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
            drawFrame()
            local w, h = getSafeSize()
            term.setTextColor(theme.prompt)
            term.setCursorPos(math.floor(w/2 - 5), 5)
            term.write("MAIN MENU")

            for i, opt in ipairs(options) do
                if i == selection then
                    term.setBackgroundColor(theme.highlightBg)
                    term.setTextColor(theme.highlightText)
                else
                    term.setBackgroundColor(theme.bg)
                    term.setTextColor(theme.text)
                end
                term.setCursorPos(math.floor(w/2 - #opt/2), 7 + i)
                term.write(opt)
            end

            local event, key = os.pullEvent("key")
            if key == keys.up then selection = math.max(1, selection - 1)
            elseif key == keys.down then selection = math.min(#options, selection + 1)
            elseif key == keys.enter then return options[selection]
            elseif key == keys.q then return "Quit" end
        end
    end

    local function showLevelSelect()
        local selection = 1
        local scroll = 0
        local maxVisible = 10
        while true do
            drawFrame()
            local w, h = getSafeSize()
            term.setTextColor(theme.prompt)
            term.setCursorPos(math.floor(w/2 - 6), 3)
            term.write("LEVEL SELECT")

            for i = 1, maxVisible do
                local idx = i + scroll
                if idx > #levels then break end
                local lvl = levels[idx]
                
                if idx == selection then
                    term.setBackgroundColor(theme.highlightBg)
                    term.setTextColor(theme.highlightText)
                else
                    term.setBackgroundColor(theme.bg)
                    term.setTextColor(theme.text)
                end
                local label = string.format("%d. %s", idx, lvl.name)
                term.setCursorPos(math.floor(w/2 - #label/2), 5 + i)
                term.write(label)
            end

            term.setBackgroundColor(theme.bg); term.setTextColor(colors.gray)
            term.setCursorPos(2, h); term.write(" ARROWS: Scroll | ENTER: Play | Q: Back ")

            local event, key = os.pullEvent("key")
            if key == keys.up then 
                selection = math.max(1, selection - 1)
                if selection <= scroll then scroll = math.max(0, scroll - 1) end
            elseif key == keys.down then 
                selection = math.min(#levels, selection + 1)
                if selection > scroll + maxVisible then scroll = math.min(#levels - maxVisible, scroll + 1) end
            elseif key == keys.enter then currentLevel = selection; return true
            elseif key == keys.backspace or key == keys.q then return false end
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

            local event, key = os.pullEvent("key")
            if key == keys.up then sizeSelection = math.max(1, sizeSelection - 1)
            elseif key == keys.down then sizeSelection = math.min(#sizes, sizeSelection + 1)
            elseif key == keys.enter then
                ew, eh = sizes[sizeSelection].w, sizes[sizeSelection].h
                break
            elseif key == keys.q or key == keys.backspace then return end
        end

        local editorBoard = {}
        local cx, cy = 1, 1
        local brush = "#" -- Default brush: Wall
        local brushes = { "#", "X", ".", "@", " " }
        local brushNames = { ["#"] = "Wall", ["X"] = "Box", ["."] = "Target", ["@"] = "Player", [" "] = "Empty" }

        for y = 1, eh do editorBoard[y] = {}; for x = 1, ew do editorBoard[y][x] = " " end end

        local function drawEditor()
            drawFrame()
            local w, h = getSafeSize()
            local ox = math.floor((w - ew) / 2)
            local oy = math.floor((h - eh) / 2)

            for y, row in ipairs(editorBoard) do
                term.setCursorPos(ox, oy + y - 1)
                for x, char in ipairs(row) do
                    local fg, bg = theme.text, theme.bg
                    if x == cx and y == cy then bg = theme.highlightBg; fg = theme.highlightText end
                    
                    if char == "#" then fg = theme.wall
                    elseif char == "X" then fg = theme.box
                    elseif char == "." then fg = theme.target
                    elseif char == "@" then fg = theme.player end

                    term.setTextColor(fg); term.setBackgroundColor(bg)
                    term.write(char)
                end
            end

            term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
            term.setCursorPos(2, h-2); term.write("Brush: " .. (brushNames[brush] or brush) .. " (1-5 to change)")
            term.setCursorPos(math.floor(w/2 - 20), h)
            term.setBackgroundColor(theme.border); term.write(" ARROWS: Move | SPACE: Place | S: Save | P: Publish | Q: Exit ")
        end

        while true do
            drawEditor()
            local event, key = os.pullEvent()
            if event == "key" then
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
                    sleep(1.5)
                elseif key == keys.q then return end
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

            local event, key = os.pullEvent("key")
            if key == keys.up then 
                selection = math.max(1, selection - 1)
                if selection <= scroll then scroll = math.max(0, scroll - 1) end
            elseif key == keys.down then 
                selection = math.min(#maps, selection + 1)
                if selection > scroll + maxVisible then scroll = math.min(#maps - maxVisible, scroll + 1) end
            elseif key == keys.enter then
                local selected = maps[selection]
                local originalLevel = currentLevel
                levels[100] = { map = selected.data, name = selected.name }
                currentLevel = 100
                gameLoop()
                currentLevel = originalLevel
            elseif key == keys.backspace or key == keys.q then return end
        end
    end

    local function showCommunityMaps()
        drawFrame()
        local w, h = getSafeSize()
        term.setTextColor(theme.prompt)
        term.setCursorPos(math.floor(w/2 - 7), 3)
        term.write("COMMUNITY MAPS")

        arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
        if not arcadeServerId then
            term.setTextColor(colors.red)
            term.setCursorPos(5, 5); term.write("Server Offline.")
            sleep(1.5); return
        end

        rednet.send(arcadeServerId, { type = "list_community_maps", game = gameName }, "ArcadeGames")
        local id, msg = rednet.receive("ArcadeGames", 3)
        if not msg or not msg.maps then
            term.setTextColor(colors.red)
            term.setCursorPos(5, 5); term.write("No maps found.")
            sleep(1.5); return
        end

        local selection = 1
        while true do
            drawFrame()
            term.setTextColor(theme.prompt)
            term.setCursorPos(math.floor(w/2 - 7), 3); term.write("COMMUNITY MAPS")
            
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

            local event, key = os.pullEvent("key")
            if key == keys.up then selection = math.max(1, selection - 1)
            elseif key == keys.down then selection = math.min(#msg.maps, selection + 1)
            elseif key == keys.enter then
                local selectedMap = msg.maps[selection]
                rednet.send(arcadeServerId, { type = "get_community_map", game = gameName, filename = selectedMap.filename }, "ArcadeGames")
                local rid, rmsg = rednet.receive("ArcadeGames", 3)
                if rmsg and rmsg.success then
                    -- Play the map
                    local originalLevel = currentLevel
                    levels[99] = { map = rmsg.map.data, name = rmsg.map.name }
                    currentLevel = 99
                    gameLoop()
                    currentLevel = originalLevel
                end
            elseif key == keys.backspace or key == keys.q then return end
        end
    end

    local function gameLoop()
        loadLevel(currentLevel)
        while true do
            drawBoard()
            local event, key = os.pullEvent("key")
            if key == keys.up then move(0, -1)
            elseif key == keys.down then move(0, 1)
            elseif key == keys.left then move(-1, 0)
            elseif key == keys.right then move(1, 0)
            elseif key == keys.u then undo()
            elseif key == keys.r then loadLevel(currentLevel)
            elseif key == keys.q then return end

            if checkWin() then
                local w, h = getSafeSize()
                drawBoard()
                term.setCursorPos(1, h-1); print("Level Clear!")
                sleep(1)
                currentLevel = currentLevel + 1
                if currentLevel > #levels then
                    print("Game Complete!")
                    arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
                    if arcadeServerId then
                        rednet.send(arcadeServerId, {type = "submit_score", game = gameName, user = username, score = 1000 - moveCount}, "ArcadeGames")
                    end
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
