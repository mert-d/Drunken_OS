--[[
    Drunken Developer Portal (v1.0)
    
    The official IDE for building apps on Drunken OS using the Drunken SDK.
]]

local SDK = require("lib.sdk")
local appVersion = 1.0

local developer = {}

--- Draws the main menu
local function mainMenu(context)
    -- Check Admin Status (Assume context has it or check sys)
    -- Ideally we ask the server "Am I admin?" but for speed let's check local state or context.
    -- context in Drunken_OS_Client has state.isAdmin? No, we didn't expose it to apps yet.
    -- But Drunken_OS_Client.lua has 'state = { isAdmin = ... }'.
    -- If we pass 'state' as 'context', we can access it.
    -- Let's assume context.isAdmin exists. (If not, we default false).
    local isAdmin = context.isAdmin or false

    while true do
        SDK.UI.drawWindow("Developer Portal")
        
        local options = {
            "New Project",
            "Documentation",
            "Submit App"
        }
        
        if isAdmin then
            table.insert(options, "Admin Panel")
        end
        table.insert(options, "Exit")
        
        local selected_idx = context.drawMenu(options, 1, 2, 4) or #options
        local selected = options[selected_idx]
        
        if selected == "Exit" then break end
        
        if selected == "New Project" then
            -- ... (Existing New Project Logic) ...
        elseif selected == "Documentation" then
            -- ... (Existing Docs Logic) ...
        elseif selected == "Submit App" then
            -- ... (Existing Submit Logic) ...
        elseif selected == "Admin Panel" then
            while true do
                SDK.UI.drawWindow("Admin Panel")
                term.setCursorPos(2,3); term.write("Fetching submissions...")
                
                -- Fetch List
                if not rednet.isOpen() then SDK.Net.connect() end
                local server = rednet.lookup("SimpleMail", "mail.server")
                local submissions = {}
                
                if server then
                    rednet.send(server, { type = "admin_get_submissions", username = SDK.System.getUsername() }, "SimpleMail")
                    local _, resp = rednet.receive("SimpleMail", 3)
                    if resp and resp.success then submissions = resp.list end
                end
                
                SDK.UI.drawWindow("Review Queue")
                local subOpts = {}
                for _, sub in ipairs(submissions) do
                    table.insert(subOpts, sub.name .. " by " .. sub.author)
                end
                table.insert(subOpts, "Back")
                
                local sIdx = context.drawMenu(subOpts, 1, 2, 4)
                if subOpts[sIdx] == "Back" then break end
                
                local sub = submissions[sIdx]
                
                -- Review Detail
                while true do
                    SDK.UI.drawWindow("Review: " .. sub.name)
                    term.setCursorPos(2,4); term.write("Author: " .. sub.author)
                    term.setCursorPos(2,5); term.write("ID: " .. sub.id)
                    term.setCursorPos(2,7); term.write(sub.desc or "No description.")
                    
                    local actions = {"Test Code", "Approve", "Reject", "Back"}
                    local aIdx = context.drawMenu(actions, 1, 2, 10)
                    local action = actions[aIdx]
                    
                    if action == "Back" then break end
                    
                    if action == "Test Code" then
                        SDK.UI.drawWindow("Downloading " .. sub.name .. "...")
                        rednet.send(server, { type = "admin_get_code", username = SDK.System.getUsername(), id = sub.id }, "SimpleMail")
                        local _, cResp = rednet.receive("SimpleMail", 3)
                        
                        if cResp and cResp.success then
                             local tempPath = "temp_test.lua"
                             local f = fs.open(tempPath, "w")
                             f.write(cResp.code)
                             f.close()
                             
                             SDK.UI.drawWindow("Running Test...")
                             sleep(0.5)
                             theme.clear() -- Clear for app
                             shell.run(tempPath)
                             
                             SDK.UI.showMessage("Test Ended", "Returned to Review.")
                             fs.delete(tempPath)
                        else
                             SDK.UI.showMessage("Error", "Failed to fetch code.")
                        end
                        
                    elseif action == "Approve" or action == "Reject" then
                         SDK.UI.drawWindow(action .. "ing...")
                         rednet.send(server, { 
                             type = "admin_action", 
                             username = SDK.System.getUsername(), 
                             action = action:lower(), 
                             id = sub.id 
                         }, "SimpleMail")
                         local _, aResp = rednet.receive("SimpleMail", 3)
                         SDK.UI.showMessage("Result", (aResp and aResp.msg) or "No response")
                         break -- Go back to list
                    end
                end
            end
        end
    end
end
-- ... existing run function ...        -- Simple menu loop using internal context helper if available, or SDK if refined
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
            -- Submit App
            SDK.UI.drawWindow("Submit App")
            term.setCursorPos(2,4); term.write("File Path: ")
            local path = read()
            
            if not fs.exists(path) then
                SDK.UI.showMessage("Error", "File not found!")
            else
                term.setCursorPos(2,6); term.write("Description: ")
                local desc = read()
                
                SDK.UI.drawWindow("Sending...")
                
                -- Read Code
                local f = fs.open(path, "r")
                local code = f.readAll()
                f.close()
                
                -- Connect
                if not rednet.isOpen() then SDK.Net.connect() end
                local server = rednet.lookup("SimpleMail", "mail.server")
                
                if server then
                    local name = fs.getName(path):gsub("%.lua$", "")
                    rednet.send(server, {
                        type = "submit_app",
                        name = name,
                        code = code,
                        description = desc,
                        author = SDK.System.getUsername()
                    }, "SimpleMail")
                    
                    local _, resp = rednet.receive("SimpleMail", 5)
                    if resp and resp.success then
                        SDK.UI.showMessage("Success", "App submitted for review!")
                    else
                        SDK.UI.showMessage("Error", (resp and resp.reason) or "Timeout")
                    end
                else
                    SDK.UI.showMessage("Error", "Server Offline.")
                end
            end
        end
    end
end

function developer.run(context)
    mainMenu(context)
end

return developer
