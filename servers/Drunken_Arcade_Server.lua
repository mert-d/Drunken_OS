--[[
    Drunken Arcade Server (v1.3 - Premium UI)
    by MuhendizBey

    Purpose:
    Dedicated hardware offload for Drunken OS Arcade operations.
    Handles global leaderboards and centralized P2P matchmaking lobbies.
    Designed to run on a separate computer connected via Wired Modem.
]]

--==============================================================================
-- Environment Setup
--==============================================================================
package.path = "/?.lua;" .. package.path

local GAMES_DB = "games.db"
local LOG_FILE = "arcade.log"
local GITHUB_GAMES_URL = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/games/"

--==============================================================================
-- Utility Functions
--==============================================================================

local logHistory = {}
local arcadeLobbies = {} -- { [id] = { user = "name", game = "Game" } }

local hasColor = term.isColor and term.isColor()
local theme = {
    bg = colors.black,
    windowBg = colors.black,
    title = colors.cyan,
    text = colors.white,
    prompt = colors.lime,
    statusBarBg = colors.gray,
    statusBarText = colors.white,
    highlightBg = colors.blue,
    highlightText = colors.white,
    error = colors.red,
}

local currentScreen = "dashboard" -- "dashboard", "logs"
local needsRedraw = true
local startTime = os.time()

local function saveTableToFile(path, data)
    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serialize(data))
        f.close()
        return true
    end
    return false
end

local function loadTableFromFile(path)
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data or {}
    end
    return {}
end

local function logActivity(msg, isErr)
    local timestamp = os.date("%H:%M:%S")
    local entry = string.format("[%s] %s%s", timestamp, isErr and "[ERROR] " or "", msg)
    table.insert(logHistory, entry)
    if #logHistory > 200 then table.remove(logHistory, 1) end
    
    -- Persistent Log
    if not fs.exists("logs") then fs.makeDir("logs") end
    local f = fs.open(LOG_FILE, "a")
    if f then f.writeLine(entry); f.close() end
    needsRedraw = true
end

local function drawWindow(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg); term.clear()
    
    -- Title Bar
    term.setBackgroundColor(theme.title)
    term.setCursorPos(1, 1); term.write(string.rep(" ", w))
    term.setTextColor(colors.black)
    local titleText = " " .. (title or "DRUNKEN ARCADE SERVER") .. " "
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, 1); term.write(titleText)
    
    -- Status Bar
    term.setBackgroundColor(theme.statusBarBg)
    term.setCursorPos(1, h); term.write(string.rep(" ", w))
    term.setTextColor(theme.statusBarText)
    local footer = "[D] Dash | [L] Logs | [S] Sync | [ENTER] Cmd"
    term.setCursorPos(math.floor((w - #footer) / 2) + 1, h); term.write(footer)

    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
end

local function drawDashboard()
    drawWindow("ARCADE DASHBOARD")
    local w, h = term.getSize()
    
    term.setTextColor(theme.prompt)
    term.setCursorPos(2, 3); term.write("System Status:")
    term.setTextColor(theme.text)
    term.setCursorPos(4, 4); term.write("Uptime: " .. math.floor(os.clock()) .. "s")
    
    local numGames = 0
    if fs.exists("games") then numGames = #fs.list("games") end
    term.setCursorPos(4, 5); term.write("Library: " .. numGames .. " Games")

    -- Lobbies
    term.setTextColor(theme.prompt)
    term.setCursorPos(2, 7); term.write("Active Lobbies:")
    local count = 0
    local lobbyList = {}
    for id, lob in pairs(arcadeLobbies) do table.insert(lobbyList, {id=id, lob=lob}) end
    
    if #lobbyList == 0 then
        term.setTextColor(colors.gray); term.setCursorPos(4, 8); term.write("None")
    else
        for i, entry in ipairs(lobbyList) do
            if i > 5 then break end
            term.setTextColor(theme.text)
            term.setCursorPos(4, 7 + i); term.write(string.format("- %s @ %s", entry.lob.user, entry.lob.game))
        end
    end

    -- Mini Log
    term.setTextColor(theme.prompt)
    term.setCursorPos(2, h-6); term.write("Recent Logs:")
    for i = 1, 4 do
        local log = logHistory[#logHistory - 4 + i]
        if log then
            term.setCursorPos(2, h-5 + i)
            term.setTextColor(log:find("ERROR") and theme.error or theme.text)
            term.write(log:sub(1, w - 4))
        end
    end
end

local function drawLogs()
    drawWindow("ARCADE LOGS")
    local w, h = term.getSize()
    local logLines = h - 2
    for i = 1, logLines do
        local log = logHistory[#logHistory - logLines + i]
        if log then
            term.setCursorPos(2, i + 1)
            term.setTextColor(log:find("ERROR") and theme.error or theme.text)
            term.write(log:sub(1, w - 2))
        end
    end
end

local function redrawUI()
    if not needsRedraw then return end
    if currentScreen == "dashboard" then
        drawDashboard()
    elseif currentScreen == "logs" then
        drawLogs()
    end
    needsRedraw = false
end

--==============================================================================
-- Arcade Logic handlers
--==============================================================================

local games = loadTableFromFile(GAMES_DB)

local gameHandlers = {}

function gameHandlers.submit_score(senderId, message)
    local game, user, score = message.game, message.user, message.score
    if not games[game] then games[game] = {} end
    if not games[game][user] or score > games[game][user] then
        games[game][user] = score
        saveTableToFile(GAMES_DB, games)
        logActivity(string.format("Score: %s @ %s = %d", user, game, score))
    end
end

function gameHandlers.get_leaderboard(senderId, message)
    local game = message.game
    local leaderboard = games[game] or {}
    rednet.send(senderId, { leaderboard = leaderboard }, "ArcadeGames")
end

function gameHandlers.host_game(senderId, message)
    arcadeLobbies[senderId] = { user = message.user, game = message.game, startTime = os.clock() }
    logActivity(string.format("Lobby: %s hosting %s", message.user, message.game))
end

function gameHandlers.list_lobbies(senderId, message)
    rednet.send(senderId, { lobbies = arcadeLobbies }, "ArcadeGames")
end

function gameHandlers.close_lobby(senderId, message)
    if arcadeLobbies[senderId] then
        logActivity(string.format("Closed: %s's lobby", arcadeLobbies[senderId].user))
        arcadeLobbies[senderId] = nil
    end
end

local function cleanupLobbies()
    local now = os.clock()
    local removed = 0
    for id, lob in pairs(arcadeLobbies) do
        if not lob.startTime then lob.startTime = now end
        if now - lob.startTime > 600 then -- 10 minutes session
            arcadeLobbies[id] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        logActivity(string.format("Cleaned up %d staled lobbies.", removed))
    end
end

-- New: Game Distribution handlers
function gameHandlers.get_gamelist(senderId, message)
    local gameList = {}
    local files = fs.list("games/")
    for _, file in ipairs(files) do
        if not fs.isDir(fs.combine("games", file)) and file:match("%.lua$") then
            -- Optional: read version or display name from file
            local name = file:gsub("%.lua$", ""):gsub("_", " ")
            name = name:gsub("^%l", string.upper)
            table.insert(gameList, {name = name, file = "games/" .. file})
        end
    end
    rednet.send(senderId, { games = gameList }, "ArcadeGames")
end

function gameHandlers.get_game_update(senderId, message)
    local filename = message.filename
    -- Basic security: ensure we only read from the games directory
    if filename:find("%.%.") or not filename:find("^games/") then
        rednet.send(senderId, { error = "Invalid path" }, "ArcadeGames")
        return
    end

    if fs.exists(filename) then
        local f = fs.open(filename, "r")
        local code = f.readAll()
        f.close()
        rednet.send(senderId, { code = code }, "ArcadeGames")
    else
        rednet.send(senderId, { error = "Game not found" }, "ArcadeGames")
    end
end

function gameHandlers.get_all_game_versions(senderId, message)
    local versions = {}
    local files = fs.list("games/")
    for _, file in ipairs(files) do
        local path = fs.combine("games", file)
        if not fs.isDir(path) and file:match("%.lua$") then
            local f = fs.open(path, "r")
            if f then
                local content = f.readAll(); f.close()
                local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") 
                       or content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
                versions["games/" .. file] = tonumber(v) or 1.0
            end
        end
    end
    rednet.send(senderId, { type = "game_versions_response", versions = versions }, "ArcadeGames")
end

local function syncGames()
    logActivity("Syncing games from GitHub repository...")
    
    local GITHUB_CONTENT_API = "https://api.github.com/repos/mert-d/Drunken_OS/contents/games"
    local LIST_HEADERS = { ["User-Agent"] = "Drunken-Arcade-Server" }

    if not fs.exists("games") then fs.makeDir("games") end

    logActivity("Fetching game list from GitHub...")
    local ok, response = pcall(http.get, GITHUB_CONTENT_API, LIST_HEADERS)
    
    local gamesToDownload = {}
    if ok and response then
        local content = response.readAll()
        response.close()
        local data = textutils.unserializeJSON(content)
        if data and type(data) == "table" then
            for _, item in ipairs(data) do
                if item.type == "file" and item.name:match("%.lua$") then
                    table.insert(gamesToDownload, item.name)
                end
            end
        end
    end

    -- Fallback to hardcoded list if API fails
    if #gamesToDownload == 0 then
        logActivity("GitHub API failed or empty. Using fallback list.", true)
        gamesToDownload = {
            "snake.lua", "tetris.lua", "invaders.lua", "floppa_bird.lua",
            "Drunken_Dungeons.lua", "Drunken_Duels.lua", "Drunken_Pong.lua",
            "Drunken_Sweeper.lua", "Drunken_Sokoban.lua", "Drunken_Doom.lua"
        }
    end

    logActivity(string.format("Preparing to sync %d games...", #gamesToDownload))
    
    local updated = 0
    local failed = 0
    local activeRequests = {}

    -- Start parallel requests
    for _, filename in ipairs(gamesToDownload) do
        local url = GITHUB_GAMES_URL .. filename
        http.request(url, nil, LIST_HEADERS)
        activeRequests[url] = filename
    end

    local timeout = os.startTimer(15) -- 15 seconds global timeout
    while next(activeRequests) do
        local event, url, response = os.pullEvent()
        
        if event == "http_success" then
            local filename = activeRequests[url]
            if filename then
                local code = response.readAll()
                response.close()
                if code and #code > 0 then
                    local f = fs.open("games/" .. filename, "w")
                    if f then
                        f.write(code)
                        f.close()
                        updated = updated + 1
                        logActivity("Synced: " .. filename)
                    else
                        logActivity("FS Error: " .. filename, true)
                        failed = failed + 1
                    end
                else
                    logActivity("Empty Res: " .. filename, true)
                    failed = failed + 1
                end
                activeRequests[url] = nil
            end
        elseif event == "http_failure" then
            local filename = activeRequests[url]
            if filename then
                logActivity("Net Error: " .. filename, true)
                failed = failed + 1
                activeRequests[url] = nil
            end
        elseif event == "timer" and url == timeout then
            logActivity("Sync timed out for some games.", true)
            for u, f in pairs(activeRequests) do
                logActivity("Timed out: " .. f, true)
                failed = failed + 1
            end
            break
        end
    end

    logActivity(string.format("Sync complete. %d updated, %d failed.", updated, failed))
end

local function handleCommand(cmd)
    if cmd == "sync" then
        syncGames()
    elseif cmd == "clear" or cmd == "cls" then
        logHistory = {}
    elseif cmd == "help" then
        logActivity("Commands: sync, clear, help, exit")
    elseif cmd == "exit" then
        error("Server shutdown")
    end
end

--==============================================================================
-- Main Loops
--==============================================================================

local function main()
    -- Initialize Modems
    local found = false
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            found = true
        end
    end
    
    if not found then error("Arcade Server requires a Modem!") end
    
    rednet.host("ArcadeGames_Internal", "arcade.server.internal")
    rednet.host("ArcadeGames", "arcade.server")
    logActivity("Arcade Server Online (Dual Protocol)")
    
    while true do
        redrawUI()
        
        -- Use parallel to handle both rednet and console input
        parallel.waitForAny(
            function()
                local id, msg, proto = rednet.receive(nil, 1)
                if id and (proto == "ArcadeGames_Internal" or proto == "ArcadeGames") and msg and msg.type then
                    if gameHandlers[msg.type] then
                        gameHandlers[msg.type](id, msg)
                    end
                end
            end,
            function()
                local w, h = term.getSize()
                -- Only show prompt area if on dashboard?
                -- For now, let's just listen for keys for screen switching
                local event, p1 = os.pullEvent()
                if event == "key" then
                    if p1 == keys.d then
                        currentScreen = "dashboard"
                        needsRedraw = true
                    elseif p1 == keys.l then
                        currentScreen = "logs"
                        needsRedraw = true
                    elseif p1 == keys.s then
                        syncGames()
                        needsRedraw = true
                    elseif p1 == keys.enter then
                        -- Enter command mode
                        term.setCursorPos(2, h)
                        term.setBackgroundColor(theme.statusBarBg)
                        term.setTextColor(theme.statusBarText)
                        term.write(string.rep(" ", w))
                        term.setCursorPos(2, h)
                        term.write("CMD: ")
                        term.setCursorBlink(true)
                        local cmd = read()
                        term.setCursorBlink(false)
                        if cmd and cmd ~= "" then
                            handleCommand(cmd)
                        end
                        needsRedraw = true
                    elseif p1 == keys.escape then
                        error("Server shutdown")
                    end
                end
            end,
            function()
                -- Lobby Cleanup (Auto-expire after 10 mins)
                cleanupLobbies()
                sleep(60)
            end
        )
    end
end

local ok, err = pcall(main)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Arcade Server Error: " .. err)
end
