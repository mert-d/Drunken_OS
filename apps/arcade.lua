--[[
    Drunken Arcade (v3.0)
    Unified Lobby App with Touch & Scroll Support
]]

local theme = require("lib.theme")
local utils = require("lib.utils")
local P2P_Socket = require("lib.p2p_socket")

local ok_sound, Sound = pcall(require, "lib.sound")
if not ok_sound or type(Sound) ~= "table" then
    Sound = {
        playClick = function() end,
        playSuccess = function() end
    }
end

-- Clear previous failed require cache if present
if package and package.loaded and package.loaded["lib.score_cache"] == false then
    package.loaded["lib.score_cache"] = nil
end

local ok_sc, sc = pcall(require, "lib.score_cache")
local scoreCache
if ok_sc and type(sc) == "table" then
    scoreCache = sc
else
    scoreCache = {
        loadScores = function() return {} end,
        getPersonalBest = function() return 0 end,
        getLocalLeaderboard = function() return {} end,
        recordScore = function() return false, "error" end,
        getPendingCount = function() return 0 end,
        syncPending = function() return 0, 0 end
    }
end

local arcade = {}
local arcadeVersion = 3.0

-- Human-readable game display titles
local GAME_DISPLAY_NAMES = {
    ["city.lua"] = "City Builder",
    ["Drunken_Battleship.lua"] = "Battleship",
    ["Drunken_Connect4.lua"] = "Connect 4",
    ["Drunken_Doom.lua"] = "Drunken Doom",
    ["Drunken_Duels.lua"] = "Drunken Duels",
    ["Drunken_Dungeons.lua"] = "Drunken Dungeons",
    ["Drunken_Pong.lua"] = "Neon Pong",
    ["Drunken_Sokoban.lua"] = "Sokoban Box",
    ["Drunken_Sudoku.lua"] = "Sudoku Master",
    ["Drunken_Sweeper.lua"] = "Mine Sweeper",
    ["floppa_bird.lua"] = "Floppa Bird",
    ["invaders.lua"] = "Space Invaders",
    ["snake.lua"] = "Retro Snake",
    ["tetris.lua"] = "Classic Tetris"
}

---
-- Converts a raw filename into a clean, human-readable title.
-- @param filename string: The game file name.
-- @return string: Formatted display title.
local function formatGameName(filename)
    if GAME_DISPLAY_NAMES[filename] then
        return GAME_DISPLAY_NAMES[filename]
    end
    local clean = filename:gsub("%.lua$", ""):gsub("^Drunken_", ""):gsub("_", " ")
    return clean:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function getParent(context)
    return (context and context.parent) or context or {}
end

---
-- Helper to extract version, author, and network protocol from a raw game file.
-- @param path string: File path to the game code.
-- @return table|nil: Parsed metadata {version, author, protocol}.
local function parseGameInfo(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    
    local version = tonumber(content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or content:match("[Vv]ersion:?%s*([%d%.]+)")) or 1.0
    local author_raw = content:match("by%s+([A-Z][A-Za-z%s&_]+)") or "Unknown"
    local author = author_raw:gsub("^%s*(.-)%s*$", "%1")
    if author:len() > 30 then author = author:sub(1, 30) end
    local protocol = content:match('P2P_Socket%.new%s*%(%s*".-",%s*[%d%.]+,%s*"([^"]+)"') 
                  or content:match('rednet%.host%s*%(%s*"([^"]+)"') 
                  or "Unknown"
                  
    return { version = version, author = author, protocol = protocol }
end

---
-- Main application entry point for the Drunken Arcade.
-- @param context table: The OS context providing UI and networking APIs.
function arcade.run(context)
    local selectedIdx = 1
    local scrollOffset = 0
    local games = {}
    
    local cachedLeaderboard = nil
    local cachedLobbies = nil
    local socketCache = {}
    local needsSideRefresh = true
    
    -- Resolve games directory relative to programDir
    local baseDir = (context and context.programDir) or ""
    local gamesDir = fs.combine(baseDir, "games")
    
    -- Load Games List
    local function loadGameList()
        games = {}
        if not fs.exists(gamesDir) then fs.makeDir(gamesDir) end
        local list = fs.list(gamesDir)
        for _, file in ipairs(list) do
            if file:match("%.lua$") then
                local fullPath = fs.combine(gamesDir, file)
                local info = parseGameInfo(fullPath)
                table.insert(games, {
                    name = formatGameName(file),
                    rawName = file:gsub("%.lua$", ""),
                    filename = file,
                    path = fullPath,
                    version = info and info.version or 1.0,
                    author = info and info.author or "Unknown",
                    protocol = info and info.protocol or "Unknown"
                })
            end
        end
        table.sort(games, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    
    -- Attempt to fetch games from Mainframe if none found locally
    local function syncGamesFromServer()
        local server = rednet.lookup("SimpleMail", "mail.server")
        if not server then return false end
        
        rednet.send(server, { type = "get_manifest" }, "SimpleMail")
        local _, resp = rednet.receive("SimpleMail", 3)
        if not resp or not resp.manifest then return false end
        
        local gameFiles = resp.manifest.all_games or {}
        if #gameFiles == 0 and resp.manifest.packages and resp.manifest.packages.client then
            for _, f in ipairs(resp.manifest.packages.client.files or {}) do
                if f:match("^games/") then
                    table.insert(gameFiles, f)
                end
            end
        end
        
        if #gameFiles == 0 then return false end
        
        local downloaded = 0
        for _, gamePath in ipairs(gameFiles) do
            local filename = fs.getName(gamePath)
            local localPath = fs.combine(gamesDir, filename)
            if not fs.exists(localPath) then
                rednet.send(server, { type = "get_file", path = gamePath }, "SimpleMail")
                local _, fileData = rednet.receive("SimpleMail", 3)
                if fileData and fileData.success and fileData.code then
                    if not fs.exists(gamesDir) then fs.makeDir(gamesDir) end
                    local f = fs.open(localPath, "w")
                    if f then
                        f.write(fileData.code)
                        f.close()
                        downloaded = downloaded + 1
                    end
                end
            end
        end
        return downloaded > 0
    end
    
    loadGameList()
    
    -- If no games found locally, try fetching from server
    if #games == 0 then
        if context and context.drawWindow then
            context.drawWindow("Drunken Arcade")
        else
            utils.drawWindow("DRUNKEN ARCADE", context)
        end
        term.setCursorPos(2, 4)
        term.setTextColor(theme.text)
        term.write("No games found. Syncing from server...")
        if syncGamesFromServer() then
            loadGameList()
        end
    end
    
    local function fetchSideData(game)
        cachedLeaderboard = nil
        cachedLobbies = nil
        if not game then return end
        
        -- Get Leaderboard
        local server = rednet.lookup("ArcadeGames", "arcade.server")
        if server then
            rednet.send(server, { type = "get_board", game = game.filename }, "ArcadeGames")
            local _, msg = rednet.receive("ArcadeGames", 0.05)
            if msg and msg.type == "leaderboard_response" and msg.game == game.filename then
                cachedLeaderboard = msg.board
            end
        end

        if not cachedLeaderboard or #cachedLeaderboard == 0 then
            local localBests = scoreCache.getLocalLeaderboard(game.filename)
            if #localBests > 0 then
                cachedLeaderboard = {}
                for _, b in ipairs(localBests) do
                    table.insert(cachedLeaderboard, { user = b.user, score = b.score, isLocal = true })
                end
            end
        end

        -- Get Lobbies
        if game.protocol and game.protocol ~= "Unknown" then
            local socket = socketCache[game.filename]
            if not socket then
                socket = P2P_Socket.new(game.filename, game.version, game.protocol)
                socketCache[game.filename] = socket
            end
            local lobbies = socket:findLobbies()
            cachedLobbies = lobbies or {}
        else
            cachedLobbies = {}
        end
    end
    
    local function launchGame(game, extraArg1, extraArg2)
        if not game then return end
        if Sound and Sound.playClick then Sound.playClick() end
        if context and context.clear then context.clear() end
        local run_shell = (context and context.shell) or _G.shell
        if run_shell then
            local user = getParent(context).username
            local ok, err
            if extraArg1 then
                ok, err = pcall(run_shell.run, game.path, user, extraArg1, extraArg2)
            else
                ok, err = pcall(run_shell.run, game.path, user)
            end
            if not ok and err then
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.red)
                if context and context.showMessage then
                    pcall(context.showMessage, "Game Error", tostring(err):sub(1, 60))
                end
            end
        end
        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.text)
        term.clear()
    end

    local function promptJoinId(game)
        if not game then return end
        local w, h = term.getSize()
        local isPocket = (w <= 30)
        local inputY = isPocket and (h - 2) or 17
        local inputX = isPocket and 2 or 23
        term.setCursorPos(inputX, inputY)
        term.setTextColor(theme.prompt or colors.cyan)
        term.write("Join ID: ")
        term.setTextColor(theme.text or colors.white)
        term.setCursorBlink(true)
        local idStr = read()
        term.setCursorBlink(false)
        local id = tonumber(idStr)
        
        local targetLobby = nil
        for _, l in ipairs(cachedLobbies or {}) do
            if l.id == id then targetLobby = l; break end
        end
        
        if targetLobby then
            launchGame(game, "join", tostring(id))
        else
            if context and context.showMessage then
                context.showMessage("Lobby Join Error", "Lobby ID " .. (idStr or "nil") .. " not found.")
            end
        end
    end

    -- Initial side data fetch on desktop
    local w, h = term.getSize()
    if #games > 0 and w > 30 then
        fetchSideData(games[1])
        needsSideRefresh = false
    end

    while true do
        w, h = term.getSize()
        local isPocket = (w <= 30)
        
        if context and context.drawWindow then
            context.drawWindow("Drunken Arcade")
        else
            utils.drawWindow("DRUNKEN ARCADE", context)
        end
        
        local listStartY = 3
        local footerH = isPocket and 3 or 2
        local listHeight = math.max(4, h - listStartY - footerH)
        local colW = isPocket and (w - 3) or 20
        local scrollBarX = colW + 2
        
        -- Clamp selection & scroll offset
        if selectedIdx < 1 then selectedIdx = 1 end
        if selectedIdx > #games then selectedIdx = #games end
        if selectedIdx <= scrollOffset then
            scrollOffset = selectedIdx - 1
        elseif selectedIdx > scrollOffset + listHeight then
            scrollOffset = selectedIdx - listHeight
        end
        if scrollOffset < 0 then scrollOffset = 0 end
        local maxScroll = math.max(0, #games - listHeight)
        if scrollOffset > maxScroll then scrollOffset = maxScroll end

        -- Fetch side data on desktop if selection changed
        if not isPocket and needsSideRefresh and games[selectedIdx] then
            fetchSideData(games[selectedIdx])
            needsSideRefresh = false
        end

        -- Draw Games List
        for i = 1, listHeight do
            local idx = scrollOffset + i
            local y = listStartY + i - 1
            term.setCursorPos(2, y)
            if idx <= #games then
                local g = games[idx]
                local isSel = (idx == selectedIdx)
                if isSel then
                    term.setTextColor(theme.highlightText or colors.black)
                    term.setBackgroundColor(theme.highlightBg or colors.cyan)
                else
                    term.setTextColor(theme.text or colors.white)
                    term.setBackgroundColor(theme.bg or colors.black)
                end
                
                local prefix = isSel and "> " or "  "
                local availW = colW - #prefix
                local title = g.name
                if #title > availW then
                    title = title:sub(1, math.max(1, availW - 1)) .. "."
                end
                local line = prefix .. title .. string.rep(" ", math.max(0, availW - #title))
                term.write(line)
            else
                term.setBackgroundColor(theme.bg or colors.black)
                term.write(string.rep(" ", colW))
            end
        end

        -- Draw Scrollbar if list overflows
        if #games > listHeight then
            term.setBackgroundColor(theme.bg or colors.black)
            -- Up arrow
            term.setCursorPos(scrollBarX, listStartY)
            term.setTextColor(scrollOffset > 0 and (theme.accent or colors.yellow) or (theme.mutedText or colors.gray))
            term.write("^")
            
            -- Track & Knob
            local trackH = math.max(1, listHeight - 2)
            local progress = (#games > 1) and ((selectedIdx - 1) / (#games - 1)) or 0
            local knobRel = math.floor(progress * (trackH - 1) + 0.5)
            
            for ty = 1, trackH do
                term.setCursorPos(scrollBarX, listStartY + ty)
                if (ty - 1) == knobRel then
                    term.setTextColor(theme.accent or colors.yellow)
                    term.write("#")
                else
                    term.setTextColor(theme.mutedText or colors.gray)
                    term.write("|")
                end
            end
            
            -- Down arrow
            term.setCursorPos(scrollBarX, listStartY + listHeight - 1)
            term.setTextColor((scrollOffset + listHeight < #games) and (theme.accent or colors.yellow) or (theme.mutedText or colors.gray))
            term.write("v")
        end

        if not isPocket then
            -- DESKTOP LAYOUT (Split Screen)
            -- Separator bar
            local sepX = scrollBarX + 1
            term.setBackgroundColor(theme.bg or colors.black)
            term.setTextColor(theme.mutedText or colors.gray)
            for i = 3, h - 2 do
                term.setCursorPos(sepX, i)
                term.write("|")
            end
            
            -- Right Column: Details
            local game = games[selectedIdx]
            if game then
                local xBase = sepX + 2
                
                -- Title & Info
                term.setTextColor(theme.accent or colors.yellow)
                term.setCursorPos(xBase, 3)
                term.write(game.name)
                
                term.setTextColor(theme.mutedText or colors.gray)
                term.setCursorPos(xBase, 4)
                term.write("v" .. tostring(game.version) .. " by " .. tostring(game.author))
                
                -- Leaderboard
                term.setTextColor(theme.prompt or colors.cyan)
                term.setCursorPos(xBase, 6)
                term.write("Top Scores:")
                
                term.setTextColor(theme.text or colors.white)
                if cachedLeaderboard == "offline" then
                    term.setCursorPos(xBase, 7)
                    term.setTextColor(theme.errorText or colors.red)
                    term.write("Server Offline")
                elseif cachedLeaderboard and #cachedLeaderboard > 0 then
                    local rankColors = {
                        [1] = theme.accent or colors.yellow,
                        [2] = colors.lightGray or colors.white,
                        [3] = colors.orange or colors.white,
                        [4] = theme.text or colors.white
                    }
                    for k = 1, 4 do
                        if cachedLeaderboard[k] then
                            term.setCursorPos(xBase, 6 + k)
                            local s = cachedLeaderboard[k]
                            term.setTextColor(rankColors[k] or theme.text or colors.white)
                            local userShort = tostring(s.user or "Player"):sub(1, 8)
                            term.write(string.format("%d. %-8s (%d)", k, userShort, s.score or 0))
                        end
                    end
                else
                    term.setCursorPos(xBase, 7)
                    term.setTextColor(theme.mutedText or colors.gray)
                    term.write("No scores recorded.")
                end
                
                -- Active Lobbies
                term.setTextColor(theme.prompt or colors.cyan)
                term.setCursorPos(xBase, 12)
                term.write("Active Lobbies:")
                
                if cachedLobbies and #cachedLobbies > 0 then
                    for k = 1, 3 do
                        if cachedLobbies[k] then
                            term.setCursorPos(xBase, 12 + k)
                            local lob = cachedLobbies[k]
                            term.setTextColor(theme.text or colors.white)
                            term.write(string.format("[%d] %s", lob.id, tostring(lob.user):sub(1, 10)))
                        end
                    end
                    term.setTextColor(theme.mutedText or colors.gray)
                    term.setCursorPos(xBase, 16)
                    term.write("Click lobby or [J] to Join")
                else
                    term.setCursorPos(xBase, 13)
                    term.setTextColor(theme.mutedText or colors.gray)
                    term.write("No matches found.")
                end
            end
        else
            -- MOBILE LAYOUT (Pocket Computer)
            local game = games[selectedIdx]
            if game then
                term.setCursorPos(2, h - 2)
                term.setTextColor(theme.accent or colors.yellow)
                local info = game.name .. " (v" .. tostring(game.version) .. ")"
                if #info > w - 3 then info = info:sub(1, w - 4) .. "." end
                term.write(info)
            end
        end
        
        -- Controls Footer
        term.setBackgroundColor(theme.bg or colors.black)
        term.setCursorPos(2, h - 1)
        if isPocket then
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("[Play]")
            term.setTextColor(theme.mutedText or colors.gray)
            term.write(" Tap/Enter")
            term.setCursorPos(math.max(18, w - 9), h - 1)
            term.setTextColor(theme.mutedText or colors.gray)
            term.write("[Q:Exit]")
        else
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("[Enter]")
            term.setTextColor(theme.text or colors.white)
            term.write(" Play  ")
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("[L]")
            term.setTextColor(theme.text or colors.white)
            term.write(" Refresh  ")
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("[J]")
            term.setTextColor(theme.text or colors.white)
            term.write(" Join  ")
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("[Q]")
            term.setTextColor(theme.text or colors.white)
            term.write(" Exit")
        end
        
        -- Event Handling (Keyboard, Mouse Click, Mouse Scroll, Mouse Drag)
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "key" then
            local key = p1
            if key == keys.up then
                if selectedIdx > 1 then
                    selectedIdx = selectedIdx - 1
                    needsSideRefresh = true
                    if Sound and Sound.playClick then Sound.playClick() end
                end
            elseif key == keys.down then
                if selectedIdx < #games then
                    selectedIdx = selectedIdx + 1
                    needsSideRefresh = true
                    if Sound and Sound.playClick then Sound.playClick() end
                end
            elseif key == keys.pageUp then
                if selectedIdx > 1 then
                    selectedIdx = math.max(1, selectedIdx - listHeight)
                    needsSideRefresh = true
                    if Sound and Sound.playClick then Sound.playClick() end
                end
            elseif key == keys.pageDown then
                if selectedIdx < #games then
                    selectedIdx = math.min(#games, selectedIdx + listHeight)
                    needsSideRefresh = true
                    if Sound and Sound.playClick then Sound.playClick() end
                end
            elseif key == keys.home then
                selectedIdx = 1
                needsSideRefresh = true
                if Sound and Sound.playClick then Sound.playClick() end
            elseif key == keys.keysEnd or key == keys["end"] then
                selectedIdx = #games
                needsSideRefresh = true
                if Sound and Sound.playClick then Sound.playClick() end
            elseif key == keys.enter or key == keys.space then
                launchGame(games[selectedIdx])
                needsSideRefresh = true
            elseif key == keys.l then
                needsSideRefresh = true
            elseif key == keys.j and games[selectedIdx] then
                promptJoinId(games[selectedIdx])
                needsSideRefresh = true
            elseif key == keys.q or key == keys.tab or key == keys.x then
                break
            end
            
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir < 0 then
                if selectedIdx > 1 then
                    selectedIdx = selectedIdx - 1
                    needsSideRefresh = true
                    if Sound and Sound.playClick then Sound.playClick() end
                end
            else
                if selectedIdx < #games then
                    selectedIdx = selectedIdx + 1
                    needsSideRefresh = true
                    if Sound and Sound.playClick then Sound.playClick() end
                end
            end
            
        elseif event == "mouse_click" or event == "mouse_drag" then
            local btn, clickX, clickY = p1, p2, p3
            
            -- Title bar close button (top right [X])
            if clickY == 1 and clickX >= w - 3 then
                break
            end
            
            -- Click on left Game List
            if clickX >= 2 and clickX <= colW + 1 and clickY >= listStartY and clickY < listStartY + listHeight then
                local clickedIdx = scrollOffset + (clickY - listStartY + 1)
                if clickedIdx >= 1 and clickedIdx <= #games then
                    if event == "mouse_click" and selectedIdx == clickedIdx then
                        -- Double-tap / tap already selected item: Launch game!
                        launchGame(games[selectedIdx])
                        needsSideRefresh = true
                    else
                        selectedIdx = clickedIdx
                        needsSideRefresh = true
                        if Sound and Sound.playClick then Sound.playClick() end
                    end
                end
                
            -- Click on Scrollbar
            elseif #games > listHeight and clickX == scrollBarX then
                if clickY == listStartY then
                    if selectedIdx > 1 then
                        selectedIdx = selectedIdx - 1
                        needsSideRefresh = true
                        if Sound and Sound.playClick then Sound.playClick() end
                    end
                elseif clickY == listStartY + listHeight - 1 then
                    if selectedIdx < #games then
                        selectedIdx = selectedIdx + 1
                        needsSideRefresh = true
                        if Sound and Sound.playClick then Sound.playClick() end
                    end
                else
                    -- Jump to clicked position on track
                    local trackH = math.max(1, listHeight - 2)
                    local relY = clickY - (listStartY + 1)
                    local ratio = math.min(1, math.max(0, relY / (trackH - 1)))
                    selectedIdx = math.min(#games, math.max(1, math.floor(ratio * (#games - 1) + 1.5)))
                    needsSideRefresh = true
                    if Sound and Sound.playClick then Sound.playClick() end
                end
                
            -- Click on Desktop Right Pane
            elseif not isPocket and clickX >= colW + 4 and games[selectedIdx] then
                if clickY >= 13 and clickY <= 15 then
                    local lobIdx = clickY - 12
                    if cachedLobbies and cachedLobbies[lobIdx] then
                        launchGame(games[selectedIdx], "join", tostring(cachedLobbies[lobIdx].id))
                        needsSideRefresh = true
                    end
                elseif clickY == 16 then
                    promptJoinId(games[selectedIdx])
                    needsSideRefresh = true
                end
                
            -- Click on Footer Controls
            elseif clickY == h - 1 then
                if isPocket then
                    if clickX <= 14 then
                        launchGame(games[selectedIdx])
                        needsSideRefresh = true
                    elseif clickX >= math.max(16, w - 10) then
                        break
                    end
                else
                    if clickX >= 2 and clickX <= 14 then
                        launchGame(games[selectedIdx])
                        needsSideRefresh = true
                    elseif clickX >= 16 and clickX <= 28 then
                        needsSideRefresh = true
                    elseif clickX >= 30 and clickX <= 38 and games[selectedIdx] then
                        promptJoinId(games[selectedIdx])
                        needsSideRefresh = true
                    elseif clickX >= 40 and clickX <= 48 then
                        break
                    end
                end
            end
        end
    end
end

return arcade
