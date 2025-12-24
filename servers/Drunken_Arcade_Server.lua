--[[
    Drunken Arcade Server (v1.0)
    by Gemini Gem

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
    title = colors.cyan,
    text = colors.white,
    prompt = colors.lime,
}

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
    if #logHistory > 100 then table.remove(logHistory, 1) end
    
    -- Persistent Log
    local f = fs.open(LOG_FILE, "a")
    if f then f.writeLine(entry); f.close() end
end

local function redrawUI()
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg); term.clear()
    
    -- Title
    term.setBackgroundColor(theme.title)
    term.setCursorPos(1, 1); term.write(string.rep(" ", w))
    term.setCursorPos(math.floor(w/2 - 10), 1); term.setTextColor(colors.black); term.write(" DRUNKEN ARCADE SERVER ")
    
    -- Lobbies
    term.setBackgroundColor(theme.bg); term.setTextColor(theme.prompt)
    term.setCursorPos(2, 3); term.write("Active Lobbies:")
    local count = 0
    for id, lob in pairs(arcadeLobbies) do
        count = count + 1
        term.setTextColor(theme.text)
        term.setCursorPos(2, 3 + count); term.write(string.format("- %s (%s) @ ID:%d", lob.user, lob.game, id))
        if count > 5 then break end
    end
    if count == 0 then
        term.setTextColor(colors.gray); term.setCursorPos(4, 4); term.write("None")
    end

    -- Logs
    term.setTextColor(theme.prompt)
    term.setCursorPos(2, h-6); term.write("Recent Activity:")
    term.setTextColor(theme.text)
    for i = 1, 5 do
        local log = logHistory[#logHistory - 5 + i]
        if log then
            term.setCursorPos(2, h-5 + i)
            term.write(log:sub(1, w - 4))
        end
    end
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
    arcadeLobbies[senderId] = { user = message.user, game = message.game, time = os.time() }
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
                local v = content:match("%-%-%s*Version:%s*([%d%.]+)") or content:match("local%s+currentVersion%s*=%s*([%d%.]+)")
                versions["games/" .. file] = tonumber(v) or 1.0
            end
        end
    end
    rednet.send(senderId, { type = "game_versions_response", versions = versions }, "ArcadeGames")
end

local function syncGames()
    logActivity("Syncing games from GitHub...")
    local coreGames = {
        "snake.lua", "tetris.lua", "invaders.lua", "floppa_bird.lua",
        "Drunken_Dungeons.lua", "Drunken_Duels.lua", "Drunken_Pong.lua",
        "Drunken_Sweeper.lua", "Drunken_Sokoban.lua"
    }
    
    fs.makeDir("games")
    local updated = 0
    for _, filename in ipairs(coreGames) do
        local url = GITHUB_GAMES_URL .. filename
        local response = http.get(url)
        if response then
            local code = response.readAll()
            response.close()
            local f = fs.open("games/" .. filename, "w")
            if f then
                f.write(code)
                f.close()
                updated = updated + 1
                logActivity("Synced: " .. filename)
            else
                 logActivity("Failed to write: " .. filename, true)
            end
        else
            logActivity("Failed to sync: " .. filename .. " (HTTP Error)", true)
        end
    end
    logActivity("Sync complete. Updated " .. updated .. " games.")
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
                term.setCursorPos(2, h)
                term.setTextColor(theme.prompt)
                term.write("> ")
                term.setTextColor(theme.text)
                
                -- Wait for a character or key to trigger synchronous 'read'
                local event = {os.pullEvent()}
                if event[1] == "char" or event[1] == "key" then
                    -- If a key was pressed, let's do a full read
                    term.setCursorBlink(true)
                    local cmd = read()
                    term.setCursorBlink(false)
                    if cmd and cmd ~= "" then
                        handleCommand(cmd)
                    end
                end
            end,
            function()
                -- Lobby Cleanup (Auto-expire after 5 mins)
                -- ...
                sleep(10)
            end
        )
    end
end

local ok, err = pcall(main)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Arcade Server Error: " .. err)
end
