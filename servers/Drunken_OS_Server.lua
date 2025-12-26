--[[
    Drunken OS - Mainframe Server (v12.0 - Modular Architecture)
    by MuhendizBey

    Purpose:
    Major performance overhaul focusing on I/O throughput and reduced latency.
    
    Key Changes:
    - Implemented Mail Metadata Caching: Eliminates disk-scans for unread counts.
    - Lazy Database Persistence: Global DBs now use background saving for higher throughput.
    - Parallel Event Loop: Decoupled admin prompt from network listening.
]]

--==============================================================================
-- Environment Setup
--==============================================================================

-- Set up the package path to correctly resolve libraries from the root.
-- This ensures that `require("lib.sha1_hmac")` correctly maps to `/lib/sha1_hmac.lua`.
package.path = "/?.lua;" .. package.path

--==============================================================================
-- API & Library Initialization
--==============================================================================

-- Securely load the cryptography library. If it fails, the server cannot run.
local ok_crypto, crypto = pcall(require, "lib.sha1_hmac")
if not ok_crypto then
    term.setBackgroundColor(colors.red); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1, 1)
    print("================ FATAL ERROR ================")
    print("Required library 'lib/sha1_hmac.lua' not found!")
    print("Please ensure the file exists at:")
    print(" > /lib/sha1_hmac.lua")
    print("=============================================")
    print("Server shutting down.")
    error("sha1_hmac library not found.", 0)
end

-- Securely load the HyperAuthClient API. This is critical for authentication.
local ok_auth, AuthClient = pcall(require, "HyperAuthClient/api/auth_client")
if not ok_auth then
    term.setBackgroundColor(colors.red); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1, 1)
    print("================ FATAL ERROR ================")
    print("The HyperAuthClient API could not be found.")
    print("Please ensure the file exists at:")
    print(" > /HyperAuthClient/api/auth_client.lua")
    print("=============================================")
    print("Server shutting down.")
    error("HyperAuthClient API not found.", 0)
end

-- Load internal server modules
local ChatModule = require("servers.modules.chat")
local AuthModule = require("servers.modules.auth")
local MailModule = require("servers.modules.mail")

--==============================================================================
-- Configuration & State
--==============================================================================

local admins = {} -- This will now be loaded from a file
local users, lists, games, chatHistory, gameList, pendingAuths = {}, {}, {}, {}, {}, {}
local userLocations = {} -- Stores latest (x, y, z) for each user
local programVersions, programCode, gameCode = {}, {}, {}
local logHistory, adminInput, motd = {}, "", ""
local mailCountCache = {} -- Cache for unread mail counts
local manifest = {} -- Manifest table
local monitor = nil
local ADMINS_DB = "admins.db" -- New database file for admins
local USERS_DB = "users.db"
local LISTS_DB = "lists.db"
local GAMES_DB = "games.db"
local CHAT_DB = "chat.db"
local UPDATER_DB = "updater.db"
local GAMELIST_DB = "gamelist.db"
local MOTD_FILE = "motd.txt"
local LOG_FILE = "server.log"
local GAMES_CODE_DB = "games_code.db"
local AUTH_SERVER_PROTOCOL = "auth.secure.v1_Internal"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"
local ADMIN_PROTOCOL = "Drunken_Admin"

local dbDirty = {}
local dbPointers = {
    [ADMINS_DB] = function() return admins end,
    [USERS_DB] = function() return users end,
    [LISTS_DB] = function() return lists end,
    [GAMES_DB] = function() return games end,
    [CHAT_DB] = function() return chatHistory end,
    [GAMELIST_DB] = function() return gameList end,
    [UPDATER_DB] = function() return {v = programVersions, c = programCode} end,
    [GAMES_CODE_DB] = function() return gameCode end
}

local function queueSave(dbPath)
    dbDirty[dbPath] = true
end

--==============================================================================
-- UI & Theme Configuration
--==============================================================================

local hasColor = term.isColor and term.isColor()
local theme = {
    bg = hasColor and colors.black or colors.black,
    text = hasColor and colors.white or colors.white,
    windowBg = hasColor and colors.darkGray or colors.gray,
    title = hasColor and colors.red or colors.red,
    prompt = hasColor and colors.cyan or colors.cyan,
    statusBarBg = hasColor and colors.gray or colors.lightGray,
    statusBarText = hasColor and colors.white or colors.white
}

---
-- Wraps long lines of text to fit within a specified width.
-- Handles both explicit newlines and long strings of words.
-- @param text The string to wrap.
-- @param width The maximum width of each line.
-- @return {table} A table of strings, each representing a wrapped line.
local function wordWrap(text, width)
    local lines = {}
    -- Iterate through each explicit line in the text
    for line in text:gmatch("[^\n]+") do
        if #line <= width then
            -- Line already fits, just add it
            table.insert(lines, line)
        else
            -- Line is too long, wrap it by words
            local currentLine = ""
            for word in line:gmatch("[^%s]+") do
                if #currentLine + #word + 1 > width then
                    -- Adding this word would exceed width, start a new line
                    table.insert(lines, currentLine)
                    currentLine = word
                else
                    -- Append word to the current line
                    currentLine = currentLine == "" and word or (currentLine .. " " .. word)
                end
            end
            -- Add the last piece of the line
            table.insert(lines, currentLine)
        end
    end
    return lines
end

local function parseVersion(content)
    if not content then return 0 end
    local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or
              content:match("local%s+appVersion%s*=%s*([%d%.]+)") or
              content:match("%(v([%d%.]+)%)") or
              content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
    return tonumber(v) or 1.0
end

---
-- Redraws the entire admin console UI on the server's terminal.
-- This includes the title bar, a scrollable log area, and an interactive input prompt.
local function redrawAdminUI()
    local w, h = term.getSize()
    term.setBackgroundColor(theme.windowBg)
    term.clear()

    -- Title Bar: Centered text on a highlighted background
    term.setBackgroundColor(theme.title)
    term.setCursorPos(1, 1)
    term.write((" "):rep(w))
    term.setTextColor(colors.white)
    local title = " Mainframe Admin Console "
    term.setCursorPos(math.floor((w - #title) / 2) + 1, 1)
    term.write(title)

    -- Status Bar: Displays the current server state at the bottom
    term.setBackgroundColor(theme.statusBarBg)
    term.setTextColor(theme.statusBarText)
    term.setCursorPos(1, h)
    term.write((" "):rep(w))
    local status = "RUNNING | Type 'help' for commands"
    term.setCursorPos(2, h)
    term.write(status)

    -- Log Area: Displays recent activity logs with word-wrapping
    term.setBackgroundColor(theme.windowBg)
    term.setTextColor(theme.text)
    local logAreaHeight = h - 4
    local displayLines = {}
    -- Iterate backwards through logs to fill the screen from the bottom up
    for i = #logHistory, 1, -1 do
        local wrappedLines = wordWrap(logHistory[i], w - 2)
        for j = #wrappedLines, 1, -1 do
            table.insert(displayLines, 1, " " .. wrappedLines[j])
            if #displayLines >= logAreaHeight then break end
        end
        if #displayLines >= logAreaHeight then break end
    end
    for i = 1, math.min(#displayLines, logAreaHeight) do
        term.setCursorPos(1, 1 + i)
        term.write(displayLines[i])
    end

    -- Input Area: Separator and a cyan prompt for admin commands
    term.setCursorPos(1, h - 2)
    term.write(('-'):rep(w))
    term.setCursorPos(1, h - 1)
    term.setTextColor(theme.prompt)
    term.write("> ")
    term.setTextColor(theme.text)
    term.write(adminInput)
end

---
-- Redraws the log view on the external monitor.
local function redrawMonitorUI()
    if not monitor then return end
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    -- Title Bar
    monitor.setBackgroundColor(colors.gray)
    monitor.setCursorPos(1, 1)
    monitor.write(string.rep(" ", w))
    monitor.setTextColor(colors.white)
    local title = " MAINFRAME LIVE FEED "
    monitor.setCursorPos(math.floor((w - #title) / 2) + 1, 1)
    monitor.write(title)
    
    -- Log Area
    monitor.setBackgroundColor(colors.black)
    local logAreaHeight = h - 2
    local displayLines = {}
    
    -- We use the same wordWrap as the admin UI
    for i = #logHistory, 1, -1 do
        local wrappedLines = wordWrap(logHistory[i], w - 2)
        for j = #wrappedLines, 1, -1 do
            table.insert(displayLines, 1, " " .. wrappedLines[j])
            if #displayLines >= logAreaHeight then break end
        end
        if #displayLines >= logAreaHeight then break end
    end
    
    for i = 1, math.min(#displayLines, logAreaHeight) do
        monitor.setCursorPos(1, 1 + i)
        local line = displayLines[i]
        if line:find("%[ERROR%]") then monitor.setTextColor(colors.red)
        elseif line:find("%[INFO%]") then monitor.setTextColor(colors.white)
        else monitor.setTextColor(colors.lightGray) end
        monitor.write(line)
    end
end

---
-- Logs a message to the internal history, the display UI, and a persistent log file.
-- Automatically prunes history to prevent memory leaks (max 200 entries).
-- @param message The message to log.
-- @param isError (Optional) True if the message should be flagged as an error.
local function logActivity(message, isError)
    local prefix = isError and "[ERROR] " or "[INFO] "
    local logEntry = os.date("[%H:%M:%S] ") .. prefix .. message
    
    -- Update in-memory history
    table.insert(logHistory, logEntry)
    if #logHistory > 200 then table.remove(logHistory, 1) end
    
    -- Append to log file for persistence
    local file = fs.open(LOG_FILE, "a")
    if file then
        file.writeLine(os.date("[%Y-%m-%d %H:%M:%S] ") .. prefix .. message)
        file.close()
    end
    
    -- Refresh UIs
    redrawAdminUI()
    if monitor then redrawMonitorUI() end
end


--==============================================================================
-- Data Persistence Functions
--==============================================================================

---
-- Saves a Lua table to a file using an atomic write pattern to prevent corruption.
-- @param path The file path to save to.
-- @param data The table to save.
-- @return {boolean} True on success, false on failure.
local function saveTableToFile(path, data)
    local tempPath = path .. ".tmp"
    local file, err_open = fs.open(tempPath, "w")
    if not file then
        logActivity("Could not open temporary file " .. tempPath .. ": " .. tostring(err_open), true)
        return false
    end

    local success, err_write = pcall(function()
        file.write(textutils.serialize(data))
        file.close()
    end)

    if not success then
        logActivity("Failed to write to temporary file " .. tempPath .. ': ' .. tostring(err_write), true)
        fs.delete(tempPath) -- Clean up the failed temp file
        return false
    end

    -- This section makes the write atomic.
    if fs.exists(path) then
        fs.delete(path)
    end
    fs.move(tempPath, path)
    
    return true
end

---
-- Loads a Lua table from a file, with recovery logic for interrupted saves.
-- @param path The file path to load from.
-- @return {table} The loaded table, or an empty table on failure.
local function loadTableFromFile(path)
    local tempPath = path .. ".tmp"
    -- Recovery: If the main file is gone but the temp file exists, the last write was interrupted after delete but before move.
    if not fs.exists(path) and fs.exists(tempPath) then
        logActivity("Found incomplete save, restoring from " .. tempPath, false)
        fs.move(tempPath, path)
    end

    if fs.exists(path) then
        local file, err_open = fs.open(path, "r")
        if file then
            local data = file.readAll()
            file.close()
            local success, result = pcall(textutils.unserialize, data)
            if success and type(result) == "table" then
                return result
            else
                logActivity("Corrupted data in " .. path .. ". A new file will be created.", true)
            end
        else
            logActivity("Could not open " .. path .. " for reading: " .. tostring(err_open), true)
        end
    end
    return {}
end

local function persistenceLoop()
    while true do
        sleep(30) -- Save every 30 seconds if dirty
        for path, isDirty in pairs(dbDirty) do
            if isDirty and dbPointers[path] then
                logActivity("Background saving " .. path .. "...")
                if saveTableToFile(path, dbPointers[path]()) then
                    dbDirty[path] = false
                end
            end
        end
    end
end

---
-- Loads all server databases from disk into memory.
-- Initializes missing files with defaults (e.g., ensuring a default admin exists).
-- Scans the 'games/' directory to automatically populate the arcade catalog.
local function loadAllData()
    admins = loadTableFromFile(ADMINS_DB)
    if not admins.MuhendizBey then
        -- Bootstrapping: Ensure the primary developer always has admin rights
        admins.MuhendizBey = true
        queueSave(ADMINS_DB)
    end
    
    -- Load various entity databases
    users = loadTableFromFile(USERS_DB)
    lists = loadTableFromFile(LISTS_DB)
    games = loadTableFromFile(GAMES_DB)
    chatHistory = loadTableFromFile(CHAT_DB)
    gameList = loadTableFromFile(GAMELIST_DB)
    
    -- Load update distribution data (versions and source code)
    local updaterData = loadTableFromFile(UPDATER_DB)
    programVersions = updaterData.v or {}
    programCode = updaterData.c or {}
    gameCode = loadTableFromFile(GAMES_CODE_DB)
    
    -- Load MOTD (Message of the Day)
    if fs.exists(MOTD_FILE) then
        local file = fs.open(MOTD_FILE, "r")
        motd = file.readAll()
        file.close()
    end

    -- Synchronization: Scan the 'games' folder and update the gameList metadata
    if fs.exists("games") then
        gameList = {}
        for _, file in ipairs(fs.list("games")) do
            local name = file:gsub(".lua", "")
            name = name:gsub("_", " ")
            name = name:gsub("^%l", string.upper) -- Simple title casing
            table.insert(gameList, {name = name, file = "games/" .. file})
        end
        saveTableToFile(GAMELIST_DB, gameList)
    end

    -- Load Manifest
    if fs.exists("manifest.lua") then
        local f = fs.open("manifest.lua", "r")
        local content = f.readAll()
        f.close()
        local func = load(content, "manifest", "t", {})
        if func then 
            manifest = func() 
            logActivity("Manifest loaded (v" .. (manifest.version or "?") .. ")")
        else
            logActivity("Error loading manifest.lua", true)
        end
    else
        logActivity("manifest.lua not found!", true)
    end

    logActivity("Mainframe data loaded.")
end

--==============================================================================
-- Helper Closure for Context
--==============================================================================

local function getContext()
    return {
        users = users,
        admins = admins,
        lists = lists,
        games = games,
        chatHistory = chatHistory,
        pendingAuths = pendingAuths,
        mailCountCache = mailCountCache,
        
        queueSave = queueSave,
        saveTableToFile = saveTableToFile,
        logActivity = logActivity,
        
        getMailCount = function(u) return MailModule.getMailCount(u, {mailCountCache = mailCountCache}) end,
        
        USERS_DB = USERS_DB,
        LISTS_DB = LISTS_DB,
        CHAT_DB = CHAT_DB,
        ADMINS_DB = ADMINS_DB
    }
end

--==============================================================================
-- Network Request Handlers
--==============================================================================

local mailHandlers = {}

function mailHandlers.get_manifest(senderId, message)
    rednet.send(senderId, { type = "manifest_response", manifest = manifest }, "SimpleMail")
end

function mailHandlers.get_file(senderId, message)
    local path = message.path
    if not path or type(path) ~= "string" then return end
    
    -- Security check: prevent directory traversal
    if path:find("%.%.") or path:sub(1,1) == "/" or path:match("^[a-zA-Z]:") then
         rednet.send(senderId, { success = false, reason = "Invalid path security violation" }, "SimpleMail")
         return
    end

    if fs.exists(path) and not fs.isDir(path) then
        local f = fs.open(path, "r")
        local content = f.readAll()
        f.close()
        rednet.send(senderId, { success = true, path = path, code = content }, "SimpleMail")
        logActivity("Served file '" .. path .. "' to " .. senderId)
    else
        rednet.send(senderId, { success = false, reason = "File not found" }, "SimpleMail")
        logActivity("Client " .. senderId .. " requested missing file: " .. path, true)
    end
end

function mailHandlers.get_version(senderId, message)
    local prog = message.program
    if prog:match("^app%.") then
        local appName = prog:gsub("^app%.", "")
        local appPath = "apps/" .. appName .. ".lua"
        if fs.exists(appPath) then
            local f = fs.open(appPath, "r")
            if f then
                local content = f.readAll(); f.close()
                -- Extract version using multiple patterns
                local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or
                          content:match("local%s+appVersion%s*=%s*([%d%.]+)") or
                          content:match("%(v([%d%.]+)%)") or
                          content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
                rednet.send(senderId, { version = tonumber(v) or 1.0 }, "SimpleMail")
            else
                rednet.send(senderId, { version = 0 }, "SimpleMail")
            end
        else
            rednet.send(senderId, { version = 0 }, "SimpleMail")
        end
    else
        local version = programVersions[prog]
        if not version or version == 0 then
            -- Fallback: check games/ directory
            local gamePath = "games/" .. prog
            if fs.exists(gamePath) then
                local f = fs.open(gamePath, "r")
                if f then
                    version = parseVersion(f.readAll())
                    f.close()
                end
            else
                -- Fallback 2: check lib/ directory
                local libPath = "lib/" .. prog .. ".lua"
                if fs.exists(libPath) then
                    local f = fs.open(libPath, "r")
                    if f then
                        version = parseVersion(f.readAll())
                        f.close()
                    end
                end
            end
        end
        rednet.send(senderId, { version = version or 0 }, "SimpleMail")
    end
end

function mailHandlers.get_all_app_versions(senderId, message)
    local versions = {}
    local files = fs.list("apps/")
    for _, file in ipairs(files) do
        if not fs.isDir("apps/" .. file) and file:match("%.lua$") then
            local path = "apps/" .. file
            local f = fs.open(path, "r")
            if f then
                local content = f.readAll(); f.close()
                local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or
                          content:match("local%s+appVersion%s*=%s*([%d%.]+)") or
                          content:match("%(v([%d%.]+)%)") or
                          content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
                versions["app." .. file:gsub("%.lua$", "")] = tonumber(v) or 1.0
            end
        end
    end
    rednet.send(senderId, { type = "app_versions_response", versions = versions }, "SimpleMail")
end

function mailHandlers.get_all_game_versions(senderId, message)
    local versions = {}
    if fs.exists("games/") then
        local files = fs.list("games/")
        for _, file in ipairs(files) do
            if not fs.isDir("games/" .. file) and file:match("%.lua$") then
                local path = "games/" .. file
                local f = fs.open(path, "r")
                if f then
                    versions[file] = parseVersion(f.readAll())
                    f.close()
                end
            end
        end
    end
    rednet.send(senderId, { type = "game_versions_response", versions = versions }, "SimpleMail")
end

function mailHandlers.get_update(senderId, message)
    local prog = message.program
    if prog:match("^app%.") then
        local appName = prog:gsub("^app%.", "")
        local appPath = "apps/" .. appName .. ".lua"
        if fs.exists(appPath) then
            local f = fs.open(appPath, "r")
            local code = f.readAll(); f.close()
            rednet.send(senderId, { code = code }, "SimpleMail")
        else
            rednet.send(senderId, { code = nil }, "SimpleMail")
        end
    else
        local code = programCode[prog]
        if not code then
            -- Fallback: check games/ directory
            local gamePath = "games/" .. prog
            if fs.exists(gamePath) then
                local f = fs.open(gamePath, "r")
                if f then
                    code = f.readAll()
                    f.close()
                end
            else
                -- Fallback 2: check lib/ directory
                local libPath = "lib/" .. prog .. ".lua"
                if fs.exists(libPath) then
                    local f = fs.open(libPath, "r")
                    if f then
                        code = f.readAll()
                        f.close()
                    end
                end
            end
        end
        rednet.send(senderId, { code = code }, "SimpleMail")
    end
end

-- UNIFIED LIBRARY HANDLER: Serves code directly from the programCode database.
function mailHandlers.get_lib_code(senderId, message)
    local libName = message.lib
    if not libName then return end

    if programCode[libName] then
        rednet.send(senderId, { success = true, code = programCode[libName] }, "SimpleMail")
        logActivity("Served library '" .. libName .. "' to client " .. senderId)
    elseif libName:match("^app%.") then
        local appFileName = libName:gsub("^app%.", "") .. ".lua"
        local appPath = "apps/" .. appFileName
        if fs.exists(appPath) then
            local f = fs.open(appPath, "r")
            local code = f.readAll()
            f.close()
            rednet.send(senderId, { success = true, code = code }, "SimpleMail")
            logActivity("Served applet '" .. appFileName .. "' to client " .. senderId)
        else
            rednet.send(senderId, { success = false, reason = "Applet file not found on server." }, "SimpleMail")
        end
    else
        logActivity("Client requested non-existent library: '" .. libName .. "'", true)
        rednet.send(senderId, { success = false, reason = "Library not in server database." }, "SimpleMail")
    end
end

function mailHandlers.register(senderId, message)
    AuthModule.handleRegister(senderId, message, getContext())
end

function mailHandlers.login(senderId, message)
    AuthModule.handleLogin(senderId, message, getContext())
end

function mailHandlers.submit_auth_token(senderId, message)
    AuthModule.handleSubmitToken(senderId, message, getContext())
end

function mailHandlers.user_exists(senderId, message)
    AuthModule.handleUserExists(senderId, message, getContext())
end

function mailHandlers.send(senderId, message)
    MailModule.handleSend(senderId, message, getContext())
end

-- ... Cloud handlers stay separately for now as they are file system ops ...

function mailHandlers.fetch(senderId, message)
    MailModule.handleFetch(senderId, message, getContext())
end

function mailHandlers.delete(senderId, message)
    MailModule.handleDelete(senderId, message, getContext())
end

function mailHandlers.create_list(senderId, message)
    MailModule.handleCreateList(senderId, message, getContext())
end

function mailHandlers.join_list(senderId, message)
    MailModule.handleJoinList(senderId, message, getContext())
end

function mailHandlers.get_lists(senderId, message)
    MailModule.handleGetLists(senderId, message, getContext())
end

function mailHandlers.get_motd(senderId, message)
    rednet.send(senderId, { motd = motd }, "SimpleMail")
end

function mailHandlers.get_chat_history(senderId, message)
    ChatModule.handleGetHistory(senderId, message, { chatHistory = chatHistory })
end

function mailHandlers.get_unread_count(senderId, message)
    MailModule.handleGetUnreadCount(senderId, message, getContext())
end

--==============================================================================
-- Cloud Storage Handlers (Pocket Edition Support)
--==============================================================================

function mailHandlers.list_cloud(senderId, message)
    local user = message.user
    local path = "cloud/" .. user
    local files = {}
    if fs.exists(path) and fs.isDir(path) then
        for _, fileName in ipairs(fs.list(path)) do
            local filePath = path .. "/" .. fileName
            local size = fs.getSize(filePath)
            table.insert(files, { name = fileName, size = size, isDir = fs.isDir(filePath) })
        end
    end
    rednet.send(senderId, { type = "cloud_list_response", files = files }, "SimpleMail")
    logActivity("User '" .. user .. "' listed their cloud storage.")
end

function mailHandlers.sync_file(senderId, message)
    local user = message.user
    local fileName = message.filename
    local content = message.content
    
    if not user or not fileName or not content then
        rednet.send(senderId, { success = false, reason = "Incomplete sync data." }, "SimpleMail")
        return
    end

    local path = "cloud/" .. user
    if not fs.exists(path) then fs.makeDir(path) end
    
    local filePath = path .. "/" .. fileName
    local file = fs.open(filePath, "w")
    if file then
        file.write(content)
        file.close()
        rednet.send(senderId, { success = true, status = "File synced to cloud." }, "SimpleMail")
        logActivity("Synced file '" .. fileName .. "' to cloud for user '" .. user .. "'")
    else
        rednet.send(senderId, { success = false, reason = "Server FS error." }, "SimpleMail")
    end
end

function mailHandlers.download_cloud(senderId, message)
    local user = message.user
    local fileName = message.filename
    local filePath = "cloud/" .. user .. "/" .. fileName
    
    if fs.exists(filePath) and not fs.isDir(filePath) then
        local file = fs.open(filePath, "r")
        local content = file.readAll()
        file.close()
        rednet.send(senderId, { success = true, filename = fileName, content = content }, "SimpleMail")
        logActivity("User '" .. user .. "' downloaded '" .. fileName .. "' from cloud.")
    else
        rednet.send(senderId, { success = false, reason = "File not found." }, "SimpleMail")
    end
end

function mailHandlers.delete_cloud(senderId, message)
    local filePath = "cloud/" .. message.user .. "/" .. message.filename
    if fs.exists(filePath) then
        fs.delete(filePath)
        rednet.send(senderId, { success = true }, "SimpleMail")
        logActivity("User '" .. message.user .. "' deleted cloud file '" .. message.filename .. "'")
    else
        rednet.send(senderId, { success = false, reason = "File not found." }, "SimpleMail")
    end
end

function mailHandlers.fetch(senderId, message)
    -- Use MailModule to fetch mail
    local mail = {}
    if MailModule and MailModule.loadMail then
        mail = MailModule.loadMail(message.user)
    end
    rednet.send(senderId, { mail = mail }, "SimpleMail")
end

function mailHandlers.delete(senderId, message)
    if deleteItem(message.user, message.id, "mail") then
        logActivity(string.format("User '%s' deleted mail '%s'", message.user, message.id))
    end
end

function mailHandlers.create_list(senderId, message)
    if lists[message.name] then
        rednet.send(senderId, { success = false, status = "List exists." }, "SimpleMail")
    else
        lists[message.name] = { message.creator }
        queueSave(LISTS_DB)
        rednet.send(senderId, { success = true, status = "List created." }, "SimpleMail")
        logActivity(string.format("'%s' created list '%s'", message.creator, message.name))
    end
end

function mailHandlers.join_list(senderId, message)
    if not lists[message.name] then
        rednet.send(senderId, { success = false, status = "List not found." }, "SimpleMail")
        return
    end
    for _, member in ipairs(lists[message.name]) do
        if member == message.user then
            rednet.send(senderId, { success = false, status = "Already a member." }, "SimpleMail")
            return
        end
    end
    table.insert(lists[message.name], message.user)
    queueSave(LISTS_DB)
    rednet.send(senderId, { success = true, status = "Joined list." }, "SimpleMail")
    logActivity(string.format("'%s' joined list '%s'", message.user, message.name))
end

function mailHandlers.get_lists(senderId, message)
    rednet.send(senderId, { lists = lists }, "SimpleMail")
end

function mailHandlers.get_motd(senderId, message)
    rednet.send(senderId, { motd = motd }, "SimpleMail")
end

function mailHandlers.get_chat_history(senderId, message)
    ChatModule.handleGetHistory(senderId, message, { chatHistory = chatHistory })
end

function mailHandlers.get_unread_count(senderId, message)
    -- Use the module-scoped function if available, otherwise 0
    local count = 0
    if MailModule and MailModule.getMailCount then
         count = MailModule.getMailCount(message.user, {mailCountCache=mailCountCache})
    end
    rednet.send(senderId, { type = "unread_count_response", count = count }, "SimpleMail")
end

function mailHandlers.report_location(senderId, message)
    if message.user and message.x and message.y and message.z then
        userLocations[message.user] = {
            x = message.x,
            y = message.y,
            z = message.z,
            dimension = message.dimension or "homeworld",
            timestamp = os.time()
        }
        -- No response needed for heartbeat to reduce traffic
    end
end

function mailHandlers.get_user_locations(senderId, message)
    -- clean up old locations (> 5 mins in-game time)
    local now = os.time()
    for user, data in pairs(userLocations) do
        if now - data.timestamp > 0.1 then -- 0.1 game days is roughly 2 mins real time
            userLocations[user] = nil
        end
    end
    rednet.send(senderId, { type = "user_locations_response", locations = userLocations }, "SimpleMail")
end



function mailHandlers.user_exists(senderId, message)
    local exists = false
    if message.recipient:sub(1,1) == "@" then
        if message.recipient == "@all" or lists[message.recipient:sub(2)] then
            exists = true
        end
    elseif users[message.recipient] then
        exists = true
    end
    rednet.send(senderId, { exists = exists }, "SimpleMail")
end

function mailHandlers.is_admin_check(senderId, message)
    local senderUser = nil
    for user, data in pairs(users) do
        if data.session_token and rednet.lookup("SimpleMail", message.user) == senderId then
            senderUser = user
            break
        end
    end
    rednet.send(senderId, { isAdmin = (senderUser and admins[senderUser]) }, "SimpleMail")
end

function mailHandlers.get_user_data(senderId, message)
    local senderUser = nil
    for user, data in pairs(users) do
        if data.session_token and rednet.lookup("SimpleMail", user) == senderId then
            senderUser = user
            break
        end
    end

    if senderUser and admins[senderUser] then
        local user = message.user
        if users[user] then
            rednet.send(senderId, { success = true, pass_hash = users[user].password }, "SimpleMail")
        else
            rednet.send(senderId, { success = false, reason = "User not found." }, "SimpleMail")
        end
    else
        rednet.send(senderId, { success = false, reason = "Insufficient permissions." }, "SimpleMail")
    end
end



function mailHandlers.get_admin_tool(senderId, message)
    -- Security Check: Only serve to admins
    local user = message.user
    if not user or not admins[user] then
        rednet.send(senderId, { success = false, reason = "Unauthorized" }, "SimpleMail")
        return
    end

    local path = "clients/Admin_Console.lua"
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local code = f.readAll()
        f.close()
        rednet.send(senderId, { type = "admin_tool_response", code = code }, "SimpleMail")
    else
        rednet.send(senderId, { success = false, reason = "File not found on server" }, "SimpleMail")
    end
end

--==============================================================================
-- Admin Command Handlers & Main Loops (REPAIRED)
--==============================================================================

--==============================================================================
-- Admin Command Implementation
-- These functions are triggered by input at the server terminal or via
-- the remote Admin Console tool.
--==============================================================================

local adminCommands = {}

---
-- Displays a list of available admin commands.
function adminCommands.help()
    logActivity("--- Mainframe Admin Commands ---")
    logActivity(" [User Management] ")
    logActivity("   users, deluser <name>, addadmin <name>, deladmin <name>")
    logActivity(" [Communication] ")
    logActivity("   lists, dellist <name>, motd <msg>, broadcast <msg>")
    logActivity(" [Arcade & Stats] ")
    logActivity("   games, board <game>, delscore <game> <user>")
    logActivity(" [Distribution] ")
    logActivity("   sync [all|client|libs|apps|games|auditor]")
end

---
-- Lists all registered users and their nicknames.
function adminCommands.users()
    logActivity("Users:")
    for u, d in pairs(users) do
        logActivity("- " .. u .. " (Nick: " .. (d.nickname or "N/A") .. ")")
    end
end

function adminCommands.deluser(a)
    local u = a[2]
    if not u then
        logActivity("Usage: deluser <name>")
        return
    end
    if users[u] then
        users[u] = nil
        saveTableToFile(USERS_DB, users)
        logActivity("Deleted user: " .. u)
    else
        logActivity("User not found: " .. u)
    end
end

function adminCommands.lists()
    logActivity("Lists:")
    for n, m in pairs(lists) do
        logActivity("- " .. n .. " (" .. #m .. " members)")
    end
end

function adminCommands.dellist(a)
    local n = a[2]
    if not n then
        logActivity("Usage: dellist <name>")
        return
    end
    if lists[n] then
        lists[n] = nil
        saveTableToFile(LISTS_DB, lists)
        logActivity("Deleted list: " .. n)
    else
        logActivity("List not found: " .. n)
    end
end

function adminCommands.board(a)
    local g = a[2]
    if not g then
        logActivity("Usage: board <game>")
        return
    end
    if games[g] then
        logActivity("Board for " .. g .. ":")
        for u, s in pairs(games[g]) do
            logActivity("- " .. u .. ": " .. s)
        end
    else
        logActivity("No board for game: " .. g)
    end
end

function adminCommands.delscore(a)
    local g, u = a[2], a[3]
    if not g or not u then
        logActivity("Usage: delscore <game> <user>")
        return
    end
    if games[g] and games[g][u] then
        games[g][u] = nil
        saveTableToFile(GAMES_DB, games)
        logActivity("Deleted score for '" .. u .. "' in '" .. g .. "'")
    else
        logActivity("No score for user '" .. u .. "' in game '" .. g .. "'")
    end
end

function adminCommands.motd(a)
    table.remove(a, 1)
    motd = table.concat(a, " ")
    local f = fs.open(MOTD_FILE, "w")
    if f then
        f.write(motd)
        f.close()
    end
    logActivity("New MOTD set.")
end

function adminCommands.broadcast(a)
    table.remove(a, 1)
    local t = table.concat(a, " ")
    rednet.broadcast({type = "broadcast", text = t}, "SimpleMail")
    logActivity("Broadcast: " .. t)
end

-- All publication is now handled via the 'sync' command for safety.

function adminCommands.games()
    logActivity("Registered Games:")
    for _, g in ipairs(gameList or {}) do
        logActivity("- " .. (g.name or "Unknown") .. " (file: " .. (g.file or "N/A") .. ")")
    end
end

function adminCommands.sync(a)
    local target = a[2] or "all"
    
    if target == "client" or target == "all" then
        logActivity("Syncing Drunken_OS_Client...")
        local path = "clients/Drunken_OS_Client.lua"
        local absPath = fs.combine("/", path)
        logActivity("Checking local path: " .. absPath)
        
        local code, v
        if fs.exists(absPath) then
            local f = fs.open(path, "r")
            code = f.readAll()
            f.close()
            v = code:match("[%w%.]+Version%s*=%s*([%d%.]+)")
        else
            logActivity("Local file needed? No. Check GitHub...")
            local url = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/clients/Drunken_OS_Client.lua"
            local response = http.get(url)
            if response then
                code = response.readAll()
                response.close()
                v = code:match("[%w%.]+Version%s*=%s*([%d%.]+)")
                logActivity("Fetched from GitHub.")
            else
                logActivity("Error: Could not fetch from GitHub.", true)
            end
        end

        if code and v then
            local version = tonumber(v)
            programCode["Drunken_OS_Client"] = code
            programVersions["Drunken_OS_Client"] = version
            saveTableToFile(UPDATER_DB, {v = programVersions, c = programCode})
            logActivity("Published Client v" .. version)
        else
            logActivity("Error: Valid code/version not found.", true)
        end
    end
    
    if target == "apps" or target == "all" then
        logActivity("Syncing Applets...")
        local appsList = { "arcade.lua", "bank.lua", "chat.lua", "files.lua", "mail.lua", "merchant.lua", "system.lua" }
        local baseUrl = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/apps/"
        
        if not fs.exists("apps") then fs.makeDir("apps") end
        local appUpdated = 0
        
        for _, filename in ipairs(appsList) do
            local url = baseUrl .. filename
            logActivity("Pulling: " .. filename)
            local response = http.get(url)
            if response then
                local code = response.readAll()
                response.close()
                if code and #code > 0 then
                    local f = fs.open("apps/" .. filename, "w")
                    if f then
                        f.write(code)
                        f.close()
                        appUpdated = appUpdated + 1
                        
                        -- Extract version for logging
                        local v = code:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or
                                  code:match("local%s+appVersion%s*=%s*([%d%.]+)") or
                                  code:match("%(v([%d%.]+)%)") or
                                  code:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
                        logActivity("Synced " .. filename .. (v and (" (v" .. v .. ")") or ""))
                    end
                end
            else
                logActivity("Failed to pull " .. filename, true)
            end
        end
        logActivity("App sync complete. " .. appUpdated .. " apps updated.")
    end
    
    if target == "libs" or target == "all" then
        logActivity("Syncing Libraries...")
        local libs = { "lib/drunken_os_apps.lua", "lib/sha1_hmac.lua", "lib/updater.lua", "lib/app_loader.lua" }
        local baseUrl = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/"
        
        for _, path in ipairs(libs) do
            local code, v = nil, nil
            local absPath = "/" .. path
            
            -- Strategy 1: Local File
            if fs.exists(absPath) then
                local f = fs.open(absPath, "r")
                code = f.readAll()
                f.close()
            else
                -- Strategy 2: GitHub Fallback
                logActivity("Local " .. path .. " not found. Fetching from GitHub...")
                local response = http.get(baseUrl .. path)
                if response then
                    code = response.readAll()
                    response.close()
                    logActivity("Fetched " .. path .. " from GitHub.")
                end
            end
            
            if code then
                local name = fs.getName(path):gsub("%.lua$", "")
                programCode[name] = code
                
                -- Attempt to extract version
                v = code:match("[%w%.]+Version%s*=%s*([%d%.]+)") or 
                    code:match("[%w%.]*_VERSION%s*=%s*([%d%.]+)") or 
                    code:match("%(v([%d%.]+)%)")
                
                if v then
                    programVersions[name] = tonumber(v)
                    logActivity("Published library: " .. name .. " (v" .. v .. ")")
                else
                    logActivity("Warning: No version found for library " .. name, true)
                end
            else
                logActivity("Error: Could not find library " .. path .. " locally or on GitHub.", true)
            end
        end
        saveTableToFile(UPDATER_DB, {v = programVersions, c = programCode})
    end
    
    if target == "games" or target == "all" then
       logActivity("Note: Game syncing has been migrated to the Arcade Server.", true)
    end
    
    if target == "auditor" or target == "all" then
        logActivity("Syncing Auditor...")
        local path = "turtles/Auditor.lua"
        local code = nil
        
        -- Strategy 1: Local File
        if fs.exists("/" .. path) then
            local f = fs.open("/" .. path, "r")
            code = f.readAll()
            f.close()
        else
            -- Strategy 2: GitHub Fallback
            logActivity("Local " .. path .. " not found. Fetching from GitHub...")
            local url = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/" .. path
            local response = http.get(url)
            if response then
                code = response.readAll()
                response.close()
                logActivity("Fetched Auditor from GitHub.")
            end
        end

        if code then
            programCode["Auditor"] = code
            saveTableToFile(UPDATER_DB, {v = programVersions, c = programCode})
            logActivity("Published Auditor.")
        else
            logActivity("Error: Auditor source not found locally or on GitHub.", true)
        end
    end
end



function adminCommands.addadmin(args)
    local username = args[2]
    if not username then
        logActivity("Usage: addadmin <username>")
        return
    end
    if not users[username] then
        logActivity("Error: User '" .. username .. "' does not exist.", true)
        return
    end

    admins[username] = true
    if saveTableToFile(ADMINS_DB, admins) then
        logActivity("User '" .. username .. "' has been granted admin privileges.")
    else
        logActivity("Failed to save admin database.", true)
        admins[username] = nil -- Revert on failure
    end
end

function adminCommands.deladmin(args)
    local username = args[2]
    if not username then
        logActivity("Usage: deladmin <username>")
        return
    end
    if not admins[username] then
        logActivity("Error: User '" .. username .. "' is not an admin.", true)
        return
    end

    admins[username] = nil
    if saveTableToFile(ADMINS_DB, admins) then
        logActivity("Admin privileges have been revoked for '" .. username .. "'.")
    else
        logActivity("Failed to save admin database.", true)
        admins[username] = true -- Revert on failure
    end
end

local function executeAdminCommand(command)
    local output = {}
    local oldPrint = print
    local oldLogActivity = logActivity

    _G.print = function(...)
        local args = {...}
        local line = ""
        for i = 1, #args do
            line = line .. tostring(args[i]) .. "\t"
        end
        table.insert(output, line)
    end
    
    -- Capture logActivity calls too, since most commands use that
    logActivity = function(msg, isErr)
        oldLogActivity(msg, isErr) -- Do the actual logging
        print(msg) -- Feed into our print capture
    end

    local args = {}
    for arg in command:gmatch("[^%s]+") do
        table.insert(args, arg)
    end
    local cmd = args[1]
    if adminCommands[cmd] then
        adminCommands[cmd](args)
    else
        print("Unknown command.")
    end
    
    _G.print = oldPrint
    logActivity = oldLogActivity
    return table.concat(output, "\n")
end

---
-- Central dispatcher for all incoming rednet messages.
-- The central dispatcher for all incoming Rednet messages.
-- This function handles proxy unwrapping, session verification, and routing
-- messages to specialized handlers (mail, chat, admin, etc).
-- @param senderId The Rednet ID of the message sender (or proxy).
-- @param message The raw message table.
-- @param protocol The Rednet protocol string.
local function handleRednetMessage(senderId, message, protocol)
    local actualMsg = message
    local origSender = senderId
    local isProxied = false
    
    -- Unpack proxy messages if they come from a known Network Proxy
    if message and message.proxy_orig_sender then
        origSender = message.proxy_orig_sender
        actualMsg = message.proxy_orig_msg
        isProxied = true
    end

    -- Encapsulated response function that handles proxy routing automatically
    local realRednetSend = rednet.send
    local function sendResponse(p_id, p_msg, p_proto)
        if isProxied and p_id == origSender then
            -- Re-wrap response for the proxy to deliver back to the client
            realRednetSend(senderId, { proxy_orig_sender = origSender, proxy_response = p_msg }, protocol)
        else
            -- Direct rednet response
            realRednetSend(p_id, p_msg, p_proto or protocol)
        end
    end

    -- Dispatch to appropriate subsystem handler
    if protocol == "SimpleMail_Internal" and actualMsg and actualMsg.type and mailHandlers[actualMsg.type] then
        -- Temporary rednet.send override allows handlers to remain stateless
        local oldSend = rednet.send
        rednet.send = sendResponse
        mailHandlers[actualMsg.type](origSender, actualMsg)
        rednet.send = oldSend

    elseif protocol == "SimpleChat_Internal" and actualMsg and actualMsg.from then
        ChatModule.handleProtocolMessage(senderId, actualMsg, {
            users = users,
            chatHistory = chatHistory,
            queueSave = queueSave,
            CHAT_DB = CHAT_DB
        }) 

    elseif protocol == AUTH_INTERLINK_PROTOCOL and actualMsg.type == "user_exists_check" then
        -- Cross-service communication for checking existence
        sendResponse(senderId, { user = actualMsg.user, exists = (users[actualMsg.user] ~= nil) }, AUTH_INTERLINK_PROTOCOL)

    elseif protocol == "Drunken_Admin_Internal" and actualMsg.type == "execute_command" then
        -- Remote command execution for the Admin Console app
        if actualMsg.user and admins[actualMsg.user] then
            logActivity("Remote cmd from " .. actualMsg.user)
            local output = executeAdminCommand(actualMsg.command)
            sendResponse(senderId, { output = output }, "Drunken_Admin_Internal")
        else
            logActivity("Unauthorized cmd from " .. (actualMsg.user or "unknown"), true)
            sendResponse(senderId, { output = "Access denied." }, "Drunken_Admin_Internal")
        end
    end
end

local function handleTerminalInput(event, p1)
    if event == "key" then
        if p1 == keys.enter then
            if adminInput ~= "" then
                logActivity("Local cmd: " .. adminInput)
                local output = executeAdminCommand(adminInput)
                for line in output:gmatch("[^\n]+") do logActivity(line) end
                adminInput = ""
            end
        elseif p1 == keys.backspace then
            adminInput = adminInput:sub(1, -2)
        end
    elseif event == "char" then
        adminInput = adminInput .. p1
    end
    redrawAdminUI()
end

local function mainEventLoop()
    -- Admin Prompt logic needs to be factored out for parallel
    local function adminPrompt()
        while true do
            local event, p1 = os.pullEvent()
            if event == "key" or event == "char" then
                handleTerminalInput(event, p1)
            elseif event == "terminate" then
                break
            end
        end
    end

    local function rednetListener()
        while true do
            local senderId, message, protocol = rednet.receive()
            if senderId then
                handleRednetMessage(senderId, message, protocol)
            end
        end
    end

    parallel.waitForAny(adminPrompt, rednetListener, persistenceLoop)
end

local function main()
    loadAllData()
    
    -- Monitor Initialization
    monitor = peripheral.find("monitor")
    if monitor then
        monitor.setTextScale(0.5)
        redrawMonitorUI()
    end

    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            local m = peripheral.wrap(side)
            if not m.isWireless() then
                rednet.open(side)
                logActivity("Wired modem opened on " .. side)
            end
        end
    end
    rednet.host("SimpleMail_Internal", "mail.server.internal")
    rednet.host("SimpleChat_Internal", "chat.server.internal")
    rednet.host("Drunken_Admin_Internal", "admin.server.internal")
    rednet.host("auth.secure.v1_Internal", "auth.client.internal")
    logActivity("Mainframe Server v12.0 (Internal Only) Initialized.")
    mainEventLoop()
end

main()
