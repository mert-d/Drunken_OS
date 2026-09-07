--[[
    Drunken OS - Mobile Client (v16.7 - Performance Edition)
    by MuhendizBey
]]

--==============================================================================
-- Environment & Path Setup
--==============================================================================

local programDir = (shell and shell.getRunningProgram and fs.getDir(shell.getRunningProgram())) or ""
-- Construct a clean, predictable package search path
-- We use full module names (e.g. require("lib.sha1_hmac")), so we only need ?.lua
local paths = {
    "?.lua",
    "?/init.lua",
    (programDir ~= "" and fs.combine(programDir, "?.lua") or nil),
    (programDir ~= "" and fs.combine(programDir, "?/init.lua") or nil)
}
package.path = table.concat(paths, ";") .. ";" .. package.path
local crypto = require("lib.sha1_hmac")
local ok_dns, dns = pcall(require, "lib.dns")
if ok_dns and dns and dns.patchRednet then
    dns.patchRednet()
end

--==============================================================================
-- Configuration & State
--==============================================================================

local currentVersion = 16.8
local programName = "Drunken_OS_Client" -- Correct program name for updates
local SESSION_FILE = ".session"
local REQUIRED_LIBS = {
    { name = "sha1_hmac" },
    { name = "updater" },
    { name = "drunken_os_apps" },
    { name = "app_loader" },
    { name = "theme" },
    { name = "utils" },
    { name = "p2p_socket" },
    { name = "dns" },
    { name = "crypto_packet" },
    { name = "transfer" },
    { name = "rpc" }
}

local REQUIRED_APPS = {
    "mail", "bank", "files", "chat", "arcade", "system", "merchant", "calc", "notes", "remote", "radar"
}

--==============================================================================
-- UI & Theme Helpers
--==============================================================================

local sdk = require("lib.sdk")
local theme = require("lib.theme")
local utils = require("lib.utils")
local wordWrap = utils.wordWrap
local printCentered = utils.printCentered
local colorToBlit = theme.colorToBlit

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

---
-- Clears the terminal and resets the cursor to the top-left corner.
local function clear()
    term.clear()
    term.setCursorPos(1,1)
end

---
-- Draws a standard OS window frame with a centered title bar.
-- This creates a consistent look and feel across all applications.
-- @param title The text to display in the top title bar.
local function drawWindow(title)
    -- Route through lib/utils.lua
    -- utils and theme are loaded at top-level or main()
    local ctx = { theme = theme }
    utils.drawWindow(title, ctx)
end

-- printCentered moved to lib.utils

---
-- Displays a standard message dialog to the user, pausing execution until acknowledged.
-- @param title The title text of the message box.
-- @param message The main content text to display.
local function showMessage(title, message)
    -- Route through lib/sdk.lua
    sdk.UI.showMessage(title, message)
end

---
-- Renders a multi-item vertical menu on screen, highlighting the selected item.
-- @param options A table of string labels for the menu items.
-- @param selected The index of the currently selected option.
-- @param startX The initial X coordinate to draw the menu list.
-- @param startY The initial Y coordinate to start the menu list.
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

---
-- Prompts the user for text input at a specific Y coordinate.
-- @param prompt The prompt text displayed before the cursor.
-- @param y The Y coordinate to draw the prompt on.
-- @param isPassword Boolean determining whether typed characters should be masked with '*'.
-- @return The string inputted by the user.
local function readInput(prompt, y, isPassword)
    term.setCursorPos(2, y)
    term.setTextColor(theme.prompt)
    term.write(prompt)
    term.setTextColor(theme.text)
    term.setCursorBlink(true)
    local input = read(isPassword and "*" or nil)
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
    -- Look for Auth service
    state.authServerId = rednet.lookup("auth.secure.v1", "auth.server")
    
    state.adminServerId = state.mailServerId -- Unified mainframe admin
    
    if not state.mailServerId then
        return false, "Mainframe (mail.server) not found."
    elseif not state.authServerId then
        return false, "Auth Server (auth.server) not found."
    end
    return true
end

state.crypto = crypto

-- Context is fully populated inside main() after libraries are loaded.
-- Declared here at module scope so functions like drawWindow can reference it.
context = {}

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
    package.loaded["lib.updater"] = nil
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
        -- Clear package.loaded cache so updated libraries take effect immediately
        local libs = {"lib.sha1_hmac", "lib.drunken_os_apps", "lib.app_loader", "lib.theme", "lib.utils", "lib.p2p_socket", "lib.sdk"}
        for _, lib in ipairs(libs) do package.loaded[lib] = nil end
        
        -- Reset local references so they are re-required in main()
        crypto, apps, state.appLoader, theme, utils = nil, nil, nil, nil, nil
        
        print("System integrity verified. Hot-reloaded libraries.")
        return true
    else
        print("Manifest sync failed. Running in offline/cached mode.")
        sleep(1)
    end
    
    return true
end

---
-- Checks the Mainframe server to see if a newer version of the Drunken_OS_Client exists.
-- If an update is available, it silently downloads it, overwrites the current program, and reboots.
-- @return {boolean} True if an update was triggered (which calls os.reboot), false otherwise.
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
            local path = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "Drunken_OS_Client.lua"
            local parentDir = fs.getDir(path)
            if parentDir and parentDir ~= "" and not fs.exists(parentDir) then
                fs.makeDir(parentDir)
            end
            local file = fs.open(path, "w")
            if file then
                file.write(update.code)
                file.close()
                print("Update complete. Rebooting...")
                sleep(2)
                os.reboot()
                return true
            else
                print("Update failed: could not write to file.")
                sleep(2)
            end
        else
            print("Update failed.")
            sleep(2)
        end
    end
    return false
end

---
-- Synchronizes the local library of games with the server's master list.
-- Checks local file versions and downloads newer versions from the Mainframe if necessary.
local function updateGames()
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
                -- Use same version parsing patterns as the server
                local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)")
                       or content:match("local%s+appVersion%s*=%s*([%d%.]+)")
                       or content:match("%(v([%d%.]+)%)")
                       or content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
                localVersion = tonumber(v) or 0
            end
        end
        
        if serverVersion > localVersion then
            term.setCursorPos(4, y + 1); term.write("-> New version found! Downloading...")
            -- Use get_file which the Mainframe already handles (get_game_update doesn't exist)
            rednet.send(state.mailServerId, {type = "get_file", path = "games/" .. filename}, "SimpleMail")
            local _, update = rednet.receive("SimpleMail", 10)
            
            if update and update.success and update.code then
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

---
-- Attempts to download and execute the Admin Console tool from the server.
-- @param context The shared UI state context, passed into the tool.
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

--==============================================================================
-- Program Entry Point
--==============================================================================

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

---
-- Core OS shell navigation loop. Replaces standard terminal UI.
-- Responsible for rendering favorites, app directories, and handling generic OS navigation keys.
local function mainMenu()
    loadFavorites()
    
    while true do
        context.drawWindow("Drunken OS v" .. currentVersion)
        
        -- Build Menu Options
        local menuItems = {}
        
        -- 1. Favorites Section
        local hasFavs = false
        for appName, _ in pairs(favorites) do
            -- Verify app still exists
            local path = "apps/" .. appName .. ".lua" -- Assumption based on naming convention
            hasFavs = true
        end
        
        -- Construct list: { label="Display", action=func, isApp=true, path=... }
        local mainOptions = {}
        
        -- A. Favorites
        if fs.exists("apps") and fs.isDir("apps") then
            for _, path in ipairs(fs.list("apps")) do
                if not fs.isDir("apps/"..path) and path:match("%.lua$") then
                    local name = path:gsub("%.lua$", "")
                    local label = name:gsub("_", " ")
                    if favorites[label] then
                        local display = name:gsub("(%a)([%w_']*)", function(first, rest)
                            return first:upper() .. rest:lower():gsub("_", " ")
                        end)
                        table.insert(mainOptions, { label = "★ " .. display, path = "apps/"..path, isApp = true }) 
                    end
                end
            end
        end
        
        -- Default shortcuts if no user favorites pinned yet
        if not hasFavs then
            local defaults = { "mail", "bank", "chat", "arcade", "files", "calc", "notes", "remote", "radar", "drunken_bites" }
            for _, d in ipairs(defaults) do
                local p = "apps/" .. d .. ".lua"
                if fs.exists(p) then
                    local display = d:gsub("(%a)([%w_']*)", function(first, rest)
                        return first:upper() .. rest:lower():gsub("_", " ")
                    end)
                    table.insert(mainOptions, { label = "★ " .. display, path = p, isApp = true })
                end
            end
        end
        
        -- B. Core Folders
        table.insert(mainOptions, { label = "[+] All Apps", isFolder = true })
        table.insert(mainOptions, { label = "[S] App Store", path = "apps/store.lua", isApp = true })
        table.insert(mainOptions, { label = "[*] System", path = "apps/system.lua", isApp = true })
        table.insert(mainOptions, { label = "[X] Shutdown", action = os.shutdown })
        table.insert(mainOptions, { label = "[R] Reboot", action = os.reboot })

        local selected = 1
        local scrollOffset = 0
        local inFolder = false
        local cachedAllApps = nil
        
        local function executeChoice(choice)
            if not choice then return true end
            if choice.action == "back" then
                inFolder = false
                selected = 1
                scrollOffset = 0
                return true
            elseif choice.isFolder then
                inFolder = choice.label:gsub("%[%+%] ", "")
                selected = 1
                scrollOffset = 0
                return true
            elseif choice.isApp then
                local appName = choice.path:match("apps/(.+)%.lua$")
                if appName then
                    state.appLoader.run(appName, context)
                else
                    context.showMessage("Error", "Invalid app path: " .. choice.path)
                end
                return false -- break inner loop to reload on return
            elseif choice.action then
                choice.action()
                return true
            end
            return true
        end

        -- Navigation Loop
        while true do
            local w, h = term.getSize()
            context.drawWindow("Drunken OS v" .. currentVersion)
            
            local currentList = mainOptions
            local viewingFolder = nil
            
            if inFolder == "All Apps" then
                viewingFolder = "All Apps"
                if not cachedAllApps then
                    cachedAllApps = {}
                    -- Populate All Apps
                    if fs.exists("apps") and fs.isDir("apps") then
                        local appList = fs.list("apps")
                        table.sort(appList)
                        for _, path in ipairs(appList) do
                            if not fs.isDir("apps/"..path) and path:match("%.lua$") then
                                local name = path:gsub("%.lua$", "")
                                local label = name:gsub("(%a)([%w_']*)", function(first, rest)
                                    return first:upper() .. rest:lower():gsub("_", " ")
                                end)
                                -- Exclude daemon turtle scripts from GUI client
                                if not name:find("turtle") then
                                    table.insert(cachedAllApps, { label = label, path = "apps/"..path, isApp = true })
                                end
                            end
                        end
                    end
                    table.insert(cachedAllApps, { label = "⬅ Back", action = "back" })
                end
                currentList = cachedAllApps
            end
            
            -- Draw Menu
            local startY = 3
            if viewingFolder then 
                term.setCursorPos(2, startY)
                term.setTextColor(colors.yellow)
                term.write("Folder: " .. viewingFolder) 
                startY = startY + 1
            end
            
            local maxVisible = h - startY - 1
            if maxVisible < 1 then maxVisible = 1 end

            -- Keep selected within bounds
            if selected < 1 then selected = 1 end
            if selected > #currentList then selected = #currentList end

            -- Adjust scrollOffset so selected is always visible
            if selected <= scrollOffset then
                scrollOffset = selected - 1
            elseif selected > scrollOffset + maxVisible then
                scrollOffset = selected - maxVisible
            end
            if scrollOffset < 0 then scrollOffset = 0 end
            if scrollOffset > math.max(0, #currentList - maxVisible) then
                scrollOffset = math.max(0, #currentList - maxVisible)
            end

            -- Scroll indicator at top
            if scrollOffset > 0 then
                term.setCursorPos(w - 2, startY - 1)
                term.setTextColor(colors.yellow)
                term.write("^")
            end

            for i = 1, maxVisible do
                local itemIdx = scrollOffset + i
                local opt = currentList[itemIdx]
                if opt then
                    local y = startY + (i - 1)
                    term.setCursorPos(2, y)
                    if itemIdx == selected then
                        term.setTextColor(theme.highlightText)
                        term.setBackgroundColor(theme.highlightBg)
                        local itemWidth = math.min(w - 3, 24)
                        local displayLabel = opt.label
                        if #displayLabel < itemWidth then
                            displayLabel = displayLabel .. string.rep(" ", itemWidth - #displayLabel)
                        end
                        term.write(" " .. displayLabel .. " ")
                        term.setBackgroundColor(theme.bg)
                        
                        -- Show Pin Hint
                        if opt.isApp and viewingFolder == "All Apps" and h >= 16 then
                            term.setCursorPos(2, h - 1)
                            term.setTextColor(theme.mutedText or colors.gray)
                            term.write("[F] Pin/Unpin Shortcut")
                        end
                    else
                        term.setTextColor(theme.text)
                        term.write(" " .. opt.label .. " ")
                    end
                end
            end

            -- Scroll indicator at bottom
            if scrollOffset + maxVisible < #currentList then
                term.setCursorPos(w - 2, startY + maxVisible)
                term.setTextColor(colors.yellow)
                term.write("v")
            end
            
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                local key = p1
                if key == keys.up then
                    selected = (selected == 1) and #currentList or selected - 1
                elseif key == keys.down then
                    selected = (selected == #currentList) and 1 or selected + 1
                elseif key == keys.enter then
                    local choice = currentList[selected]
                    if not executeChoice(choice) then break end
                elseif key == keys.f and inFolder == "All Apps" then
                    local choice = currentList[selected]
                    if choice and choice.isApp then
                        toggleFavorite(choice.label)
                        context.showMessage("Favorites", "Toggled " .. choice.label)
                    end
                end
            elseif event == "mouse_click" then
                local btn, clickX, clickY = p1, p2, p3
                local relativeRow = clickY - startY + 1
                if relativeRow >= 1 and relativeRow <= maxVisible then
                    local clickedIdx = scrollOffset + relativeRow
                    if clickedIdx >= 1 and clickedIdx <= #currentList then
                        selected = clickedIdx
                        local choice = currentList[selected]
                        if not executeChoice(choice) then break end
                    end
                end
            elseif event == "mouse_scroll" then
                local dir = p1
                if dir < 0 then
                    selected = (selected == 1) and #currentList or selected - 1
                else
                    selected = (selected == #currentList) and 1 or selected + 1
                end
            end
        end
    end
end

-- GPS Heartbeat: Polls for location every 60 seconds and reports to the Mainframe.
-- Falls back silently if GPS is unavailable (no satellites / no modem).
local function gpsHeartbeat()
    while true do
        sleep(60)
        if state.username and state.mailServerId then
            local x, y, z = gps.locate(2) -- 2 second timeout
            if x then
                state.location = { x = x, y = y, z = z }
                rednet.send(state.mailServerId, {
                    type = "report_location",
                    user = state.username,
                    x = x, y = y, z = z
                }, "SimpleMail")
            end
        end
    end
end

---
-- Background Rednet Listener Thread.
-- Constantly processes incoming messages across multiple protocols without interrupting UI.
-- For example: Merchant payment requests, unread mail counts, or shop discovery broadcasts.
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
        elseif protocol == "DrunkenRadar" and type(message) == "table" and message.type == "radar_ping" then
            local myGps = state.location
            if not myGps and gps and gps.locate then
                local gx, gy, gz = gps.locate(0.2)
                if gx and gy and gz then myGps = { x = math.floor(gx), y = math.floor(gy), z = math.floor(gz) } end
            end
            rednet.send(senderId, {
                type = "radar_pong",
                id = os.getComputerID(),
                user = state.username or "Pocket User",
                device = "Pocket",
                label = os.getComputerLabel() or ("Pocket #" .. os.getComputerID()),
                gps = myGps
            }, "DrunkenRadar")
        end
        
        -- Occasional sync (Mail/Unread count & Pending Game Scores) every 10 seconds
        if now - lastSync > 10 then
            pcall(function()
                local scoreCache = require("lib.score_cache")
                scoreCache.syncPending()
            end)
            if state.mailServerId then
                rednet.send(state.mailServerId, { type = "get_unread_count", user = state.username }, "SimpleMail")
                local _, response = rednet.receive("SimpleMail", 0.5)
                if response and response.count then
                    state.unreadCount = response.count
                end
            end
            lastSync = now
        end
    end
end

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
    
    -- Check for updates.
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
                rednet.close(peripheral.getName(peripheral.find("modem")))
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
            f.write(textutils.serialize({ username = state.username, session_token = state.session_token }))
            f.close()
            
            rednet.send(state.mailServerId, {type = "get_motd"}, "SimpleMail")
            local _, motd_response = rednet.receive("SimpleMail", 3)
            if motd_response and motd_response.motd and motd_response.motd ~= "" then
                context.showMessage("Message of the Day", motd_response.motd)
            end
            
            -- Background listeners extracted to core scope

            parallel.waitForAny(mainMenu, gpsHeartbeat, backgroundListener)
            
            peripheral.find("modem", rednet.close)
            if not state.username then
                clear(); print("Goodbye!"); break
            end
        end -- else
    end -- while true
end -- main()


main()
