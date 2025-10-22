--[[
    Drunken Beard Bank - Clerk Terminal (v1.0 - Initial Release)
    by Gemini Gem & MuhendizBey

    Purpose:
    This program provides a secure, user-friendly interface for bank staff
    to create bank cards. It replaces the old admin command and securely
    fetches the correct user password hash from the main server to write
    onto the card, fixing the placeholder issue.
]]

--==============================================================================
-- API & Library Initialization
--==============================================================================

local crypto = require("lib.sha1_hmac")

--==============================================================================
-- Configuration & State
--==============================================================================

local mainServerId = nil
local bankServerId = nil

local CLERK_PROTOCOL = "DB_Clerk"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"

--==============================================================================
-- Graphical UI & Theme
--==============================================================================

local theme = {
    bg = colors.black,
    text = colors.white,
    border = colors.blue,
    titleBg = colors.lightBlue,
    titleText = colors.white,
    highlightBg = colors.yellow,
    highlightText = colors.black,
    errorBg = colors.red,
    errorText = colors.white,
}

local function drawFrame(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg); term.clear()
    term.setBackgroundColor(theme.border)
    for y=1,h do term.setCursorPos(1,y); term.write(" "); term.setCursorPos(w,y); term.write(" ") end
    for x=1,w do term.setCursorPos(x,1); term.write(" "); term.setCursorPos(x,h); term.write(" ") end
    term.setBackgroundColor(theme.titleBg); term.setTextColor(theme.titleText)
    local titleText = " " .. (title or "Drunken Beard Bank - Clerk Terminal") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
end

local function printCentered(startY, text)
    local w, h = term.getSize()
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, startY)
    term.write(text)
end

local function showMessage(title, message, isError)
    local w, h = term.getSize()
    local boxBg = isError and theme.errorBg or theme.titleBg
    local boxText = isError and theme.errorText or theme.titleText
    local boxW, boxH = math.floor(w * 0.8), math.floor(h * 0.7)
    local boxX, boxY = math.floor((w - boxW) / 2), math.floor((h - boxH) / 2)

    term.setBackgroundColor(boxBg)
    for y = boxY, boxY + boxH - 1 do
        term.setCursorPos(boxX, y); term.write(string.rep(" ", boxW))
    end

    term.setTextColor(boxText)
    local titleText = " " .. title .. " ";
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, boxY + 1); term.write(titleText)

    local lines = {}
    for line in message:gmatch("[^\n]+") do
        while #line > boxW - 4 do
            table.insert(lines, line:sub(1, boxW - 4))
            line = line:sub(boxW - 3)
        end
        table.insert(lines, line)
    end

    for i, line in ipairs(lines) do
        term.setCursorPos(boxX + 2, boxY + 3 + i)
        print(line)
    end

    local continueText = "Press any key to continue..."
    term.setCursorPos(math.floor((w - #continueText) / 2) + 1, boxY + boxH - 2)
    print(continueText)

    os.pullEvent("key")
end

--==============================================================================
-- Core Application Logic
--==============================================================================

local function makeCard()
    drawFrame("Create Bank Card")
    term.setCursorPos(3, 4)
    print("Enter the username for the new bank card.")
    term.setCursorPos(3, 6)
    write("> ")
    term.setCursorBlink(true)
    local user = read()
    term.setCursorBlink(false)

    if not user or user == "" then
        showMessage("Error", "Username cannot be empty.", true)
        return
    end

    printCentered(8, "Verifying user with Mainframe...")
    rednet.send(mainServerId, { type = "user_exists_check", user = user }, AUTH_INTERLINK_PROTOCOL)
    local _, response = rednet.receive(AUTH_INTERLINK_PROTOCOL, 5)

    if not response or not response.exists then
        showMessage("Error", "Mainframe reports user '" .. user .. "' does not exist.", true)
        return
    end

    printCentered(10, "User verified. Requesting password hash from Mainframe...")
    rednet.send(mainServerId, { type = "get_user_data", user = user }, AUTH_INTERLINK_PROTOCOL)
    local _, userData = rednet.receive(AUTH_INTERLINK_PROTOCOL, 5)

    if not userData or not userData.success then
        showMessage("Error", "Could not retrieve user data from Mainframe.", true)
        return
    end

    printCentered(12, "Password hash received. Please insert a blank disk.")
    local drive = peripheral.find("drive")
    if not drive then
        showMessage("Error", "No disk drive attached to this terminal.", true)
        return
    end

    if not drive.isDiskPresent() then
        showMessage("Error", "No disk in the drive.", true)
        return
    end

    local mount_path = drive.getMountPath()
    if not mount_path then
        showMessage("Error", "Could not get disk mount path.", true)
        return
    end

    drive.setDiskLabel("DrunkenBeard_Card_" .. user)

    local cardData = { pass_hash = userData.pass_hash }
    local cardFile = fs.open(mount_path .. "/.card_data", "w")
    if cardFile then
        cardFile.write(textutils.serialize(cardData))
        cardFile.close()
        showMessage("Success", "Successfully created bank card for " .. user)
    else
        showMessage("Error", "Could not write data file to disk.", true)
    end
end

local function mainMenu()
    while true do
        drawFrame("Clerk Main Menu")
        local options = { "Create Bank Card", "Exit" }
        local choice = drawMenu("Select an option:", options, "Welcome, Clerk.")

        if not choice or choice == 2 then break end

        if choice == 1 then makeCard() end
    end
end

local function drawMenu(title, options, help)
    local w, h = term.getSize()
    local selected = 1
    while true do
        drawFrame(title)
        for i, opt in ipairs(options) do
            term.setCursorPos(4, 4 + i)
            if i == selected then
                term.setBackgroundColor(theme.highlightBg)
                term.setTextColor(theme.highlightText)
            else
                term.setBackgroundColor(theme.bg)
                term.setTextColor(theme.text)
            end
            term.write(" " .. opt .. string.rep(" ", w - 6 - #opt) .. " ")
        end
        term.setBackgroundColor(theme.bg)
        term.setTextColor(colors.yellow)
        if help then
            printCentered(h - 2, help)
        end
        local _, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            term.setBackgroundColor(theme.bg)
            term.setTextColor(theme.text)
            return selected
        elseif key == keys.q or key == keys.tab then return nil
        end
    end
end

--==============================================================================
-- Main Program Loop
--==============================================================================

local function main()
    local modem = peripheral.find("modem")
    if not modem then error("No modem attached.", 0) end
    rednet.open(peripheral.getName(modem))

    mainServerId = rednet.lookup("SimpleMail", "mail.server")
    if not mainServerId then error("Could not find main Drunken OS server.", 0) end

    bankServerId = rednet.lookup("DB_Bank", "bank.server")
    if not bankServerId then error("Could not find bank server.", 0) end

    drawFrame("Login")
    printCentered(4, "Please enter your Drunken OS username.")
    term.setCursorPos(3, 6)
    write("> ")
    term.setCursorBlink(true)
    local user = read()
    term.setCursorBlink(false)

    rednet.send(mainServerId, { type = "is_admin_check", user = user }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 5)

    if response and response.isAdmin then
        mainMenu()
    else
        showMessage("Access Denied", "You are not authorized to use this terminal.", true)
    end

    rednet.close(peripheral.getName(modem))
    drawFrame("Goodbye")
    printCentered(8, "Clerk terminal shutting down.")
    sleep(2)
end

main()
