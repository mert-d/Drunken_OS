--[[
    Drunken OS - Mobile Client (v14.0 - Modular Refactor)
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

local currentVersion = 14.1
local programName = "Drunken_OS_Client" -- Correct program name for updates
local SESSION_FILE = ".session"
local REQUIRED_LIBS = {
    { name = "sha1_hmac" },
    { name = "updater" },
    { name = "drunken_os_apps" },
    { name = "app_loader" }
}

local REQUIRED_APPS = {
    "mail", "bank", "files", "chat", "arcade", "system", "merchant"
}

--==============================================================================
-- UI & Theme Helpers
--==============================================================================

local theme = {
    bg = colors.black,
    text = colors.white,
    prompt = colors.cyan,
    titleBg = colors.blue,
    titleText = colors.white,
    highlightBg = colors.cyan,
    highlightText = colors.black,
    errorBg = colors.red,
    errorText = colors.white,
    windowBg = colors.black -- Alias for apps library
}

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

-- Universal word-wrap
local function wordWrap(text, maxWidth)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        while #line > maxWidth do
            local breakPoint = maxWidth
            while breakPoint > 0 and line:sub(breakPoint, breakPoint) ~= " " do
                breakPoint = breakPoint - 1
            end
            if breakPoint == 0 then breakPoint = maxWidth end
            table.insert(lines, line:sub(1, breakPoint))
            line = line:sub(breakPoint + 1)
        end
        table.insert(lines, line)
    end
    return lines
end

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

local function printCentered(startY, message)
    local w, h = term.getSize()
    -- USE W-2 to maximize space, and 3 column/row padding for frame
    local lines = wordWrap(message, w - 2)
    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, startY + i - 1)
        term.write(line)
    end
end

local function showMessage(title, message)
    drawWindow(title)
    local w, h = term.getSize()
    printCentered(4, message)
    
    local continueText = "Press any key to continue..."
    term.setCursorPos(math.floor((w - #continueText) / 2) + 1, h - 1)
    term.setTextColor(colors.gray)
    term.write(continueText)
    os.pullEvent("key")
end

local function drawMenu(options, selected, startX, startY)
    local w, h = term.getSize()
    for i, opt in ipairs(options) do
        term.setCursorPos(startX, startY + i - 1)
        if i == selected then
            term.setBackgroundColor(theme.highlightBg)
            term.setTextColor(theme.highlightText)
            term.write(" " .. opt .. string.rep(" ", w - startX - #opt - 1) .. " ")
        else
            term.setBackgroundColor(theme.bg)
            term.setTextColor(theme.text)
            term.write(" " .. opt .. " ")
        end
    end
    term.setBackgroundColor(theme.bg)
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
    
    -- Sync essential libraries defined in REQUIRED_LIBS
    for _, libDef in ipairs(REQUIRED_LIBS) do
        local libName = libDef.name
        local libPath = fs.combine(programDir, "lib/" .. libName .. ".lua")
        
        local currentVer = 0
        if fs.exists(libPath) then
            -- Determine the current local version
            local ok, libOrError = pcall(require, "lib." .. libName)
            if ok and type(libOrError) == "table" then
                currentVer = libOrError._VERSION or 0
                if currentVer == 0 then
                    -- Fallback: Parse the version from the file header
                    local f = fs.open(libPath, "r")
                    if f then
                        local content = f.readAll()
                        f.close()
                        local v = content:match("%.?_VERSION%s*=%s*([%d%.]+)")
                        if not v then v = content:match("%(v([%d%.]+)%)") end
                        currentVer = tonumber(v) or 0
                    end
                end
            end
        end

        -- Check with server and download if a newer version exists
        if updater.check(libName, currentVer, libPath) then
            needsReboot = true
        end
    end

    -- Sync Apps
    if not fs.exists(fs.combine(programDir, "apps")) then fs.makeDir(fs.combine(programDir, "apps")) end
    for _, appName in ipairs(REQUIRED_APPS) do
        local appPath = fs.combine(programDir, "apps/" .. appName .. ".lua")
        -- We don't have version tracking for apps yet, so we'll just ensure they exist or use updater.check if we add them to DB
        -- For now, let's just use the same check but targeting the apps folder
        if updater.check("app." .. appName, 0, appPath) then
            -- Note: We prefix app names with 'app.' in the server DB to avoid collisions
        end
    end
    
    if needsReboot then
        print("System components updated. Rebooting...")
        sleep(2)
        os.reboot()
        return true 
    end
    
    return true
end

local function autoUpdateCheck()
    rednet.send(state.mailServerId, { type = "get_version", program = programName }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 15)
    if response and response.version and response.version > currentVersion then
        term.clear(); term.setCursorPos(1, 1)
        print("New version available: " .. response.version)
        print("Downloading update...")
        rednet.send(state.mailServerId, { type = "get_update", program = programName }, "SimpleMail")
        local _, update = rednet.receive("SimpleMail", 10)
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
    sleep(2)
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

local function mainMenu()
    -- Security cleanup: If not admin, ensure tool is removed
    if not state.isAdmin and fs.exists("Admin_Console.lua") then
        fs.delete("Admin_Console.lua")
    end

    while true do
        rednet.send(state.mailServerId, { type = "get_unread_count", user = state.username }, "SimpleMail")
        local _, response = rednet.receive("SimpleMail", 2)
        state.unreadCount = response and response.count or 0
        
        local invoiceCount = state.pendingInvoices and #state.pendingInvoices or 0
        local payLabel = "Pay Merchant" .. (invoiceCount > 0 and " ("..invoiceCount.." pending)" or "")

        local options = {
            "Pocket Bank",
            payLabel,
            "File Manager",
            "Mail" .. (state.unreadCount > 0 and " (" .. state.unreadCount .. " unread)" or ""),
            "General Chat", 
            "Games", 
            "System", 
            "Logout"
        }
        
        -- THE FIX: Correctly check for admin status
        if state.isAdmin then
            table.insert(options, "Admin Console")
        end
        
        local selected = 1
        local choice = nil
        
        while true do
            -- Redraw menu
            drawWindow("Home")
            drawMenu(options, selected, 2, 4)
            
            -- Handle Input
            local event, key = os.pullEvent("key")
            if key == keys.up then
                selected = (selected == 1) and #options or selected - 1
            elseif key == keys.down then
                selected = (selected == #options) and 1 or selected + 1
            elseif key == keys.enter then
                choice = selected
                break
            elseif key == keys.q or key == keys.tab then
                -- choice remains nil, signals exit
                break
            end
        end
        
        if not choice or options[choice] == "Logout" then break end
        
        local selection = options[choice]
        -- Use 'appLoader' for dynamic apps
        if selection == "Pocket Bank" then state.appLoader.run("bank", context)
        elseif selection == "Pay Merchant" then state.appLoader.run("bank", context, "pay")
        elseif selection == "File Manager" then state.appLoader.run("files", context)
        elseif selection:match("^Mail") then state.appLoader.run("mail", context)
        elseif selection == "General Chat" then state.appLoader.run("chat", context)
        elseif selection == "Games" then state.appLoader.run("arcade", context)
        elseif selection == "System" then state.appLoader.run("system", context)
        elseif selection == "Admin Console" then runAdminConsole(context)
        end
    end
    state.username = nil -- Signal logout
end

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
            
            rednet.send(state.mailServerId, {type = "get_motd"}, "SimpleMail")
            local _, motd_response = rednet.receive("SimpleMail", 3)
            if motd_response and motd_response.motd and motd_response.motd ~= "" then
                state.apps.showMessage(state, "Message of the Day", motd_response.motd)
            end
            
            -- Helper to keep track of location (Stubbed for now)
            local function gpsHeartbeat()
                while true do
                    -- Update state.location if/when needed
                    sleep(60)
                end
            end

            -- Background Listener for Merchant Requests & Broadcasts
            local function merchantListener()
                while true do
                    -- Listen for Payment Requests (Targeted)
                    local senderId, message, protocol = rednet.receive("DB_Merchant_Req")
                    if senderId and message then
                        -- Verify it's for us
                        if message.type == "payment_request" and message.target == state.username then
                             -- Add notification to a queue or just pop up if idle?
                             -- For now, let's use a temporary HUD notification if possible.
                             -- Or just rely on the user checking "Pay Merchant".
                             -- Better: Add to a "Pending Invoices" list in state?
                             if not state.pendingInvoices then state.pendingInvoices = {} end
                             table.insert(state.pendingInvoices, message)
                             
                             -- Play sound
                             local speaker = peripheral.find("speaker")
                             if speaker then speaker.playNote("pling", 1, 2) end
                        end
                    end
                    
                    -- Listen for Shop Broadcasts (Public)
                    -- We can use a short timeout since we're in parallel
                    local b_sender, b_msg = rednet.receive("DB_Shop_Broadcast", 0.5)
                    if b_sender and b_msg and b_msg.menu then
                        -- Store the latest shop we saw
                        state.nearbyShop = b_msg
                    end
                    
                    -- Cleanup old nearbyShop if no signal?
                    -- Simplified: Just overwrite whenever we see one.
                end
            end

            parallel.waitForAny(mainMenu, gpsHeartbeat, merchantListener)
            
            peripheral.find("modem", rednet.close)
            if not state.username then
                clear(); print("Goodbye!"); break
            end
        end
    end
end


main()
