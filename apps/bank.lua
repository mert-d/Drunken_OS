--[[
    Drunken OS - Bank Applet
    Modularized from drunken_os_apps.lua
]]

local bank = {}
local appVersion = 1.2
local BANK_PROTOCOL = "DB_Bank"
local ok_sound, Sound = pcall(require, "lib.sound")

local function getParent(context)
    return (context and context.parent) or context or {}
end

---
-- Helper to perform the interactive PIN setup/login flow visually.
-- @param context table: The OS app context.
-- @return number, string, number, table: Returns (BankServerID, PIN Hash, Balance, CurrencyRates) on success.
local function getBankSession(context)
    local bankServerId = nil
    context.drawWindow("Connecting...")
    term.setCursorPos(2, 4); term.write("Locating Bank Server...")
    
    for i = 1, 2 do
        bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server")
        if bankServerId then break end
        sleep(0.5)
    end

    if not bankServerId then
        context.showMessage("Offline", "Bank Server is unreachable.\n(Server chunk may be unloaded).")
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

    local crypto = (context and context.crypto) or (getParent(context) and getParent(context).crypto)
    if not crypto then
        local ok, lib = pcall(require, "lib.sha1_hmac")
        if ok and lib then crypto = lib end
    end
    if not crypto or not crypto.hex then
        context.showMessage("Error", "Crypto module unavailable.")
        return nil, nil
    end

    local pin_hash = crypto.hex(pin_str)
    
    context.drawWindow("Verifying...")
    rednet.send(bankServerId, { type = "login", user = getParent(context).username, pin_hash = pin_hash }, BANK_PROTOCOL)
    local _, response = rednet.receive(BANK_PROTOCOL, 5.0)

    if response and response.success then
        return bankServerId, pin_hash, response.balance, response.rates or {}
    elseif response and response.reason == "setup_required" then
        context.showMessage("Setup Required", "Please visit an ATM to set up your PIN.")
        return nil, nil
    else
        context.showMessage("Offline", (response and response.reason) or "Server didn't respond in time.\n(Chunk may be unloaded).")
        return nil, nil
    end
end

---
-- Main application entry point for the Pocket Bank app.
-- Shows balances, runs transfers, and lists currency values.
-- @param context table: The OS app context.
function bank.run(context)
    local bankServerId, pin_hash, balance, rates = getBankSession(context)
    if not bankServerId then return end

    while true do
        local options = {"Check Balance", "View Rates", "Transfer Funds", "Exit"}
        local selected = 1
        
        while true do
            context.drawWindow("Pocket Bank | $" .. balance)
            context.drawMenu(options, selected, 2, 4)
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                local key = p1
                if key == keys.up then selected = (selected == 1) and #options or selected - 1
                elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
                elseif key == keys.enter then break
                elseif key == keys.tab or key == keys.q then return end
            elseif event == "mouse_click" then
                local btn, clickX, clickY = p1, p2, p3
                local clickedIdx = clickY - 4 + 1
                if clickedIdx >= 1 and clickedIdx <= #options then
                    selected = clickedIdx
                    break
                end
            elseif event == "mouse_scroll" then
                local dir = p1
                if dir < 0 then selected = (selected == 1) and #options or selected - 1
                else selected = (selected == #options) and 1 or selected + 1 end
            end
        end
        
        if selected == 4 then return end
        
        if selected == 1 then
            context.showMessage("Balance", "Your current balance is: $" .. balance)
        elseif selected == 2 then
            context.drawWindow("Exchange Rates")
            local w, h = context.getSafeSize()
            local y = 4
            local sortedRates = {}
            for name, data in pairs(rates) do
                table.insert(sortedRates, { name = name, data = data })
            end
            table.sort(sortedRates, function(a, b) return a.name < b.name end)
            
            for _, entry in ipairs(sortedRates) do
                if y > h - 2 then break end
                term.setCursorPos(2, y)
                local clean = entry.name:gsub("minecraft:", ""):gsub("_", " ")
                local val = (type(entry.data) == "table" and (entry.data.current or entry.data.price)) or tonumber(entry.data) or 0
                term.write(string.format("%s: $%d", clean:sub(1,15), val))
                y = y + 1
            end
            term.setCursorPos(2, h-1); term.setTextColor(context.theme.prompt); term.write("Press any key...")
            os.pullEvent()
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
                            pin_hash = pin_hash,
                            recipient = recipient,
                            amount = amount
                        }, BANK_PROTOCOL)
                        
                        local _, resp = rednet.receive(BANK_PROTOCOL, 15)
                        if resp and resp.success then
                            balance = resp.newBalance
                            if ok_sound and Sound and Sound.playCoin then pcall(Sound.playCoin) end
                            context.showMessage("Success", "Sent $" .. amount .. " to " .. recipient)
                        else
                            context.showMessage("Failed", (resp and (resp.reason or "Transfer failed")) or "Connection timeout.")
                        end
                    else
                        context.showMessage("Error", "Insufficient funds.")
                    end
                end
            end
        end
    end
end

---
-- External entry point for merchant checkouts.
-- Activated contextually by POS terminals detecting nearby merchants.
-- @param context table: The OS app context.
function bank.pay(context)
    local bankServerId, pin_hash, balance = getBankSession(context)
    if not bankServerId then return end

    while true do
        context.drawWindow("Pay Merchant")
        term.setCursorPos(2, 4); term.write("Balance: $" .. balance)
        
        local shop = getParent(context).nearbyShop
        if shop then
             term.setCursorPos(2, 6); term.setTextColor(context.theme.successText or colors.green)
             term.write("Nearby: " .. shop.name)
             term.setTextColor(context.theme.text)
        else
             term.setCursorPos(2, 6); term.setTextColor(context.theme.mutedText or colors.gray)
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
                term.setCursorPos(2, 6); term.setTextColor(context.theme.successText or colors.green)
                term.write("Nearby: " .. shop.name)
                term.setTextColor(context.theme.text)
            end
            context.drawMenu(options, selected, 2, 8)
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                local key = p1
                if key == keys.up then selected = (selected == 1) and #options or selected - 1
                elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
                elseif key == keys.enter then break
                elseif key == keys.tab or key == keys.q then return end
            elseif event == "mouse_click" then
                local btn, clickX, clickY = p1, p2, p3
                local clickedIdx = clickY - 8 + 1
                if clickedIdx >= 1 and clickedIdx <= #options then
                    selected = clickedIdx
                    break
                end
            elseif event == "mouse_scroll" then
                local dir = p1
                if dir < 0 then selected = (selected == 1) and #options or selected - 1
                else selected = (selected == #options) and 1 or selected + 1 end
            end
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
                local mailObj = {
                    from = getParent(context).username,
                    from_nickname = getParent(context).nickname,
                    to = "@all", -- Reports sent as broadcast/all admins or use a list
                    subject = "REPORT: " .. userToReport,
                    body = reason,
                    timestamp = os.time()
                }
                rednet.send(getParent(context).mailServerId, { type = "send", mail = mailObj }, "SimpleMail")
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

                local _, resp = rednet.receive(BANK_PROTOCOL, 15)
                if resp and resp.success then
                    balance = resp.newBalance
                    if ok_sound and Sound and Sound.playCoin then pcall(Sound.playCoin) end
                    context.showMessage("Success", "Paid $" .. amount .. " to " .. recipient)
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

return bank
