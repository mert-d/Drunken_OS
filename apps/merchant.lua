--[[
    Drunken OS - Merchant Applet
    Modularized from drunken_os_apps.lua
]]

local merchant = {}
local appVersion = 1.1
local MERCHANT_CATALOG_FILE = "merchant_catalog.json"
local MERCHANT_TURTLE_ID_FILE = "merchant_turtle.id"
local MERCHANT_BROADCAST_PROTOCOL = "DB_Shop_Broadcast"

local function getParent(context)
    return context.parent
end

local function loadCatalog(context)
    local path = fs.combine(context.programDir, MERCHANT_CATALOG_FILE)
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local data = textutils.unserialize(f.readAll()); f.close()
        return data or {}
    end
    return {}
end

local function saveCatalog(context, catalog)
    local path = fs.combine(context.programDir, MERCHANT_CATALOG_FILE)
    local f = fs.open(path, "w"); f.write(textutils.serialize(catalog)); f.close()
end

function merchant.cashier(context)
    local catalog = loadCatalog(context)
    local broadcasting = false
    local turtleId = nil
    if fs.exists(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE)) then
        local f = fs.open(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE), "r")
        turtleId = tonumber(f.readAll()); f.close()
    end

    while true do
        context.drawWindow("Merchant Cashier")
        local options = {"Toggle Shop: " .. (broadcasting and "ON" or "OFF"), "Edit Catalog", "Link Turtle", "Exit"}
        local selected = 1
        while true do
            context.drawWindow("Merchant Cashier")
            context.drawMenu(options, selected, 2, 4)
            local event, key = os.pullEvent("key")
            if key == keys.up then selected = (selected == 1) and #options or selected - 1
            elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
            elseif key == keys.enter then break
            elseif key == keys.tab then return end
        end

        if selected == 1 then
            broadcasting = not broadcasting
            if broadcasting then
                logActivity("Shop '" .. getParent(context).nickname .. "' opened.")
                parallel.waitForAny(function()
                    while broadcasting do
                        rednet.broadcast({ type = "shop_heartbeat", name = getParent(context).nickname .. "'s Shop" }, MERCHANT_BROADCAST_PROTOCOL)
                        sleep(5)
                    end
                end, function()
                    while broadcasting do
                        local _, msg = rednet.receive("DB_Merchant_Recv")
                        if msg and msg.type == "payment_proof" then
                            context.showMessage("SALE", string.format("Received $%d from %s", msg.amount, msg.from))
                        end
                    end
                end)
            end
        elseif selected == 2 then
            -- Simple catalog editor placeholder
            context.showMessage("Catalog", "Feature coming in next update.")
        elseif selected == 3 then
            context.drawWindow("Link Turtle")
            local id = tonumber(context.readInput("Turtle ID: ", 4))
            if id then
                turtleId = id
                local f = fs.open(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE), "w")
                f.write(tostring(id)); f.close()
                context.showMessage("Linked", "Turtle linked: " .. id)
            end
        elseif selected == 4 then break end
    end
end

function merchant.pos(context)
    local catalog = loadCatalog(context)
    local bill = {} -- { {name, price, count}, ... }
    local total = 0
    
    while true do
        context.drawWindow("Merchant POS | Total: $" .. total)
        local options = {"Add Item", "Clear Bill", "Checkout (Show Total)", "Exit"}
        
        -- Display current bill summary
        local y = 6
        for _, item in ipairs(bill) do
            if y > 15 then break end
            term.setCursorPos(2, y)
            term.write(string.format("%dx %s ($%d)", item.count, item.name, item.price * item.count))
            y = y + 1
        end

        local selected = context.drawMenu(options, 1, 2, nill) -- Using nil for y to let it auto-place or modify drawMenu? 
        -- Actually drawMenu usage in existing files usually takes (options, selected, x, y). 
        -- Let's stick to the pattern used in cashier:
        -- context.drawMenu(options, selected, 2, 4)
        
        -- Since drawMenu is blocking in `drunken_os_apps` usually, but here the loop handles keys?
        -- Wait, look at `cashier` function nearby. It has its OWN loop for keys.
        -- context.drawMenu likely just RENDERS.
        -- Re-reading `cashier` code (Steps 1166):
        -- while true do drawWindow; drawMenu; pullEvent end.
        
        -- So I need to replicate that loop here interactively.
        -- Simpler approach: Use a sub-loop for the menu.
        
        local menuSel = 1
        while true do
            context.drawWindow("Merchant POS | Total: $" .. total)
            -- Draw Bill
            term.setCursorPos(2, 4); term.write("--- Current Bill ---")
            local y = 5
            for _, item in ipairs(bill) do
                if y > 12 then break end
                term.setCursorPos(2, y)
                term.write(string.format("%dx %s", item.count, item.name:sub(1,10)))
                term.setCursorPos(18, y)
                term.write("$" .. (item.price * item.count))
                y = y + 1
            end
            
            context.drawMenu(options, menuSel, 2, 14)
            
            local event, key = os.pullEvent("key")
            if key == keys.up then menuSel = (menuSel == 1) and #options or menuSel - 1
            elseif key == keys.down then menuSel = (menuSel == #options) and 1 or menuSel + 1
            elseif key == keys.enter then break
            elseif key == keys.tab then return end
        end
        
        if menuSel == 4 then return end
        
        if menuSel == 1 then
            -- Add Item
            context.drawWindow("Select Item")
            local itemOpts = {}
            for name, price in pairs(catalog) do
                table.insert(itemOpts, name .. " ($" .. price .. ")")
            end
            table.insert(itemOpts, "Custom Item")
            table.insert(itemOpts, "Cancel")
            
            local iSel = 1
            -- Selection Loop
            local chosenInfo = nil
            if #itemOpts > 2 then
                while true do
                    context.drawWindow("Add Item")
                    context.drawMenu(itemOpts, iSel, 2, 4)
                    local _, k = os.pullEvent("key")
                    if k==keys.up  then iSel=(iSel==1) and #itemOpts or iSel-1
                    elseif k==keys.down then iSel=(iSel==#itemOpts) and 1 or iSel+1
                    elseif k==keys.enter then break end
                end
            end
            
            local choiceName = itemOpts[iSel]
            if choiceName == "Cancel" then
                -- do nothing
            elseif choiceName == "Custom Item" then
                local name = context.readInput("Item Name: ", 4)
                local price = tonumber(context.readInput("Price: $", 6))
                if name and price then
                    chosenInfo = {name=name, price=price}
                end
            else
                -- Parse "Name ($Price)"
                local name = choiceName:match("^(.-)%s%(%$%d+%)$")
                local price = catalog[name]
                if name and price then chosenInfo = {name=name, price=price} end
            end
            
            if chosenInfo then
                local qty = tonumber(context.readInput("Quantity: ", 10) or "1") or 1
                table.insert(bill, {name=chosenInfo.name, price=chosenInfo.price, count=qty})
                total = total + (chosenInfo.price * qty)
            end
            
        elseif menuSel == 2 then
            bill = {}
            total = 0
            
        elseif menuSel == 3 then
            -- Checkout
            context.drawWindow("Checkout | Total: $" .. total)
            term.setCursorPos(2, 6); term.write("Waiting for payment...")
            term.setCursorPos(2, 8); term.write("Ask customer to use")
            term.setCursorPos(2, 9); term.write("'Pay Merchant'")
            term.setCursorPos(2, 10); term.write("on their Bank App.")
            term.setCursorPos(2, 13); term.write("Press Q to Cancel")
            
            -- Ideally here we broadcast an invoice to nearby phones?
            -- context.broadcastInvoice(bill, total) 
            
            while true do
                local e, p1, p2 = os.pullEvent()
                if e == "key" and p1 == keys.q then break end
                if e == "rednet_message" then
                    local sender, msg, proto = p1, p2, p3
                    if proto == "DB_Merchant_Recv" and msg.type == "payment_proof" then
                        if msg.amount >= total then
                            context.showMessage("PAID!", "Payment received from " .. msg.from)
                            bill = {}
                            total = 0
                            break
                        end
                    end
                end
            end
        end
    end
end

function merchant.run(context)
    merchant.cashier(context)
end

return merchant
