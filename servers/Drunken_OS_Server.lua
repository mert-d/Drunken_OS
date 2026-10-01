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

-- Environment Setup

-- Set up the package path to correctly resolve libraries from the root.
-- This ensures that `require("lib.sha1_hmac")` correctly maps to `/lib/sha1_hmac.lua`.
package.path = "/?.lua;" .. package.path

-- API & Library Initialization

-- Load internal server modules
local ChatModule = require("servers.modules.chat")
local AuthModule = require("servers.modules.auth")

-- Load shared libraries
local DB = require("lib.db")
local utils = require("lib.utils")
local ServiceGuard = require("lib.service_guard")

-- Configuration & State

local admins = {} -- This will now be loaded from a file
local games, chatHistory, gameList, pendingApps = {}, {}, {}, {}
local active_sessions = {} -- populated via Drunken_Auth_Interlink
local clientProxies = {} -- Map client ID -> Proxy ID
local userLocations = {} -- Stores latest (x, y, z) for each user
local programVersions, programCode, gameCode = {}, {}, {}
local logHistory, adminInput, motd = {}, "", ""
local uiDirty = true
local manifest = {} -- Manifest table (loaded in loadAllData)
local monitor = nil
local ADMINS_DB = "admins.db" -- New database file for admins
local GAMES_DB = "games.db"
local CHAT_DB = "chat.db"
local UPDATER_DB = "updater.db"
local GAMELIST_DB = "gamelist.db"
local SUBMISSIONS_DB = "submissions.db"
local MOTD_FILE = "motd.txt"
local LOGS_DIR = "logs"
local LOG_FILE = LOGS_DIR .. "/server.log"
local GAMES_CODE_DB = "games_code.db"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"
local ADMIN_PROTOCOL = "Drunken_Admin"

local dbDirty = {}
local dbPointers = {
    [ADMINS_DB] = function() return admins end,
    [GAMES_DB] = function() return games end,
    [CHAT_DB] = function() return chatHistory end,
    [GAMELIST_DB] = function() return gameList end,
    [SUBMISSIONS_DB] = function() return pendingApps end,
    [UPDATER_DB] = function() return {v = programVersions, c = programCode} end,
    [GAMES_CODE_DB] = function() return gameCode end
}

-- Dirty tracker will be created after logActivity is defined
local dbTracker = nil
local function queueSave(dbPath)
    if dbTracker then
        dbTracker.queueSave(dbPath)
    else
        dbDirty[dbPath] = true
    end
end

-- UI & Theme Configuration

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

-- Use shared wordWrap from lib/utils
local wordWrap = utils.wordWrap

local function parseVersion(content)
    if not content then return 0 end
    local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or
              content:match("local%s+appVersion%s*=%s*([%d%.]+)") or
              content:match("%(v([%d%.]+)%)") or
              content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
    return tonumber(v) or 1.0
end

local function getLogDisplayLines(maxLines, width)
    local lines = {}
    for i = #logHistory, 1, -1 do
        local wrapped = wordWrap(logHistory[i], width)
        for j = #wrapped, 1, -1 do
            table.insert(lines, 1, " " .. wrapped[j])
            if #lines >= maxLines then return lines end
        end
    end
    return lines
end

local function redrawAdminUI()
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg or colors.black)
    term.clear()

    -- 1. Unified Top Title Bar
    term.setBackgroundColor(theme.titleBg or colors.blue)
    term.setCursorPos(1, 1)
    term.write((" "):rep(w))
    term.setTextColor(theme.titleText or colors.white)
    term.setCursorPos(2, 1)
    local title = "[*] Mainframe Admin Console"
    term.write(title)

    local rightInfo = ""
    if os.getComputerID then
        rightInfo = string.format("#%d [NET] ", os.getComputerID())
    end
    if os.time and textutils and textutils.formatTime then
        pcall(function() rightInfo = rightInfo .. textutils.formatTime(os.time(), false) .. " " end)
    end
    if #rightInfo > 0 and w > #title + #rightInfo + 2 then
        term.setCursorPos(w - #rightInfo + 1, 1)
        term.write(rightInfo)
    end

    -- 2. Unified Bottom Status Bar
    term.setBackgroundColor(theme.statusBarBg or colors.gray)
    term.setTextColor(theme.statusBarText or colors.white)
    term.setCursorPos(1, h)
    term.write((" "):rep(w))
    term.setCursorPos(2, h)
    term.write("RUNNING | Type 'help' for commands | Ctrl+T to exit")

    term.setBackgroundColor(theme.bg or colors.black)
    term.setTextColor(theme.text or colors.white)
    local logAreaHeight = h - 4
    local displayLines = getLogDisplayLines(logAreaHeight, w - 2)
    for i = 1, math.min(#displayLines, logAreaHeight) do
        term.setCursorPos(1, 1 + i)
        term.write(displayLines[i])
    end

    term.setCursorPos(1, h - 2)
    term.write(('-'):rep(w))
    term.setCursorPos(1, h - 1)
    term.setTextColor(theme.prompt or colors.yellow)
    term.write("> ")
    term.setTextColor(theme.text or colors.white)
    term.write(adminInput)
end

local function redrawMonitorUI()
    if not monitor then return end
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    monitor.setBackgroundColor(colors.gray)
    monitor.setCursorPos(1, 1)
    monitor.write(string.rep(" ", w))
    monitor.setTextColor(colors.white)
    local title = " MAINFRAME LIVE FEED "
    monitor.setCursorPos(math.floor((w - #title) / 2) + 1, 1)
    monitor.write(title)
    
    monitor.setBackgroundColor(colors.black)
    local logAreaHeight = h - 2
    local displayLines = getLogDisplayLines(logAreaHeight, w - 2)
    for i = 1, math.min(#displayLines, logAreaHeight) do
        monitor.setCursorPos(1, 1 + i)
        local line = displayLines[i]
        if line:find("%[ERROR%]") then monitor.setTextColor(colors.red)
        elseif line:find("%[INFO%]") then monitor.setTextColor(colors.white)
        else monitor.setTextColor(colors.lightGray) end
        monitor.write(line)
    end
end

local logBuffer = {}
local logWriteIdx = 0
local LOG_MAX = 200
local logsDirExists = false

local function logActivity(message, isError)
    local prefix = isError and "[ERROR] " or "[INFO] "
    local logEntryFull = os.date("[%Y-%m-%d %H:%M:%S] ") .. prefix .. message
    local logEntryDisplay = logEntryFull:sub(12) -- Extract "[H:M:S] ..." for display
    
    logWriteIdx = logWriteIdx + 1
    logHistory[logWriteIdx] = logEntryDisplay
    if logWriteIdx > LOG_MAX then
        local newHistory = {}
        for i = LOG_MAX - 99, LOG_MAX do
            table.insert(newHistory, logHistory[i])
        end
        logHistory = newHistory
        logWriteIdx = #logHistory
    end
    
    table.insert(logBuffer, logEntryFull)
    uiDirty = true
end

local function flushLogs()
    if #logBuffer == 0 then return end
    if not logsDirExists then
        local dir = LOGS_DIR or (LOG_FILE and fs.getDir(LOG_FILE)) or "logs"
        if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        logsDirExists = true
    end
    local file = fs.open(LOG_FILE, "a")
    if file then
        for _, entry in ipairs(logBuffer) do
            file.writeLine(entry)
        end
        file.close()
    end
    logBuffer = {}
end


-- Data Persistence Functions

-- Use shared database functions from lib/db
local function saveTableToFile(path, data)
    return DB.saveTableToFile(path, data, logActivity)
end

local function loadTableFromFile(path)
    return DB.loadTableFromFile(path, logActivity)
end

local function persistenceLoop()
    -- Initialize tracker now that logActivity is defined
    if not dbTracker then
        dbTracker = DB.createDirtyTracker(dbPointers, logActivity)
        -- Drain any saves queued before tracker was initialized
        for path, isDirty in pairs(dbDirty) do
            if isDirty then dbTracker.queueSave(path) end
        end
        dbDirty = {}
    end
    
    while true do
        sleep(30) -- Save every 30 seconds if dirty
        dbTracker.backgroundSave()
        flushLogs()
        -- GC and Mail Cache removed since they are outsourced to Microservices
    end
end

local function uiRenderLoop()
    while true do
        if uiDirty then
            redrawAdminUI()
            if monitor then redrawMonitorUI() end
            uiDirty = false
        end
        sleep(0.05) -- Max 20 FPS redraw handling to prevent CPU blocking
    end
end

local function loadAllData()
    admins = loadTableFromFile(ADMINS_DB)
    if not admins.MuhendizBey then
        -- Bootstrapping: Ensure the primary developer always has admin rights
        admins.MuhendizBey = true
        queueSave(ADMINS_DB)
    end
    
    -- Load various entity databases
    games = loadTableFromFile(GAMES_DB)
    chatHistory = loadTableFromFile(CHAT_DB)
    -- Load clean
    pendingApps = loadTableFromFile(SUBMISSIONS_DB)
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
            local name = file:gsub("%.lua$", "")
            name = name:gsub("_", " ")
            name = name:gsub("^%l", string.upper) -- Simple title casing
            table.insert(gameList, {name = name, file = "games/" .. file})
        end
        saveTableToFile(GAMELIST_DB, gameList)
    end

    -- Load Manifest
    local manifestPath = "manifest.lua"
    if not fs.exists(manifestPath) and fs.exists("installer/manifest.lua") then
        manifestPath = "installer/manifest.lua"
    end

    if fs.exists(manifestPath) then
        local f = fs.open(manifestPath, "r")
        local content = f.readAll()
        f.close()
        local env = {
            table = table,
            string = string,
            math = math,
            os = os,
            textutils = textutils,
            pairs = pairs,
            ipairs = ipairs,
            tonumber = tonumber,
            tostring = tostring
        }
        local func = load(content, "manifest", "t", env)
        if func then 
            manifest = func() or {}
            logActivity("Manifest loaded (v" .. (manifest.version or "?") .. ")")
        else
            logActivity("Error loading " .. manifestPath, true)
            manifest = manifest or {}
        end
    else
        logActivity("Warning: manifest.lua not found (run 'sync manifest' to pull)", true)
        manifest = manifest or {}
    end

    logActivity("Mainframe data loaded.")
end

-- Helper Closure for Context

local serverContext = nil

local function getContext()
    if not serverContext then
        serverContext = {
            admins = admins,
            users = users,
            active_sessions = active_sessions,
            games = games,
            chatHistory = chatHistory,
            
            queueSave = queueSave,
            saveTableToFile = saveTableToFile,
            logActivity = logActivity,
            sendResponse = sendResponse,
            
            CHAT_DB = CHAT_DB,
            ADMINS_DB = ADMINS_DB,
            USERS_DB = USERS_DB,
            AUTH_INTERLINK_PROTOCOL = AUTH_INTERLINK_PROTOCOL
        }
    end
    return serverContext
end

-- Network Request Handlers

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

    -- Attempt 1: Check memory cache (programCode)
    -- Map path (e.g., "clients/Drunken_OS_Client.lua", "lib/theme.lua") to module name
    local moduleName = path:match("([^/]+)%.lua$")
    if moduleName and programCode[moduleName] then
        rednet.send(senderId, { success = true, path = path, code = programCode[moduleName] }, "SimpleMail")
        logActivity("Served cached file '" .. path .. "' to " .. senderId)
        return
    end

    -- Attempt 2: Check local disk
    if fs.exists(path) and not fs.isDir(path) then
        local f = fs.open(path, "r")
        local content = f.readAll()
        f.close()
        rednet.send(senderId, { success = true, path = path, code = content }, "SimpleMail")
        logActivity("Served local file '" .. path .. "' to " .. senderId)
    else
        rednet.send(senderId, { success = false, reason = "File not found" }, "SimpleMail")
        logActivity("Client " .. senderId .. " requested missing file: " .. path, true)
    end
end

local function resolveProgramCode(prog)
    if not prog or type(prog) ~= "string" then return nil end
    if prog:match("^app%.") then
        local appPath = "apps/" .. prog:gsub("^app%.", "") .. ".lua"
        if fs.exists(appPath) then
            local f = fs.open(appPath, "r")
            if f then
                local c = f.readAll(); f.close()
                return c
            end
        end
        return nil
    end
    if programCode[prog] then return programCode[prog] end
    for _, path in ipairs({ "games/" .. prog, "lib/" .. prog .. ".lua" }) do
        if fs.exists(path) then
            local f = fs.open(path, "r")
            if f then
                local c = f.readAll(); f.close()
                return c
            end
        end
    end
    return nil
end

function mailHandlers.get_version(senderId, message)
    local prog = message.program
    local version = programVersions[prog]
    if not version or version == 0 then
        local code = resolveProgramCode(prog)
        version = code and parseVersion(code) or 0
    end
    rednet.send(senderId, { version = version or 0 }, "SimpleMail")
end

local appVersionCache = nil

function mailHandlers.get_all_app_versions(senderId, message)
    if not appVersionCache then
        appVersionCache = {}
        local files = fs.list("apps/")
        for _, file in ipairs(files) do
            if not fs.isDir("apps/" .. file) and file:match("%.lua$") then
                local path = "apps/" .. file
                local f = fs.open(path, "r")
                if f then
                    local content = f.readAll(); f.close()
                    appVersionCache["app." .. file:gsub("%.lua$", "")] = parseVersion(content)
                end
            end
        end
    end
    rednet.send(senderId, { type = "app_versions_response", versions = appVersionCache }, "SimpleMail")
end

local gameVersionCache = nil

function mailHandlers.get_all_game_versions(senderId, message)
    if not gameVersionCache then
        gameVersionCache = {}
        if fs.exists("games/") then
            local files = fs.list("games/")
            for _, file in ipairs(files) do
                if not fs.isDir("games/" .. file) and file:match("%.lua$") then
                    local path = "games/" .. file
                    local f = fs.open(path, "r")
                    if f then
                        gameVersionCache[file] = parseVersion(f.readAll())
                        f.close()
                    end
                end
            end
        end
    end
    rednet.send(senderId, { type = "game_versions_response", versions = gameVersionCache }, "SimpleMail")
end

function mailHandlers.get_update(senderId, message)
    rednet.send(senderId, { code = resolveProgramCode(message.program) }, "SimpleMail")
end

    -- Duplicate handlers removed (get_manifest and get_file -- see authoritative definitions above)

-- Backwards compatibility: older clients send get_game_update instead of get_file
function mailHandlers.get_game_update(senderId, message)
    local filename = message.program or message.filename
    if not filename or type(filename) ~= "string" then return end
    -- Ensure we only serve from games/ directory
    local path = "games/" .. filename
    if fs.exists(path) and not fs.isDir(path) then
        local f = fs.open(path, "r")
        if f then
            local code = f.readAll()
            f.close()
            rednet.send(senderId, { success = true, code = code }, "SimpleMail")
            logActivity("Served game '" .. filename .. "' to client " .. senderId)
            return
        end
    end
    rednet.send(senderId, { success = false, code = nil }, "SimpleMail")
end

function mailHandlers.submit_app(senderId, message)
    -- Validate required fields
    if not message.name or not message.code or message.name == "" then
        rednet.send(senderId, { success = false, reason = "Missing required fields (name, code)." }, "SimpleMail")
        return
    end
    -- { type="submit_app", name="...", code="...", description="...", author="..." }
    local subId = tostring(os.epoch("utc"))
    
    pendingApps[subId] = {
        name = message.name,
        code = message.code,
        description = message.description,
        author = message.author or "Anonymous",
        timestamp = os.epoch("utc")
    }
    
    queueSave(SUBMISSIONS_DB)
    logActivity("New App Submission: " .. message.name .. " by " .. (message.author or "?"))
    rednet.send(senderId, { success = true, msg = "Submitted for review." }, "SimpleMail")
end

-- Shared Authentication Helper (must be defined before handlers that use it)
local function verifySecureSession(message)
    local u = message.user or message.username
    local token = message.session_token
    if not u or not token then return false end
    if active_sessions[u] and active_sessions[u].token == token then
        return true
    end
    -- Fallback: query Auth Server over interlink if active_sessions is missing entry (e.g. after Mainframe reboot)
    local authServerId = rednet.lookup("auth.secure.v1", "auth.server")
    if authServerId then
        rednet.send(authServerId, { type = "verify_session", user = u, session_token = token }, AUTH_INTERLINK_PROTOCOL)
        local _, response = rednet.receive(AUTH_INTERLINK_PROTOCOL, 2.5)
        if response and response.type == "verify_session_response" and response.valid then
            active_sessions[u] = { token = token, nickname = response.nickname }
            return true
        end
    end
    return false
end

-- Forward-declare adminCommands (populated later, used by admin_action handler)
local adminCommands = {}

-- Admin Review Handlers
function mailHandlers.admin_get_submissions(senderId, message)
    if not verifySecureSession(message) or not admins[message.username] then 
        rednet.send(senderId, { success = false, reason = "Unauthorized" }, "SimpleMail")
        return
    end
    
    local list = {}
    for id, app in pairs(pendingApps) do
        table.insert(list, { id = id, name = app.name, author = app.author, desc = app.description })
    end
    rednet.send(senderId, { success = true, list = list }, "SimpleMail")
end

function mailHandlers.admin_get_code(senderId, message)
    if not verifySecureSession(message) or not admins[message.username] then
        rednet.send(senderId, { success = false, reason = "Unauthorized" }, "SimpleMail")
        return
    end
    
    local app = pendingApps[message.id]
    if app then
        rednet.send(senderId, { success = true, code = app.code, name = app.name }, "SimpleMail")
    else
        rednet.send(senderId, { success = false, reason = "Not found" }, "SimpleMail")
    end
end

function mailHandlers.verify_session(senderId, message)
    local success = verifySecureSession(message)
    rednet.send(senderId, { success = success }, "SimpleMail")
end

function mailHandlers.admin_action(senderId, message)
    if not verifySecureSession(message) or not admins[message.username] then 
        rednet.send(senderId, { success = false, reason = "Unauthorized" }, "SimpleMail")
        return 
    end
    
    local action = message.action
    local id = message.id
    
    local result = "Invalid Action"
    if action == "approve" then
        local args = { "approve", id }
        if message.overwrite then table.insert(args, "overwrite") end
        result = adminCommands.approve(args)
    elseif action == "reject" then
        result = adminCommands.reject({ "reject", id })
    end
    
    rednet.send(senderId, { success = true, msg = result }, "SimpleMail")
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

local function proxyToInterlink(senderId, message)
    if message.type == "get_unread_count" and not message.session_token and message.user and active_sessions[message.user] then
        message.session_token = active_sessions[message.user].token
    end
    if not verifySecureSession(message) then 
        rednet.send(senderId, { success = false, reason = "Unauthorized session." }, "SimpleMail")
        return 
    end
    local payload = {
        forwarded = true,
        type = message.type,
        message = message,
        original_senderId = senderId,
        proxy_senderId = clientProxies[senderId],
        original_protocol = "SimpleMail"
    }
    rednet.broadcast(payload, AUTH_INTERLINK_PROTOCOL)
end

function mailHandlers.send(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.fetch(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.delete(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.create_list(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.join_list(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.get_lists(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.get_unread_count(senderId, message) proxyToInterlink(senderId, message) end

function mailHandlers.list_cloud(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.sync_file(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.download_cloud(senderId, message) proxyToInterlink(senderId, message) end
function mailHandlers.delete_cloud(senderId, message) proxyToInterlink(senderId, message) end

function mailHandlers.get_motd(senderId, message)
    rednet.send(senderId, { motd = motd }, "SimpleMail")
end

function mailHandlers.get_chat_history(senderId, message)
    ChatModule.handleGetHistory(senderId, message, { chatHistory = chatHistory })
end

-- NOTE: fetch, delete, create_list, join_list, get_lists, get_motd, get_chat_history,
-- and get_unread_count are handled by the module-delegating handlers defined above.
-- Stale inline overrides removed to prevent silent overwrites and undefined-function crashes.

function mailHandlers.report_location(senderId, message)
    if message.user and message.x and message.y and message.z then
        userLocations[message.user] = {
            x = message.x,
            y = message.y,
            z = message.z,
            dimension = message.dimension or "homeworld",
            timestamp = os.epoch("utc")
        }
        -- No response needed for heartbeat to reduce traffic
    end
end

function mailHandlers.get_user_locations(senderId, message)
    -- clean up old locations (> 2 minutes real time)
    local now = os.epoch("utc")
    for user, data in pairs(userLocations) do
        if now - (data.timestamp or 0) > 120000 then -- 2 minutes in ms
            userLocations[user] = nil
        end
    end
    rednet.send(senderId, { type = "user_locations_response", locations = userLocations }, "SimpleMail")
end



-- NOTE: user_exists is handled by AuthModule.handleUserExists (see line ~670).
-- Stale inline override removed -- it referenced message.recipient instead of message.user
-- and would have crashed with a nil index error.

function mailHandlers.is_admin_check(senderId, message)
    local user = message.user
    local token = message.session_token
    local isAdmin = false
    if user and active_sessions[user] and token and active_sessions[user].token == token then
        isAdmin = admins[user] or false
    end
    rednet.send(senderId, { isAdmin = isAdmin }, "SimpleMail")
end

function mailHandlers.get_user_data(senderId, message)
    -- API Gateway proxy to get detailed user data from Auth Server (not implemented locally)
    -- In this architecture, passwords are kept safely away from Mainframe.
    rednet.send(senderId, { success = false, reason = "Password hashes are restricted to Auth Node." }, "SimpleMail")
end



function mailHandlers.get_admin_tool(senderId, message)
    -- Security Check: Verify session token AND admin status
    if not verifySecureSession(message) or not admins[message.user or message.username] then
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

-- Admin Command Handlers & Main Loops (REPAIRED)

--==============================================================================
-- Admin Command Implementation
-- These functions are triggered by input at the server terminal or via
-- the remote Admin Console tool.
--==============================================================================

-- adminCommands table is forward-declared above (before mailHandlers.admin_action)

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
adminCommands.commands = adminCommands.help
adminCommands["?"] = adminCommands.help

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

local function fetchSyncFile(relPath)
    local absPath = fs.combine("/", relPath)
    if fs.exists(absPath) then
        local f = fs.open(relPath, "r")
        if f then
            local c = f.readAll(); f.close()
            return c
        end
    end
    if http and http.get then
        local url = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/" .. relPath
        local resp = http.get(url)
        if resp then
            local c = resp.readAll(); resp.close()
            return c
        end
    end
    return nil
end

function adminCommands.sync(a)
    local target = a[2] or "all"
    
    if target == "client" or target == "all" then
        logActivity("Syncing Drunken_OS_Client...")
        local code = fetchSyncFile("clients/Drunken_OS_Client.lua")
        if code then
            local v = parseVersion(code)
            programCode["Drunken_OS_Client"] = code
            programVersions["Drunken_OS_Client"] = tonumber(v) or 1.0
            saveTableToFile(UPDATER_DB, {v = programVersions, c = programCode})
            logActivity("Published Client v" .. (v or 1.0))
        else
            logActivity("Error: Could not fetch Drunken_OS_Client.", true)
        end
    end
    
    if target == "apps" or target == "all" then
        logActivity("Syncing Applets...")
        local appsList = { "arcade.lua", "bank.lua", "chat.lua", "files.lua", "mail.lua", "merchant.lua", "system.lua" }
        if not fs.exists("apps") then fs.makeDir("apps") end
        local appUpdated = 0
        for _, filename in ipairs(appsList) do
            local code = fetchSyncFile("apps/" .. filename)
            if code and #code > 0 then
                local f = fs.open("apps/" .. filename, "w")
                if f then
                    f.write(code); f.close()
                    appUpdated = appUpdated + 1
                    logActivity("Synced " .. filename .. " (v" .. parseVersion(code) .. ")")
                end
            else
                logActivity("Failed to pull " .. filename, true)
            end
        end
        logActivity("App sync complete. " .. appUpdated .. " apps updated.")
    end
    
    if target == "libs" or target == "all" then
        logActivity("Syncing Libraries...")
        local libs = { "lib/drunken_os_apps.lua", "lib/sha1_hmac.lua", "lib/updater.lua", "lib/app_loader.lua", "lib/theme.lua", "lib/utils.lua", "lib/sdk.lua", "lib/p2p_socket.lua" }
        for _, path in ipairs(libs) do
            local code = fetchSyncFile(path)
            if code then
                local name = fs.getName(path):gsub("%.lua$", "")
                programCode[name] = code
                local v = parseVersion(code)
                programVersions[name] = tonumber(v) or 1.0
                logActivity("Published library: " .. name .. " (v" .. (v or 1.0) .. ")")
            else
                logActivity("Error: Could not find library " .. path, true)
            end
        end
        saveTableToFile(UPDATER_DB, {v = programVersions, c = programCode})
    end
    
    if target == "manifest" or target == "all" then
        logActivity("Syncing Manifest...")
        local code = fetchSyncFile("installer/manifest.lua")
        if code and #code > 0 then
            local f = fs.open("manifest.lua", "w")
            if f then
                f.write(code); f.close()
                local env = { table = table, string = string, math = math, os = os, textutils = textutils, peripheral = peripheral, rednet = rednet, fs = fs, term = term, colors = colors, colours = colours, keys = keys }
                local func = load(code, "manifest", "t", env)
                if func then
                    manifest = func()
                    logActivity("Manifest updated to v" .. (manifest.version or "?"))
                end
            end
        else
            logActivity("Failed to pull manifest.lua from GitHub", true)
        end
    end
    
    if target == "games" or target == "all" then
       logActivity("Note: Game syncing has been migrated to the Arcade Server.", true)
    end
    
    if target == "auditor" or target == "all" then
        logActivity("Syncing Auditor...")
        local code = fetchSyncFile("turtles/Auditor.lua")
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

function adminCommands.submissions()
    local count = 0
    local output = "--- Pending Apps ---\n"
    for id, app in pairs(pendingApps) do
        output = output .. string.format("[%s] %s by %s\n", id, app.name, app.author)
        count = count + 1
    end
    if count == 0 then output = "No pending submissions." end
    return output
end

function adminCommands.approve(args)
    local subId = args[2]
    local overwrite = args[3] == "overwrite"

    if not subId or not pendingApps[subId] then
        return "Usage: approve <id> [overwrite] (ID not found)"
    end
    
    local app = pendingApps[subId]
    local filename = "apps/" .. app.name .. ".lua"

    -- We now add to 'store' instead of 'all_apps' to make it Optional/On-Demand
    if not manifest.store then manifest.store = {} end

    -- Check uniqueness or overwrite
    if manifest.store[app.name] and not overwrite then
        return "App '" .. app.name .. "' already exists. Use 'approve " .. subId .. " overwrite' to replace it."
    end
    
    -- 1. Save File Locally
    -- Ensure apps dir exists
    if not fs.exists("apps") then fs.makeDir("apps") end
    local f = fs.open(filename, "w")
    f.write(app.code)
    f.close()
    
    -- 2. Update Manifest (Dynamic!)
    manifest.store[app.name] = filename
    
    -- Save the manifest table back to manifest.lua
    local fMan = fs.open("manifest.lua", "w")
    fMan.write("return " .. textutils.serialize(manifest))
    fMan.close()
    
    -- 3. Cleanup
    pendingApps[subId] = nil
    queueSave(SUBMISSIONS_DB)
    
    return "App '" .. app.name .. "' approved and published to App Store."
end

function adminCommands.reject(args)
    local subId = args[2]
    if not subId or not pendingApps[subId] then return "Usage: reject <id>" end
    local name = pendingApps[subId].name
    pendingApps[subId] = nil
    queueSave(SUBMISSIONS_DB)
    return "Rejected submission '" .. name .. "'."
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

function adminCommands.setupauth(args)
    -- Temporarily take over the screen for an interactive prompt
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    
    term.setCursorPos(1, 2)
    term.setTextColor(colors.yellow)
    term.write("=== HyperAuth Setup Initialization ===")
    term.setTextColor(colors.white)
    
    term.setCursorPos(1, 4)
    term.write("Enter Protocol Name:")
    term.setCursorPos(1, 5)
    term.setTextColor(colors.cyan)
    local protocol = read()
    term.setTextColor(colors.white)
    
    term.setCursorPos(1, 7)
    term.write("Enter Client ID:")
    term.setCursorPos(1, 8)
    term.setTextColor(colors.cyan)
    local client_id = read()
    term.setTextColor(colors.white)
    
    term.setCursorPos(1, 10)
    term.write("Enter Shared Secret:")
    term.setCursorPos(1, 11)
    term.setTextColor(colors.cyan)
    local secret = read()
    term.setTextColor(colors.white)
    
    if protocol == "" or client_id == "" or secret == "" then
        return "Setup aborted: All fields are required."
    end
    
    -- Generate new configuration file
    local configCode = string.format([[
return {
  PROTOCOL_NAME = "%s",

  CLIENT_ID     = "%s",
  SHARED_SECRET = "%s",

  KNOWN_SERVER_ID         = nil,
  DEFAULT_TIMEOUT_SECONDS = 6,
}
]], protocol, client_id, secret)

    if not fs.exists("HyperAuthClient") then
        fs.makeDir("HyperAuthClient")
    end
    
    local f = fs.open("HyperAuthClient/config.lua", "w")
    if f then
        f.write(configCode)
        f.close()
        return "HyperAuth configuration successfully written! Please reboot."
    else
        return "Error: Could not write to HyperAuthClient/config.lua"
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

local function handleRednetMessage(senderId, message, protocol)
    local actualMsg = message
    local origSender = senderId
    local isProxied = false
    
    -- Unpack proxy messages if they come from a known Network Proxy
    if message and message.proxy_orig_sender then
        origSender = message.proxy_orig_sender
        actualMsg = message.proxy_orig_msg
        isProxied = true
        clientProxies[origSender] = senderId
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
        if isProxied then
            -- Temporary rednet.send override allows handlers to remain stateless
            local oldSend = rednet.send
            rednet.send = sendResponse
            local ok, err = pcall(mailHandlers[actualMsg.type], origSender, actualMsg)
            rednet.send = oldSend
            if not ok then
                logActivity("Error in mail handler '" .. tostring(actualMsg.type) .. "': " .. tostring(err), true)
            end
        else
            local ok, err = pcall(mailHandlers[actualMsg.type], origSender, actualMsg)
            if not ok then
                logActivity("Error in mail handler '" .. tostring(actualMsg.type) .. "': " .. tostring(err), true)
            end
        end

    elseif protocol == "SimpleChat_Internal" and actualMsg and actualMsg.from then
        ChatModule.handleProtocolMessage(senderId, actualMsg, {
            active_sessions = active_sessions,
            chatHistory = chatHistory,
            queueSave = queueSave,
            CHAT_DB = CHAT_DB
        }) 

    elseif protocol == AUTH_INTERLINK_PROTOCOL then
        if actualMsg.type == "session_authorized" then
            active_sessions[actualMsg.user] = { token = actualMsg.session_token, nickname = actualMsg.nickname }
            logActivity("Session registered for: " .. actualMsg.user)
        elseif actualMsg.type == "user_exists_check" then
            local authServerId = rednet.lookup("auth.secure.v1", "auth.server")
            if authServerId then
                rednet.send(authServerId, { type = "user_exists", user = actualMsg.user }, AUTH_INTERLINK_PROTOCOL)
                local _, response = rednet.receive(AUTH_INTERLINK_PROTOCOL, 3)
                if response and response.type == "user_exists_response" then
                    sendResponse(senderId, { exists = response.exists }, AUTH_INTERLINK_PROTOCOL)
                    return
                end
            end
            sendResponse(senderId, { exists = false }, AUTH_INTERLINK_PROTOCOL)
        elseif actualMsg.original_type then
            -- This is a proxy response from the Mail/Auth server, forward it back!
            local targetId = actualMsg.original_senderId
            local proxyId = actualMsg.proxy_senderId or clientProxies[targetId]
            local targetProto = actualMsg.original_protocol or "SimpleMail"
            local internalProto = targetProto .. "_Internal"
            if targetId then
                logActivity(string.format("Relaying async resp '%s' to client %d (proxy: %s)", tostring(actualMsg.original_type), targetId, tostring(proxyId)))
                local wrappedResp = { proxy_orig_sender = targetId, proxy_response = actualMsg }
                
                -- Fail-safe 3-way delivery:
                -- 1. Direct unicast to proxy if known
                if proxyId then
                    realRednetSend(proxyId, wrappedResp, internalProto)
                end
                -- 2. Broadcast on internalProto so ANY proxy on the network relays it to the phone
                rednet.broadcast(wrappedResp, internalProto)
                -- 3. Direct send in case client is on wired/internal network
                realRednetSend(targetId, actualMsg, targetProto)
            end
        elseif actualMsg.type == "new_mail_notification" then
            -- Relay notification to proxies and clients
            local notifyMsg = {
                type = "new_mail",
                recipient = actualMsg.recipient,
                mail = actualMsg.mail
            }
            rednet.broadcast(notifyMsg, "SimpleMail_Internal")
            rednet.broadcast(notifyMsg, "SimpleMail")
        end

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
    uiDirty = true
end

local function registerProtocols()
    local protos = {
        { proto = "SimpleMail_Internal", host = "mail.server.internal" },
        { proto = "SimpleChat_Internal", host = "chat.server.internal" },
        { proto = "Drunken_Admin_Internal", host = "admin.server.internal" },
        { proto = "auth.secure.v1_Internal", host = "auth.client.internal" },
        { proto = AUTH_INTERLINK_PROTOCOL, host = "interlink.server.internal" },
    }
    for _, item in ipairs(protos) do
        if rednet and rednet.unhost then pcall(rednet.unhost, item.proto, item.host) end
        if rednet and rednet.host then pcall(rednet.host, item.proto, item.host) end
    end
end

local function flushMainframeState()
    if dbTracker and dbTracker.backgroundSave then
        pcall(dbTracker.backgroundSave)
    end
    flushLogs()
end

local function mainEventLoop()
    -- Admin Prompt logic needs to be factored out for parallel
    local function adminPrompt()
        while true do
            local event, p1 = os.pullEventRaw()
            if event == "key" or event == "char" then
                handleTerminalInput(event, p1)
            elseif event == "terminate" then
                error("Terminated", 0)
            end
        end
    end

    local function rednetListener()
        while true do
            local event, p1, p2, p3 = os.pullEventRaw()
            if event == "rednet_message" then
                local senderId, message, protocol = p1, p2, p3
                if senderId then
                    ServiceGuard.protectHandler("Mainframe:packet", handleRednetMessage, logActivity, senderId, message, protocol)
                end
            elseif event == "peripheral" or event == "peripheral_detach" then
                ServiceGuard.handlePeripheralEvent(event, p1, registerProtocols, logActivity, function(monName)
                    monitor = peripheral.wrap(monName)
                    if monitor then
                        monitor.setTextScale(0.5)
                        redrawMonitorUI()
                    end
                end)
            end
        end
    end

    parallel.waitForAny(adminPrompt, rednetListener, persistenceLoop, uiRenderLoop)
end

local function main()
    loadAllData()
    
    -- Monitor Initialization
    monitor = peripheral.find("monitor")
    if monitor then
        monitor.setTextScale(0.5)
        redrawMonitorUI()
    end

    local modems = ServiceGuard.initModems("wired")
    if modems.count == 0 then
        logActivity("Warning: No wired modem attached on startup.", true)
    else
        logActivity("Wired modems initialized: " .. table.concat(modems.all, ", "))
    end

    registerProtocols()
    logActivity("Mainframe Server v12.1 (Internal Only) Initialized under ServiceGuard.")
    ServiceGuard.runSupervisor("Mainframe Server", mainEventLoop, flushMainframeState, logActivity)
end

main()
