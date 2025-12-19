--[[
    Drunken OS - Mobile Client (v13.0 - Sentinel Update)
    by Gemini Gem & MuhendizBey

    Purpose:
    This definitive client version is fully compatible with the new unified
    code distribution system of Server v10.6+.

    Key Changes:
    - Version number incremented to v12.3.
    - Added support for dynamic game installation (auto-download on first launch).
    - Improved menu event loop.
]]

--==============================================================================
-- Environment & Path Setup
--==============================================================================

-- Get the directory where this program is running.
local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path
local crypto = require("lib.sha1_hmac")

--==============================================================================
-- Configuration & State
--==============================================================================

local currentVersion = 13.0
local programName = "Drunken_OS_Client" -- Correct program name for updates
local SESSION_FILE = ".session"
local REQUIRED_LIBS = {
    { name = "sha1_hmac" },
    { name = "drunken_os_apps", version = 1.6 }
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

local state = {
    mailServerId = nil,
    adminServerId = nil,
    username = nil,
    isAdmin = false,
    apps = nil,
    crypto = nil,
    chatServerId = nil,
    nickname = nil,
    unreadCount = 0,
    location = nil -- {x, y, z}
}

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

local function drawWindow(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg)
    term.clear()
    term.setBackgroundColor(theme.titleBg)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", w))
    term.setTextColor(theme.titleText)
    local titleText = " " .. (title or "Drunken Beard OS") .. " "
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, 1)
    term.write(titleText)
    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
end

local function printCentered(startY, text)
    local w, h = term.getSize()
    local lines = wordWrap(text, w - 4)
    for i, line in ipairs(lines) do
        term.setCursorPos(math.floor((w - #line) / 2) + 1, startY + i - 1)
        term.write(line)
    end
end

local function showMessage(title, message, isError)
    drawWindow(title)
    local w, h = term.getSize()
    term.setTextColor(isError and theme.errorBg or theme.text)
    printCentered(4, message)
    term.setCursorPos(math.floor((w - 26) / 2) + 1, h - 1)
    term.setTextColor(colors.gray)
    term.write("Press any key to continue...")
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

local function findServers()
    state.mailServerId = rednet.lookup("SimpleMail", "mail.server")
    state.chatServerId = rednet.lookup("SimpleChat", "chat.server")
    state.adminServerId = state.mailServerId -- Often same server
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

local function installDependencies()
    local needsReboot = false
    
    for _, libDef in ipairs(REQUIRED_LIBS) do
        local libName = libDef.name
        local targetVersion = libDef.version
        
        local ok, libOrError = pcall(require, "lib." .. libName)
        
        local needsUpdate = false
        if not ok then
            needsUpdate = true
        elseif targetVersion then
            -- Check version if module loaded successfully
            if type(libOrError) == "table" then
                if not libOrError._VERSION or libOrError._VERSION < targetVersion then
                    needsUpdate = true
                    print("Updating library '" .. libName .. "' to v" .. targetVersion .. "...")
                end
            end
        end

        if needsUpdate then
            needsReboot = true -- A reboot will be required if we install anything.
            term.clear(); term.setCursorPos(1,1)
            print("Missing or outdated library: " .. libName)
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
                package.loaded["lib."..libName] = nil -- Force reload on next require (though we reboot anyway)
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
    shell.run(consolePath, state.username, state.adminServerId)
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
        
        local options = {
            "Pocket Bank",
            "Pay Merchant",
            "Read Mail" .. (state.unreadCount > 0 and " (" .. state.unreadCount .. " unread)" or ""),
            "Send Mail", 
            "General Chat", 
            -- "People Tracker", -- Hidden for now
            "Mailing Lists", 
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
        -- Use 'context' for all calls
        if selection == "Pocket Bank" then state.apps.bankApp(context)
        elseif selection == "Pay Merchant" then state.apps.onlinePayment(context)
        elseif selection:match("Read Mail") then state.apps.viewInbox(context)
        elseif selection == "Send Mail" then state.apps.sendMail(context)
        elseif selection == "General Chat" then state.apps.startChat(context)
        -- elseif selection == "People Tracker" then state.apps.peopleTracker(context)
        elseif selection == "Mailing Lists" then state.apps.manageLists(context)
        elseif selection == "Games" then state.apps.enterArcade(context)
        elseif selection == "System" then state.apps.systemMenu(context)
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
    rednet.open("back")
    local connected, reason = findServers()
    
    -- Try to update even if "findServers" failed (maybe we can reach mail server specifically?)
    -- But findServers sets state.mailServerId, so we need it.
    if connected then
         if autoUpdateCheck() then return end
    end

    showSplashScreen()
    while true do
        rednet.open("back")
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

            state.crypto = crypto
            state.apps = apps

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
            
            -- Call the local mainMenu controller with GPS in parallel
            local function gpsHeartbeat()
                while true do
                    if state.username and state.mailServerId then
                        local x, y, z = gps.locate(2) -- 2 second timeout
                        if x then
                            state.location = {x=math.floor(x), y=math.floor(y), z=math.floor(z)}
                            rednet.send(state.mailServerId, {
                                type = "report_location",
                                user = state.username,
                                x = state.location.x,
                                y = state.location.y,
                                z = state.location.z
                            }, "SimpleMail")
                        else
                            state.location = nil
                        end
                    end
                    sleep(30)
                end
            end

            parallel.waitForAny(mainMenu, gpsHeartbeat)
            
            rednet.close("back")
            if not state.username then
                clear(); print("Goodbye!"); break
            end
        end
    end
end


main()
