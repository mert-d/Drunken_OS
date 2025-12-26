--[[
    Drunken OS - System Applet
    Modularized from drunken_os_apps.lua
]]

local updater = require("lib.updater")
local theme = require("lib.theme")
local system = {}
local appVersion = 1.7 -- Bump version for this change

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
    context.drawWindow("System Update")
    local y = 4
    local updatesFound = false
    
    -- 1. Check for Arcade Game Updates
    term.setCursorPos(2, y); term.write("Checking Arcade Server...")
    local arcadeServer = rednet.lookup("ArcadeGames", "arcade.server")
    if arcadeServer then
        rednet.send(arcadeServer, { type = "get_all_game_versions" }, "ArcadeGames")
        local _, response = rednet.receive("ArcadeGames", 5)
        if response and response.type == "game_versions_response" and response.versions then
            local gamesDir = fs.combine(context.programDir, "games")
            if not fs.exists(gamesDir) then fs.makeDir(gamesDir) end
            
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
                    term.setCursorPos(2, y + 1); term.clearLine(); term.write("Updating Game: " .. cleanName)
                    rednet.send(arcadeServer, {type = "get_game_update", filename = filename}, "ArcadeGames")
                    local _, update = rednet.receive("ArcadeGames", 5)
                    if update and update.code then
                        local file = fs.open(path, "w")
                        if file then file.write(update.code); file.close() end
                    end
                end
            end
        end
    else
        term.setCursorPos(2, y); term.setTextColor(colors.red); term.write("Arcade Server offline.")
        term.setTextColor(theme.text); y = y + 1
    end

    -- 2. Check for System Updates via Manifest (Mainframe)
    y = y + 2
    term.setCursorPos(2, y); term.write("Checking System Files...")
    
    local function uiCallback(msg)
        term.setCursorPos(2, y + 1)
        term.clearLine()
        term.write(msg)
        if #msg > 48 then -- Simple truncation
             term.setCursorPos(2, y + 1)
             term.write(msg:sub(1, 45) .. "...")
        end
    end
    
    -- We assume we are the 'client' package.
    -- Ideally, we'd know our package type, but for a standard client, 'client' is safe.
    -- If this was an ATM, it might be different, but system.lua is shared.
    -- Maybe we can infer or pass it? For now, standard 'client' is the main use case for this menu.
    
    local success = updater.install_package("client", uiCallback)
    if success then
        updatesFound = true
    else
        term.setCursorPos(2, y + 1); term.setTextColor(colors.red); term.write("Update failed.")
        term.setTextColor(theme.text)
    end

    context.showMessage("Update Status", updatesFound and "System successfully updated!" or "All components are up to date.")
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
