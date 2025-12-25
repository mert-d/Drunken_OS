--[[
    Modularized from drunken_os_apps.lua
]]

local arcade = {}
local appVersion = 1.4

local function getParent(context)
    return context.parent
end

local function parseLocalVersion(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local content = f.readAll()
    f.close()
    local v = content:match("local%s+[gac]%w*Version%s*=%s*([%d%.]+)") 
           or content:match("%-%-%s*[Vv]ersion:%s*([%d%.]+)")
    return tonumber(v) or 1.0
end

function arcade.run(context)
    context.drawWindow("Arcade")
    term.setCursorPos(2, 4); term.write("Fetching game list...")
    local arcadeServer = rednet.lookup("ArcadeGames", "arcade.server")
    if not arcadeServer then
        context.showMessage("Error", "Arcade Server not found.")
        return
    end

    rednet.send(arcadeServer, { type = "get_gamelist" }, "ArcadeGames")
    local _, response = rednet.receive("ArcadeGames", 10)

    if not response or not response.games then
        context.showMessage("Error", (response and "Could not get game list from server.") or "Connection timeout.")
        return
    end

    local games = response.games
    if #games == 0 then
        context.showMessage("Arcade", "No games are currently available.")
        return
    end

    local selected = 1
    while true do
        local options = {}
        for _, game in ipairs(games) do
            local localVer = parseLocalVersion(fs.combine(context.programDir, game.file))
            local display = game.name .. " (v" .. (game.version or "1.0") .. ")"
            if localVer then
                if game.version and game.version > localVer then
                    display = display .. " [!] UPDATE"
                end
            else
                display = display .. " [NEW]"
            end
            table.insert(options, display)
        end
        table.insert(options, "Back")

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
                
                local localVer = parseLocalVersion(gameFile)
                local needsUpdate = not localVer or (game.version and game.version > localVer)

                if needsUpdate then
                    term.setCursorPos(2, h-1)
                    term.write((not localVer and "Downloading " or "Updating ") .. game.name .. "...")
                    rednet.send(arcadeServer, {type = "get_game_update", filename = game.file}, "ArcadeGames")
                    local _, update = rednet.receive("ArcadeGames", 10)
                    
                    if update and update.code then
                        local file = fs.open(gameFile, "w")
                        if file then
                            file.write(update.code)
                            file.close()
                            context.clear()
                            
                            local run_shell = context.shell or _G.shell
                            if run_shell and run_shell.run then
                                run_shell.run(gameFile, getParent(context).username)
                            else
                                context.showMessage("Error", "Shell API (run) is not available.")
                            end
                        else
                            context.showMessage("Error", "Could not save game file.")
                        end
                    else
                        context.showMessage("Error", "Could not download game from server.")
                    end
                else
                    context.clear()
                    local run_shell = context.shell or _G.shell
                    local ok = false
                    if run_shell and run_shell.run then
                        ok = run_shell.run(gameFile, getParent(context).username)
                    else
                        context.showMessage("Error", "Shell API (run) is not available.")
                    end
                    if not ok then
                        print("\nGame exited with error.")
                        print("Press any key to return.")
                        os.pullEvent("key")
                    end
                end
            else
                break
            end
        elseif key == keys.tab then break end
    end
end

return arcade
