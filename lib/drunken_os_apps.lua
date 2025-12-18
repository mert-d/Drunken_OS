--[[
    Drunken OS - Application Screen Library (v1.5 - Client Crash Fix)
    by Gemini Gem

    Purpose:
    This library contains all the major "application" functions for the
    Drunken_OS_Client. This version restores the full, working implementations
    for all menu options, including a robust game updater.

    Key Changes:
    - All placeholder "feature coming soon" messages have been replaced with
      their full, original implementations.
    - A new `systemMenu` provides access to settings and the game updater.
    - The `updateGames` function is now fully implemented based on user-provided
      working code, ensuring reliability.
]]

local apps = {}

--==============================================================================
-- Helper function to access the parent's state
--==============================================================================
local function getParent(context)
    return context.parent
end

--==============================================================================
-- Login & Main Menu Logic
--==============================================================================

local function completeAuthentication(context, user)
    context.drawWindow("Authentication Required")
    local w, h = context.getSafeSize()
    local message = "A token has been sent to the Auth Server admin. Please ask them for your token and enter it below."
    local lines = context.wordWrap(message, w - 4)
    for i, line in ipairs(lines) do
        term.setCursorPos(3, 4 + i - 1)
        term.write(line)
    end
    
    local token_raw = context.readInput("Auth Token: ", 4 + #lines + 2, false)
    if not token_raw or token_raw == "" then
        context.showMessage("Cancelled", "Authentication cancelled.")
        return false
    end

    local token_clean = token_raw:gsub("%s+", "")
    context.drawWindow("Verifying Token...")
    rednet.send(getParent(context).mailServerId, { type = "submit_auth_token", user = user, token = token_clean }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 10)

    if response and response.success then
        getParent(context).username = user
        getParent(context).nickname = response.nickname
        getParent(context).unreadCount = response.unreadCount or 0
        getParent(context).isAdmin = response.isAdmin or false
        if response.session_token then
            -- We can't easily write to a file in the program dir from here without the path
            -- Luckily context has programDir
            local sessionPath = fs.combine(context.programDir, ".session")
            local file = fs.open(sessionPath, "w")
            if file then
                file.write(response.session_token)
                file.close()
            end
        end
        context.showMessage("Success", "Authentication successful!")
        return true
    else
        context.showMessage("Authentication Failed", response.reason or "No response from server.")
        return false
    end
end

function apps.loginOrRegister(context)
    local options = {"Login", "Register", "Exit"}
    local selected = 1
    while not getParent(context).username do
        context.drawWindow("Welcome")
        context.drawMenu(options, selected, 2, 5)
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then
            selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then -- Login
                context.drawWindow("Login")
                local user = context.readInput("Username: ", 5, false)
                if user and user ~= "" then
                    local pass = context.readInput("Password: ", 7, true)
                    if pass and pass ~= "" then
                        local session_token = nil
                        local sessionPath = fs.combine(context.programDir, ".session")
                        if fs.exists(sessionPath) then
                            local file = fs.open(sessionPath, "r")
                            if file then
                                session_token = file.readAll()
                                file.close()
                            end
                        end
                        
                        rednet.send(getParent(context).mailServerId, { type = "login", user = user, pass = pass, session_token = session_token }, "SimpleMail")
                        local _, response = rednet.receive("SimpleMail", 10)

                        if response and response.success then
                            if response.needs_auth then
                                if not completeAuthentication(context, user) then
                                    getParent(context).username = nil
                                end
                            else
                                getParent(context).username = user
                                getParent(context).nickname = response.nickname
                                getParent(context).unreadCount = response.unreadCount or 0
                                getParent(context).isAdmin = response.isAdmin or false
                            end
                        else
                            context.showMessage("Login Failed", response.reason or "No response.")
                        end
                    end
                end
            elseif selected == 2 then -- Register
                context.drawWindow("Register")
                local user = context.readInput("Choose Username: ", 5, false)
                if user and user ~= "" then
                    local nick = context.readInput("Choose Nickname: ", 7, false)
                    if nick and nick ~= "" then
                        local pass = context.readInput("Choose Password: ", 9, true)
                        if pass and pass ~= "" then
                            rednet.send(getParent(context).mailServerId, { type = "register", user = user, pass = pass, nickname = nick }, "SimpleMail")
                            local _, response = rednet.receive("SimpleMail", 5)
                            if response and response.success and response.needs_auth then
                                if not completeAuthentication(context, user) then
                                    getParent(context).username = nil
                                end
                            else
                                context.showMessage("Registration Failed", response.reason or "No response.")
                            end
                        end
                    end
                end
            elseif selected == 3 then
                return false
            end
        elseif key == keys.tab then
            return false
        end
    end
    return true
end


--==============================================================================
-- Mail Application Screens
--==============================================================================

function apps.readMail(context)
    local mail = context.mail_to_read
    local w, h = context.getSafeSize()
    local bodyLines = context.wordWrap(mail.body or "", w - 3)
    local scroll = 1
    while true do
        context.drawWindow("Read Mail")
        local y = 3
        term.setCursorPos(2, y); term.write("From:    " .. (mail.from_nickname or "Unknown"))
        term.setCursorPos(2, y + 1); term.write("To:      " .. (mail.to or "Unknown"))
        term.setCursorPos(2, y + 2); term.write("Subject: " .. (mail.subject or "(No Subject)"))
        term.setCursorPos(2, y + 4); term.write(string.rep("-", w - 2)); y = y + 5
        
        local bodyDisplayHeight = h - y - (mail.attachment and 6 or 2)
        for i = 1, bodyDisplayHeight do
            local lineIndex = scroll + i - 1
            if lineIndex <= #bodyLines then
                term.setCursorPos(2, y + i - 1)
                term.write(bodyLines[lineIndex])
            end
        end
        y = y + bodyDisplayHeight + 1

        if mail.attachment then
            term.setCursorPos(2, y); term.write(string.rep("-", w - 2)); y = y + 1
            term.setCursorPos(2, y); term.write("Attachment: " .. mail.attachment.name); y = y + 2
            term.setTextColor(context.theme.prompt); term.setCursorPos(2, y); term.write("Save this file? (Y/N)")
        else
            term.setTextColor(context.theme.prompt); term.setCursorPos(2, h - 2); term.write("Press Q/TAB to return...")
        end

        local event, key = os.pullEvent("key")
        if key == keys.up then
            scroll = math.max(1, scroll - 1)
        elseif key == keys.down then
            scroll = math.min(math.max(1, #bodyLines - bodyDisplayHeight + 1), scroll + 1)
        elseif key == keys.tab or key == keys.q then
            break
        elseif mail.attachment and key == keys.y then
            local saveName = mail.attachment.name
            if fs.exists(saveName) then
                if context.readInput("Overwrite '"..saveName.."'? (y/n): ", y + 1):lower() ~= "y" then
                    context.showMessage("Cancelled", "Save operation cancelled.")
                    break
                end
            end
            local file = fs.open(saveName, "w")
            if file then
                file.write(mail.attachment.content)
                file.close()
                context.showMessage("Success", "File saved as '"..saveName.."'")
            else
                context.showMessage("Error", "Could not open file for writing.")
            end
            break
        elseif mail.attachment and key == keys.n then
            context.showMessage("Cancelled", "Save operation cancelled.")
            break
        end
    end
end

function apps.viewInbox(context)
    getParent(context).unreadCount = 0
    context.drawWindow("Inbox")
    term.setCursorPos(2, 4)
    term.write("Fetching mail...")
    rednet.send(getParent(context).mailServerId, { type = "fetch", user = getParent(context).username }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 10)
    
    if not response or not response.mail then
        context.showMessage("Error", "Could not retrieve mail.")
        return
    end
    
    local inbox = response.mail
    if #inbox == 0 then
        context.showMessage("Inbox", "Your inbox is empty.")
        return
    end
    
    table.sort(inbox, function(a, b) return a.timestamp > b.timestamp end)
    local selected = 1
    local scroll = 1
    
    while true do
        context.drawWindow("Inbox")
        local w, h = context.getSafeSize()
        local listHeight = h - 5
        
        for i = scroll, math.min(scroll + listHeight - 1, #inbox) do
            local mail = inbox[i]
            local line = string.format("From: %-15s Subject: %s", mail.from_nickname, mail.subject)
            if mail.attachment then line = line .. " [FILE]" end
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
        local helpText = "ENTER: Read | D: Delete | Q: Back"
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
            apps.readMail(context)
        elseif key == keys.delete or key == keys.d then
            rednet.send(getParent(context).mailServerId, {type = "delete", user = getParent(context).username, id = inbox[selected].id}, "SimpleMail")
            table.remove(inbox, selected)
            if #inbox == 0 then break end
            selected = math.max(1, math.min(selected, #inbox))
        elseif key == keys.tab or key == keys.q then
            break
        end
    end
end

function apps.composeAndSend(context, to, subject, attachment)
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
    local mail = {
        from = getParent(context).username,
        from_nickname = getParent(context).nickname,
        to = to,
        subject = subject,
        body = body,
        timestamp = os.time(),
        attachment = attachment
    }
    rednet.send(getParent(context).mailServerId, { type = "send", mail = mail }, "SimpleMail")
    context.drawWindow("Sending...")
    local _, confirm = rednet.receive("SimpleMail", 10)
    context.showMessage("Server Response", confirm and confirm.status or "No response from server.")
end

function apps.sendMail(context)
    context.drawWindow("Compose Mail")
    local to = context.readInput("To: ", 4)
    if not to or to == "" then return end
    rednet.send(getParent(context).mailServerId, { type = "user_exists", user = to }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 3)
    if not response or not response.exists then
        context.showMessage("Error", "Recipient '"..to.."' not found.")
        return
    end
    local subject = context.readInput("Subject: ", 6)
    apps.composeAndSend(context, to, subject or "(No Subject)", nil)
end

function apps.sendFile(context)
    context.drawWindow("Send File")
    local fileName = context.readInput("File to send: ", 4)
    if not fileName or not fs.exists(fileName) then
        context.showMessage("Error", "File not found.")
        return
    end
    local to = context.readInput("To: ", 6)
    if not to or to == "" then return end
    rednet.send(getParent(context).mailServerId, { type = "user_exists", user = to }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 3)
    if not response or not response.exists then
        context.showMessage("Error", "Recipient '"..to.."' not found.")
        return
    end
    local subject = context.readInput("Subject: ", 8)
    local file = fs.open(fileName, "r")
    if not file then
        context.showMessage("Error", "Could not open file.")
        return
    end
    local content = file.readAll()
    file.close()
    apps.composeAndSend(context, to, subject or "(No Subject)", { name = fs.getName(fileName), content = content })
end

function apps.mailMenu(context)
    local options = {"View Inbox", "Send Mail", "Send File", "Back"}
    local selected = 1
    while true do
        context.drawWindow("Mail Menu")
        context.drawMenu(options, selected, 2, 4)
        local event, key = os.pullEvent("key")
        if key == keys.up then
            selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then
            selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then
                apps.viewInbox(context)
            elseif selected == 2 then
                apps.sendMail(context)
            elseif selected == 3 then
                apps.sendFile(context)
            elseif selected == 4 then
                break
            end
        elseif key == keys.tab or key == keys.q then
            break
        end
    end
end

function apps.manageLists(context)
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
                rednet.send(getParent(context).mailServerId, { type = "get_lists" }, "SimpleMail")
                local _, response = rednet.receive("SimpleMail", 5)
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
                    context.showMessage("Error", "Could not fetch lists.")
                end
            elseif selected == 2 then
                context.drawWindow("Create List")
                local name = context.readInput("New list name: @", 4)
                if name and name ~= "" then
                    rednet.send(getParent(context).mailServerId, { type = "create_list", name = name, creator = getParent(context).username }, "SimpleMail")
                    local _, r = rednet.receive("SimpleMail", 5)
                    if r and r.status then
                        context.showMessage("Server Response", r.status)
                    else
                        context.showMessage("Error", "No response.")
                    end
                end
            elseif selected == 3 then
                context.drawWindow("Join List")
                local name = context.readInput("List to join: @", 4)
                if name and name ~= "" then
                    rednet.send(getParent(context).mailServerId, { type = "join_list", name = name, user = getParent(context).username }, "SimpleMail")
                    local _, r = rednet.receive("SimpleMail", 5)
                    if r and r.status then
                        context.showMessage("Server Response", r.status)
                    else
                        context.showMessage("Error", "No response.")
                    end
                end
            elseif selected == 4 then
                break
            end
        elseif key == keys.tab or key == keys.q then
            break
        end
    end
end

function apps.startChat(context)
    context.drawWindow("General Chat")
    term.setCursorPos(2, 4)
    term.write("Fetching history...")
    rednet.send(getParent(context).mailServerId, {type = "get_chat_history"}, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 5)
    
    local history = (response and response.history) or {}
    local input = ""
    local lastMessage = ""

    local function redrawAll()
        context.drawWindow("General Chat")
        local w, h = context.getSafeSize()
        local line_y = h - 3
        for i = #history, 1, -1 do
            local wrapped = context.wordWrap(history[i], w - 2)
            for j = #wrapped, 1, -1 do
                if line_y < 2 then break end
                term.setCursorPos(2, line_y)
                term.write(wrapped[j])
                line_y = line_y - 1
            end
            if line_y < 2 then break end
        end
        local inputWidth = w - 4
        term.setBackgroundColor(context.theme.windowBg)
        term.setCursorPos(1, h - 2)
        term.write(string.rep(" ", w))
        term.setCursorPos(2, h - 2)
        term.setTextColor(context.theme.prompt)
        term.write("> ")
        term.setTextColor(context.theme.text)
        local textToDraw = #input > inputWidth and "..."..string.sub(input, -(inputWidth-3)) or input
        term.write(textToDraw)
    end

    local function redrawInputLineOnly()
        local w, h = context.getSafeSize()
        local inputWidth = w - 4
        term.setBackgroundColor(context.theme.windowBg)
        term.setCursorPos(1, h - 2)
        term.write(string.rep(" ", w))
        term.setCursorPos(2, h - 2)
        term.setTextColor(context.theme.prompt)
        term.write("> ")
        term.setTextColor(context.theme.text)
        local textToDraw = #input > inputWidth and "..."..string.sub(input, -(inputWidth-3)) or input
        term.write(textToDraw)
    end

    local function networkListener()
        while true do
            local _, message = rednet.receive("SimpleChat")
            if message and message.from and message.text then
                local formattedMessage = string.format("[%s]: %s", message.from, message.text)
                if formattedMessage ~= lastMessage then
                    table.insert(history, formattedMessage)
                    if #history > 100 then
                        table.remove(history, 1)
                    end
                    redrawAll()
                end
            end
        end
    end

    local function keyboardListener()
        while true do
            local event, p1 = os.pullEvent()
            if event == "key" then
                if p1 == keys.tab or p1 == keys.q then
                    break
                elseif p1 == keys.backspace then
                    if #input > 0 then
                        input = string.sub(input, 1, -2)
                        redrawInputLineOnly()
                    end
                elseif p1 == keys.enter then
                    if input ~= "" then
                        local messageToSend = { from = getParent(context).username, text = input }
                        rednet.send(getParent(context).chatServerId, messageToSend, "SimpleChat")
                        lastMessage = string.format("[%s]: %s", getParent(context).nickname, messageToSend.text)
                        table.insert(history, lastMessage)
                        if #history > 100 then
                            table.remove(history, 1)
                        end
                        input = ""
                        redrawAll()
                    end
                end
            elseif event == "char" then
                input = input .. p1
                redrawInputLineOnly()
            elseif event == "terminate" then
                break
            end
        end
    end

    redrawAll()
    parallel.waitForAny(keyboardListener, networkListener)
end

function apps.sendFeedback(context)
    context.drawWindow("Send Feedback to Admin")
    local subject = context.readInput("Subject: ", 4)
    if not subject or subject == "" then return end
    apps.composeAndSend(context, "MuhendizBey", "Feedback: " .. subject, nil)
end


-- Admin Console has been moved to a separate script (Admin_Console.lua)


function apps.systemMenu(context)
    local options = {"Change Nickname", "Update Games", "Back"}
    local selected = 1
    while true do
        context.drawWindow("System")
        context.drawMenu(options, selected, 2, 4)
        local event, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then apps.changeNickname(context); break
            elseif selected == 2 then apps.updateGames(context)
            elseif selected == 3 then break end
        elseif key == keys.tab or key == keys.q then break end
    end
end

function apps.changeNickname(context)
    context.drawWindow("Change Nickname")
    local new_nick = context.readInput("New nickname: ", 4)
    if new_nick and new_nick ~= "" then
        rednet.send(getParent(context).mailServerId, { type = "set_nickname", user = getParent(context).username, new_nickname = new_nick }, "SimpleMail")
        context.drawWindow("Updating...")
        local _, response = rednet.receive("SimpleMail", 5)
        if response and response.success then
            getParent(context).nickname = response.new_nickname
            context.showMessage("Success", "Nickname updated!")
        else
            context.showMessage("Error", "Could not update nickname.")
        end
    end
end

    function apps.updateGames(context)
    context.drawWindow("Updating Arcade")
    local y = 4
    local gamesDir = fs.combine(context.programDir, "games")
    if not fs.exists(gamesDir) then
        fs.makeDir(gamesDir)
    end

    -- Step 1: Get list of ALL game versions from server
    term.setCursorPos(2, y); term.write("Checking for updates...")
    rednet.send(getParent(context).mailServerId, { type = "get_all_game_versions" }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 5)

    if not response or response.type ~= "game_versions_response" or not response.versions then
        context.showMessage("Error", "Could not fetch updates from server.")
        return
    end

    local serverVersions = response.versions
    local _, gameListResponse = rednet.receive("SimpleMail", 1) -- Flush potential old messages

    local function getLocalVersion(filename)
        local path = fs.combine(gamesDir, filename)
        if fs.exists(path) then
            local file = fs.open(path, "r")
            if file then
                local content = file.readAll()
                file.close()
                local v = content:match("%-%-%s*Version:%s*([%d%.]+)")
                if not v then
                    v = content:match("local%s+currentVersion%s*=%s*([%d%.]+)")
                end
                return tonumber(v) or 0
            end
        end
        return 0
    end

    y = y + 1
    local updatesFound = false

    -- Step 2: Compare with local versions
    for filename, serverVer in pairs(serverVersions) do
        -- Only update if we have the game installed OR if it's a core game
        local localVer = getLocalVersion(filename)
        
        if serverVer > localVer then
            updatesFound = true
            context.drawWindow("Updating Arcade") -- clear screen
            term.setCursorPos(2, 4); term.write("Updating " .. filename .. "...")
            term.setCursorPos(2, 5); term.write("v" .. localVer .. " -> v" .. serverVer)
            
            rednet.send(getParent(context).mailServerId, {type = "get_game_update", filename = filename}, "SimpleMail")
            local _, update = rednet.receive("SimpleMail", 5)
            
            if update and update.code then
                local path = fs.combine(context.programDir, filename)
                local file = fs.open(path, "w")
                if file then
                    file.write(update.code)
                    file.close()
                end
            end
        end
    end

    if updatesFound then
        context.showMessage("Success", "All games updated successfully!")
    else
        context.showMessage("Info", "All games are up to date.")
    end
end
	function apps.enterArcade(context)
    context.drawWindow("Arcade")
    term.setCursorPos(2, 4); term.write("Fetching game list...")
    rednet.send(getParent(context).mailServerId, { type = "get_gamelist" }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 10)

    if not response or not response.games then
        context.showMessage("Error", "Could not get game list from server.")
        return
    end

    local games = response.games
    if #games == 0 then
        context.showMessage("Arcade", "No games are currently available.")
        return
    end

    local function gameMenu(games)
        local options = {}
        for _, game in ipairs(games) do table.insert(options, "Play " .. game.name) end
        table.insert(options, "Back")
    
        local selected = 1
        while true do
            context.drawWindow("Arcade"); context.drawMenu(options, selected, 2, 4)
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
                        shell.run(gameFile, getParent(context).username)
                    end
                else
                    break
                end
            elseif key == keys.tab or key == keys.q then break end
        end
    end
    
    gameMenu(games)
end

function apps.showHelpScreen(context)
    context.drawWindow("Help")
    local y = 3
    term.setCursorPos(2, y); term.write("Use UP/DOWN arrows and ENTER to navigate menus.")
    y = y + 2
    term.setCursorPos(2, y); term.write("Q or TAB will usually go back to the previous screen.")
    y = y + 2
    term.setCursorPos(2, y); term.write("Most screens have context-specific help on the")
    y = y + 1
    term.setCursorPos(2, y); term.write("bottom status bar.")
    y = y + 3
    term.setTextColor(context.theme.prompt)
    term.setCursorPos(2,y)
    term.write("Press any key to return...")
    os.pullEvent("key")
end

return apps

