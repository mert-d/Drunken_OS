--[[
    Drunken Arcade (v2.0)
    Unified Lobby App
]]

local theme = require("lib.theme")
local utils = require("lib.utils")
local P2P_Socket = require("lib.p2p_socket")
local arcade = {}
local arcadeVersion = 2.1 -- Bumped for crash fixes

local function getParent(context)
    return context.parent
end

local function parseGameInfo(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local content = f.readAll()
    f.close()
    
    local version = tonumber(content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")) or 1.0
    local author = content:match("%-%-%s*by%s+([%w%s]+)") or "Unknown"
    local protocol = content:match('P2P_Socket%.new%s*%(%s*".-",%s*[%d%.]+,%s*"([^"]+)"') 
                  or content:match('rednet%.host%s*%(%s*"([^"]+)"') 
                  or "Unknown"
                  
    return { version = version, author = author, protocol = protocol }
end

function arcade.run(context)
    local w, h = term.getSize()
    local selectedIdx = 1
    local scrollOffset = 0
    local games = {}
    
    local selectedGameData = nil
    local lastFetchTime = 0
    local cachedLeaderboard = nil
    local cachedLobbies = nil
    
    -- Load Games List
    if not fs.exists("games") then fs.makeDir("games") end
    local list = fs.list("games")
    for _, file in ipairs(list) do
        if file:match("%.lua$") then
            local info = parseGameInfo("games/" .. file)
            table.insert(games, {
                name = file:gsub("%.lua$", ""):gsub("_", " "),
                filename = file,
                path = "games/" .. file,
                version = info.version,
                author = info.author,
                protocol = info.protocol
            })
        end
    end
    table.sort(games, function(a,b) return a.name < b.name end)
    
    local function fetchSideData(game)
        cachedLeaderboard = nil
        cachedLobbies = nil
        
        -- Get Leaderboard
        local server = rednet.lookup("ArcadeGames", "arcade.server")
        if server then
            rednet.send(server, {type="get_board", game=game.filename}, "ArcadeGames")
            -- We don't wait here to avoid blocking UI too much, we check messages in loop
            -- actually, for simplicity in v2.0, let's just do a quick peek-receive or standard receive with short timeout
            local id, msg = rednet.receive("ArcadeGames", 0.2)
            if msg and msg.type == "leaderboard_response" and msg.game == game.filename then
                cachedLeaderboard = msg.board
            end
        else
            cachedLeaderboard = "offline"
        end
        
        -- Get Lobbies
        -- Use P2P Socket logic (emulated or direct)
        -- We instantiate a temporary socket to use its findLobbies logic if possible, 
        -- but P2P_Socket requires protocol. We parsed it!
        if game.protocol and game.protocol ~= "Unknown" then
            local tempSocket = P2P_Socket.new(game.filename, game.version, game.protocol)
            local lobbies, err = tempSocket:findLobbies()
            cachedLobbies = lobbies or {}
        else
            cachedLobbies = {} -- Cannot scan without protocol
        end
    end
    
    -- Initial Fetch
    if #games > 0 then fetchSideData(games[1]) end

    while true do
        utils.drawWindow("DRUNKEN ARCADE", context)
        
        -- Draw Layout
        -- Left Column: Game List
        -- x=2, y=3, w=20, h=14
        term.setBackgroundColor(theme.windowBg or colors.black)
        for i = 1, 14 do
            local idx = scrollOffset + i
            if idx <= #games then
                term.setCursorPos(2, 2 + i)
                if idx == selectedIdx then
                    term.setTextColor(theme.highlightText)
                    term.setBackgroundColor(theme.highlightBg)
                else
                    term.setTextColor(theme.text)
                    term.setBackgroundColor(theme.bg)
                end
                local name = games[idx].name
                if #name > 18 then name = name:sub(1,15).."..." end
                term.write( " " .. name .. string.rep(" ", 18 - #name) )
            end
        end
        
        if w > 30 then
            -- DESKTOP LAYOUT (Split Screen)
            
            -- Separator
            term.setBackgroundColor(theme.bg)
            term.setTextColor(colors.gray)
            for i=3, h-2 do
                term.setCursorPos(21, i); term.write("|")
            end
            
            -- Right Column: Details
            local game = games[selectedIdx]
            if game then
                local xBase = 23
                
                -- Info
                term.setTextColor(theme.prompt)
                term.setCursorPos(xBase, 3); term.write(game.name)
                term.setTextColor(colors.gray)
                term.setCursorPos(xBase, 4); term.write("v" .. game.version .. " by " .. game.author)
                
                -- Leaderboard
                term.setTextColor(theme.prompt)
                term.setCursorPos(xBase, 6); term.write("Top Scores:")
                term.setTextColor(theme.text)
                if cachedLeaderboard == "offline" then
                    term.setCursorPos(xBase, 7); term.setTextColor(theme.errorText or colors.red); term.write("Server Offline")
                elseif cachedLeaderboard and #cachedLeaderboard > 0 then
                    for k=1, 4 do
                        if cachedLeaderboard[k] then
                            term.setCursorPos(xBase, 6+k)
                            local s = cachedLeaderboard[k]
                            term.write(string.format("%d. %s (%d)", k, s.user:sub(1,8), s.score))
                        end
                    end
                else
                    term.setCursorPos(xBase, 7); term.write("No scores yet.")
                end
                
                -- Active Lobbies
                term.setTextColor(theme.prompt)
                term.setCursorPos(xBase, 12); term.write("Active Lobbies:")
                term.setTextColor(theme.text)
                if cachedLobbies and #cachedLobbies > 0 then
                     for k=1, 3 do
                        if cachedLobbies[k] then
                            term.setCursorPos(xBase, 12+k)
                            local lob = cachedLobbies[k]
                            term.write(string.format("[%d] %s", lob.id, lob.user))
                        end
                    end
                    term.setTextColor(colors.gray)
                    term.setCursorPos(xBase, 16); term.write("Press J to Join ID")
                else
                    term.setCursorPos(xBase, 13); term.write("No matches found.")
                end
            end
        else
            -- MOBILE LAYOUT (Pocket Computer)
            -- Just show the list, and maybe basic info for selected item at bottom
             local game = games[selectedIdx]
             if game then
                term.setCursorPos(2, h-2)
                term.setTextColor(colors.gray)
                term.write(game.name .. " v" .. game.version)
             end
        end
        
        -- Controls Footer
        term.setCursorPos(2, 18)
        term.setTextColor(colors.gray)
        term.write("[ENTER] Play  [L] Refresh  [Q] Quit")
        
        -- Input Handling
        local event, p1 = os.pullEvent("key")
        if p1 == keys.up then
            if selectedIdx > 1 then 
                selectedIdx = selectedIdx - 1
                if selectedIdx < scrollOffset + 1 then scrollOffset = scrollOffset - 1 end
                fetchSideData(games[selectedIdx])
            end
        elseif p1 == keys.down then
            if selectedIdx < #games then 
                selectedIdx = selectedIdx + 1
                if selectedIdx > scrollOffset + 14 then scrollOffset = scrollOffset + 1 end
                fetchSideData(games[selectedIdx])
            end
        elseif p1 == keys.enter then
            -- Launch Game
            context.clear()
            local run_shell = context.shell or _G.shell
            if run_shell then
                 -- Pass username and any other standard args
                 run_shell.run(game.path, getParent(context).username)
            end
            -- Redraw on return
        elseif p1 == keys.l then
            fetchSideData(games[selectedIdx])
        elseif p1 == keys.j and cachedLobbies and #cachedLobbies > 0 then
             -- Simple Join via ID input
             term.setCursorPos(23, 17)
             term.write("Join ID: ")
             term.setCursorBlink(true)
             local idStr = read()
             term.setCursorBlink(false)
             local id = tonumber(idStr)
             
             local targetLobby = nil
             for _, l in ipairs(cachedLobbies) do if l.id == id then targetLobby = l break end end
             
             if targetLobby then
                 context.clear()
                 local run_shell = context.shell or _G.shell
                 -- Launch with connect args: game.lua username connect <hostID>
                 run_shell.run(game.path, getParent(context).username, "connect", tostring(id))
             end
        elseif p1 == keys.q or p1 == keys.tab then
            break
        end
    end
end

return arcade
