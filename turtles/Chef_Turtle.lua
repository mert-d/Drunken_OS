--[[
    Drunken Bites - Chef Turtle (v1.0)
    by MuhendizBey

    Purpose:
    A "dumb" worker turtle that listens for Work Orders from the
    Restaurant Queue Manager. It scans adjacent inventories for
    required ingredients, collects them, and drops them onto the
    Create Depot for processing.

    It knows NOTHING about recipes — it only follows ingredient lists.
    Modeled after DB_Bank_Clerk.lua pairing pattern.
]]

--==============================================================================
-- Configuration
--==============================================================================

local CHEF_PROTOCOL = "Drunken_Chef_v1"
local CONFIG_FILE   = "chef.conf"

-- Default drop direction for the Create Depot
local DROP_DIRECTION = "front" -- front/top/bottom

-- Movement retry settings
local MOVE_RETRIES = 3
local MOVE_RETRY_DELAY = 0.5

--==============================================================================
-- Core Functions
--==============================================================================

local function logActivity(msg, isError)
    local prefix = os.date("[%H:%M:%S] ")
    if isError then
        term.setTextColor(colors.red)
        print(prefix .. "ERROR: " .. msg)
        term.setTextColor(colors.white)
    else
        print(prefix .. msg)
    end
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        local default = {
            server_id = nil,
            drop_direction = "front", -- front, top, bottom
        }
        local f = fs.open(CONFIG_FILE, "w")
        f.write(textutils.serialize(default))
        f.close()
        logActivity("Generated default chef.conf. Set server_id and restart.")
        return default
    end
    local f = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data or {}
end

--- Drop items in the configured direction.
local function dropItem(direction)
    if direction == "top" then return turtle.dropUp()
    elseif direction == "bottom" then return turtle.dropDown()
    else return turtle.drop()
    end
end

--- Suck items from the configured direction.
local function suckItem(direction, count)
    if direction == "top" then return turtle.suckUp(count)
    elseif direction == "bottom" then return turtle.suckDown(count)
    else return turtle.suck(count)
    end
end

--==============================================================================
-- Smart Inventory Scanning
--==============================================================================

--- Scan all adjacent inventory peripherals for needed items.
-- @param ingredients table: { {name="minecraft:...", count=N}, ... }
-- @return table, string: collected items map OR nil + missing item name
local function collectIngredients(ingredients)
    -- Find all adjacent inventories
    local inventories = { peripheral.find("inventory") }

    if #inventories == 0 then
        return nil, "No inventory peripherals found"
    end

    logActivity("Found " .. #inventories .. " inventory peripheral(s).")
    local turtleSlot = 1

    for _, ingredient in ipairs(ingredients) do
        local needed = ingredient.count
        local collected = 0

        logActivity(string.format("Looking for %dx %s ...", needed, ingredient.name))

        for _, inv in ipairs(inventories) do
            if collected >= needed then break end

            local invName = peripheral.getName(inv)
            local ok, contents = pcall(inv.list)
            if ok and contents then
                for slot, item in pairs(contents) do
                    if collected >= needed then break end
                    if item.name == ingredient.name then
                        local toTake = math.min(item.count, needed - collected)

                        -- Use pushItems to move from inventory to turtle
                        -- The turtle's own inventory name for pushItems is "front"/"top"/etc
                        -- depending on orientation, but we can use turtle.suck instead.
                        -- Strategy: Move item to slot 1 of that inventory, then suck.
                        -- Actually, for non-chest peripherals, pushItems to the turtle
                        -- is the cleanest approach. We'll try direct suck first.

                        -- Try to pull the item using the inventory's pushItems
                        -- targeting the turtle's side. Since we can't reliably know
                        -- which side we are on, we'll use turtle.suck after
                        -- shuffling items to a known position.

                        -- For simplicity and reliability: use the inventory API to
                        -- push items into the turtle. The turtle is accessible as
                        -- a peripheral from the inventory's perspective.

                        -- Attempt method: pushItems to turtle
                        local turtleName = nil
                        -- The turtle can receive items via its own peripheral name
                        -- but this is tricky. Use suck-based approach instead.

                        -- Suck-based approach: move item to slot 1, then suck
                        if slot ~= 1 then
                            pcall(inv.pushItems, invName, slot, toTake, 1)
                        end

                        -- Now suck from the inventory direction
                        -- We need to face the inventory. Since we used peripheral.find,
                        -- we need to determine which side this inventory is on.
                        local side = invName
                        turtle.select(turtleSlot)

                        local sucked = false
                        for attempt = 1, MOVE_RETRIES do
                            if side == "top" then
                                sucked = turtle.suckUp(toTake)
                            elseif side == "bottom" then
                                sucked = turtle.suckDown(toTake)
                            else
                                -- For horizontal sides, we need to face the right direction
                                -- Since peripheral.find returns wrapped peripherals,
                                -- and the name tells us the side, try suck from front
                                sucked = turtle.suck(toTake)
                            end
                            if sucked then break end
                            sleep(MOVE_RETRY_DELAY)
                        end

                        if sucked then
                            local detail = turtle.getItemDetail(turtleSlot)
                            if detail and detail.name == ingredient.name then
                                collected = collected + detail.count
                                logActivity(string.format("  Collected %d from %s slot %d",
                                    detail.count, invName, slot))
                                if detail.count >= 64 or turtleSlot >= 16 then
                                    turtleSlot = turtleSlot + 1
                                end
                            end
                        end
                    end
                    -- Yield to prevent "too long without yielding"
                    os.queueEvent("chef_yield")
                    os.pullEvent("chef_yield")
                end
            end
        end

        if collected < needed then
            logActivity(string.format("MISSING: Only found %d/%d of %s",
                collected, needed, ingredient.name), true)
            return nil, ingredient.name
        end

        logActivity(string.format("  Got %d/%d %s", collected, needed, ingredient.name))
    end

    return true
end

--- Drop all items in turtle inventory onto the Create Depot.
local function dropAllItems(direction)
    logActivity("Dropping items onto depot (" .. direction .. ")...")
    local dropped = 0
    for i = 1, 16 do
        turtle.select(i)
        if turtle.getItemCount(i) > 0 then
            local success = false
            for attempt = 1, MOVE_RETRIES do
                success = dropItem(direction)
                if success then break end
                sleep(MOVE_RETRY_DELAY)
            end
            if success then
                dropped = dropped + 1
            else
                logActivity("Failed to drop slot " .. i .. " after retries!", true)
            end
        end
    end
    turtle.select(1)
    return dropped
end

--- Return all items in turtle inventory back to the first available inventory.
local function returnAllItems()
    logActivity("Returning items to inventory...")
    local inventories = { peripheral.find("inventory") }
    if #inventories == 0 then
        logActivity("No inventory to return items to!", true)
        return
    end

    -- Just drop everything back into the first inventory
    local invName = peripheral.getName(inventories[1])
    for i = 1, 16 do
        turtle.select(i)
        if turtle.getItemCount(i) > 0 then
            if invName == "top" then
                turtle.dropUp()
            elseif invName == "bottom" then
                turtle.dropDown()
            else
                turtle.drop()
            end
        end
    end
    turtle.select(1)
end

--==============================================================================
-- Work Order Handler
--==============================================================================

local function handleWorkOrder(serverId, message)
    local orderId = message.order_id
    local ingredients = message.ingredients

    if not ingredients or #ingredients == 0 then
        logActivity("Received empty ingredient list for order " .. tostring(orderId), true)
        rednet.send(serverId, {
            type = "work_complete",
            order_id = orderId,
        }, CHEF_PROTOCOL)
        return
    end

    logActivity(string.format("=== WORK ORDER: %s (%d ingredients) ===", orderId, #ingredients))

    -- Phase 1: Collect all ingredients
    local success, missingItem = collectIngredients(ingredients)

    if not success then
        logActivity("Aborting order " .. orderId .. " - missing: " .. tostring(missingItem), true)
        returnAllItems()
        rednet.send(serverId, {
            type = "missing_item",
            order_id = orderId,
            item = missingItem,
        }, CHEF_PROTOCOL)
        return
    end

    -- Phase 2: Drop everything onto the Create Depot
    dropAllItems(DROP_DIRECTION)

    logActivity("=== ORDER " .. orderId .. " COMPLETE ===")
    rednet.send(serverId, {
        type = "work_complete",
        order_id = orderId,
    }, CHEF_PROTOCOL)
end

--==============================================================================
-- Main Program
--==============================================================================

local function main()
    term.clear(); term.setCursorPos(1, 1)
    term.setTextColor(colors.orange)
    print("=== Drunken Bites Chef Turtle v1.0 ===")
    term.setTextColor(colors.white)

    -- Load config
    local cfg = loadConfig()
    DROP_DIRECTION = cfg.drop_direction or "front"

    -- Find modem
    local modem = peripheral.find("modem")
    if not modem then
        printError("FATAL: No modem attached.")
        return
    end
    rednet.open(peripheral.getName(modem))

    -- Display pairing info
    print("--- Configuration ---")
    print("My Computer ID: " .. os.getComputerID())
    print("Paired Server ID: " .. tostring(cfg.server_id or "NOT SET"))
    print("Drop Direction: " .. DROP_DIRECTION)
    print("---------------------")

    if not cfg.server_id then
        printError("No server_id set in chef.conf!")
        printError("Edit chef.conf and set server_id to the Restaurant Server's ID.")
        return
    end

    -- Scan available inventories
    local invCount = #{ peripheral.find("inventory") }
    logActivity("Adjacent inventories detected: " .. invCount)

    term.setTextColor(colors.lime)
    print("Chef Turtle ONLINE. Waiting for orders...")
    term.setTextColor(colors.white)

    -- Main listener loop
    while true do
        local senderId, message, proto = rednet.receive()
        if type(message) == "table" and message.type and proto == CHEF_PROTOCOL then
            -- Only accept commands from paired server
            if senderId == cfg.server_id then
                if message.type == "work_order" then
                    handleWorkOrder(senderId, message)
                elseif message.type == "ping" then
                    logActivity("Ping from server " .. senderId)
                    rednet.send(senderId, { type = "pong" }, CHEF_PROTOCOL)
                end
            else
                logActivity("Rejected command from unauthorized ID: " .. senderId, true)
            end
        end
    end
end

-- Crash-safe wrapper
while true do
    local ok, err = pcall(main)
    if not ok then
        local f = fs.open("chef_crash.log", "a")
        if f then f.writeLine(os.date() .. " - " .. tostring(err)); f.close() end
        printError("FATAL: " .. tostring(err))
        print("Restarting in 5s...")
        sleep(5)
        os.reboot()
    else
        break
    end
end
