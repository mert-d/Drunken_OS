--[[
    Drunken OS - Restaurant Queue Manager (v1.0)
    by MuhendizBey

    Purpose:
    The brain of the Restaurant Automation System. Manages order intake,
    payment processing via Drunken Bank, recipe resolution, and task
    dispatch to Chef and Waiter Turtles.

    Architecture:
    - Non-blocking event loop using parallel.waitForAny()
    - File-based recipe database (recipes.json) for hot-reload
    - Session-token based payment via Bank Server's restaurant_charge handler
    - Crisis management with automatic refunds and alerts
]]

--==============================================================================
-- API & Library Initialization
--==============================================================================

local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path
local DB = require("lib.db")
local sharedTheme = require("lib.theme")
local utils = require("lib.utils")

--==============================================================================
-- Configuration & Constants
--==============================================================================

local RESTAURANT_PROTOCOL    = "Drunken_Restaurant_v1"
local CHEF_PROTOCOL          = "Drunken_Chef_v1"
local WAITER_PROTOCOL        = "Drunken_Waiter_v1"
local BANK_PROTOCOL          = "DB_Bank"
local ALERT_PROTOCOL         = "Drunken_Restaurant_Alert"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"

local CONFIG_FILE  = "restaurant.conf"
local RECIPES_FILE = "recipes.json"
local LOG_FILE     = "logs/restaurant.log"

-- Order states
local STATE = {
    PENDING_PAYMENT = "PENDING_PAYMENT",
    PAID            = "PAID",
    COOKING         = "COOKING",
    READY           = "READY",
    DELIVERING      = "DELIVERING",
    COMPLETE        = "COMPLETE",
    CANCELLED       = "CANCELLED",
}

--==============================================================================
-- Runtime State
--==============================================================================

local config = {}          -- Loaded from restaurant.conf
local recipes = {}         -- Loaded from recipes.json (hot-reload capable)
local orderQueue = {}      -- Active orders: { [order_id] = order }
local nextOrderId = 1
local bankServerId = nil
local chefBusy = false
local waiterBusy = false
local logHistory = {}
local logWriteIdx = 0
local LOG_MAX = 150
local uiDirty = true
local startupComplete = false

--==============================================================================
-- UI & Theme
--==============================================================================

local safeColor = sharedTheme.safeColor
local theme = {
    bg           = safeColor("black", colors.black),
    text         = safeColor("white", colors.white),
    title        = safeColor("orange", colors.yellow),
    titleBg      = safeColor("brown", colors.gray),
    titleText    = safeColor("white", colors.white),
    prompt       = safeColor("yellow", colors.yellow),
    statusBarBg  = safeColor("gray", colors.lightGray),
    statusBarText= safeColor("white", colors.white),
    success      = safeColor("lime", colors.white),
    error        = safeColor("red", colors.red),
    orderNew     = safeColor("lime", colors.white),
    orderCook    = safeColor("orange", colors.yellow),
    orderDone    = safeColor("cyan", colors.white),
}

--==============================================================================
-- Logging
--==============================================================================

local logBuffer = {}

local function logActivity(message, isError)
    local prefix = isError and "[ERROR] " or "[INFO] "
    local logEntry = os.date("[%H:%M:%S] ") .. prefix .. message

    if not startupComplete then
        print(logEntry)
    end

    logWriteIdx = logWriteIdx + 1
    logHistory[logWriteIdx] = logEntry
    if logWriteIdx > LOG_MAX then
        local newHistory = {}
        for i = LOG_MAX - 49, LOG_MAX do
            table.insert(newHistory, logHistory[i])
        end
        logHistory = newHistory
        logWriteIdx = #logHistory
    end

    table.insert(logBuffer, logEntry)
    uiDirty = true
end

local function flushLogs()
    if #logBuffer == 0 then return end
    if not fs.exists("logs") then fs.makeDir("logs") end
    local file = fs.open(LOG_FILE, "a")
    if file then
        for _, entry in ipairs(logBuffer) do
            file.writeLine(entry)
        end
        file.close()
    end
    logBuffer = {}
end

--==============================================================================
-- Data Loading
--==============================================================================

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        -- Generate default config
        local defaultConfig = {
            restaurant_name = "Drunken Bites Tavern",
            owner_username  = "admin",
            owner_computer_id = os.getComputerID(),
            chef_turtle_id  = nil,
            waiter_turtle_id = nil,
            -- Table coordinate map: table_number -> {x, y, z}
            tables = {
                [1] = { x = 100, y = 65, z = 200 },
                [2] = { x = 104, y = 65, z = 200 },
                [3] = { x = 108, y = 65, z = 200 },
                [4] = { x = 112, y = 65, z = 200 },
            },
            -- Waiter base station coords
            waiter_base = { x = 100, y = 65, z = 195 },
            -- Waiter pickup depot coords
            waiter_pickup = { x = 98, y = 65, z = 195 },
        }
        local f = fs.open(CONFIG_FILE, "w")
        f.write(textutils.serialize(defaultConfig))
        f.close()
        logActivity("Generated default restaurant.conf. Please edit and restart.")
        return defaultConfig
    end

    local f = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data or {}
end

local function loadRecipes()
    if not fs.exists(RECIPES_FILE) then
        -- Generate a sample recipe database
        local sampleRecipes = {
            -- Category: Mains
            {
                id = "steak_dinner",
                name = "Grilled Steak",
                category = "Mains",
                price = 25,
                ingredients = {
                    { name = "minecraft:cooked_beef", count = 2 },
                    { name = "minecraft:baked_potato", count = 1 },
                },
            },
            {
                id = "chicken_plate",
                name = "Roast Chicken",
                category = "Mains",
                price = 18,
                ingredients = {
                    { name = "minecraft:cooked_chicken", count = 2 },
                    { name = "minecraft:bread", count = 1 },
                },
            },
            {
                id = "pork_chop",
                name = "Pork Chop Deluxe",
                category = "Mains",
                price = 20,
                ingredients = {
                    { name = "minecraft:cooked_porkchop", count = 2 },
                    { name = "minecraft:carrot", count = 2 },
                },
            },
            {
                id = "fish_fillet",
                name = "Cod Fillet",
                category = "Mains",
                price = 15,
                ingredients = {
                    { name = "minecraft:cooked_cod", count = 2 },
                    { name = "minecraft:kelp", count = 1 },
                },
            },
            {
                id = "mutton_feast",
                name = "Mutton Feast",
                category = "Mains",
                price = 22,
                ingredients = {
                    { name = "minecraft:cooked_mutton", count = 3 },
                    { name = "minecraft:beetroot", count = 2 },
                },
            },
            -- Category: Sides & Drinks
            {
                id = "bread_basket",
                name = "Bread Basket",
                category = "Sides",
                price = 5,
                ingredients = {
                    { name = "minecraft:bread", count = 3 },
                },
            },
            {
                id = "golden_brew",
                name = "Golden Brew",
                category = "Drinks",
                price = 30,
                ingredients = {
                    { name = "minecraft:golden_apple", count = 1 },
                },
            },
            {
                id = "sweet_pie",
                name = "Pumpkin Pie",
                category = "Desserts",
                price = 12,
                ingredients = {
                    { name = "minecraft:pumpkin_pie", count = 1 },
                },
            },
        }
        DB.saveTableToFileJSON(RECIPES_FILE, sampleRecipes, logActivity)
        logActivity("Generated sample recipes.json with 8 items.")
        return sampleRecipes
    end

    local data = DB.loadTableFromFileJSON(RECIPES_FILE, logActivity)
    if data and #data > 0 then
        logActivity("Loaded " .. #data .. " recipes from recipes.json.")
        return data
    else
        logActivity("WARNING: recipes.json is empty or malformed.", true)
        return {}
    end
end

--- Hot-reload recipes from disk without restarting the server.
local function reloadRecipes()
    recipes = loadRecipes()
    logActivity("Recipes hot-reloaded. " .. #recipes .. " items on menu.")
end

--==============================================================================
-- Order Management
--==============================================================================

local function generateOrderId()
    local id = string.format("ORD-%04d-%d", nextOrderId, os.epoch("utc") % 10000)
    nextOrderId = nextOrderId + 1
    return id
end

local function getRecipeById(recipeId)
    for _, recipe in ipairs(recipes) do
        if recipe.id == recipeId then
            return recipe
        end
    end
    return nil
end

local function calculateOrderTotal(items)
    local total = 0
    for _, item in ipairs(items) do
        local recipe = getRecipeById(item.id)
        if recipe then
            total = total + (recipe.price * (item.qty or 1))
        end
    end
    return total
end

--- Collect all ingredients needed for an order.
local function getOrderIngredients(items)
    local ingredients = {}
    for _, item in ipairs(items) do
        local recipe = getRecipeById(item.id)
        if recipe then
            local qty = item.qty or 1
            for _, ing in ipairs(recipe.ingredients) do
                -- Merge duplicate ingredients
                local found = false
                for _, existing in ipairs(ingredients) do
                    if existing.name == ing.name then
                        existing.count = existing.count + (ing.count * qty)
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(ingredients, {
                        name = ing.name,
                        count = ing.count * qty,
                    })
                end
            end
        end
    end
    return ingredients
end

--==============================================================================
-- Bank Integration
--==============================================================================

local function chargeCustomer(order)
    if not bankServerId then
        bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server")
    end
    if not bankServerId then
        return false, "Bank Server unreachable."
    end

    rednet.send(bankServerId, {
        type = "restaurant_charge",
        customer = order.customer,
        restaurant_owner = config.owner_username,
        amount = order.total,
        order_id = order.id,
        session_token = order.session_token,
    }, BANK_PROTOCOL)

    local _, response = rednet.receive(BANK_PROTOCOL, 10)
    if response and response.success then
        return true
    else
        return false, (response and response.reason) or "No response from Bank."
    end
end

local function refundCustomer(order, reason)
    if not bankServerId then
        bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server")
    end
    if not bankServerId then
        logActivity("CRITICAL: Cannot refund - Bank Server unreachable!", true)
        return false
    end

    rednet.send(bankServerId, {
        type = "restaurant_refund",
        customer = order.customer,
        restaurant_owner = config.owner_username,
        amount = order.total,
        order_id = order.id,
        reason = reason,
    }, BANK_PROTOCOL)

    local _, response = rednet.receive(BANK_PROTOCOL, 10)
    if response and response.success then
        logActivity(string.format("Refunded $%d to '%s' for order %s.", response.refunded, order.customer, order.id))
        return true
    else
        logActivity("CRITICAL: Refund failed for order " .. order.id, true)
        return false
    end
end

--==============================================================================
-- Alert System
--==============================================================================

local function sendAlert(order, alertMsg)
    -- Alert restaurant owner
    if config.owner_computer_id then
        rednet.send(config.owner_computer_id, {
            type = "restaurant_alert",
            order_id = order.id,
            customer = order.customer,
            message = alertMsg,
            timestamp = os.epoch("utc"),
        }, ALERT_PROTOCOL)
    end

    -- Broadcast on alert channel for any monitoring systems
    rednet.broadcast({
        type = "restaurant_alert",
        restaurant = config.restaurant_name,
        order_id = order.id,
        customer = order.customer,
        message = alertMsg,
        timestamp = os.epoch("utc"),
    }, ALERT_PROTOCOL)

    logActivity("ALERT: " .. alertMsg)
end

--==============================================================================
-- Task Dispatch
--==============================================================================

local function dispatchChefOrder(order)
    if not config.chef_turtle_id then
        logActivity("No Chef Turtle configured!", true)
        return false
    end

    local ingredients = getOrderIngredients(order.items)
    logActivity(string.format("Dispatching work order %s to Chef (ID: %d) with %d ingredient types.",
        order.id, config.chef_turtle_id, #ingredients))

    rednet.send(config.chef_turtle_id, {
        type = "work_order",
        order_id = order.id,
        ingredients = ingredients,
    }, CHEF_PROTOCOL)

    order.state = STATE.COOKING
    chefBusy = true
    uiDirty = true
    return true
end

local function dispatchWaiterOrder(order)
    if not config.waiter_turtle_id then
        logActivity("No Waiter Turtle configured!", true)
        return false
    end

    local tableCoords = config.tables[order.table_num]
    if not tableCoords then
        logActivity("Invalid table number: " .. tostring(order.table_num), true)
        return false
    end

    logActivity(string.format("Dispatching delivery order %s to Waiter (ID: %d) for table %d.",
        order.id, config.waiter_turtle_id, order.table_num))

    rednet.send(config.waiter_turtle_id, {
        type = "delivery_order",
        order_id = order.id,
        pickup = config.waiter_pickup,
        table_coords = tableCoords,
        base_coords = config.waiter_base,
    }, WAITER_PROTOCOL)

    order.state = STATE.DELIVERING
    waiterBusy = true
    uiDirty = true
    return true
end

--==============================================================================
-- Network Message Handlers
--==============================================================================

local handlers = {}

--- Client requests the restaurant menu.
function handlers.get_menu(senderId, message)
    -- Hot-reload recipes on every menu request for freshness
    reloadRecipes()

    -- Build categorized menu for the client
    local menu = {}
    local categories = {}
    for _, recipe in ipairs(recipes) do
        local cat = recipe.category or "Other"
        if not categories[cat] then
            categories[cat] = {}
        end
        table.insert(categories[cat], {
            id = recipe.id,
            name = recipe.name,
            price = recipe.price,
            category = cat,
        })
    end

    -- Flatten to ordered list with category headers
    local sortedCats = {}
    for cat, _ in pairs(categories) do table.insert(sortedCats, cat) end
    table.sort(sortedCats)

    for _, cat in ipairs(sortedCats) do
        table.insert(menu, { type = "category", name = cat })
        for _, item in ipairs(categories[cat]) do
            table.insert(menu, { type = "item", id = item.id, name = item.name, price = item.price })
        end
    end

    rednet.send(senderId, {
        type = "menu_response",
        restaurant_name = config.restaurant_name,
        menu = menu,
        tables = config.tables and #config.tables or 4,
    }, RESTAURANT_PROTOCOL)

    logActivity("Sent menu to client ID " .. senderId)
end

--- Client places an order.
function handlers.place_order(senderId, message)
    if not message.items or #message.items == 0 then
        rednet.send(senderId, { type = "order_rejected", reason = "No items in order." }, RESTAURANT_PROTOCOL)
        return
    end
    if not message.table_num then
        rednet.send(senderId, { type = "order_rejected", reason = "No table specified." }, RESTAURANT_PROTOCOL)
        return
    end
    if not message.session_token or not message.user then
        rednet.send(senderId, { type = "order_rejected", reason = "Authentication required." }, RESTAURANT_PROTOCOL)
        return
    end

    -- Validate all items exist in recipe DB
    for _, item in ipairs(message.items) do
        if not getRecipeById(item.id) then
            rednet.send(senderId, { type = "order_rejected", reason = "Item '" .. (item.id or "?") .. "' not on menu." }, RESTAURANT_PROTOCOL)
            return
        end
    end

    -- Validate table number
    local tableNum = tonumber(message.table_num)
    if not tableNum or not config.tables[tableNum] then
        rednet.send(senderId, { type = "order_rejected", reason = "Invalid table number." }, RESTAURANT_PROTOCOL)
        return
    end

    local total = calculateOrderTotal(message.items)

    local order = {
        id = generateOrderId(),
        customer = message.user,
        session_token = message.session_token,
        client_id = senderId,
        items = message.items,
        table_num = tableNum,
        total = total,
        state = STATE.PENDING_PAYMENT,
        created_at = os.epoch("utc"),
    }

    logActivity(string.format("New order %s from '%s': %d items, $%d, table %d.",
        order.id, order.customer, #order.items, order.total, order.table_num))

    -- Attempt payment
    rednet.send(senderId, { type = "order_status", order_id = order.id, status = "processing_payment", total = total }, RESTAURANT_PROTOCOL)

    local paymentOk, paymentErr = chargeCustomer(order)

    if paymentOk then
        order.state = STATE.PAID
        orderQueue[order.id] = order
        logActivity(string.format("Payment confirmed for order %s ($%d).", order.id, order.total))
        rednet.send(senderId, {
            type = "order_accepted",
            order_id = order.id,
            total = order.total,
            status = "paid",
        }, RESTAURANT_PROTOCOL)
        uiDirty = true
    else
        logActivity(string.format("Payment FAILED for order %s: %s", order.id, paymentErr or "Unknown"), true)
        rednet.send(senderId, {
            type = "order_rejected",
            order_id = order.id,
            reason = paymentErr or "Payment failed.",
        }, RESTAURANT_PROTOCOL)
    end
end

--- Chef reports work completion.
function handlers.work_complete(senderId, message)
    if senderId ~= config.chef_turtle_id then return end

    local order_id = message.order_id
    local order = orderQueue[order_id]
    if not order then
        logActivity("Chef reported completion for unknown order: " .. tostring(order_id), true)
        chefBusy = false
        return
    end

    logActivity(string.format("Chef completed order %s. Food ready for delivery!", order_id))
    order.state = STATE.READY
    chefBusy = false
    uiDirty = true

    -- Notify the customer
    rednet.send(order.client_id, {
        type = "order_status",
        order_id = order_id,
        status = "ready_for_delivery",
    }, RESTAURANT_PROTOCOL)
end

--- Chef reports a missing ingredient — trigger crisis management.
function handlers.missing_item(senderId, message)
    if senderId ~= config.chef_turtle_id then return end

    local order_id = message.order_id
    local missing = message.item or "unknown"
    local order = orderQueue[order_id]

    chefBusy = false

    if not order then
        logActivity("Chef reported missing item for unknown order: " .. tostring(order_id), true)
        return
    end

    local alertMsg = string.format("STOCKOUT: '%s' missing for order %s (customer: %s). Auto-refunding.",
        missing, order_id, order.customer)

    logActivity(alertMsg, true)

    -- Issue refund
    refundCustomer(order, "Missing ingredient: " .. missing)

    -- Notify customer
    rednet.send(order.client_id, {
        type = "order_cancelled",
        order_id = order_id,
        reason = "We're sorry! Ingredient '" .. missing .. "' is out of stock. A full refund has been issued.",
    }, RESTAURANT_PROTOCOL)

    -- Alert restaurant owner
    sendAlert(order, alertMsg)

    order.state = STATE.CANCELLED
    uiDirty = true
end

--- Waiter reports delivery completion.
function handlers.delivery_complete(senderId, message)
    if senderId ~= config.waiter_turtle_id then return end

    local order_id = message.order_id
    local order = orderQueue[order_id]

    waiterBusy = false

    if not order then
        logActivity("Waiter reported delivery for unknown order: " .. tostring(order_id), true)
        return
    end

    logActivity(string.format("Order %s delivered to table %d! Customer: %s", order_id, order.table_num, order.customer))
    order.state = STATE.COMPLETE
    uiDirty = true

    -- Notify the customer
    rednet.send(order.client_id, {
        type = "order_status",
        order_id = order_id,
        status = "delivered",
        message = "Your order has been delivered to table " .. order.table_num .. ". Enjoy!",
    }, RESTAURANT_PROTOCOL)
end

--- Chef or waiter pings to confirm pairing.
function handlers.ping(senderId, message)
    rednet.send(senderId, { type = "pong", server_name = config.restaurant_name }, RESTAURANT_PROTOCOL)
    logActivity("Responded to ping from ID " .. senderId)
end

--==============================================================================
-- Main Loops (Non-Blocking)
--==============================================================================

--- Network listener loop — dispatches all incoming rednet messages.
local function networkLoop()
    while true do
        local senderId, message, proto = rednet.receive()
        if type(message) == "table" and message.type then
            if proto == RESTAURANT_PROTOCOL then
                local handler = handlers[message.type]
                if handler then
                    local ok, err = pcall(handler, senderId, message)
                    if not ok then
                        logActivity("Handler error (" .. message.type .. "): " .. tostring(err), true)
                    end
                end
            elseif proto == CHEF_PROTOCOL then
                local handler = handlers[message.type]
                if handler then
                    local ok, err = pcall(handler, senderId, message)
                    if not ok then
                        logActivity("Chef handler error: " .. tostring(err), true)
                    end
                end
            elseif proto == WAITER_PROTOCOL then
                local handler = handlers[message.type]
                if handler then
                    local ok, err = pcall(handler, senderId, message)
                    if not ok then
                        logActivity("Waiter handler error: " .. tostring(err), true)
                    end
                end
            end
        end
    end
end

--- Tick loop — processes the order queue and dispatches work to idle turtles.
local function tickLoop()
    while true do
        sleep(2)

        -- Dispatch PAID orders to Chef if idle
        if not chefBusy then
            for id, order in pairs(orderQueue) do
                if order.state == STATE.PAID then
                    dispatchChefOrder(order)
                    break -- One at a time
                end
            end
        end

        -- Dispatch READY orders to Waiter if idle
        if not waiterBusy then
            for id, order in pairs(orderQueue) do
                if order.state == STATE.READY then
                    dispatchWaiterOrder(order)
                    break -- One at a time
                end
            end
        end

        -- Garbage collect completed/cancelled orders older than 5 minutes
        local now = os.epoch("utc")
        for id, order in pairs(orderQueue) do
            if (order.state == STATE.COMPLETE or order.state == STATE.CANCELLED)
                and (now - order.created_at > 300000) then
                orderQueue[id] = nil
            end
        end

        -- Flush logs periodically
        flushLogs()
    end
end

--==============================================================================
-- Terminal UI
--==============================================================================

local function drawUI()
    if not uiDirty then return end
    uiDirty = false

    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg)
    term.clear()

    -- Title bar
    term.setBackgroundColor(theme.titleBg)
    term.setTextColor(theme.titleText)
    term.setCursorPos(1, 1)
    local titleStr = " " .. (config.restaurant_name or "Restaurant Server") .. " "
    local pad = string.rep(" ", math.max(0, w - #titleStr))
    term.write(titleStr .. pad)

    -- Status bar
    term.setCursorPos(1, 2)
    term.setBackgroundColor(theme.statusBarBg)
    term.setTextColor(theme.statusBarText)

    local activeOrders = 0
    for _, order in pairs(orderQueue) do
        if order.state ~= STATE.COMPLETE and order.state ~= STATE.CANCELLED then
            activeOrders = activeOrders + 1
        end
    end

    local statusStr = string.format(" Orders: %d | Chef: %s | Waiter: %s | Menu: %d items ",
        activeOrders,
        chefBusy and "BUSY" or "IDLE",
        waiterBusy and "BUSY" or "IDLE",
        #recipes)
    term.write(statusStr .. string.rep(" ", math.max(0, w - #statusStr)))

    -- Order list
    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
    local y = 4
    term.setCursorPos(1, 3)
    term.setTextColor(theme.prompt)
    term.write(" Active Orders:")
    term.setTextColor(theme.text)

    for id, order in pairs(orderQueue) do
        if y > h - 3 then break end
        if order.state ~= STATE.COMPLETE and order.state ~= STATE.CANCELLED then
            term.setCursorPos(2, y)
            local stateColor = theme.text
            if order.state == STATE.PAID then stateColor = theme.orderNew
            elseif order.state == STATE.COOKING then stateColor = theme.orderCook
            elseif order.state == STATE.DELIVERING then stateColor = theme.orderDone end

            term.setTextColor(stateColor)
            local line = string.format("%s [T%d] %s $%d (%s)",
                order.id:sub(1, 8), order.table_num, order.customer:sub(1, 10), order.total, order.state)
            term.write(line:sub(1, w - 2))
            y = y + 1
        end
    end

    -- Log area
    term.setTextColor(theme.text)
    local logStart = h - 4
    if logStart > y + 1 then
        term.setCursorPos(1, logStart - 1)
        term.setTextColor(theme.prompt)
        term.write(" Recent Log:")
        term.setTextColor(colors.lightGray)
        local logLines = math.min(4, logWriteIdx)
        for i = 0, logLines - 1 do
            local idx = logWriteIdx - logLines + 1 + i
            if logHistory[idx] then
                term.setCursorPos(2, logStart + i)
                term.write(logHistory[idx]:sub(1, w - 2))
            end
        end
    end

    -- Bottom bar
    term.setCursorPos(1, h)
    term.setBackgroundColor(theme.titleBg)
    term.setTextColor(theme.titleText)
    local bottomStr = " [R]eload Menu | [Q]uit "
    term.write(bottomStr .. string.rep(" ", math.max(0, w - #bottomStr)))
    term.setBackgroundColor(theme.bg)
end

--- Admin input loop — handles keyboard input for admin controls.
local function adminLoop()
    while true do
        drawUI()
        local event, key = os.pullEvent("key")
        if key == keys.r then
            reloadRecipes()
            uiDirty = true
        elseif key == keys.q then
            flushLogs()
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1, 1)
            print("Restaurant Server shut down.")
            rednet.unhost(RESTAURANT_PROTOCOL)
            return
        end
    end
end

--- Periodic UI refresh to keep the display alive.
local function uiRefreshLoop()
    while true do
        sleep(3)
        uiDirty = true
    end
end

--==============================================================================
-- Main Entry Point
--==============================================================================

local function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("Drunken Bites Restaurant Server v1.0")
    print("=====================================")

    -- Peripherals
    local modem = peripheral.find("modem")
    if not modem then
        printError("FATAL: No modem attached.")
        return
    end
    rednet.open(peripheral.getName(modem))

    -- Load data
    config = loadConfig()
    recipes = loadRecipes()

    -- Discover Bank Server
    print("Locating Bank Server...")
    for i = 1, 3 do
        bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server")
        if bankServerId then break end
        sleep(1)
    end
    if bankServerId then
        logActivity("Bank Server found at ID " .. bankServerId)
    else
        logActivity("WARNING: Bank Server not found. Payments will fail.", true)
    end

    -- Host the restaurant protocol
    rednet.host(RESTAURANT_PROTOCOL, "restaurant.server")
    logActivity("Hosting protocol: " .. RESTAURANT_PROTOCOL)
    logActivity("Restaurant '" .. (config.restaurant_name or "?") .. "' is OPEN.")
    logActivity("Chef Turtle ID: " .. tostring(config.chef_turtle_id or "NOT SET"))
    logActivity("Waiter Turtle ID: " .. tostring(config.waiter_turtle_id or "NOT SET"))

    startupComplete = true
    uiDirty = true

    -- Run all loops in parallel (non-blocking)
    parallel.waitForAny(
        networkLoop,
        tickLoop,
        adminLoop,
        uiRefreshLoop
    )
end

-- Crash-safe wrapper
while true do
    local ok, err = pcall(main)
    if not ok then
        local file = fs.open("restaurant_crash.log", "a")
        if file then
            file.writeLine(os.date() .. " - FATAL: " .. tostring(err))
            file.close()
        end
        printError("FATAL ERROR: " .. tostring(err))
        print("Restarting in 5 seconds...")
        sleep(5)
        os.reboot()
    else
        break -- Clean exit via admin [Q]
    end
end
