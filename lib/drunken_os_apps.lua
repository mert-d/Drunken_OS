--[[
    Drunken OS - Core Application Library (v2.0 - Modular)
    by Gemini Gem & MuhendizBey

    Purpose:
    This library contains the core Login and Authentication logic for Drunken OS.
    Most application logic has been moved to the /apps/ directory.
]]

local apps = {}
apps._VERSION = 2.0

local function getParent(context)
    return context.parent
end

local function completeAuthentication(context, user)
    context.drawWindow("Authentication Required")
    local w, h = context.getSafeSize()
    local message = "A verification token has been sent to you via the HyperAuth API. Please enter the code below to finalize your registration/login."
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
            local sessionPath = fs.combine(context.programDir, ".session")
            local file = fs.open(sessionPath, "w")
            if file then file.write(response.session_token); file.close() end
        end
        context.showMessage("Success", "Authentication successful!")
        return true
    else
        context.showMessage("Authentication Failed", (response and response.reason) or "No response.")
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
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            if selected == 1 then
                context.drawWindow("Login")
                local user = context.readInput("Username: ", 5, false)
                if user and user ~= "" then
                    local pass = context.readInput("Password: ", 7, true)
                    if pass and pass ~= "" then
                        local session_token = nil
                        local sessionPath = fs.combine(context.programDir, ".session")
                        if fs.exists(sessionPath) then
                            local file = fs.open(sessionPath, "r")
                            if file then session_token = file.readAll(); file.close() end
                        end
                        rednet.send(getParent(context).mailServerId, { type = "login", user = user, pass = pass, session_token = session_token }, "SimpleMail")
                        local _, response = rednet.receive("SimpleMail", 15)
                        if response and response.success then
                            if response.needs_auth then
                                if not completeAuthentication(context, user) then getParent(context).username = nil end
                            else
                                getParent(context).username = user
                                getParent(context).nickname = response.nickname
                                getParent(context).unreadCount = response.unreadCount or 0
                                getParent(context).isAdmin = response.isAdmin or false
                            end
                        else
                            context.showMessage("Login Failed", (response and response.reason) or "No response.")
                        end
                    end
                end
            elseif selected == 2 then
                context.drawWindow("Register")
                local user = context.readInput("Username: ", 5, false)
                if user and user ~= "" then
                    local nick = context.readInput("Nickname: ", 7, false)
                    if nick and nick ~= "" then
                        local pass = context.readInput("Password: ", 9, true)
                        if pass and pass ~= "" then
                            rednet.send(getParent(context).mailServerId, { type = "register", user = user, pass = pass, nickname = nick }, "SimpleMail")
                            local _, response = rednet.receive("SimpleMail", 15)
                            if response and response.success and response.needs_auth then
                                if not completeAuthentication(context, user) then getParent(context).username = nil end
                            else
                                context.showMessage("Registration Failed", (response and response.reason) or "No response.")
                            end
                        end
                    end
                end
            elseif selected == 3 then return false end
        end
    end
    return true
end

function apps.showHelpScreen(context)
    context.drawWindow("Help")
    term.setCursorPos(2, 3); term.write("Use UP/DOWN and ENTER to navigate.")
    term.setCursorPos(2, 5); term.write("Q or TAB to go back.")
    term.setTextColor(context.theme.prompt); term.setCursorPos(2, 7); term.write("Press any key to return...")
    os.pullEvent("key")
end

return apps
