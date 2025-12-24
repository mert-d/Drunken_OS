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
        local id, msg, proto = rednet.receive(nil, 1)
        if id and (proto == "ArcadeGames_Internal" or proto == "ArcadeGames") and msg and msg.type then
            if gameHandlers[msg.type] then
                gameHandlers[msg.type](id, msg)
            end
        end
        
        -- Lobby Cleanup (Auto-expire after 5 mins)
        local now = os.time()
        for lid, l in pairs(arcadeLobbies) do
            -- os.time() is in game-hours 0-24, difficult to use for real-time timeout without os.epoch
            -- For simplicity, let's just keep them until explicitly closed or computer restarts.
        end
    end
end

local ok, err = pcall(main)
if not ok then
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
    print("Arcade Server Error: " .. err)
end
