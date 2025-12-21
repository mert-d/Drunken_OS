--[[
    Drunken Beard Bank - ATM Terminal (v5.6 - Proxy & UI Update)
    by MuhendizBey

    Purpose:
    This version provides a definitive hotfix to the login function,
    ensuring it correctly handles numeric-only passwords by replicating the
    hashing behavior of the main Drunken OS client.

    Changelog:
    v5.5:
    - Re-engineered the 'login' function to convert numeric-only password
      input into a 'number' type before hashing. This resolves the hash
      mismatch with bank cards created by the main OS client.
    v5.4:
    - Added type-safe comparison to the login function.
]]

--==============================================================================
-- API & Library Initialization
--==============================================================================

local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path
local crypto = require("lib.sha1_hmac")

local CONFIG_PATH = "atm.conf" -- Define the config file path

--==============================================================================
-- Configuration & State
--==============================================================================

local bankServerId = nil
local turtleClerkId = nil
local username = nil
local card_data = nil
local balance = 0
local currencyRates = {}

local BANK_PROTOCOL = "DB_Bank"
local TURTLE_CLERK_PROTOCOL = "DB_ATM_Turtle"

--==============================================================================
-- Graphical UI & Theme (With new "Beer" theme and text wrapping)
--==============================================================================
-- A new table for reusable utility functions.
local utils = {}

-- A universal word-wrap function.
-- @param text The string to wrap.
-- @param maxWidth The maximum width of each line.
-- @return A table of strings, where each entry is a wrapped line.
function utils.wordWrap(text, maxWidth)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        while #line > maxWidth do
            local breakPoint = maxWidth
            -- Try to find a space to break at.
            while breakPoint > 0 and line:sub(breakPoint, breakPoint) ~= " " do
                breakPoint = breakPoint - 1
            end
            if breakPoint == 0 then breakPoint = maxWidth end -- Force break if no space
            
            table.insert(lines, line:sub(1, breakPoint))
            line = line:sub(breakPoint + 1)
        end
        table.insert(lines, line)
    end
    return lines
end
-- A theme table to make color changes simple and consistent.
-- A theme table to make color changes simple and consistent.
local theme = {
    bg = colors.black,
    text = colors.white,
    border = colors.cyan, -- matched to client
    titleBg = colors.blue, -- matched to client
    titleText = colors.white,
    highlightBg = colors.cyan, -- matched to client
    highlightText = colors.black, -- matched to client
    errorBg = colors.red,
    errorText = colors.white,
}

-- (The 'drawFrame' function is unchanged) -> REPLACED with Premium Style
local function drawFrame(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg)
    term.clear()
    
    -- Draw subtle frame/border
    term.setBackgroundColor(theme.titleBg)
    term.setCursorPos(1, 1); term.write(string.rep(" ", w))
    term.setCursorPos(1, h); term.write(string.rep(" ", w))
    for i = 2, h - 1 do
        term.setCursorPos(1, i); term.write(" ")
        term.setCursorPos(w, i); term.write(" ")
    end

    term.setCursorPos(1, 1)
    term.setTextColor(theme.titleText)
    local titleText = " " .. (title or "Drunken Beard Bank") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    
    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
end

-- NEW: A word-wrapping version of printCentered to prevent text overflow.
local function printCenteredWrapped(startY, text)
    local w, h = term.getSize()
    local lines = utils.wordWrap(text, w - 4)

    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, startY + i - 1)
        term.write(line)
    end
end

local function printCentered(startY, text)
    local w, h = term.getSize()
    local lines = utils.wordWrap(text, w - 2)

    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, startY + i - 1)
        term.write(line)
    end
end

local function showMessage(title, message, isError)
    drawFrame(title)
    local w, h = term.getSize()
    local lines = utils.wordWrap(message, w - 2)

    term.setTextColor(isError and theme.errorBg or theme.text)
    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, 4 + i)
        term.write(line)
    end
    
    local continueText = "Press any key to continue..."
    term.setCursorPos(math.floor((w - #continueText) / 2) + 1, h - 1)
    term.setTextColor(colors.gray)
    term.write(continueText)
    
    os.pullEvent("key")
    term.setTextColor(theme.text)
end

local function drawMenu(title, options, help)
    local w, h = term.getSize()
    local selected = 1
    while true do
        drawFrame(title)
        
        -- Draw Help Text if present
        if help then
            term.setTextColor(colors.gray)
            local helpLines = utils.wordWrap(help, w - 4)
             for i, line in ipairs(helpLines) do
                local x = math.floor((w - #line) / 2) + 1
                term.setCursorPos(x, h - 2 - (#helpLines - i))
                term.write(line)
            end
        end

        -- Draw Options
        for i, opt in ipairs(options) do
            local y = 4 + i
            if y >= h - 2 then break end -- prevent overlap
            
            term.setCursorPos(2, y)
             if i == selected then
                term.setBackgroundColor(theme.highlightBg)
                term.setTextColor(theme.highlightText)
                term.write(" " .. opt .. string.rep(" ", w - 4 - #opt) .. " ")
            else
                term.setBackgroundColor(theme.bg)
                term.setTextColor(theme.text)
                term.write(" " .. opt .. " ")
            end
        end
        
        term.setBackgroundColor(theme.bg)
        
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
-- Core Application Logic (With Corrected 'deposit' function)
--==============================================================================

local function readPin(prompt)
    while true do
        drawFrame(prompt or "Enter 6-Digit PIN")
        term.setCursorPos(3, 6)
        write("PIN: ")
        term.setCursorBlink(true)
        local pin = read("*")
        term.setCursorBlink(false)
        
        if #pin == 6 and tonumber(pin) then
            return crypto.hex(pin)
        elseif #pin == 0 then
            return nil
        else
            showMessage("Error", "PIN must be exactly 6 digits.", true)
        end
    end
end

local function setupPin()
    drawFrame("PIN Setup Required")
    printCenteredWrapped(6, "This card is new. Please set a 6-digit PIN.")
    sleep(2)

    local pin1 = readPin("Set New 6-Digit PIN")
    if not pin1 then return false end

    local pin2 = readPin("Confirm 6-Digit PIN")
    if not pin2 then return false end

    if pin1 ~= pin2 then
        showMessage("Error", "PINs do not match. Restarting setup.", true)
        return setupPin()
    end

    printCentered(12, "Registering PIN...")
    rednet.send(bankServerId, {
        type = "set_pin",
        user = username,
        pin_hash = pin1
    }, BANK_PROTOCOL)

    local _, response = rednet.receive(BANK_PROTOCOL, 15)
    if response and response.success then
        showMessage("Success", "PIN set successfully. You can now log in.")
        return true
    else
        showMessage("Error", (response and response.reason) or "Registration failed.", true)
        return false
    end
end

local function login()
    local pin_hash = nil
    local login_success = false
    
    while not login_success do
        printCenteredWrapped(12, "Contacting Bank Server...")
        rednet.send(bankServerId, { type = "login", user = username, pin_hash = pin_hash }, BANK_PROTOCOL)
        local _, response = rednet.receive(BANK_PROTOCOL, 15)

        if not response then
            showMessage("Error", "No response from bank server.", true)
            return false
        end

        if response.success then
            balance = response.balance
            currencyRates = response.rates
            login_success = true
            return true
        elseif response.reason == "setup_required" then
            if setupPin() then
                pin_hash = nil -- Reset and try login again
            else
                return false
            end
        else
            pin_hash = readPin("Enter 6-Digit PIN for " .. username)
            if not pin_hash then
                return false
            end
        end
    end
    return true
end

-- NEW: Corrected deposit function with full handshake logic
local function deposit()
    drawFrame("Deposit")
    printCentered(6, "Requesting deposit from Vault Clerk...")
    printCentered(8, "Please place items in the deposit barrel.")
    
    rednet.send(turtleClerkId, {type = "request_deposit"}, TURTLE_CLERK_PROTOCOL)

    -- 1. Wait for the turtle to report back with the items it collected.
    printCentered(10, "Waiting for clerk to collect items...")
    local _, turtle_response = rednet.receive(TURTLE_CLERK_PROTOCOL, 30)

    if not turtle_response or turtle_response.type ~= "deposit_count" or not turtle_response.items or #turtle_response.items == 0 then
        showMessage("Deposit Failed", (turtle_response and turtle_response.reason) or "No valid items were deposited.", true)
        return
    end

    -- 2. Send the collected items to the bank server for valuation.
    printCentered(12, "Items collected. Contacting bank for valuation...")
    rednet.send(bankServerId, {type = "deposit", user = username, items = turtle_response.items}, BANK_PROTOCOL)
    local _, server_response = rednet.receive(BANK_PROTOCOL, 15)

    if server_response and server_response.success then
        -- 3. If server is happy, tell the turtle to confirm and store the items.
        printCentered(14, "Valuation complete. Confirming with clerk...")
        rednet.send(turtleClerkId, { type = "confirm_deposit", new_balance = server_response.newBalance }, TURTLE_CLERK_PROTOCOL)

        -- 4. Wait for the turtle's final confirmation that items are stored.
        local _, final_response = rednet.receive(TURTLE_CLERK_PROTOCOL, 15)
        if final_response and final_response.success then
            balance = final_response.new_balance
            showMessage("Success", "Deposit complete. Your new balance is $" .. balance)
        else
            -- This is a serious error state - the server gave value but turtle failed to store.
            showMessage("CRITICAL ERROR", "Clerk failed to store items, but the transaction may have been partially processed. Please contact an admin.", true)
        end
    else
        -- 5. If server rejected the deposit, tell the turtle to return the items.
        rednet.send(turtleClerkId, {type = "cancel_deposit"}, TURTLE_CLERK_PROTOCOL)
        showMessage("Deposit Failed", (server_response and server_response.reason) or "Bank server did not respond.", true)
    end
end


local function withdraw()
    local options = {}
    local item_names = {}
    for name, data in pairs(currencyRates) do
        local clean_name = name:gsub("minecraft:", ""):gsub("_", " ")
        table.insert(options, string.format("%s ($%d)", clean_name, data.current))
        table.insert(item_names, name)
    end
    table.insert(options, "Cancel")
    
    local choice = drawMenu("Select Item to Withdraw", options, "Your balance: $" .. balance)
    if choice == nil or choice > #item_names then return end
    
    local item_name = item_names[choice]
    local rate = currencyRates[item_name].current

    drawFrame("Withdraw Amount")
    term.setCursorPos(3, 4); print("How many " .. item_name:gsub("minecraft:", ""):gsub("_", " ") .. " would you like?")
    term.setCursorPos(3, 5); print("(Cost: $"..rate.." each | Your balance: $"..balance..")")
    term.setCursorPos(3, 7); write("> "); term.setCursorBlink(true)
    local amount_str = read()
    term.setCursorBlink(false)
    
    local amount = tonumber(amount_str)
    if not amount or amount <= 0 then
        showMessage("Error", "Invalid amount entered.", true)
        return
    end

    -- THE FIX: Implement the 3-phase withdrawal protocol.
    
    -- Phase 1: Authorize with the Bank Server
    printCentered(10, "Contacting bank server for authorization...")
    rednet.send(bankServerId, {
        type = "withdraw_item",
        user = username,
        item_name = item_name,
        count = amount
    }, BANK_PROTOCOL)
    
    local _, server_response = rednet.receive(BANK_PROTOCOL, 15)
    
    if not server_response or not server_response.success then
        showMessage("Withdrawal Failed", (server_response and server_response.reason) or "No response from server.", true)
        return
    end
    
    -- Phase 2: If authorized, request physical dispense from the Turtle
    printCentered(12, "Authorization received. Requesting item dispense...")
    rednet.send(turtleClerkId, {
        type = "request_dispense",
        item_name = item_name,
        count = amount
    }, TURTLE_CLERK_PROTOCOL)
    
    local _, turtle_response = rednet.receive(TURTLE_CLERK_PROTOCOL, 30)
    
    if not turtle_response or not turtle_response.success then
        showMessage("Withdrawal Failed", (turtle_response and turtle_response.reason) or "Clerk turtle did not respond.", true)
        -- NOTE: We do not contact the server here, as no items were dispensed and no funds should be deducted.
        return
    end
    
    -- Phase 3: If turtle succeeds, finalize the transaction with the Bank Server
    printCentered(14, "Dispense successful. Finalizing transaction...")
    rednet.send(bankServerId, {
        type = "finalize_withdrawal",
        user = username,
        item_name = item_name,
        count = amount
    }, BANK_PROTOCOL)
    
    local _, final_response = rednet.receive(BANK_PROTOCOL, 15)
    
    if final_response and final_response.success then
        balance = final_response.newBalance
        showMessage("Success", "Please collect your items. New balance: $" .. balance)
    else
        -- This is a critical error state. The user has the items but their balance was not updated.
        showMessage("CRITICAL ERROR", "Could not finalize transaction. Please contact an admin.", true)
    end
end

local function transferFunds()
    drawFrame("Transfer Funds")
    term.setCursorPos(3, 4)
    print("Recipient Username:")
    term.setCursorPos(3, 5)
    write("> ")
    term.setCursorBlink(true)
    local recipient = read()
    term.setCursorBlink(false)

    if not recipient or recipient == "" then return end
    if recipient == username then
        showMessage("Error", "You cannot transfer money to yourself.", true)
        return
    end

    drawFrame("Transfer Amount")
    term.setCursorPos(3, 4)
    print("Amount to transfer to " .. recipient .. ":")
    term.setCursorPos(3, 5)
    print("(Your balance: $" .. balance .. ")")
    term.setCursorPos(3, 7)
    write("> ")
    term.setCursorBlink(true)
    local amount_str = read()
    term.setCursorBlink(false)

    local amount = tonumber(amount_str)
    if not amount or amount <= 0 then
        showMessage("Error", "Invalid amount.", true)
        return
    end

    if amount > balance then
        showMessage("Error", "Insufficient funds.", true)
        return
    end

    -- Confirmation
    drawFrame("Confirm Transfer")
    printCentered(6, "Transfer $" .. amount .. " to " .. recipient .. "?")
    printCentered(8, "This action cannot be undone.")
    
    local confirm = drawMenu("Confirm Transaction", {"Confirm Transfer", "Cancel"}, "Recipient: " .. recipient)
    if confirm ~= 1 then return end

    printCentered(12, "Processing transfer...")
    rednet.send(bankServerId, {
        type = "transfer",
        user = username,
        recipient = recipient,
        amount = amount
    }, BANK_PROTOCOL)

    local _, response = rednet.receive(BANK_PROTOCOL, 15)

    if response and response.success then
        balance = response.newBalance
        showMessage("Success", "Transfer complete. Your new balance is $" .. balance)
    else
        showMessage("Transfer Failed", (response and response.reason) or "No response from server.", true)
    end
end

local function readPin(prompt)
    while true do
        drawFrame(prompt or "Enter 6-Digit PIN")
        term.setCursorPos(3, 6)
        write("PIN: ")
        term.setCursorBlink(true)
        local pin = read("*")
        term.setCursorBlink(false)
        
        if #pin == 6 and tonumber(pin) then
            return crypto.hex(pin)
        elseif #pin == 0 then
            return nil
        else
            showMessage("Error", "PIN must be exactly 6 digits.", true)
        end
    end
end

local function changePin()
    local old_pin_hash = readPin("Current PIN")
    if not old_pin_hash then return end

    local new_pin1 = readPin("Enter New 6-Digit PIN")
    if not new_pin1 then return end

    local new_pin2 = readPin("Confirm New 6-Digit PIN")
    if not new_pin2 then return end

    if new_pin1 ~= new_pin2 then
        showMessage("Error", "PINs do not match.", true)
        return
    end

    printCentered(12, "Updating PIN...")
    rednet.send(bankServerId, {
        type = "change_pin",
        user = username,
        old_pin_hash = old_pin_hash,
        new_pin_hash = new_pin1
    }, BANK_PROTOCOL)

    local _, response = rednet.receive(BANK_PROTOCOL, 10)
    if response and response.success then
        showMessage("Success", "PIN updated successfully.")
    else
        showMessage("Error", (response and response.reason) or "Update failed.", true)
    end
end

local function setupPin()
    drawFrame("PIN Setup Required")
    printCenteredWrapped(6, "This card is new. Please set a 6-digit PIN.")
    sleep(2)

    local pin1 = readPin("Set New 6-Digit PIN")
    if not pin1 then return false end

    local pin2 = readPin("Confirm 6-Digit PIN")
    if not pin2 then return false end

    if pin1 ~= pin2 then
        showMessage("Error", "PINs do not match. Restarting setup.", true)
        return setupPin()
    end

    printCentered(12, "Registering PIN...")
    rednet.send(bankServerId, {
        type = "set_pin",
        user = username,
        pin_hash = pin1
    }, BANK_PROTOCOL)

    local _, response = rednet.receive(BANK_PROTOCOL, 10)
    if response and response.success then
        showMessage("Success", "PIN set successfully. You can now log in.")
        return true
    else
        showMessage("Error", (response and response.reason) or "Registration failed.", true)
        return false
    end
end

local function mainMenu()
    local drive = peripheral.find("drive")
    while true do
        local options = { "Check Balance / Rates", "Deposit Items", "Withdraw Items", "Transfer Funds", "Change PIN", "Exit" }
        local choice = drawMenu("ATM Main Menu", options, "Welcome, " .. username .. " | Balance: $" .. balance)

        if not choice or choice == 6 then break end
        
        if choice == 1 then
            drawFrame("Current Exchange Rates")
            local w,h = term.getSize()
            
            -- THE FIX: Create a two-column layout
            local itemColWidth = math.floor((w - 6) * 0.7)
            local rateColWidth = w - 6 - itemColWidth
            
            term.setCursorPos(3, 4)
            term.setTextColor(colors.yellow)
            term.write(string.format("%-"..itemColWidth.."s %"..rateColWidth.."s", " Item", "Value "))
            term.setCursorPos(3, 5)
            term.write(string.rep("-", w - 4))
            term.setTextColor(colors.white)

            local y = 6
            for name, data in pairs(currencyRates) do
                local clean_name = name:gsub("minecraft:", ""):gsub("_", " ")
                -- Truncate name if it's too long for the column
                if #clean_name > itemColWidth - 1 then
                    clean_name = clean_name:sub(1, itemColWidth - 4) .. "..."
                end
                
                local rate = "$" .. data.current
                
                term.setCursorPos(3, y)
                term.write(string.format(" %-"..itemColWidth-1 .."s %"..rateColWidth.."s", clean_name, rate))
                y = y + 1
            end
            
            printCenteredWrapped(h - 2, "Press any key to return...")
            os.pullEvent("key")
        elseif choice == 2 then deposit()
        elseif choice == 3 then withdraw()
        elseif choice == 4 then transferFunds()
        elseif choice == 5 then changePin()
        end
    end

    drive.ejectDisk()
    rednet.close(peripheral.getName(peripheral.find("modem")))
    drawFrame("Goodbye")
    printCenteredWrapped(8, "Thank you for banking with Drunken Beard Bank!")
    sleep(2)
end

local function runSession()
    local modem = peripheral.find("modem")
    if not modem then error("No modem attached.", 0) end
    rednet.open(peripheral.getName(modem))

    -- THE FIX: Load the paired turtle ID from the config file.
    if not fs.exists("/" .. CONFIG_PATH) then
        error("Configuration not found. Please run the installer disk.", 0)
    end
    
    local file = fs.open("/" .. CONFIG_PATH, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()
    
    if not data or not data.turtleClerkId then
        fs.delete(CONFIG_PATH)
        error("Configuration file is corrupt. Deleting and restarting.", 0)
    end
    
    turtleClerkId = data.turtleClerkId
    
    -- The ATM no longer looks up the turtle, it knows its private ID.
    bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server")
    if not bankServerId then error("Could not find bank server.", 0) end
    
    drawFrame("Welcome")
    -- THE FIX: Use the new word-wrapping function.
    printCenteredWrapped(8, "Welcome to Drunken Beard Bank")
    printCenteredWrapped(10, "Please insert your bank card...")

    local drive = peripheral.find("drive")
    if not drive then error("No Disk Drive is attached to this terminal.", 0) end
    
    local event, p1 = os.pullEvent("disk")
    local disk_label = disk.getLabel(p1)
    if not disk_label or not disk_label:match("^DrunkenBeard_Card_.+") then
        showMessage("Card Error", "This is not a valid Drunken Beard Bank card.", true)
        disk.eject(p1)
        return
    end
    username = disk_label:match("^DrunkenBeard_Card_(.+)")
    local handle = fs.open(disk.getMountPath(p1) .. "/.card_data", "r")
    if not handle then
        showMessage("Card Error", "Card is missing its data file.", true)
        disk.eject(p1)
        return
    end
    local card_contents = handle.readAll()
    handle.close()
    local ok, data = pcall(textutils.unserialize, card_contents)
    if not ok or not data then
        showMessage("Card Error", "Card data is corrupt.", true)
        disk.eject(p1)
        return
    end
    card_data = data
    if login() then
        mainMenu()
    else
        disk.eject(p1)
        drawFrame("Login Failed")
        printCentered(8, "Card ejected.")
        sleep(2)
    end
end

--==============================================================================
-- Main Program Loop (Unchanged)
--==============================================================================

while true do
    local ok, err = pcall(runSession)
    if not ok then
        local file = fs.open("atm_crash.log", "a")
        if file then
            file.writeLine(os.date() .. " - FATAL ERROR: " .. tostring(err))
            file.close()
        end
        drawFrame("FATAL ERROR")
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.setCursorPos(2, 4); print("A fatal error occurred. The ATM will now reboot.")
        term.setCursorPos(2, 6); print(tostring(err))
        sleep(5)
        os.reboot()
    end
end
