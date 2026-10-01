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
    return (context and context.parent) or context or {}
end

local function logActivity(msg)
    -- Safe stub for activity tracking
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

---
-- Runs the persistent merchant broadcast loop for a cashier terminal.
-- Constantly pings its location on rednet for local POS or shoppers.
-- @param context table: OS app context.
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
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                local key = p1
                if key == keys.up then selected = (selected == 1) and #options or selected - 1
                elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
                elseif key == keys.enter then break
                elseif key == keys.tab or key == keys.q then return end
            elseif event == "mouse_scroll" then
                local dir = p1
                if dir < 0 then selected = (selected == 1) and #options or selected - 1
                else selected = (selected == #options) and 1 or selected + 1 end
            elseif event == "mouse_click" then
                local btn, cx, cy = p1, p2, p3
                local clickedIdx = cy - 4 + 1
                if clickedIdx >= 1 and clickedIdx <= #options then
                    selected = clickedIdx
                    break
                elseif cy == 1 and cx >= 20 then
                    return
                end
            end
        end

        if selected == 1 then
            broadcasting = not broadcasting
            if broadcasting then
                local shopOwner = getParent(context).nickname or getParent(context).username or "Merchant"
                logActivity("Shop '" .. shopOwner .. "' opened.")
                context.drawWindow("Shop Open")
                if context.drawText then
                    context.drawText("Broadcasting...", 2, 4)
                    context.drawText("Press Q or Enter to Close", 2, 6)
                else
                    term.setCursorPos(2, 4); term.write("Broadcasting...")
                    term.setCursorPos(2, 6); term.write("Press Q or Enter to Close")
                end
                parallel.waitForAny(
                    function()
                        while broadcasting do
                            rednet.broadcast({ type = "shop_heartbeat", name = shopOwner .. "'s Shop" }, MERCHANT_BROADCAST_PROTOCOL)
                            sleep(5)
                        end
                    end,
                    function()
                        while broadcasting do
                            local _, msg = rednet.receive("DB_Merchant_Recv", 1)
                            if msg and msg.type == "payment_proof" then
                                context.showMessage("SALE", string.format("Received $%d from %s", msg.amount or 0, msg.from or "unknown"))
                                context.drawWindow("Shop Open")
                                if context.drawText then
                                    context.drawText("Broadcasting...", 2, 4)
                                    context.drawText("Press Q or Enter to Close", 2, 6)
                                else
                                    term.setCursorPos(2, 4); term.write("Broadcasting...")
                                    term.setCursorPos(2, 6); term.write("Press Q or Enter to Close")
                                end
                            end
                        end
                    end,
                    function()
                        while broadcasting do
                            local event, p1 = os.pullEvent()
                            if event == "key" and (p1 == keys.q or p1 == keys.enter or p1 == keys.backspace) then
                                broadcasting = false
                                break
                            elseif event == "mouse_click" then
                                broadcasting = false
                                break
                            end
                        end
                    end
                )
                logActivity("Shop closed.")
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

---
-- Interactive Point Of Sale terminal logic.
-- Allows shop owners to compile a bill, and wait for confirmation of bank payment.
-- @param context table: OS app context.
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
            
            local event, p1, p2, p3 = os.pullEvent()
            if event == "key" then
                local key = p1
                if key == keys.up then menuSel = (menuSel == 1) and #options or menuSel - 1
                elseif key == keys.down then menuSel = (menuSel == #options) and 1 or menuSel + 1
                elseif key == keys.enter then break
                elseif key == keys.tab or key == keys.q then return end
            elseif event == "mouse_scroll" then
                local dir = p1
                if dir < 0 then menuSel = (menuSel == 1) and #options or menuSel - 1
                else menuSel = (menuSel == #options) and 1 or menuSel + 1 end
            elseif event == "mouse_click" then
                local btn, cx, cy = p1, p2, p3
                local clickedIdx = cy - 14 + 1
                if clickedIdx >= 1 and clickedIdx <= #options then
                    menuSel = clickedIdx
                    break
                elseif cy == 1 and cx >= 20 then
                    return
                end
            end
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
                    local event, p1, p2, p3 = os.pullEvent()
                    if event == "key" then
                        local k = p1
                        if k == keys.up then iSel = (iSel == 1) and #itemOpts or iSel - 1
                        elseif k == keys.down then iSel = (iSel == #itemOpts) and 1 or iSel + 1
                        elseif k == keys.enter then break
                        elseif k == keys.tab or k == keys.q then iSel = #itemOpts; break end
                    elseif event == "mouse_scroll" then
                        local dir = p1
                        if dir < 0 then iSel = (iSel == 1) and #itemOpts or iSel - 1
                        else iSel = (iSel == #itemOpts) and 1 or iSel + 1 end
                    elseif event == "mouse_click" then
                        local btn, cx, cy = p1, p2, p3
                        local clickedIdx = cy - 4 + 1
                        if clickedIdx >= 1 and clickedIdx <= #itemOpts then
                            iSel = clickedIdx
                            break
                        elseif cy == 1 and cx >= 20 then
                            iSel = #itemOpts
                            break
                        end
                    end
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
            term.setCursorPos(2, 13); term.write("Scan User ID... (Input)")
            term.setCursorPos(2, 14); term.write("Press Q to Cancel")
            
            -- Find Bank Server
            local bankServerId = rednet.lookup("DB_Bank", "bank.server")
            
            local customer = context.readInput("Customer Name: ", 4)
            if not customer or customer == "" then break end
            
            context.drawWindow("Verifying Payment...")
            term.setCursorPos(2,6); term.write("Customer: " .. customer)
            term.setCursorPos(2,7); term.write("Amount: $" .. total)
            term.setCursorPos(2,8); term.write("Checking Bank...")
            
            local verified = false
            while not verified do
                -- Poll Bank every 3 seconds
                if bankServerId then
                   rednet.send(bankServerId, {
                       type = "verify_transaction",
                       merchant = getParent(context).username,
                       customer = customer,
                       amount = total,
                       interval = 60000 -- Look back 60s
                   }, "DB_Bank")
                   local _, resp = rednet.receive("DB_Bank", 3)
                   if resp and resp.success then
                       verified = true
                   end
                end
                
                if verified then break end
                
                term.setCursorPos(2, 10); term.write("Waiting...")
                
                -- Allow Exit
                local e, p1 = os.pullEvent()
                if e == "key" and (p1 == keys.q or p1 == keys.tab) then break
                elseif e == "mouse_click" then break end
            end
            
            if verified then
                context.showMessage("PAID!", "Payment Confirmed!")
                
                -- VENDING LOGIC
                if fs.exists(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE)) then
                     local f = fs.open(fs.combine(context.programDir, MERCHANT_TURTLE_ID_FILE), "r")
                     local tid = tonumber(f.readAll()); f.close()
                     if tid then
                         -- Send dispense command
                         rednet.send(tid, { type="dispense", items=bill }, "DB_Vending_Turtle")
                         context.showMessage("Vending", "Dispensing items...")
                     end
                end
                
                bill = {}
                total = 0
                break
            else
                context.showMessage("Cancelled", "Payment not verified.")
            end
        end
    end
end

---
-- Main Entry Point for Merchant Application. Defaults to cashier interface.
-- @param context table: OS Application context.
function merchant.run(context)
    merchant.cashier(context)
end

return merchant
