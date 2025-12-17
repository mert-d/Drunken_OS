```lua
--[[
    Drunken OS - Mobile Client (v12.0 - Release Version)
    by Gemini Gem & MuhendizBey

    Purpose:
    This definitive client version is fully compatible with the new unified
    code distribution system of Server v10.6+.

    Key Changes:
    - Version number incremented to v11.9.
    - Corrected the `autoUpdateCheck` to use the `programName` variable,
      ensuring it correctly checks its own version against the server.
    - No other functional changes needed; the installer logic from v11.7
      is already compatible with the new server.
]]

--==============================================================================
-- Environment & Path Setup
--==============================================================================

-- Get the directory where this program is running.
local programDir = fs.getDir(shell.getRunningProgram())

-- Add the program's local library folder to the list of places Lua looks for modules.
package.path = "/?.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path

--==============================================================================
-- Configuration & State
--==============================================================================

local currentVersion = 11.9
local programName = "Drunken_OS_Client" -- Correct program name for updates
local SESSION_FILE = ".session"
local REQUIRED_LIBS = { "sha1_hmac", "drunken_os_apps" }

-- This table holds the program's state, which is passed to the app library.
local state = {
    mailServerId = nil,
    chatServerId = nil,
    gameServerId = nil,
    username = nil,
    nickname = nil,
    session_token = nil,
    isAdmin = false,
    programDir = programDir,
    -- Forward-declare functions so the app library can call them
    showMessage = nil,
    drawMenu = nil,
    drawWindow = nil,
    getSafeSize = nil,
    wordWrap = nil
}

--==============================================================================
-- UI & Theme
--==============================================================================

local hasColor = term.isColor and term.isColor()
local function safeColor(colorName, fallbackColor)
    if hasColor and colors[colorName] ~= nil then
        return colors[colorName]
    end
    return fallbackColor
end

local theme = {
    bg = safeColor("black", colors.black),
    text = safeColor("white", colors.white),
    windowBg = safeColor("darkGray", colors.gray),
    border = safeColor("lightGray", colors.white),
    title = safeColor("green", colors.lime),
    prompt = safeColor("cyan", colors.cyan),
    highlightBg = safeColor("blue", colors.blue),
    highlightText = safeColor("white", colors.white),
    statusBarBg = safeColor("gray", colors.lightGray),
    statusBarText = safeColor("white", colors.white),
}

--==============================================================================
-- Core Utility & UI Functions
--==============================================================================

local function getSafeSize()
    local w, h = term.getSize()
    while not w or not h do
        sleep(0.05)
        w, h = term.getSize()
    end
    return w, h
end

local function wordWrap(text, width)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        while #line > width do
            local space = line:sub(1, width + 1):match(".+ ")
            local len = space and #space or width
            table.insert(lines, line:sub(1, len - 1))
            line = line:sub(len):match("^%s*(.*)")
        end
        table.insert(lines, line)
    end
    return lines
end

local function clear()
    term.setBackgroundColor(theme.bg)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawWindow(title)
    clear()
    local w, h = getSafeSize()
    term.setBackgroundColor(theme.windowBg)
    for y = 1, h - 1 do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", w))
    end

    term.setBackgroundColor(theme.title)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", w))
    term.setTextColor(colors.white)
    local titleText = " " .. title .. " "
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, 1)
    term.write(titleText)
    
    term.setBackgroundColor(theme.statusBarBg)
    term.setTextColor(theme.statusBarText)
    term.setCursorPos(1, h)
    term.write(string.rep(" ", w))
    local userText = "User: " .. (state.nickname or "Guest") .. (state.isAdmin and " (Admin)" or "")
    local versionText = "v" .. currentVersion
    
    if w < 35 then
        local statusText = userText .. " | " .. versionText
        term.setCursorPos(math.floor((w - #statusText) / 2) + 1, h)
        term.write(statusText)
    else
        local helpText = "See 'Help' Menu for Controls"
        term.setCursorPos(2, h)
        term.write(userText)
        term.setCursorPos(w - #versionText, h)
        term.write(versionText)
        term.setCursorPos(math.floor((w - #helpText) / 2) + 1, h)
        term.write(helpText)
    end

    term.setBackgroundColor(theme.windowBg)
    term.setTextColor(theme.text)
end

local function drawMenu(options, selectedIndex, startX, startY)
    for i, option in ipairs(options) do
        local text = option
        if (option == "Mail" or option == "View Inbox") and state.unreadCount > 0 then
            text = text .. " [" .. state.unreadCount .. "]"
        end
        term.setCursorPos(startX, startY + i - 1)
        if i == selectedIndex then
            term.setBackgroundColor(theme.highlightBg)
            term.setTextColor(theme.highlightText)
            term.write("> " .. text .. string.rep(" ", 25 - #text))
        else
            term.setBackgroundColor(theme.windowBg)
            term.setTextColor(theme.text)
            term.write("  " .. text .. string.rep(" ", 25 - #text))
        end
    end
    term.setBackgroundColor(theme.windowBg)
end

local function showMessage(title, message)
    drawWindow(title)
    local w, h = getSafeSize()
    local lines = wordWrap(message, w - 4)
    for i, line in ipairs(lines) do
        term.setCursorPos(3, 4 + i - 1)
        term.write(line)
    end
    term.setCursorPos(3, 4 + #lines + 1)
    term.setTextColor(theme.prompt)
    term.write("Press any key to continue...")
    os.pullEvent("key")
    term.setTextColor(theme.text)
end

local function readInput(prompt, y, hideText)
    local x = 2
    term.setTextColor(theme.prompt)
    term.setCursorPos(x, y)
    term.write(prompt)
    term.setTextColor(theme.text)
    term.setCursorPos(x + #prompt, y)
    term.setCursorBlink(true)
    local input = hideText and read("*") or read()
    term.setCursorBlink(false)
    return input
end

-- Create the context table that will be passed to library functions
local context = {
    getSafeSize = getSafeSize,
    wordWrap = wordWrap,
    clear = clear,
    drawWindow = drawWindow,
    drawMenu = drawMenu,
    showMessage = showMessage,
    readInput = readInput,
    theme = theme,
    programDir = programDir, -- Pass the program's directory to the library
    parent = state -- a reference to the main state table
}

--==============================================================================
-- Installation & Update Functions
--==============================================================================

local function findServers()
    state.mailServerId = rednet.lookup("SimpleMail", "mail.server")
    if not state.mailServerId then return false, "Cannot find mail.server" end
    
    state.chatServerId = rednet.lookup("SimpleChat", "chat.server")
    if not state.chatServerId then return false, "Cannot find chat.server" end

    state.gameServerId = rednet.lookup("ArcadeGames", "arcade.server")
    if not state.gameServerId then return false, "Cannot find arcade.server" end
    
    return true
end

local function installDependencies()
    local needsReboot = false
    for _, libName in ipairs(REQUIRED_LIBS) do
        local ok = pcall(require, "lib." .. libName)
        if not ok then
            needsReboot = true -- A reboot will be required if we install anything.
            term.clear(); term.setCursorPos(1,1)
            print("Missing required library: " .. libName)
            print("Attempting to download from server...")

            local server = rednet.lookup("SimpleMail", "mail.server")
            if not server then
                print("Error: Cannot find mail.server to download libraries.")
                print("Please check server and network connection.")
                return false -- Halt execution
            end

            -- Use the new, direct code transfer protocol.
            rednet.send(server, { type = "get_lib_code", lib = libName }, "SimpleMail")
            local _, response = rednet.receive("SimpleMail", 10) -- Increased timeout for reliability
            
            if response and response.success and response.code then
                print("Download successful. Installing...")
                local libPath = fs.combine(programDir, "lib/" .. libName .. ".lua")
                
                -- Ensure the /lib/ directory exists
                if not fs.isDir(fs.combine(programDir, "lib")) then
                    fs.makeDir(fs.combine(programDir, "lib"))
                end

                local file, err = fs.open(libPath, "w")
                if not file then
                    print("Error: Could not open file for writing at:")
                    print(libPath)
                    print("Reason: " .. tostring(err))
                    return false -- Halt execution
                end
                
                file.write(response.code)
                file.close()
                print("Library '" .. libName .. "' installed.")
                sleep(1) -- Give fs time to process
            else
                print("Error: Could not download library.")
                print("Reason: " .. (response and response.reason or "Timeout"))
                return false -- Halt execution
            end
        end
    end
    
    if needsReboot then
        print("All libraries installed. Rebooting...")
        sleep(2)
        os.reboot()
        -- The program will not reach here, but we return true for logical consistency.
        return true 
    end
    
    -- If we get here, no installation was needed.
    return true -- Signal success
end

local function autoUpdateCheck()
    rednet.send(state.mailServerId, { type = "get_version", program = programName }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 3)
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

local function mainMenu()
    while true do
        rednet.send(state.mailServerId, { type = "get_unread_count", user = state.username }, "SimpleMail")
        local _, response = rednet.receive("SimpleMail", 2)
        local unreadCount = response and response.count or 0
        
        local options = {
            "Read Mail" .. (unreadCount > 0 and " (" .. unreadCount .. " unread)" or ""),
            "Send Mail", "General Chat", "Mailing Lists", "Games", "System", "Help", "Logout"
        }
        
        -- THE FIX: Correctly check for admin status
        if state.isAdmin then
            table.insert(options, 8, "Admin Console")
        end
        
        local selected = 1
        local choice = nil
        
        while true do
            -- Redraw menu
            drawWindow("Main Menu - Welcome " .. (state.nickname or "Guest"))
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
        -- Use 'context' for all calls
        if selection:match("Read Mail") then state.apps.readMail(context)
        elseif selection == "Send Mail" then state.apps.sendMail(context)
        elseif selection == "General Chat" then state.apps.startChat(context)
        elseif selection == "Mailing Lists" then state.apps.manageLists(context)
        elseif selection == "Games" then state.apps.enterArcade(context)
        elseif selection == "System" then state.apps.systemMenu(context)
        elseif selection == "Help" then state.apps.showHelpScreen(context)
        elseif selection == "Admin Console" then state.apps.adminConsole(context)
        end
    end
    state.username = nil -- Signal logout
end

--==============================================================================
-- Program Entry Point
--==============================================================================

local function showSplashScreen()
    clear()
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
    showSplashScreen()
    while true do
        rednet.open("back")
        local connected, reason = findServers()
        if not connected then
            local tempShowMessage = function(title, msg) term.clear(); print(title.."\n"..msg); sleep(3) end
            tempShowMessage("Connection Error", reason or "Could not find servers. Retrying...")
            sleep(5)
        else
            if autoUpdateCheck() then return end
            if not installDependencies() then
                rednet.close("back")
                return 
            end

            -- Load libraries after ensuring they exist
            if not crypto then crypto = require("lib.sha1_hmac") end
            if not apps then apps = require("lib.drunken_os_apps") end

            state.crypto = crypto
            state.apps = apps

            state.username = nil
            state.isAdmin = false
            -- Pass 'context' so the library has access to UI functions
            if not state.apps.loginOrRegister(context) then 
                clear(); print("Goodbye!"); break
            end
            
            rednet.send(state.mailServerId, {type = "get_motd"}, "SimpleMail")
            local _, motd_response = rednet.receive("SimpleMail", 3)
            if motd_response and motd_response.motd and motd_response.motd ~= "" then
                state.apps.showMessage(state, "Message of the Day", motd_response.motd)
            end
            
            -- Call the local mainMenu controller
            mainMenu() 
            
            rednet.close("back")
            if not state.username then
                clear(); print("Goodbye!"); break
            end
        end
    end
end


main()
