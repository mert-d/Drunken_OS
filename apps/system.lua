--[[
    Drunken OS - System Applet
    Modularized from drunken_os_apps.lua
]]

local updater = require("lib.updater")
local theme = require("lib.theme")
local system = {}
local appVersion = 2.0 -- Game-only updates, system updates at boot

local function getParent(context)
    return (context and context.parent) or context or {}
end

---
-- Prompts the user to change their global nickname.
function system.changeNickname(context)
    local authId = getParent(context).authServerId or rednet.lookup("auth.secure.v1", "auth.server")
    if not authId then
        context.showMessage("Error", "Auth server unreachable.")
        return
    end
    context.drawWindow("Change Nickname")
    local new_nick = context.readInput("New nickname: ", 4)
    if new_nick and new_nick ~= "" then
        rednet.send(authId, { type = "set_nickname", user = getParent(context).username, new_nickname = new_nick, session_token = getParent(context).session_token }, "auth.secure.v1")
        context.drawWindow("Updating...")
        local _, response = rednet.receive("auth.secure.v1", 15)
        if response and response.success then
            getParent(context).nickname = response.new_nickname
            context.showMessage("Success", "Nickname updated!")
        else
            context.showMessage("Error", (response and (response.reason or "Update failed")) or "Connection timeout.")
        end
    end
end

---
-- Connects to the Arcade Server to check if locally installed arcade games
-- have remote updates available, and auto-downloads them.
-- @param context table: OS app context.
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
        term.setCursorPos(2, y); term.setTextColor(context.theme.errorText or colors.red); term.write("Arcade Server offline.")
        term.setTextColor(context.theme.text)
    end
    term.setCursorPos(2, y); term.setTextColor(context.theme.mutedText or colors.gray)
    term.write("Note: System updates happen at boot.")
    term.setTextColor(context.theme.text)
    
    sleep(2)
end

---
-- Main routing logic for System utilities menu.
-- @param context table: OS app context.
function system.run(context)
    local options = {"Change Nickname", "System Settings", "Check for Updates", "Back"}
    local selected = 1
    local ok_sound, Sound = pcall(require, "lib.sound")
    if not ok_sound or type(Sound) ~= "table" then
        Sound = { playClick = function() end }
    end

    local function executeOption(idx)
        if idx == 1 then
            system.changeNickname(context)
        elseif idx == 2 then
            local ok, loader = pcall(require, "lib.app_loader")
            if ok then
                loader.run("settings", context)
            else
                context.showMessage("Error", "Could not load settings app.")
            end
        elseif idx == 3 then
            system.updateAll(context)
        elseif idx == 4 then
            return false
        end
        return true
    end

    while true do
        context.drawWindow("System")
        context.drawMenu(options, selected, 2, 4)

        local w, h = term.getSize()
        term.setCursorPos(2, h - 1)
        term.setTextColor(context.theme and context.theme.mutedText or colors.gray)
        term.write("[Enter:Select] [Q:Back]")

        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local key = p1
            if key == keys.up then
                selected = (selected == 1) and #options or selected - 1
                if Sound and Sound.playClick then Sound.playClick() end
            elseif key == keys.down then
                selected = (selected == #options) and 1 or selected + 1
                if Sound and Sound.playClick then Sound.playClick() end
            elseif key == keys.enter then
                if not executeOption(selected) then break end
            elseif key == keys.tab or key == keys.q or key == keys.x then
                break
            end
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir < 0 then
                selected = (selected == 1) and #options or selected - 1
            else
                selected = (selected == #options) and 1 or selected + 1
            end
            if Sound and Sound.playClick then Sound.playClick() end
        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            local clickedIdx = cy - 4 + 1
            if clickedIdx >= 1 and clickedIdx <= #options then
                selected = clickedIdx
                if Sound and Sound.playClick then Sound.playClick() end
                if not executeOption(clickedIdx) then break end
            elseif cy == h - 1 and cx > math.floor(w / 2) then
                break
            elseif cy == 1 and cx >= w - 3 then
                break
            end
        end
    end
end

return system
