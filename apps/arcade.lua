--[[
    Drunken OS - Arcade Applet
    Modularized from drunken_os_apps.lua
]]

local arcade = {}

local function getParent(context)
    return context.parent
end

function arcade.run(context)
    context.drawWindow("Arcade")
    term.setCursorPos(2, 4); term.write("Fetching game list...")
    rednet.send(getParent(context).mailServerId, { type = "get_gamelist" }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 10)

    if not response or not response.games then
        context.showMessage("Error", (response and "Could not get game list from server.") or "Connection timeout.")
        return
    end

    local games = response.games
    if #games == 0 then
        context.showMessage("Arcade", "No games are currently available.")
        return
    end

    local options = {}
    for _, game in ipairs(games) do table.insert(options, "Play " .. game.name) end
    table.insert(options, "Back")

    local selected = 1
    while true do
        context.drawWindow("Arcade")
        context.drawMenu(options, selected, 2, 4)
        local event, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected <= #games then
                local w, h = term.getSize()
                local game = games[selected]
                local gameFile = fs.combine(context.programDir, game.file)
                if not fs.exists(gameFile) then
                    term.setCursorPos(2, h-1)
                    term.write("Downloading " .. game.name .. "...")
                    rednet.send(getParent(context).mailServerId, {type = "get_game_update", filename = game.file}, "SimpleMail")
                    local _, update = rednet.receive("SimpleMail", 5)
                    
                    if update and update.code then
                        local file = fs.open(gameFile, "w")
                        if file then
                            file.write(update.code)
                            file.close()
                            context.clear()
                            shell.run(gameFile, getParent(context).username)
                        else
                            context.showMessage("Error", "Could not save game file.")
                        end
                    else
                        context.showMessage("Error", "Could not download game from server.")
                    end
                else
                    context.clear()
                    local ok = shell.run(gameFile, getParent(context).username)
                    if not ok then
                        print("\nGame exited with error.")
                        print("Press any key to return.")
                        os.pullEvent("key")
                    end
                end
            else
                break
            end
        elseif key == keys.tab or key == keys.q then break end
    end
end

return arcade
