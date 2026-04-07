--[[
    Drunken Bites - Client Ordering App (v1.0)
    Modular applet for Drunken OS. Discovers restaurant via protocol,
    fetches menu, builds cart, submits order with session_token auth.
]]

local bites = {}
bites._VERSION = 1.0
local PROTOCOL = "Drunken_Restaurant_v1"

local function getParent(ctx) return ctx.parent end

--- Discover server and fetch menu.
local function fetchMenu(ctx)
    ctx.drawWindow("Connecting...")
    term.setCursorPos(2, 4); term.write("Locating restaurant...")
    local sid = nil
    for i = 1, 3 do
        sid = rednet.lookup(PROTOCOL, "restaurant.server")
        if sid then break end; sleep(1)
    end
    if not sid then ctx.showMessage("Error", "No restaurant found."); return nil end

    term.setCursorPos(2, 6); term.write("Fetching menu...")
    rednet.send(sid, { type = "get_menu" }, PROTOCOL)
    local _, resp = rednet.receive(PROTOCOL, 10)
    if not resp or resp.type ~= "menu_response" then
        ctx.showMessage("Error", "Restaurant did not respond."); return nil
    end
    return sid, resp.menu, resp.restaurant_name, resp.tables or 4
end

--- Main entry point.
function bites.run(ctx)
    local sid, menu, restName, tblCount = fetchMenu(ctx)
    if not sid then return end

    -- Parse menu into display lines
    local lines, selMap = {}, {}
    for _, e in ipairs(menu) do
        if e.type == "category" then
            table.insert(lines, { text = "--- " .. e.name .. " ---", isCat = true })
        elseif e.type == "item" then
            table.insert(lines, {
                text = string.format("  %-16s $%d", e.name:sub(1,16), e.price),
                isCat = false, id = e.id, name = e.name, price = e.price,
            })
        end
    end
    if #lines == 0 then ctx.showMessage("Empty", "No items available."); return end

    -- Cart
    local cart, cartTotal = {}, 0
    local sel, scroll = 1, 0
    for i, l in ipairs(lines) do if not l.isCat then sel = i; break end end

    local function cartQty(id)
        for _, c in ipairs(cart) do if c.id == id then return c.qty end end; return 0
    end
    local function addItem(item)
        for _, c in ipairs(cart) do
            if c.id == item.id then c.qty = c.qty + 1; cartTotal = cartTotal + item.price; return end
        end
        table.insert(cart, { id = item.id, name = item.name, price = item.price, qty = 1 })
        cartTotal = cartTotal + item.price
    end
    local function removeItem(id)
        for i, c in ipairs(cart) do
            if c.id == id then
                c.qty = c.qty - 1; cartTotal = cartTotal - c.price
                if c.qty <= 0 then table.remove(cart, i) end; return
            end
        end
    end

    -- Menu browsing loop
    while true do
        local w, h = ctx.getSafeSize()
        ctx.drawWindow(restName or "Drunken Bites")

        -- Cart summary bar
        term.setBackgroundColor(ctx.theme.highlightBg or colors.cyan)
        term.setTextColor(ctx.theme.highlightText or colors.black)
        term.setCursorPos(1, 2)
        local cs = string.format(" Cart: %d items | Total: $%d ", #cart, cartTotal)
        term.write(cs .. string.rep(" ", math.max(0, w - #cs)))
        term.setBackgroundColor(ctx.theme.bg or colors.black)
        term.setTextColor(ctx.theme.text or colors.white)

        -- Scrollable menu
        local mStart, mEnd = 3, h - 3
        local vis = mEnd - mStart + 1
        if sel - scroll > vis then scroll = sel - vis end
        if sel - scroll < 1 then scroll = sel - 1 end

        for i = 1, vis do
            local idx = i + scroll
            local y = mStart + i - 1
            term.setCursorPos(1, y)
            if idx <= #lines then
                local ln = lines[idx]
                if ln.isCat then
                    term.setTextColor(ctx.theme.prompt or colors.yellow)
                    term.setCursorPos(2, y); term.write(ln.text:sub(1, w-2))
                else
                    if idx == sel then
                        term.setBackgroundColor(ctx.theme.highlightBg or colors.cyan)
                        term.setTextColor(ctx.theme.highlightText or colors.black)
                        term.write(string.rep(" ", w)); term.setCursorPos(1, y)
                    else
                        term.setBackgroundColor(ctx.theme.bg or colors.black)
                        term.setTextColor(ctx.theme.text or colors.white)
                    end
                    term.setCursorPos(2, y); term.write(ln.text:sub(1, w-6))
                    local q = cartQty(ln.id)
                    if q > 0 then
                        term.setCursorPos(w - 3, y)
                        term.setTextColor(colors.lime); term.write("x"..q)
                    end
                    term.setBackgroundColor(ctx.theme.bg or colors.black)
                    term.setTextColor(ctx.theme.text or colors.white)
                end
            end
        end

        -- Controls
        term.setCursorPos(1, h-1); term.setTextColor(ctx.theme.prompt or colors.yellow)
        term.write(" [Enter]Add [-]Remove [C]Checkout")
        term.setCursorPos(1, h); term.setTextColor(colors.gray)
        term.write(" [Q] Cancel")
        term.setTextColor(ctx.theme.text or colors.white)

        local _, key = os.pullEvent("key")
        if key == keys.up then
            repeat sel = sel - 1; if sel < 1 then sel = #lines end
            until not lines[sel].isCat
        elseif key == keys.down then
            repeat sel = sel + 1; if sel > #lines then sel = 1 end
            until not lines[sel].isCat
        elseif key == keys.enter or key == keys.right then
            local it = lines[sel]
            if it and not it.isCat then addItem(it) end
        elseif key == keys.minus or key == keys.numPadSubtract then
            local it = lines[sel]
            if it and not it.isCat then removeItem(it.id) end
        elseif key == keys.c then
            if #cart == 0 then ctx.showMessage("Empty Cart", "Add items first.")
            else break end
        elseif key == keys.q or key == keys.tab then return end
    end

    -- === Checkout ===
    ctx.drawWindow("Checkout | Total: $" .. cartTotal)
    local w, h = ctx.getSafeSize()
    term.setCursorPos(2, 3); term.setTextColor(ctx.theme.prompt or colors.yellow)
    term.write("Your Order:"); term.setTextColor(ctx.theme.text or colors.white)
    local y = 4
    for _, ci in ipairs(cart) do
        if y > h - 6 then break end
        term.setCursorPos(3, y)
        term.write(string.format("%dx %s  $%d", ci.qty, ci.name:sub(1,14), ci.price * ci.qty))
        y = y + 1
    end
    term.setCursorPos(2, y+1); term.setTextColor(ctx.theme.prompt or colors.yellow)
    term.write("TOTAL: $" .. cartTotal)
    term.setTextColor(ctx.theme.text or colors.white)

    local tblNum = tonumber(ctx.readInput("Deliver to Table #: ", y + 3))
    if not tblNum then ctx.showMessage("Cancelled", "Order cancelled."); return end

    ctx.drawWindow("Confirm Order?")
    term.setCursorPos(2, 4); term.write(string.format("Total: $%d | Table: %d", cartTotal, tblNum))
    term.setCursorPos(2, 6); term.write("[Enter] Pay  |  [Q] Cancel")
    while true do
        local _, k = os.pullEvent("key")
        if k == keys.enter then break
        elseif k == keys.q then ctx.showMessage("Cancelled", "Order cancelled."); return end
    end

    -- === Submit Order ===
    ctx.drawWindow("Placing Order...")
    term.setCursorPos(2, 4); term.write("Sending order...")
    local items = {}
    for _, ci in ipairs(cart) do table.insert(items, { id = ci.id, qty = ci.qty }) end

    rednet.send(sid, {
        type = "place_order", items = items, table_num = tblNum,
        user = getParent(ctx).username, session_token = getParent(ctx).session_token,
    }, PROTOCOL)

    local _, resp = rednet.receive(PROTOCOL, 15)
    if not resp then ctx.showMessage("Error", "Server timed out."); return end
    if resp.type == "order_rejected" then
        ctx.showMessage("Rejected", resp.reason or "Unknown error."); return
    end

    -- Handle intermediate payment status then wait for accepted/rejected
    if resp.type == "order_status" and resp.status == "processing_payment" then
        term.setCursorPos(2, 6); term.write("Processing payment...")
        _, resp = rednet.receive(PROTOCOL, 15)
        if not resp then ctx.showMessage("Error", "Lost connection."); return end
        if resp.type == "order_rejected" then
            ctx.showMessage("Payment Failed", resp.reason or "Failed."); return
        end
    end

    if resp.type ~= "order_accepted" then
        ctx.showMessage("Error", "Unexpected response from server."); return
    end

    -- === Order Tracking ===
    local orderId = resp.order_id
    ctx.drawWindow("Order Placed!")
    term.setCursorPos(2, 4); term.setTextColor(colors.lime)
    term.write("Confirmed! ID: " .. orderId)
    term.setTextColor(ctx.theme.text or colors.white)
    term.setCursorPos(2, 6); term.write("Preparing your food...")
    term.setCursorPos(2, h-1); term.setTextColor(colors.gray)
    term.write("[Q] Close (order continues)")

    while true do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "rednet_message" then
            local msg, proto = p2, p3
            if proto == PROTOCOL and type(msg) == "table" and msg.order_id == orderId then
                if msg.type == "order_status" then
                    ctx.drawWindow("Order " .. orderId)
                    term.setCursorPos(2, 4)
                    if msg.status == "ready_for_delivery" then
                        term.setTextColor(colors.orange)
                        term.write("Food ready! Waiter incoming...")
                    elseif msg.status == "delivered" then
                        term.setTextColor(colors.lime)
                        term.write("Delivered! Enjoy your meal!")
                        if msg.message then
                            term.setCursorPos(2, 6)
                            term.setTextColor(ctx.theme.text or colors.white)
                            term.write(msg.message)
                        end
                        term.setCursorPos(2, h-1); term.setTextColor(colors.gray)
                        term.write("Press any key..."); os.pullEvent("key"); return
                    else
                        term.setTextColor(ctx.theme.text or colors.white)
                        term.write("Status: " .. (msg.status or "..."))
                    end
                    term.setTextColor(ctx.theme.text or colors.white)
                    term.setCursorPos(2, h-1); term.setTextColor(colors.gray)
                    term.write("[Q] Close (order continues)")
                elseif msg.type == "order_cancelled" then
                    ctx.showMessage("Cancelled", msg.reason or "Order cancelled. Refund issued.")
                    return
                end
            end
        elseif ev == "key" and p1 == keys.q then return end
    end
end

return bites
