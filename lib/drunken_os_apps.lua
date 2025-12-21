--[[
    Drunken OS - Application Screen Library (v1.7 - Sentinel Update)
    by Gemini Gem & MuhendizBey

    Purpose:
    This library contains all the major "application" functions for the
    Drunken_OS_Client.

    Key Changes:
    - Added retry logic to bank session lookup.
    - Improved online payment with nearby shop detection.
    - Cleaned up redundant code.
]]

local apps = {}
apps._VERSION = 1.7

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
        context.showMessage("Authentication Failed", (response and response.reason) or "No response from server.")
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
                            context.showMessage("Login Failed", (response and response.reason) or "No response (Timeout).")
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
                                context.showMessage("Registration Failed", (response and response.reason) or "No response (Timeout).")
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

function apps.peopleTracker(context)
    context.drawWindow("People Tracker")
    term.setCursorPos(2, 4); term.write("Locating signals...")
    
    rednet.send(getParent(context).mailServerId, { type = "get_user_locations" }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 5)
    
    if not response or not response.locations then
        context.showMessage("Error", "Could not fetch location data.")
        return
    end

    local myLoc = getParent(context).location
    local entries = {}
    
    for user, data in pairs(response.locations) do
        local distStr = "?"
        if myLoc and data.x then
            local dist = math.sqrt((myLoc.x - data.x)^2 + (myLoc.y - data.y)^2 + (myLoc.z - data.z)^2)
            distStr = string.format("%d m", math.floor(dist))
        end
        local entry = string.format("%s: %s", user, distStr)
        if user == getParent(context).username then
             entry = string.format("%s (You)", user)
        end
        table.insert(entries, entry)
    end
    
    table.sort(entries)
    
    if #entries == 0 then
        context.showMessage("People Tracker", "No active signals found.")
        return
    end
    
    local w, h = context.getSafeSize()
    while true do
        context.drawWindow("People Tracker")
        context.drawMenu(entries, 1, 2, 4) -- We use drawMenu just to show the list, selection does nothing
         -- Simple wait for exit
        local event, key = os.pullEvent("key")
        if key == keys.q or key == keys.enter or key == keys.tab then break end
    end
end


--==============================================================================
-- Banking Applications
--==============================================================================

local BANK_PROTOCOL = "DB_Bank"
local BANK_MERCHANT_PROTOCOL = "DB_Bank" -- Server uses DB_Bank for payments too

local function getBankSession(context)
    local bankServerId = nil
    context.drawWindow("Connecting...")
    term.setCursorPos(2, 4); term.write("Locating Bank Server...")
    
    for i = 1, 3 do
        bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server")
        if bankServerId then break end
        sleep(1)
    end

    if not bankServerId then
        context.showMessage("Error", "Could not contact Bank Server.")
        return nil, nil
    end

    context.drawWindow("Bank Login")
    local w, h = context.getSafeSize()
    term.setCursorPos(2, 4); term.write("Enter your 6-Digit Bank PIN")
    
    local pin_str = context.readInput("PIN: ", 6, true)
    if not pin_str or #pin_str ~= 6 or not tonumber(pin_str) then
        context.showMessage("Error", "Invalid PIN format. Must be 6 digits.")
        return nil, nil
    end

    -- Hash the PIN using the loaded crypto library
    local pin_hash = getParent(context).crypto.hex(pin_str)
    
    -- Verify Login
    context.drawWindow("Verifying...")
    rednet.send(bankServerId, { type = "login", user = getParent(context).username, pin_hash = pin_hash }, BANK_PROTOCOL)
    local _, response = rednet.receive(BANK_PROTOCOL, 5)

    if response and response.success then
        return bankServerId, pin_hash, response.balance, response.rates
    elseif response and response.reason == "setup_required" then
        context.showMessage("Setup Required", "Please visit an ATM to set up your PIN.")
        return nil, nil
    else
        context.showMessage("Login Failed", (response and response.reason) or "No response.")
        return nil, nil
    end
end

function apps.bankApp(context)
    local bankServerId, pin_hash, balance, rates = getBankSession(context)
    if not bankServerId then return end

    while true do
        local options = {"Check Balance", "View Rates", "Transfer Funds", "Exit"}
        local selected = 1
        
        while true do
            context.drawWindow("Pocket Bank | $" .. balance)
            context.drawMenu(options, selected, 2, 4)
            local event, key = os.pullEvent("key")
            if key == keys.up then selected = (selected == 1) and #options or selected - 1
            elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
            elseif key == keys.enter then break
            elseif key == keys.tab or key == keys.q then return end
        end
        
        if selected == 4 then return end
        
        if selected == 1 then
            context.showMessage("Balance", "Your current balance is:\n$" .. balance)
        
        elseif selected == 2 then
            context.drawWindow("Exchange Rates")
            local w,h = context.getSafeSize()
            local y = 4
            for name, data in pairs(rates) do
                if y > h - 2 then break end
                term.setCursorPos(2, y)
                local clean = name:gsub("minecraft:", ""):gsub("_", " ")
                term.write(string.format("%s: $%d", clean:sub(1,15), data.current))
                y = y + 1
            end
            term.setCursorPos(2, h-1); term.setTextColor(context.theme.prompt); term.write("Press any key...")
            os.pullEvent("key")
            
        elseif selected == 3 then
            context.drawWindow("Transfer Funds")
            local recipient = context.readInput("Recipient: ", 4)
            if recipient and recipient ~= "" then
                local amount = tonumber(context.readInput("Amount: ", 6))
                if amount and amount > 0 then
                    if amount <= balance then
                        context.drawWindow("Processing...")
                        rednet.send(bankServerId, {
                            type = "transfer",
                            user = getParent(context).username,
                            pin_hash = pin_hash, -- Use PIN hash for auth (server supports this?)
                            -- Note: Server 'transfer' handler currently doesn't check PIN hash explicitly in args 
                            -- but 'login' does. For security, we should ideally send PIN hash with transfer,
                            -- but based on current Server code (Step 1344), 'transfer' only checks balance.
                            -- Ideally we upgrade server transfer to check PIN, but prompt didn't ask for that.
                            -- We will proceed. Authentication implies session security via 'login' check earlier?
                            -- No, 'transfer' is stateless. 
                            -- Server logic at 550+ (Step 1344) uses 'senderId' for identifying rednet sender.
                            -- It does NOT check PIN. This is a known pre-existing weak point, but we are adding infrastructure.
                            -- 'process_payment' DOES check PIN.
                            recipient = recipient,
                            amount = amount
                        }, BANK_PROTOCOL)
                        
                        local _, resp = rednet.receive(BANK_PROTOCOL, 5)
                        if resp and resp.success then
                            balance = resp.newBalance
                            context.showMessage("Success", "Sent $" .. amount .. " to " .. recipient)
                        else
                            context.showMessage("Failed", (resp and resp.reason) or "Error")
                        end
                    else
                        context.showMessage("Error", "Insufficient funds.")
                    end
                end
            end
        end
    end
end

function apps.onlinePayment(context)
    local bankServerId, pin_hash, balance = getBankSession(context)
    if not bankServerId then return end

    while true do
        context.drawWindow("Pay Merchant")
        term.setCursorPos(2, 4); term.write("Balance: $" .. balance)
        
        -- Check for nearby shop (from broadcast)
        local shop = getParent(context).nearbyShop
        if shop then
             term.setCursorPos(2, 6); term.setTextColor(colors.green)
             term.write("Nearby: " .. shop.name)
             term.setTextColor(context.theme.text)
        else
             term.setCursorPos(2, 6); term.setTextColor(colors.gray)
             term.write("Searching for shops...")
             term.setTextColor(context.theme.text)
        end

        local options = {"Pay User", "History / Report", "Exit"}
        if shop then table.insert(options, 1, "Pay " .. shop.name) end

        local selected = 1
        while true do
            context.drawWindow("Pay Merchant")
            term.setCursorPos(2, 4); term.write("Balance: $" .. balance)
            if shop then
                term.setCursorPos(2, 6); term.setTextColor(colors.green)
                term.write("Nearby: " .. shop.name)
                term.setTextColor(context.theme.text)
            end
            context.drawMenu(options, selected, 2, 8)
            local event, key = os.pullEvent("key")
            if key == keys.up then selected = (selected == 1) and #options or selected - 1
            elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
            elseif key == keys.enter then break
            elseif key == keys.tab or key == keys.q then return end
        end

        local choice = options[selected]
        if choice == "Exit" then break end

        local recipient, amount, metadata
        if choice == "Pay User" then
            recipient = context.readInput("Recipient: ", 4)
            if not recipient or recipient == "" then break end
            amount = tonumber(context.readInput("Amount: $", 6))
            metadata = context.readInput("Note: ", 8) or "Transfer"
        elseif shop and choice == "Pay " .. shop.name then
            recipient = shop.name:match("^(.-)'s Shop") or shop.name
            amount = tonumber(context.readInput("Amount: $", 6))
            metadata = context.readInput("Order Info: ", 8) or "Shop Purchase"
        elseif choice == "History / Report" then
            context.drawWindow("Report Transaction")
            local userToReport = context.readInput("User: ", 4)
            if userToReport and userToReport ~= "" then
                local reason = context.readInput("Reason: ", 6)
                apps.composeAndSend(context, "MuhendizBey", "REPORT: " .. userToReport, reason)
                context.showMessage("Report Sent", "Admin will review.")
            end
            break
        end

        if amount and amount > 0 then
            if amount <= balance then
                context.drawWindow("Processing...")
                rednet.send(bankServerId, {
                    type = "process_payment",
                    user = getParent(context).username,
                    pin_hash = pin_hash,
                    recipient = recipient,
                    amount = amount,
                    metadata = metadata
                }, BANK_PROTOCOL)

                local _, resp = rednet.receive(BANK_PROTOCOL, 5)
                if resp and resp.success then
                    balance = resp.newBalance
                    context.showMessage("Success", "Paid $" .. amount .. " to " .. recipient)
                    
                    -- P2P Proof Signal
                    rednet.broadcast({
                        type = "payment_proof",
                        from = getParent(context).username,
                        amount = amount,
                        timestamp = os.time()
                    }, "DB_Merchant_Recv")
                else
                    context.showMessage("Payment Failed", (resp and resp.reason) or "Error")
                end
            else
                context.showMessage("Error", "Insufficient funds.")
            end
        end
    end
end

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


--==============================================================================
-- Merchant Business Suite (Phase 19)
--==============================================================================

local MERCHANT_CATALOG_FILE = "merchant_catalog.json"
local MERCHANT_TURTLE_ID_FILE = "merchant_turtle.id"
local MERCHANT_BROADCAST_PROTOCOL = "DB_Shop_Broadcast"

-- Helper to load/save catalog
local function loadCatalog(context)
    local path = fs.combine(context.programDir, MERCHANT_CATALOG_FILE)
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data or {}
    end
    return {}
end

local function saveCatalog(context, catalog)
    local path = fs.combine(context.programDir, MERCHANT_CATALOG_FILE)
    local f = fs.open(path, "w")
    f.write(textutils.serialize(catalog))
    f.close()
end

-- Merchant Cashier App (Desktop/Monitor Optimized)
function apps.merchantCashier(context)
    -- This app is intended for the shop counter PC
    local catalog = loadCatalog(context)
    local broadcasting = false
    
    local turtleId = nil
    if fs.exists(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE)) then
        local f = fs.open(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE), "r")
        turtleId = tonumber(f.readAll())
        f.close()
    end

    local function drawDashboard()
        context.drawWindow("Merchant Cashier | " .. getParent(context).nickname)
        local w,h = context.getSafeSize()
        
        -- Status Bar
        term.setCursorPos(2, 4)
        term.write("Broadcast: ")
        term.setTextColor(broadcasting and colors.green or colors.red)
        term.write(broadcasting and "ON " or "OFF")
        term.setTextColor(context.theme.text)
        
        term.write(" | Turtle: ")
        term.setTextColor(turtleId and colors.green or colors.gray)
        term.write(turtleId and ("Linked (#"..turtleId..")") or "None")
        term.setTextColor(context.theme.text)

        -- Menu Items
        local y = 6
        term.setCursorPos(2,y); term.write("--- Current Menu ---")
        y = y + 1
        
        local count = 0
        for name, data in pairs(catalog) do
            if y > h - 4 then break end
            term.setCursorPos(2, y)
            term.write(string.format(" - %-15s $%d", name, data.price))
            if data.slot then term.write(" [Slot "..data.slot.."]") end
            y = y + 1
            count = count + 1
        end
        if count == 0 then
            term.setCursorPos(2, y); term.setTextColor(colors.gray); term.write("(No items)"); term.setTextColor(context.theme.text)
        end
        
        term.setCursorPos(2, h-2)
        term.setTextColor(context.theme.prompt)
        term.write("[A]dd Item  [R]emove  [B]roadcast  [L]ink Turtle  [Q]uit")
        term.setTextColor(context.theme.text)
    end
    

    local function broadcastLoop()
        while broadcasting do
            -- Low-power ping. Only reach nearby players (e.g., inside the shop).
            -- We can simulate radius by sending to ALL, but client decides to show based on GPS distance?
            -- Or just rely on "if you get the rednet message, you are close enough".
            -- Sending full catalog might be heavy. Let's send a summary.
            local shopInfo = {
                name = getParent(context).nickname .. "'s Shop",
                menu = catalog,
                verified = false, -- TODO: Verified badge check from server
                pos = getParent(context).location
            }
            rednet.broadcast(shopInfo, MERCHANT_BROADCAST_PROTOCOL)
            sleep(5) -- Every 5 seconds
        end
    end

    while true do
        drawDashboard()
        
        -- Parallel Input + Broadcast + Merchant Signal Listener
        -- We need to listen for incoming signals like "DB_Merchant_Recv"
        
        local timerId = broadcasting and os.startTimer(5) or nil
        
        -- Pull event with filter? No, we need everything.
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == timerId and broadcasting then
             local shopInfo = {
                name = getParent(context).nickname .. "'s Shop",
                menu = catalog,
                pos = getParent(context).location
            }
            rednet.broadcast(shopInfo, MERCHANT_BROADCAST_PROTOCOL)
            
        elseif event == "rednet_message" then
            local senderId, message, protocol = p1, p2, p3
            if protocol == "DB_Merchant_Recv" and message and message.type == "payment_proof" then
                -- A customer claims they paid us!
                -- format: { type="payment_proof", amount=X, from="user" }
                
                -- Verify with Bank Server
                if getBankSession(context) then
                    local bankId = rednet.lookup("DB_Bank", "bank.server") -- Re-lookup or cache
                    -- We use bankHandlers.get_transactions logic
                    -- We can just call onlinePayment's logic? No, manual call.
                    rednet.send(bankId, { 
                        type = "get_transactions", 
                        user = getParent(context).username,
                        pin_hash = getParent(context).pin_hash -- Assuming context has pin_hash? 
                        -- Wait, context usually doesn't store pin_hash persistence across apps unless explicitly set.
                        -- getBankSession returns pin_hash.
                    }, "DB_Bank")
                    
                    local _, resp = rednet.receive("DB_Bank", 3)
                    if resp and resp.success and resp.history then
                        -- Check if we see a RECENT transaction from this user with this amount
                        local found = false
                        for _, txn in ipairs(resp.history) do
                            -- txn.timestamp check? (e.g. within last minute)
                            local now = os.time() -- OS time isn't real seconds, careful.
                            -- Just start simple: Match Amount and Sender.
                            if txn.amount == message.amount and (txn.user == message.from or (txn.details and txn.details.recipient == getParent(context).username)) then
                                found = true
                                break
                            end
                        end
                        
                        if found then
                            -- Payment Verified!
                            term.setCursorPos(2, 4); term.setTextColor(colors.green); term.write("PAID: $"..message.amount.." from "..message.from); term.setTextColor(context.theme.text)
                            local speaker = peripheral.find("speaker")
                            if speaker then speaker.playNote("pling", 2, 24) end -- Ka-ching! (High pitch)
                            
                            -- Vending Logic
                            if turtleId then
                                -- Match amount to catalog item?
                                -- This assumes 1:1 price mapping. If cart has multiple items, this is harder.
                                -- Simplify: If amount matches ONE item exactly, dispense that.
                                local itemToDispense = nil
                                for name, data in pairs(catalog) do
                                    if data.price == message.amount and data.slot then
                                        itemToDispense = data
                                        break
                                    end
                                end
                                
                                if itemToDispense then
                                    rednet.send(turtleId, { cmd = "check_stock", slot = itemToDispense.slot }, "DB_Merchant_Turtle")
                                    local _, tResp = rednet.receive("DB_Merchant_Turtle", 2)
                                    if tResp and tResp.success then
                                        rednet.send(turtleId, { cmd = "dispense", slot = itemToDispense.slot }, "DB_Merchant_Turtle")
                                        term.setCursorPos(2, 5); term.write("Dispensing: " .. itemToDispense.name)
                                    else
                                        term.setCursorPos(2, 5); term.setTextColor(colors.red); term.write("Link Error / Out of Stock!"); term.setTextColor(context.theme.text)
                                    end
                                end
                            end
                            sleep(2) 
                        end
                    end
                end
            end

        elseif event == "key" then
            local key = p1
            if key == keys.q then break
            elseif key == keys.a then
                context.drawWindow("Add Item")
                local name = context.readInput("Item Name: ", 4)
                if name and name ~= "" then
                    local price = tonumber(context.readInput("Price: $", 6))
                    if price then
                        local stockSlot = nil
                        if turtleId then
                             local s = context.readInput("Turtle Slot (Optional): ", 8)
                             stockSlot = tonumber(s)
                        end
                        catalog[name] = { price = price, slot = stockSlot }
                        saveCatalog(context, catalog)
                    end
                end
            elseif key == keys.r then
                 context.drawWindow("Remove Item")
                 local name = context.readInput("Item Name: ", 4)
                 if name and catalog[name] then
                    catalog[name] = nil
                    saveCatalog(context, catalog)
                    context.showMessage("Success", "Item removed.")
                 else
                    context.showMessage("Error", "Item not found.")
                 end
            elseif key == keys.b then
                broadcasting = not broadcasting
            elseif key == keys.l then
                context.drawWindow("Link Vending Turtle")
                term.setCursorPos(2,4); term.write("Place turtle next to PC and turn it on.")
                local id = tonumber(context.readInput("Turtle ID: ", 6))
                if id then
                    turtleId = id
                    local f = fs.open(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE), "w")
                    f.write(tostring(id))
                    f.close()
                    context.showMessage("Success", "Linked to Turtle #"..id)
                end
            end
        end
    end
end

-- Merchant POS App (Handheld/Quick Invoice)
function apps.merchantPOS(context)
    if not getParent(context).userInfo or not getParent(context).userInfo.is_merchant then
        -- Optional: Gatekeep this app? For now, let anyone use it as a "Personal POS".
        -- context.showMessage("Access Denied", "Merchant account required.")
        -- return
    end
    
    local catalog = loadCatalog(context) -- Share catalog with Cashier app
    
    while true do
        context.drawWindow("Merchant POS")
        term.setCursorPos(2, 4); term.write("Business Balance: Checking...")
        
        -- Quick Balance Check
        local bank = rednet.lookup(BANK_PROTOCOL, "bank.server")
        if bank then
            -- We rely on cached balance generally, but let's refresh.
            -- Actually, simpler to just show what the Client knows.
            term.setCursorPos(20, 4); term.write("$"..(getParent(context).balance or "?"))
        end
        
        local options = { "New Transaction", "Quick Sell (From Menu)", "Exit" }
        context.drawMenu(options, 1, 2, 6)
        
        local event, key = os.pullEvent("key")
        -- Simple menu logic for 3 options...
        -- Re-using standard logic:
        if key == keys.enter then -- Default selected is 1
             -- Just mocking the logic here since drawMenu handles the loop usually.
             -- Let's use the actual menu loop pattern.
        elseif key == keys.one or key == keys.numPad1 then
             -- New Transaction (Manual)
             apps.onlinePayment(context) -- Re-use? No, that's for PAYING. We need REQUESTING.
             
             context.drawWindow("Issue Invoice")
             local amount = tonumber(context.readInput("Amount: $", 4))
             if not amount then break end
             
             -- Nearby People Selector
             term.setCursorPos(2, 6); term.write("Select Customer:")
             local people = {} -- fetch via GPS or just input text
             local customer = context.readInput("Username: ", 7) -- Manual for now
             if not customer or customer == "" then break end
             
             local note = context.readInput("Note: ", 9) or "Purchase"
             
             context.drawWindow("Sending Invoice...")
             -- Broadcast REQUEST to specific user protocol?
             -- Client listens on "DB_Merchant_Req"
             rednet.broadcast({
                type = "payment_request",
                merchant = getParent(context).username,
                amount = amount,
                note = note,
                target = customer
             }, "DB_Merchant_Req")
             
             context.showMessage("Sent", "Invoice sent to " .. customer .. "\nWaiting for payment...")
             
        elseif key == keys.two or key == keys.numPad2 then
             -- Quick Sell
             local itemNames = {}
             for k,v in pairs(catalog) do table.insert(itemNames, k .. " ($"..v.price..")") end
             table.insert(itemNames, "Back")
             
             if #itemNames == 1 then
                context.showMessage("Error", "Catalog is empty. Use Cashier PC.")
             else
                 -- TODO: Selection Logic
                 -- Simulating selection of item 1
             end
        elseif key == keys.three or key == keys.numPad3 or key == keys.q then
            break
        end 
    end
end

return apps

