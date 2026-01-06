--[[
    Drunken OS - Mobile Client (v15.1 - Performance Edition)
    by MuhendizBey
]]

--==============================================================================
-- Environment & Path Setup
--==============================================================================

local programDir = fs.getDir(shell.getRunningProgram())
-- Construct a clean, predictable package search path
-- We use full module names (e.g. require("lib.sha1_hmac")), so we only need ?.lua
local paths = {
    "?.lua",
    "?/init.lua",
    fs.combine(programDir, "?.lua"),
    fs.combine(programDir, "?/init.lua")
}
package.path = table.concat(paths, ";") .. ";" .. package.path
local crypto = require("lib.sha1_hmac")

--==============================================================================
-- Configuration & State
--==============================================================================

local currentVersion = 16.5
local programName = "Drunken_OS_Client" -- Correct program name for updates
local SESSION_FILE = ".session"
local REQUIRED_LIBS = {
    { name = "sha1_hmac" },
    { name = "updater" },
    { name = "drunken_os_apps" },
    { name = "app_loader" },
    { name = "theme" },
    { name = "utils" },
    { name = "p2p_socket" }
}

local REQUIRED_APPS = {
    "mail", "bank", "files", "chat", "arcade", "system", "merchant"
}

--==============================================================================
-- UI & Theme Helpers
--==============================================================================

local theme -- Delayed require
local utils -- Delayed require
local wordWrap -- Delayed assign
local printCentered -- Delayed assign

local colorToBlit -- Delayed assign (set after theme loads)

-- Global OS State: Stores session info, server IDs, and user data.
local state = {
    mailServerId = nil,   -- Rednet ID of the Mainframe
    chatServerId = nil,   -- Rednet ID of the Chat Server
    adminServerId = nil,  -- Rednet ID for admin operations
    appLoader = nil,      -- Dynamic app loader
    username = nil,       -- Logged in username
    nickname = nil,       -- User's display name
    isAdmin = false,      -- Boolean administrative flag
    apps = nil,           -- Reference to the loaded apps library
    crypto = nil,         -- Reference to the sha1_hmac library
    unreadCount = 0,      -- Persistent unread mail count
    location = nil        -- Latest GPS coordinates {x, y, z}
}

local context = {} -- Shared context for modular apps

-- wordWrap moved to lib.utils

local function clear()
    term.clear()
    term.setCursorPos(1,1)
end

---
-- Draws a standard OS window frame with a centered title bar.
-- This creates a consistent look and feel across all applications.
-- @param title The text to display in the top title bar.
local function drawWindow(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg)
    term.clear()
    
    -- Draw title and bottom borders
    term.setBackgroundColor(theme.titleBg)
    term.setCursorPos(1, 1); term.write(string.rep(" ", w))
    term.setCursorPos(1, h); term.write(string.rep(" ", w))
    -- Draw side borders
    for i = 2, h - 1 do
        term.setCursorPos(1, i); term.write(" ")
        term.setCursorPos(w, i); term.write(" ")
    end

    -- Render the centered title text
    term.setCursorPos(1, 1)
    term.setTextColor(theme.titleText)
    local titleText = " " .. (title or "Drunken OS") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    
    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
end

-- printCentered moved to lib.utils

local function showMessage(title, message)
    drawWindow(title)
    local w, h = term.getSize()
    printCentered(4, message)
    
    local continueText = "Press any key to continue..."
    term.setCursorPos(math.floor((w - #continueText) / 2) + 1, h - 2)
    term.setTextColor(colors.gray)
    term.write(continueText)
    os.pullEvent("key")
end

local function drawMenu(options, selected, startX, startY)
    local w, h = term.getSize()
    
    -- Access colorToBlit from loaded theme
    local blitMap = colorToBlit or (theme and theme.colorToBlit) or {}
    local fg_hex = blitMap[theme.text] or "0"
    local bg_hex = blitMap[theme.bg] or "f"
    local hfg_hex = blitMap[theme.highlightText] or "f"
    local hbg_hex = blitMap[theme.highlightBg] or "3"

    for i, opt in ipairs(options) do
        term.setCursorPos(startX, startY + i - 1)
        local line = " " .. opt .. string.rep(" ", w - startX - #opt - 1) .. " "
        if i == selected then
            term.blit(line, string.rep(hfg_hex, #line), string.rep(hbg_hex, #line))
        else
            term.blit(line, string.rep(fg_hex, #line), string.rep(bg_hex, #line))
        end
    end
end

local function readInput(prompt, y)
    term.setCursorPos(2, y)
    term.setTextColor(theme.prompt)
    term.write(prompt)
    term.setTextColor(theme.text)
    term.setCursorBlink(true)
    local input = read()
    term.setCursorBlink(false)
    return input
end

local function getSafeSize()
    return term.getSize()
end

--==============================================================================
-- Networking & Initialization
--==============================================================================

---
-- Discovers necessary services (Mail, Chat) on the Rednet network.
-- @return {boolean} Success status.
-- @return {string|nil} Error message if servers were not found.
local function findServers()
    -- Look for the Mainframe using the 'SimpleMail' protocol
    state.mailServerId = rednet.lookup("SimpleMail", "mail.server")
    -- Look for the Chat service
    state.chatServerId = rednet.lookup("SimpleChat", "chat.server")
    state.adminServerId = state.mailServerId -- Unified mainframe admin
    if not state.mailServerId then
        return false, "Mainframe (mail.server) not found."
    end
    return true
end

state.crypto = crypto

local context = {
    drawWindow = drawWindow,
    drawMenu = drawMenu,
    readInput = readInput,
    showMessage = showMessage,
    clear = clear,
    parent = state,
    programDir = programDir,
    wordWrap = wordWrap,
    getSafeSize = getSafeSize,
    theme = theme
}

--==============================================================================
-- Installation & Update Functions
--==============================================================================

---
-- Ensures all required libraries are installed and up to date.
-- Bootstraps the 'updater' library if missing, then uses it to sync
-- sha1_hmac and drunken_os_apps.
-- @return {boolean} Success status.
local function installDependencies()
    local needsReboot = false
    
    -- Bootstrap Stage: The OS cannot run without the library updater.
    local updaterPath = fs.combine(programDir, "lib/updater.lua")
    if not fs.exists(updaterPath) then
        print("Bootstrap: Downloading updater...")
        local server = rednet.lookup("SimpleMail", "mail.server")
        if server then
            -- Fetch raw library code from the unified distribution system
            rednet.send(server, { type = "get_lib_code", lib = "updater" }, "SimpleMail")
            local _, resp = rednet.receive("SimpleMail", 15)
            if resp and resp.success and resp.code then
                if not fs.isDir(fs.combine(programDir, "lib")) then fs.makeDir(fs.combine(programDir, "lib")) end
                local f = fs.open(updaterPath, "w")
                f.write(resp.code)
                f.close()
                print("Updater installed.")
            end
        end
    end

    -- Load the updater to manage remaining dependencies
    local ok_upd, updaterOrError = pcall(require, "lib.updater")
    if not ok_upd then
        print("Error: Could not load updater library: " .. tostring(updaterOrError))
        return false
    end
    local updater = updaterOrError
    
    -- Sync EVERYTHING via Manifest
    print("Checking Manifest...")
    local success = updater.install_package("client", function(msg) print("- " .. msg) end)
    
    if success then
        -- We don't necessarily know if meaningful changes happened, so we assume yes for safety 
        -- or we could modify updater to return 'updated' bool. 
        -- For now, let's just proceed. If updater updated key files it might have overwritten running code?
        -- Safest is to just reload context or potentially reboot if core libs changed.
        -- Given the complexity, let's assume we proceed unless vital errors occurred.
        print("System integrity verified.")
        return true
    else
        print("Manifest sync failed. Running in offline/cached mode.")
        sleep(1)
    end
    
    return true
end

local function autoUpdateCheck()
    rednet.send(state.mailServerId, { type = "get_version", program = programName }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 3)
    if response and response.version and response.version > currentVersion then
        term.clear(); term.setCursorPos(1, 1)
        print("New version available: " .. response.version)
        print("Downloading update...")
        rednet.send(state.mailServerId, { type = "get_update", program = programName }, "SimpleMail")
        local _, update = rednet.receive("SimpleMail", 5)
        if update and update.code then
            local path = shell.getRunningProgram()
            local file = fs.open(path, "w")
            file.write(update.code)
            file.close()
            print("Update complete. Rebooting...")
            sleep(2)
            os.reboot()
            return true
        else
            print("Update failed.")
            sleep(2)
        end
    end
    return false
end

function updateGames()
    drawWindow("Game Updater")
    local y = 4
    term.setCursorPos(2, y); term.write("Fetching game list from server...")
    y = y + 1

    local gamesDir = fs.combine(programDir, "games")
    if not fs.exists(gamesDir) then
        term.setCursorPos(2, y); term.write("- Creating games directory...")
        y = y + 1
        fs.makeDir(gamesDir)
    end
    
    rednet.send(state.mailServerId, { type = "get_all_game_versions" }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 10)

    if not response or not response.versions then
        term.setCursorPos(2, y); term.write("- Could not fetch server game versions.")
        sleep(2)
        return
    end

    for filename, serverVersion in pairs(response.versions) do
        local localPath = fs.combine(gamesDir, filename)
        term.setCursorPos(2, y)
        term.clearLine()
        term.write("- Checking " .. filename .. "...")
        
        local localVersion = 0
        if fs.exists(localPath) then
            local file = fs.open(localPath, "r")
            if file then
                local content = file.readAll()
                file.close()
                local foundVersion = string.match(content, "%-%-%s*Version:%s*([%d%.]+)")
                if foundVersion then
                    localVersion = tonumber(foundVersion)
                end
            end
        end
        
        if serverVersion > localVersion then
            term.setCursorPos(4, y + 1); term.write("-> New version found! Downloading...")
            rednet.send(state.mailServerId, {type = "get_game_update", program = filename}, "SimpleMail")
            local _, update = rednet.receive("SimpleMail", 10)
            
            if update and update.code then
                local file = fs.open(localPath, "w")
                if file then
                    file.write(update.code)
                    file.close()
                    term.setCursorPos(4, y + 2); term.write("-> Update successful!")
                else
                    term.setCursorPos(4, y + 2); term.write("-> Error: Could not save file.")
                end
            else
                term.setCursorPos(4, y + 2); term.write("-> Error: Download failed.")
            end
            y = y + 3
        else
            y = y + 1
        end
    end
    term.setCursorPos(2, y + 1); term.write("Update check complete.")
    sleep(1.5)
end

--==============================================================================
-- Login & Main Menu Logic
--==============================================================================

-- Legacy local implementation moved to lib/drunken_os_apps.lua

-- Legacy loginOrRegister moved to lib/drunken_os_apps.lua

local function runAdminConsole(context)
    if not state.isAdmin or not state.adminServerId then return end
    
    local consolePath = "Admin_Console.lua"
    if not fs.exists(consolePath) then
        drawWindow("Downloading Admin Tools...")
        rednet.send(state.mailServerId, { type = "get_admin_tool", user = state.username }, "SimpleMail")
        local _, response = rednet.receive("SimpleMail", 5)
        
        if response and response.type == "admin_tool_response" and response.code then
            local f = fs.open(consolePath, "w")
            f.write(response.code)
            f.close()
        else
            context.showMessage("Error", "Could not download Admin Console.")
            return
        end
    end
    
    context.clear()
    local run_shell = context.shell or shell
    if run_shell and run_shell.run then
        run_shell.run(consolePath, state.username, state.adminServerId)
    else
        context.showMessage("Error", "Shell API unavailable.")
    end
end

-- Old mainMenu removed. See Refactored Main Menu below.

--==============================================================================
-- Program Entry Point
--==============================================================================

local function showSplashScreen()
    term.clear(); term.setCursorPos(1,1)
    term.setTextColor(colors.orange)
    local w,h = getSafeSize()
    local art = {
        "         . .        ",
        "       .. . *.      ",
        "- -_ _-__-0oOo      ",
        " _-_ -__ -||||)     ",
        "    ______||||______",
        "~~~~~~~~~~`\"\"'~   "
    }
    local title = "Drunken Beard OS"
    local startY = math.floor(h / 2) - math.floor(#art / 2) - 2
    for i, line in ipairs(art) do
        term.setCursorPos(math.floor(w / 2 - #line / 2), startY + i)
        term.write(line)
    end
    term.setCursorPos(math.floor(w / 2 - #title / 2), startY + #art + 2)
    term.write(title)
    sleep(1.5)
end


local function main()
    -- Safe Boot: Check for updates BEFORE any UI code runs
    peripheral.find("modem", rednet.open)
    local connected, reason = findServers()
    
    -- Try to update even if "findServers" failed (maybe we can reach mail server specifically?)
    -- But findServers sets state.mailServerId, so we need it.
    if connected then
         if autoUpdateCheck() then return end
    end

    showSplashScreen()
    while true do
        peripheral.find("modem", rednet.open)
        connected, reason = findServers()
        if not connected then
            local tempShowMessage = function(title, msg) term.clear(); term.setCursorPos(1,1); print(title.."\n"..msg); sleep(3) end
            tempShowMessage("Connection Error", reason or "Could not find servers. Retrying...")
            sleep(5)
        else
            -- Check again in loop, but strictly dependencies
            if not installDependencies() then
                rednet.close("back")
                return 
            end

            -- Load libraries after ensuring they exist
            if not crypto then crypto = require("lib.sha1_hmac") end
            if not apps then apps = require("lib.drunken_os_apps") end
            if not state.appLoader then state.appLoader = require("lib.app_loader") end

            state.crypto = crypto
            state.apps = apps
            
            -- Load shared libraries now that we know they exist
            if not theme then theme = require("lib.theme") end
            if not utils then utils = require("lib.utils") end
            colorToBlit = theme.colorToBlit
            wordWrap = utils.wordWrap
            printCentered = utils.printCentered

            -- Populate the shared context
            context.parent = state
            context.programDir = programDir
            context.theme = theme
            context.shell = shell
            context.clear = clear
            context.drawWindow = drawWindow
            context.drawMenu = drawMenu
            context.printCentered = printCentered
            context.showMessage = showMessage
            context.readInput = readInput
            context.getSafeSize = getSafeSize
            context.wordWrap = wordWrap

            state.username = nil
            state.isAdmin = false
            -- Pass 'context' so the library has access to UI functions
            if not state.apps.loginOrRegister(context) then 
                term.clear(); term.setCursorPos(1,1); print("Goodbye!"); break
            end
            
            -- Persist Session for SDK/Apps
            local f = fs.open(".session", "w")
            f.write(textutils.serialize({ username = state.username }))
            f.close()
            
            rednet.send(state.mailServerId, {type = "get_motd"}, "SimpleMail")
            local _, motd_response = rednet.receive("SimpleMail", 3)
            if motd_response and motd_response.motd and motd_response.motd ~= "" then
                state.apps.showMessage(state, "Message of the Day", motd_response.motd)
            end
            
            -- Helper to keep track of location (Stubbed for now)
local currentApp = nil
local running = true
local favorites = {} -- Loaded from disk

-- Notification State
local notification = {
    active = false,
    title = "",
    message = "",
    color = colors.blue,
    timerId = nil
}

-- Load/Save Favorites (Existing)
local function loadFavorites()
    if fs.exists(".favorites") then
        local f = fs.open(".favorites", "r")
        favorites = textutils.unserialize(f.readAll()) or {}
        f.close()
    end
end
local function saveFavorites()
    local f = fs.open(".favorites", "w")
    f.write(textutils.serialize(favorites))
    f.close()
end

-- Helper: Draw Notification Toast
local function drawNotification()
    if not notification.active then return end
    
    local w, h = term.getSize()
    local msg = notification.message
    local width = #msg + 4
    if width < 20 then width = 20 end
    local x = w - width - 1
    local y = 2 -- Below top bar
    
    -- Draw Box
    paintutils.drawFilledBox(x, y, x+width, y+2, notification.color)
    term.setCursorPos(x, y)
    term.setTextColor(colors.white)
    term.setBackgroundColor(notification.color)
    
    -- Title (Center or Left?)
    term.setCursorPos(x+1, y)
    term.write(notification.title)
    
    -- Message
    term.setCursorPos(x+1, y+1)
    term.write(msg)
    
    -- Border/Shadow? (Optional polish)
end

-- Helper: Trigger Notification
local function showNotification(title, msg, color)
    notification.active = true
    notification.title = title or "System"
    notification.message = msg or ""
    notification.color = color or colors.blue
    
    if notification.timerId then os.cancelTimer(notification.timerId) end
    notification.timerId = os.startTimer(4) -- 4 Seconds
end

local function toggleFavorite(appName)
    if favorites[appName] then
        favorites[appName] = nil
    else
        favorites[appName] = true
    end
    saveFavorites()
end

-- Refactored Main Menu
local function mainMenu()
    loadFavorites()
    
    while true do
        drawWindow("Drunken OS v" .. currentVersion)
        
        -- Build Menu Options
        local menuItems = {}
        
        -- 1. Favorites Section
        local hasFavs = false
        for appName, _ in pairs(favorites) do
            -- Verify app still exists
            local path = "apps/" .. appName .. ".lua" -- Assumption based on naming convention
            -- Actually, we need to map Display Name -> Filename.
            -- Our 'all_apps' list is just paths. display names are derived.
            -- Let's iterate all installed apps and match.
            hasFavs = true
        end
        
        -- Construct list: { label="Display", action=func, isApp=true, path=... }
        local mainOptions = {}
        
        -- A. Favorites
        for _, path in ipairs(fs.list("apps")) do
            if not fs.isDir("apps/"..path) then
                local name = path:gsub("%.lua$", "")
                local label = name:gsub("_", " ")
                if favorites[label] then
                   table.insert(mainOptions, { label = "★ " .. label, path = "apps/"..path, isApp = true }) 
                end
            end
        end
        
        -- Separator?
        
        -- B. Core Folders
        table.insert(mainOptions, { label = "[+] All Apps", isFolder = true })
        table.insert(mainOptions, { label = "[S] App Store", path = "apps/store.lua", isApp = true })
        table.insert(mainOptions, { label = "[*] System", path = "apps/system.lua", isApp = true })
        table.insert(mainOptions, { label = "[X] Shutdown", action = os.shutdown })
        table.insert(mainOptions, { label = "[R] Reboot", action = os.reboot })

        local selected = 1
        local inFolder = false
        
        -- Navigation Loop
        while true do
            drawWindow("Drunken OS v" .. currentVersion)
            
            local currentList = mainOptions
            local viewingFolder = nil
            
            if inFolder == "All Apps" then
                viewingFolder = "All Apps"
                currentList = {}
                 -- Populate All Apps
                for _, path in ipairs(fs.list("apps")) do
                    if not fs.isDir("apps/"..path) then
                        local name = path:gsub("%.lua$", "")
                        local label = name:gsub("_", " ")
                        -- Skip system/store/hidden? No, show all using folder.
                        table.insert(currentList, { label = label, path = "apps/"..path, isApp = true })
                    end
                end
                table.insert(currentList, { label = "⬅ Back", action = "back" })
            end
            
            -- Draw Menu
            local y = 4
            if viewingFolder then 
                term.setCursorPos(2, 3); term.setTextColor(colors.yellow); term.write("Folder: " .. viewingFolder) 
            end
            
            for i, opt in ipairs(currentList) do
                term.setCursorPos(2, y)
                if i == selected then
                    term.setTextColor(theme.highlightText)
                    term.setBackgroundColor(theme.highlightBg)
                    term.write(" " .. opt.label .. string.rep(" ", 20 - #opt.label) .. " ")
                    term.setBackgroundColor(theme.bg)
                    
                    -- Show Hint
                    if opt.isApp and viewingFolder == "All Apps" then
                        term.setCursorPos(2, 18)
                        term.setTextColor(colors.gray)
                        term.write("Press 'F' to Pin/Unpin")
                    end
                else
                    term.setTextColor(theme.text)
                    term.write(" " .. opt.label .. " ")
                end
                y = y + 1
            end
            
            local event, key = os.pullEvent("key")
            if key == keys.up then selected = (selected == 1) and #currentList or selected - 1
            elseif key == keys.down then selected = (selected == #currentList) and 1 or selected + 1
            elseif key == keys.enter then
                local choice = currentList[selected]
                if choice.action == "back" then
                    inFolder = false; selected = 1
                elseif choice.isFolder then
                    inFolder = choice.label:gsub("%[%+%] ", ""); selected = 1
                elseif choice.isApp then
                    -- Run App using app_loader which has proper environment
                    local appName = choice.path:match("apps/(.+)%.lua$")
                    if appName then
                        state.appLoader.run(appName, context)
                    else
                        context.showMessage("Error", "Invalid app path: " .. choice.path)
                    end
                    -- Refresh favorites on return
                    break -- breaks inner loop, reloads outer loop
                elseif choice.action then
                    choice.action()
                end 
            elseif key == keys.f and inFolder == "All Apps" then
                local choice = currentList[selected]
                if choice.isApp then
                   -- Toggle Favorite
                   toggleFavorite(choice.label)
                   context.showMessage("Favorites", "Toggled " .. choice.label)
                end
            end
        end
end
end

-- Helper to keep track of location (Stubbed for now)
local function gpsHeartbeat()
    while true do
        sleep(60)
    end
end

-- Background Listener for Merchant Requests & Broadcasts
local function backgroundListener()
                local lastSync = 0
                while true do
                    local now = os.epoch("utc") / 1000
                    -- Fast poll for rednet messages
                    local senderId, message, protocol = rednet.receive(nil, 0.5)
                    
                    if protocol == "DB_Merchant_Req" and message then
                        if message.type == "payment_request" and message.target == state.username then
                            if not state.pendingInvoices then state.pendingInvoices = {} end
                            table.insert(state.pendingInvoices, message)
                            local speaker = peripheral.find("speaker")
                            if speaker then speaker.playNote("pling", 1, 2) end
                        end
                    elseif protocol == "DB_Shop_Broadcast" and message and message.menu then
                        state.nearbyShop = message
                    end
                    
                    -- Occasional sync (Mail/Unread count) every 10 seconds
                    if now - lastSync > 10 then
                        rednet.send(state.mailServerId, { type = "get_unread_count", user = state.username }, "SimpleMail")
                        local _, response = rednet.receive("SimpleMail", 1)
                        if response and response.count then
                            state.unreadCount = response.count
                        end
                        lastSync = now
                    end
                end
            end

            parallel.waitForAny(mainMenu, gpsHeartbeat, backgroundListener)
            
            peripheral.find("modem", rednet.close)
            if not state.username then
                clear(); print("Goodbye!"); break
            end
        end
    end
end


main()
