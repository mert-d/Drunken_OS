--[[
    Drunken Developer Portal (v1.0)
    
    The official IDE for building apps on Drunken OS using the Drunken SDK.
]]

local SDK = require("lib.sdk")
local appVersion = 1.0

local developer = {}

--- Draws the main menu
local function mainMenu(context)
    while true do
        SDK.UI.drawWindow("Developer Portal")
        
        local options = {
            "New Project",
            "Documentation",
            "Submit App (Coming Soon)",
            "Exit"
        }
        
        local selected = 1
        -- Simple menu loop using internal context helper if available, or SDK if refined
        -- Since this app *uses* the SDK, let's try to stick to SDK patterns? 
        -- But SDK doesn't have a menu helper yet! We should add one to lib/sdk.lua later.
        -- For now, falling back to context.drawMenu which is passed by the OS client.
        
        if context.drawMenu then
             -- Use the OS's native menu renderer for consistency
             -- We have to manage the selection loop ourselves though if drawMenu is just a renderer
             -- See merchant.lua for pattern
             local sel = 1
             while true do
                 SDK.UI.drawWindow("Developer Portal")
                 context.drawMenu(options, sel, 2, 4)
                 local _, k = os.pullEvent("key")
                 if k == keys.up then sel = (sel==1) and #options or sel-1
                 elseif k == keys.down then sel = (sel==#options) and 1 or sel+1
                 elseif k == keys.enter then
                    selected = sel
                    break
                 end
             end
        else
            print("Error: Context missing drawMenu.")
            return
        end
        
        if selected == 4 then break end
        
        if selected == 1 then
            -- New Project
            SDK.UI.drawWindow("New Project")
            term.setCursorPos(2,4); term.write("Project Name: ")
            local name = read()
            if name and name ~= "" then
                local filename = name .. ".lua" -- Simple single file for now
                local path = fs.combine(context.programDir, filename)
                
                if fs.exists(path) then
                    SDK.UI.showMessage("Error", "File already exists!")
                else
                    local f = fs.open(path, "w")
                    f.write("--[[ " .. name .. " - Built with Drunken SDK ]]\n\n")
                    f.write("local SDK = require(\"lib.sdk\")\n\n")
                    f.write("SDK.UI.drawWindow(\"" .. name .. "\")\n")
                    f.write("SDK.UI.showMessage(\"Hello\", \"Welcome to my app!\")\n")
                    f.close()
                    SDK.UI.showMessage("Success", "Created " .. filename)
                    -- Ideally open 'edit filename' shell command?
                    shell.run("edit", path)
                end
            end
            
        elseif selected == 2 then
            -- Documentation
            -- In real scenario w/ browser, we could open a web page.
            -- Here we just show a simple guide.
            SDK.UI.drawWindow("SDK Reference")
            term.setCursorPos(2,4); term.write("DK.UI.drawWindow(title)")
            term.setCursorPos(2,5); term.write("DK.UI.showMessage(title, text)")
            term.setCursorPos(2,6); term.write("DK.Net.createGameSocket(id)")
            term.setCursorPos(2,8); term.write("See github for full guide.")
            os.pullEvent("key")
            
        elseif selected == 3 then
            SDK.UI.showMessage("Info", "App Store submission coming in Phase 4.1")
        end
    end
end

function developer.run(context)
    mainMenu(context)
end

return developer
