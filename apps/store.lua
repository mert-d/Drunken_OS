--[[
    Drunken OS - App Store (v1.0)
    
    Browse and install optional apps from the Mainframe.
]] --

local SDK = require("lib.sdk")
local updater = require("lib.updater")
local store = {}

local function fetchStoreListing(context)
    local serverId = nil
    if not rednet.isOpen() then SDK.Net.connect() end
    
    context.drawWindow("Connecting to Store...")
    local server = rednet.lookup("SimpleMail", "mail.server")
    if not server then
        context.showMessage("Error", "Store Offline.")
        return nil
    end

    rednet.send(server, { type = "get_manifest" }, "SimpleMail")
    local _, resp = rednet.receive("SimpleMail", 3)
    
    if resp and resp.manifest and resp.manifest.store then
        return resp.manifest.store
    end
    context.showMessage("Error", "Invalid Manifest.")
    return nil
end

function store.run(context)
    local listing = fetchStoreListing(context)
    if not listing then return end
    
    while true do
        SDK.UI.drawWindow("App Store")
        
        local apps = {}
        for name, path in pairs(listing) do
            table.insert(apps, name)
        end
        table.sort(apps)
        
        table.insert(apps, "Exit")
        
        local selected = context.drawMenu(apps, 1, 2, 4) or 1
        
        -- Since drawMenu handles the loop in Drunken_OS_apps context usually
        -- Wait, 'drawMenu' in existing framework DOES NOT blocking return index usually
        -- In merchant/bank we implemented our own KEY LOOPS.
        -- But here I passed `context` which implies `Drunken_OS_Apps` harness.
        -- Let's check `apps/system.lua` or similar usage.
        -- Assuming we need our own loop if we want nice install/uninstall status next to names.
        
        -- Custom Menu Loop for Install Status
        local cursor = 1
        while true do
            SDK.UI.drawWindow("App Store")
            
            local y = 4
            for i, appName in ipairs(apps) do
                 if appName == "Exit" then
                     term.setCursorPos(2, y)
                     if i == cursor then term.setTextColor(colors.cyan); term.write("> " .. appName)
                     else term.setTextColor(colors.white); term.write("  " .. appName) end
                 else
                     local isInstalled = updater.is_installed(listing[appName]) -- Pass path? No, updater.is_installed is stubbed false
                     -- Actually let's use fs.exists since we have the path in 'listing'
                     local path = listing[appName]
                     local installed = fs.exists(path)
                     
                     term.setCursorPos(2, y)
                     if i == cursor then 
                        term.setTextColor(colors.cyan)
                        term.write("> " .. appName)
                     else 
                        term.setTextColor(colors.white)
                        term.write("  " .. appName) 
                     end
                     
                     term.setCursorPos(20, y)
                     term.setTextColor(installed and colors.green or colors.gray)
                     term.write(installed and "[INSTALLED]" or "[GET]")
                 end
                 y = y + 1
            end
            
            local _, k = os.pullEvent("key")
            if k == keys.up then cursor = (cursor==1) and #apps or cursor-1
            elseif k == keys.down then cursor = (cursor==#apps) and 1 or cursor+1
            elseif k == keys.enter then break end
        end
        
        local choice = apps[cursor]
        if choice == "Exit" then break end
        
        local path = listing[choice]
        if fs.exists(path) then
             -- Uninstall Flow
             SDK.UI.drawWindow("Manage App")
             term.setCursorPos(2,4); term.write(choice)
             term.setCursorPos(2,6); term.write("Press ENTER to Uninstall")
             term.setCursorPos(2,7); term.write("Press Q to Cancel")
             
             while true do
                 local _, k = os.pullEvent("key")
                 if k == keys.enter then
                     updater.uninstall_app(path)
                     SDK.UI.showMessage("Success", "Uninstalled " .. choice)
                     break
                 elseif k == keys.q then break end
             end
        else
             -- Install Flow
             SDK.UI.drawWindow("Install App")
             term.setCursorPos(2,4); term.write(choice)
             term.setCursorPos(2,6); term.write("Press ENTER to Download")
             term.setCursorPos(2,7); term.write("Press Q to Cancel")
             
             while true do
                 local _, k = os.pullEvent("key")
                 if k == keys.enter then
                     SDK.UI.drawWindow("Downloading...")
                     local success = updater.install_app(choice, function(msg) 
                         -- minimal UI feedback
                         term.setCursorPos(2, 6); term.clearLine(); term.write(msg)
                     end)
                     
                     if success then SDK.UI.showMessage("Success", "Installed " .. choice) end
                     break
                 elseif k == keys.q then break end
             end
        end
    end
end

return store
