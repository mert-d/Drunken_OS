--[[
    Drunken OS - File Manager Applet
    Modularized from drunken_os_apps.lua
]]

local files = {}

local function getParent(context)
    return context.parent
end

local function getFileInfo(path, filename)
    local fullPath = fs.combine(path, filename)
    local info = {
        name = filename,
        isDir = fs.isDir(fullPath),
        size = fs.getSize(fullPath),
        ext = filename:match("^.+(%.%w+)$") or ""
    }
    
    if info.isDir then
        info.icon = ">"
        info.color = colors.lightBlue
    elseif info.ext == ".lua" then
        if fullPath:match("games/") then
            info.icon = "*"
            info.color = colors.green
        else
            info.icon = "-"
            info.color = colors.yellow
        end
    elseif info.ext == ".dat" or info.ext == ".db" or info.ext == ".json" then
        info.icon = "o"
        info.color = colors.purple
    else
        info.icon = " "
        info.color = colors.white
    end
    return info
end

function files.fileActionModal(context, file, isCloud)
    local options = {}
    if not file.isDir then
        if not isCloud and file.ext == ".lua" then table.insert(options, "🚀 Run") end
        if not isCloud then table.insert(options, "☁️ Sync to Cloud") end
        if isCloud then table.insert(options, "💾 Download Local") end
        table.insert(options, "📧 Mail to...")
    end
    table.insert(options, "🗑️ Delete")
    table.insert(options, "Cancel")

    local selected = 1
    while true do
        context.drawWindow(file.name)
        local w, h = context.getSafeSize()
        term.setCursorPos(2, 4); term.setTextColor(colors.gray)
        term.write(string.format("Type: %s | Size: %d b", file.isDir and "Folder" or (file.ext ~= "" and file.ext or "File"), file.size))
        
        context.drawMenu(options, selected, 2, 6)
        local event, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then break
        elseif key == keys.tab then break end
    end

    local choice = options[selected]
    return (choice ~= "Cancel") and choice or nil
end

function files.run(context)
    local currentPath = ""
    local storageMode = "Local"
    local selected = 1
    local scroll = 1
    local cloudFiles = {}

    local function refreshCloud()
        context.drawWindow("Syncing...")
        rednet.send(getParent(context).mailServerId, { type = "list_cloud", user = getParent(context).username }, "SimpleMail")
        local _, response = rednet.receive("SimpleMail", 5)
        if response and response.files then
            cloudFiles = response.files
            for i, f in ipairs(cloudFiles) do
                f.ext = f.name:match("^.+(%.%w+)$") or ""
                f.icon = f.isDir and ">" or "-"
                f.color = f.isDir and colors.lightBlue or colors.white
            end
        else
            context.showMessage("Error", "Cloud Offline"); storageMode = "Local"
        end
    end

    while true do
        local files = {}
        if storageMode == "Local" then
            local rawFiles = fs.list(currentPath)
            if currentPath ~= "" then table.insert(files, { name = "..", isDir = true, icon = "<", color = colors.gray }) end
            for _, f in ipairs(rawFiles) do table.insert(files, getFileInfo(currentPath, f)) end
        else
            files = cloudFiles
            if #files == 0 then table.insert(files, { name = "(Cloud Empty)", icon = " ", color = colors.gray, disabled = true }) end
        end

        context.drawWindow("Files: " .. storageMode)
        local w, h = context.getSafeSize()
        term.setCursorPos(2, 2); term.setTextColor(storageMode == "Local" and colors.white or colors.gray); term.write("[Local]")
        term.setCursorPos(10, 2); term.setTextColor(storageMode == "Cloud" and colors.white or colors.gray); term.write("[Cloud]")
        term.setCursorPos(2, 3); term.setTextColor(colors.cyan); term.write("/" .. currentPath)
        
        local listHeight = h - 5
        selected = math.max(1, math.min(selected, #files))
        if selected < scroll then scroll = selected end
        if selected >= scroll + listHeight then scroll = selected - listHeight + 1 end

        for i = scroll, math.min(scroll + listHeight - 1, #files) do
            local f = files[i]
            term.setCursorPos(2, 4 + (i - scroll))
            if i == selected then term.setBackgroundColor(context.theme.highlightBg); term.setTextColor(context.theme.highlightText)
            else term.setBackgroundColor(context.theme.bg); term.setTextColor(f.color) end
            term.write(string.format(" %s %s", f.icon, f.name))
            term.setBackgroundColor(context.theme.bg)
        end

        local event, key = os.pullEvent("key")
        if key == keys.up then selected = selected - 1
        elseif key == keys.down then selected = selected + 1
        elseif key == keys.left or key == keys.right then
            storageMode = (storageMode == "Local") and "Cloud" or "Local"
            if storageMode == "Cloud" then refreshCloud() end
            selected = 1; scroll = 1
        elseif key == keys.enter then
            local f = files[selected]
            if f and not f.disabled then
                if f.isDir then
                    currentPath = (f.name == "..") and fs.getDir(currentPath) or fs.combine(currentPath, f.name)
                    selected = 1; scroll = 1
                else
                    local action = files.fileActionModal(context, f, storageMode == "Cloud")
                    if action == "🚀 Run" then
                        context.clear(); shell.run(fs.combine(currentPath, f.name)); context.showMessage("Exited", "Finished.")
                    elseif action == "☁️ Sync to Cloud" then
                        local file = fs.open(fs.combine(currentPath, f.name), "r")
                        local content = file.readAll(); file.close()
                        rednet.send(getParent(context).mailServerId, { type = "sync_file", user = getParent(context).username, filename = f.name, content = content }, "SimpleMail")
                        local _, resp = rednet.receive("SimpleMail", 5); context.showMessage("Sync", (resp and resp.success) and "Uploaded!" or "Failed")
                    elseif action == "💾 Download Local" then
                        rednet.send(getParent(context).mailServerId, { type = "download_cloud", user = getParent(context).username, filename = f.name }, "SimpleMail")
                        local _, resp = rednet.receive("SimpleMail", 10)
                        if resp and resp.success then
                            local file = fs.open(fs.combine(currentPath, f.name), "w")
                            file.write(resp.content); file.close(); context.showMessage("Sync", "Downloaded!")
                        end
                    elseif action == "📧 Mail to..." then
                        local to = context.readInput("To: ", h - 1)
                        if to and to ~= "" then
                            local content
                            if storageMode == "Cloud" then
                                rednet.send(getParent(context).mailServerId, { type = "download_cloud", user = getParent(context).username, filename = f.name }, "SimpleMail")
                                local _, resp = rednet.receive("SimpleMail", 5); content = resp and resp.content
                            else
                                local file = fs.open(fs.combine(currentPath, f.name), "r"); content = file.readAll(); file.close()
                            end
                            if content then
                                -- Need mail helper? Let's just use raw send
                                local mailObj = { from = getParent(context).username, from_nickname = getParent(context).nickname, to = to, subject = "Shared File: " .. f.name, body = "Attached: " .. f.name, timestamp = os.time(), attachment = { name = f.name, content = content } }
                                rednet.send(getParent(context).mailServerId, { type = "send", mail = mailObj }, "SimpleMail")
                                context.showMessage("Mail", "Sent!")
                            end
                        end
                    elseif action == "🗑️ Delete" then
                        if storageMode == "Local" then fs.delete(fs.combine(currentPath, f.name))
                        else rednet.send(getParent(context).mailServerId, { type = "delete_cloud", user = getParent(context).username, filename = f.name }, "SimpleMail")
                             rednet.receive("SimpleMail", 2); refreshCloud() end
                    end
                end
            end
        elseif key == keys.tab then break end
    end
end

return files
