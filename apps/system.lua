--[[
    Drunken OS - System Applet
    Modularized from drunken_os_apps.lua
]]

local updater = require("lib.updater")
local theme = require("lib.theme")
local system = {}
local appVersion = 1.9 -- Game-only updates, system updates at boot

local function getParent(context)
    return context.parent
end
-- ... (keeping existing functions until updateAll)

function system.changeNickname(context)
    -- ... (unchanged, but I need to be careful with replace_file_content range)
    -- Actually, I shouldn't replace the whole file if I can avoid it.
    -- I'll target the updateAll function specifically.
    context.drawWindow("Change Nickname")
    local new_nick = context.readInput("New nickname: ", 4)
    if new_nick and new_nick ~= "" then
        rednet.send(getParent(context).mailServerId, { type = "set_nickname", user = getParent(context).username, new_nickname = new_nick }, "SimpleMail")
        context.drawWindow("Updating...")
        local _, response = rednet.receive("SimpleMail", 15)
        if response and response.success then
            getParent(context).nickname = response.new_nickname
            context.showMessage("Success", "Nickname updated!")
        else
            context.showMessage("Error", (response and (response.reason or "Update failed")) or "Connection timeout.")
        end
    end
end

function system.updateAll(context)
    context.drawWindow("Game Updates")
    local y = 4
    local updatesFound = false
    
    -- Only check for Arcade Game Updates (System updates happen at boot)
    term.setCursorPos(2, y); term.write("Checking Arcade Server...")
    local arcadeServer = rednet.lookup("ArcadeGames", "arcade.server")
    if arcadeServer then
        rednet.send(arcadeServer, { type = "get_all_game_versions" }, "ArcadeGames")
        local _, response = rednet.receive("ArcadeGames", 5)
        if response and response.type == "game_versions_response" and response.versions then
            local gamesDir = fs.combine(context.programDir, "games")
            if not fs.exists(gamesDir) then fs.makeDir(gamesDir) end
            
            y = y + 1
            for filename, serverVer in pairs(response.versions) do
                local cleanName = filename:gsub("^games/", "")
                local path = fs.combine(gamesDir, cleanName)
                local localVer = 0
                if fs.exists(path) then
                    local f = fs.open(path, "r")
                    if f then
                        local content = f.readAll(); f.close()
                        local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") or content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
                        localVer = tonumber(v) or 0
                    end
                end
                
                if serverVer > localVer then
                    updatesFound = true
                    term.setCursorPos(2, y); term.clearLine()
                    term.write("Updating: " .. cleanName)
                    y = y + 1
                    rednet.send(arcadeServer, {type = "get_game_update", filename = filename}, "ArcadeGames")
                    local _, update = rednet.receive("ArcadeGames", 5)
                    if update and update.code then
                        local file = fs.open(path, "w")
                        if file then file.write(update.code); file.close() end
                    end
                end
            end
            
            if not updatesFound then
                term.setCursorPos(2, y); term.write("All games are up to date!")
            else
                term.setCursorPos(2, y); term.write("Game updates complete!")
            end
        else
            term.setCursorPos(2, y + 1); term.write("No response from Arcade Server.")
        end
    else
        term.setCursorPos(2, y); term.setTextColor(colors.red); term.write("Arcade Server offline.")
        term.setTextColor(theme.text)
    end
    
    y = y + 2
    term.setCursorPos(2, y); term.setTextColor(colors.gray)
    term.write("Note: System updates happen at boot.")
    term.setTextColor(theme.text)
    
    sleep(2)
end

function system.run(context)
    local options = {"Change Nickname", "Check for Updates", "Back"}
    local selected = 1
    while true do
        context.drawWindow("System")
        context.drawMenu(options, selected, 2, 4)
        local event, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then system.changeNickname(context)
            elseif selected == 2 then system.updateAll(context)
            elseif selected == 3 then break end
        elseif key == keys.tab then break end
    end
end

return system
