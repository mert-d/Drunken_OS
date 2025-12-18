--[[
    Drunken OS - Mobile Client (v12.3 - Release Version)
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

-- Add the program's local library folder to the list of places Lua looks for modules.
package.path = "/?.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path

--==============================================================================
-- Configuration & State
--==============================================================================

local currentVersion = 12.4
local programName = "Drunken_OS_Client" -- Correct program name for updates
local SESSION_FILE = ".session"
local REQUIRED_LIBS = {
    { name = "sha1_hmac" },
    { name = "drunken_os_apps", version = 1.6 }
}

-- ... (state table remains the same)

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
        local unreadCount = response and response.count or 0
        
        local options = {
            "Pocket Bank",
            "Pay Merchant",
            "Read Mail" .. (unreadCount > 0 and " (" .. unreadCount .. " unread)" or ""),
            "Send Mail", 
            "General Chat", 
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
