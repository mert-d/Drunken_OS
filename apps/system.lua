--[[
    Drunken OS - System Applet
    Modularized from drunken_os_apps.lua
]]

local system = {}

local function getParent(context)
    return context.parent
end

function system.changeNickname(context)
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

function system.updateGames(context)
    context.drawWindow("Updating Arcade")
    local y = 4
    local gamesDir = fs.combine(context.programDir, "games")
    if not fs.exists(gamesDir) then fs.makeDir(gamesDir) end

    term.setCursorPos(2, y); term.write("Checking for updates...")
    rednet.send(getParent(context).mailServerId, { type = "get_all_game_versions" }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 5)

    if not response or response.type ~= "game_versions_response" or not response.versions then
        context.showMessage("Error", (response and "Could not fetch updates.") or "Connection timeout.")
        return
    end

    local serverVersions = response.versions
    local function getLocalVersion(filename)
        local path = fs.combine(gamesDir, filename)
        if fs.exists(path) then
            local file = fs.open(path, "r")
            if file then
                local content = file.readAll()
                file.close()
                local v = content:match("%-%-%s*Version:%s*([%d%.]+)") or content:match("local%s+currentVersion%s*=%s*([%d%.]+)")
                return tonumber(v) or 0
            end
        end
        return 0
    end

    local updatesFound = false
    for filename, serverVer in pairs(serverVersions) do
        local localVer = getLocalVersion(filename)
        if serverVer > localVer then
            updatesFound = true
            context.drawWindow("Updating Arcade")
            term.setCursorPos(2, 4); term.write("Updating " .. filename .. "...")
            rednet.send(getParent(context).mailServerId, {type = "get_game_update", filename = filename}, "SimpleMail")
            local _, update = rednet.receive("SimpleMail", 5)
            if update and update.code then
                local path = fs.combine(gamesDir, filename)
                local file = fs.open(path, "w")
                if file then file.write(update.code); file.close() end
            end
        end
    end

    context.showMessage("Update Status", updatesFound and "All games updated!" or "All games are up to date.")
end

function system.run(context)
    local options = {"Change Nickname", "Update Games", "Back"}
    local selected = 1
    while true do
        context.drawWindow("System")
        context.drawMenu(options, selected, 2, 4)
        local event, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then system.changeNickname(context)
            elseif selected == 2 then system.updateGames(context)
            elseif selected == 3 then break end
        elseif key == keys.tab or key == keys.q then break end
    end
end

return system
