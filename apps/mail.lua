--[[
    Drunken OS - Mail Applet
    Modularized from drunken_os_apps.lua
]]

local mail = {}
local appVersion = 1.2

local function getParent(context)
    return (context and context.parent) or context or {}
end

local function receiveMailResponse(expectedPredicate, timeout)
    timeout = timeout or 6.0
    local timer = os.startTimer(timeout)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" and p3 == "SimpleMail" then
            local msg = p2
            if type(msg) == "table" and (not expectedPredicate or expectedPredicate(msg)) then
                return msg
            end
        elseif event == "timer" and p1 == timer then
            return nil
        end
    end
end

---
-- Displays the UI to read a given mail message structure.
-- Provides options to download attachments if present.
-- @param context table: OS app context.
function mail.readMail(context)
    local mailData = context.mail_to_read
    local w, h = context.getSafeSize()
    local bodyLines = context.wordWrap(mailData.body or "", w - 3)
    local scroll = 1
    while true do
        context.drawWindow("Read Mail")
        local y = 3
        term.setCursorPos(2, y); term.write("From:    " .. (mailData.from_nickname or "Unknown"))
        term.setCursorPos(2, y + 1); term.write("To:      " .. (mailData.to or "Unknown"))
        term.setCursorPos(2, y + 2); term.write("Subject: " .. (mailData.subject or "(No Subject)"))
        term.setCursorPos(2, y + 4); term.write(string.rep("-", w - 2)); y = y + 5
        
        local bodyDisplayHeight = h - y - (mailData.attachment and 6 or 2)
        for i = 1, bodyDisplayHeight do
            local lineIndex = scroll + i - 1
            if lineIndex <= #bodyLines then
                term.setCursorPos(2, y + i - 1)
                term.write(bodyLines[lineIndex])
            end
        end
        y = y + bodyDisplayHeight + 1

        if mailData.attachment then
            term.setCursorPos(2, y); term.write(string.rep("-", w - 2)); y = y + 1
            term.setCursorPos(2, y); term.write("Attachment: " .. mailData.attachment.name); y = y + 2
            term.setTextColor(context.theme.prompt); term.setCursorPos(2, y); term.write("Save this file? (Y/N)")
        else
            term.setTextColor(context.theme.prompt); term.setCursorPos(2, h - 2); term.write("Press TAB to return...")
        end

        local event, key = os.pullEvent("key")
        if key == keys.up then
            scroll = math.max(1, scroll - 1)
        elseif key == keys.down then
            scroll = math.min(math.max(1, #bodyLines - bodyDisplayHeight + 1), scroll + 1)
        elseif key == keys.tab then
            break
        elseif mailData.attachment and key == keys.y then
            local saveName = mailData.attachment.name
            if fs.exists(saveName) then
                if context.readInput("Overwrite '"..saveName.."'? (y/n): ", y + 1):lower() ~= "y" then
                    context.showMessage("Cancelled", "Save operation cancelled.")
                    break
                end
            end
            local file = fs.open(saveName, "w")
            if file then
                file.write(mailData.attachment.content)
                file.close()
                context.showMessage("Success", "File saved as '"..saveName.."'")
            else
                context.showMessage("Error", "Could not open file for writing.")
            end
            break
        elseif mailData.attachment and key == keys.n then
            context.showMessage("Cancelled", "Save operation cancelled.")
            break
        end
    end
end

---
-- Connects to the mainframe to download the user's current inbox data.
-- Displays it in an interactive scrolled list.
-- @param context table: OS app context.
function mail.viewInbox(context)
    getParent(context).unreadCount = 0
    context.drawWindow("Inbox")
    term.setCursorPos(2, 4)
    term.write("Fetching mail...")
    rednet.send(getParent(context).mailServerId, { type = "fetch", user = getParent(context).username, session_token = getParent(context).session_token }, "SimpleMail")
    local response = receiveMailResponse(function(m)
        return (m.mail ~= nil and type(m.mail) == "table") or m.reason ~= nil or m.status ~= nil or m.original_type == "fetch"
    end, 8.0)
    
    if not response or not response.mail then
        context.showMessage("Offline", (response and (response.reason or response.status or "Mail data missing")) or "Mail server is unreachable.\n(Chunk may be unloaded).")
        return
    end
    
    local inbox = response.mail
    if #inbox == 0 then
        context.showMessage("Inbox", "Your inbox is empty.")
        return
    end
    
    table.sort(inbox, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    local selected = 1
    local scroll = 1
    
    while true do
        context.drawWindow("Inbox")
        local w, h = context.getSafeSize()
        local listHeight = h - 5
        
        for i = scroll, math.min(scroll + listHeight - 1, #inbox) do
            local m = inbox[i]
            local line = string.format("From: %-15s Subject: %s", m.from_nickname, m.subject)
            if m.attachment then line = line .. " [FILE]" end
            term.setCursorPos(2, 2 + (i - scroll) + 1)
            if i == selected then
                term.setBackgroundColor(context.theme.highlightBg); term.setTextColor(context.theme.highlightText)
            else
                term.setBackgroundColor(context.theme.windowBg); term.setTextColor(context.theme.text)
            end
            term.write(string.sub(line, 1, w - 2))
        end
        
        term.setBackgroundColor(context.theme.windowBg)
        term.setTextColor(context.theme.prompt)
        local helpText = "ENTER: Read | D: Delete | TAB: Back"
        term.setCursorPos(w - #helpText, h - 2)
        term.write(helpText)
        
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = math.max(1, selected - 1)
            if selected < scroll then scroll = selected end
        elseif key == keys.down then
            selected = math.min(#inbox, selected + 1)
            if selected >= scroll + listHeight then scroll = selected - listHeight + 1 end
        elseif key == keys.enter then
            context.mail_to_read = inbox[selected]
            mail.readMail(context)
        elseif key == keys.delete or key == keys.d then
            rednet.send(getParent(context).mailServerId, {type = "delete", user = getParent(context).username, session_token = getParent(context).session_token, id = inbox[selected].id}, "SimpleMail")
            table.remove(inbox, selected)
            if #inbox == 0 then break end
            selected = math.max(1, math.min(selected, #inbox))
        elseif key == keys.tab then
            break
        end
    end
end

---
-- Triggers a text editor interface, compiles the result, and sends the message.
-- @param context table: OS app context.
-- @param to string: The recipient address.
-- @param subject string: The mail theme.
-- @param attachment table|nil: An optional file to embed within the mail.
function mail.composeAndSend(context, to, subject, attachment)
    context.drawWindow("Compose Mail Body")
    local w, h = context.getSafeSize()
    term.setCursorPos(w - 26, h)
    term.write("ENTER on empty line to send")
    term.setCursorPos(2, 4)
    term.write("Enter message body:")
    
    local bodyLines = {}
    local y = 6
    while y < h - 2 do
        term.setCursorPos(2, y)
        term.setCursorBlink(true)
        local line = read()
        term.setCursorBlink(false)
        if line == "" then break end
        table.insert(bodyLines, line)
        y = y + 1
    end
    
    local body = table.concat(bodyLines, "\n")
    local mailObj = {
        from = getParent(context).username,
        from_nickname = getParent(context).nickname,
        to = to,
        subject = subject,
        body = body,
        timestamp = os.time(),
        attachment = attachment
    }
    rednet.send(getParent(context).mailServerId, { type = "send", mail = mailObj, session_token = getParent(context).session_token, user = getParent(context).username }, "SimpleMail")
    context.drawWindow("Sending...")
    local confirm = receiveMailResponse(function(m)
        return m.status ~= nil or m.reason ~= nil or m.error ~= nil or m.success ~= nil or m.original_type == "send"
    end, 10.0)
    local msg = (confirm and (confirm.status or confirm.reason or confirm.error or (confirm.success and "Sent!") or "Unknown response")) or "No response from server."
    context.showMessage("Server Response", msg)
end

function mail.sendMail(context)
    context.drawWindow("Compose Mail")
    local to = context.readInput("To: ", 4)
    if not to or to == "" then return end
    rednet.send(getParent(context).mailServerId, { type = "user_exists", user = to }, "SimpleMail")
    local response = receiveMailResponse(function(m)
        return m.exists ~= nil or m.reason ~= nil or m.original_type == "user_exists"
    end, 6.0)
    if not response or not response.exists then
        context.showMessage("Offline", (response and (response.reason or "Recipient '"..to.."' not found.")) or "Mail server offline or chunk unloaded.")
        return
    end
    local subject = context.readInput("Subject: ", 6)
    mail.composeAndSend(context, to, subject or "(No Subject)", nil)
end

function mail.manageLists(context)
    local options = {"View All Lists", "Create a List", "Join a List", "Back"}
    local selected = 1
    while true do
        context.drawWindow("Mailing Lists")
        context.drawMenu(options, selected, 2, 4)
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then
            selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then
                context.drawWindow("All Lists")
                term.setCursorPos(2, 4); term.write("Fetching lists...")
                rednet.send(getParent(context).mailServerId, { type = "get_lists", user = getParent(context).username, session_token = getParent(context).session_token }, "SimpleMail")
                local response = receiveMailResponse(function(m)
                    return m.lists ~= nil or m.reason ~= nil or m.original_type == "get_lists"
                end, 6.0)
                if response and response.lists then
                    context.drawWindow("All Lists")
                    local listTable = {}
                    for name, members in pairs(response.lists) do
                        table.insert(listTable, {name = name, members = #members})
                    end
                    if #listTable == 0 then
                        context.showMessage("All Lists", "There are no mailing lists.")
                    else
                        local y = 4
                        for _, listData in ipairs(listTable) do
                            term.setCursorPos(2, y)
                            term.write(string.format("@%s (%d members)", listData.name, listData.members))
                            y = y + 1
                        end
                        term.setCursorPos(2, y + 1)
                        term.setTextColor(context.theme.prompt)
                        term.write("Press any key to continue...")
                        os.pullEvent("key")
                    end
                else
                    context.showMessage("Error", (response and (response.reason or "Could not fetch lists.")) or "Could not fetch lists (timed out).")
                end
            elseif selected == 2 then
                context.drawWindow("Create List")
                local name = context.readInput("New list name: @", 4)
                if name and name ~= "" then
                    rednet.send(getParent(context).mailServerId, { type = "create_list", name = name, creator = getParent(context).username, user = getParent(context).username, session_token = getParent(context).session_token }, "SimpleMail")
                    local r = receiveMailResponse(function(m)
                        return m.status ~= nil or m.reason ~= nil or m.success ~= nil or m.original_type == "create_list"
                    end, 6.0)
                    local msg = (r and (r.status or r.reason or (r.success and "List created.") or "Unknown response")) or "No response from server."
                    context.showMessage("Server Response", msg)
                end
            elseif selected == 3 then
                context.drawWindow("Join List")
                local name = context.readInput("List to join: @", 4)
                if name and name ~= "" then
                    rednet.send(getParent(context).mailServerId, { type = "join_list", name = name, user = getParent(context).username, session_token = getParent(context).session_token }, "SimpleMail")
                    local r = receiveMailResponse(function(m)
                        return m.status ~= nil or m.reason ~= nil or m.success ~= nil or m.original_type == "join_list"
                    end, 6.0)
                    local msg = (r and (r.status or r.reason or (r.success and "Joined list.") or "Unknown response")) or "No response from server."
                    context.showMessage("Server Response", msg)
                end
            elseif selected == 4 then
                break
            end
        elseif key == keys.tab then
            break
        end
    end
end

---
-- Main application point for the Mail applet.
-- Contains top level routing to inbox, sending, and list management.
-- @param context table: OS app context.
function mail.run(context)
    local options = {"View Inbox", "Send Mail", "Mailing Lists", "Back"}
    local selected = 1
    while true do
        context.drawWindow("Mail Menu")
        context.drawMenu(options, selected, 2, 4)
        local event, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then mail.viewInbox(context)
            elseif selected == 2 then mail.sendMail(context)
            elseif selected == 3 then mail.manageLists(context)
            elseif selected == 4 then break end
        elseif key == keys.tab then break end
    end
end

return mail
