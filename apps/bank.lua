--[[
    Drunken OS - Bank Applet
    Modularized from drunken_os_apps.lua
]]

local bank = {}
local BANK_PROTOCOL = "DB_Bank"

local function getParent(context)
    return context.parent
end

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

    local pin_hash = getParent(context).crypto.hex(pin_str)
    
    context.drawWindow("Verifying...")
    rednet.send(bankServerId, { type = "login", user = getParent(context).username, pin_hash = pin_hash }, BANK_PROTOCOL)
    local _, response = rednet.receive(BANK_PROTOCOL, 15)

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

function bank.run(context)
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
            context.showMessage("Balance", "Your current balance is: $" .. balance)
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
                            pin_hash = pin_hash,
                            recipient = recipient,
                            amount = amount
                        }, BANK_PROTOCOL)
                        
                        local _, resp = rednet.receive(BANK_PROTOCOL, 15)
                        if resp and resp.success then
                            balance = resp.newBalance
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

function bank.pay(context)
    local bankServerId, pin_hash, balance = getBankSession(context)
    if not bankServerId then return end

    while true do
        context.drawWindow("Pay Merchant")
        term.setCursorPos(2, 4); term.write("Balance: $" .. balance)
        
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
                -- Need a way to call mail.composeAndSend without it being here?
                -- For now, let's keep it simple or use a core helper if we have one.
                -- Actually, we can just use rednet.send directly.
                local mailObj = {
                    from = getParent(context).username,
                    from_nickname = getParent(context).nickname,
                    to = "MuhendizBey",
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
