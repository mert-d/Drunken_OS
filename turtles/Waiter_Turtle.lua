--[[
    Drunken Bites - Waiter Turtle (v1.0)
    by MuhendizBey & Gemini Gem

    Purpose:
    A "dumb" delivery worker turtle. Picks up finished food from the
    delivery depot, navigates to the customer's table using GPS-assisted
    coordinate navigation, drops the item, and returns to base.

    Modeled after DB_Bank_Clerk.lua pairing pattern.
]]

--==============================================================================
-- Configuration
--==============================================================================

local WAITER_PROTOCOL = "Drunken_Waiter_v1"
local CONFIG_FILE     = "waiter.conf"

local MOVE_RETRIES    = 5
local MOVE_RETRY_DELAY = 1

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
            pickup_direction = "front", -- Direction to suck finished food
        }
        local f = fs.open(CONFIG_FILE, "w")
        f.write(textutils.serialize(default))
        f.close()
        logActivity("Generated default waiter.conf. Set server_id and restart.")
        return default
    end
    local f = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data or {}
end

--==============================================================================
-- Navigation System (GPS-Based)
--==============================================================================

local currentPos = { x = 0, y = 0, z = 0 }
local currentFacing = 0 -- 0=south(+z), 1=west(-x), 2=north(-z), 3=east(+x)

-- Direction vectors for each facing
local FACING_DELTA = {
    [0] = { x = 0,  z = 1  }, -- south (+z)
    [1] = { x = -1, z = 0  }, -- west (-x)
    [2] = { x = 0,  z = -1 }, -- north (-z)
    [3] = { x = 1,  z = 0  }, -- east (+x)
}

--- Locate position via GPS. Returns true on success.
local function gpsLocate()
    local x, y, z = gps.locate(3)
    if x then
        currentPos = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
        logActivity(string.format("GPS: (%d, %d, %d)", currentPos.x, currentPos.y, currentPos.z))
        return true
    end
    logActivity("GPS failed! Navigation may be unreliable.", true)
    return false
end

--- Determine facing by moving forward and checking GPS delta.
local function calibrateFacing()
    local oldPos = { x = currentPos.x, y = currentPos.y, z = currentPos.z }

    -- Try to move forward to detect facing
    if turtle.forward() then
        gpsLocate()
        local dx = currentPos.x - oldPos.x
        local dz = currentPos.z - oldPos.z

        if dz == 1 then currentFacing = 0      -- south
        elseif dx == -1 then currentFacing = 1  -- west
        elseif dz == -1 then currentFacing = 2  -- north
        elseif dx == 1 then currentFacing = 3   -- east
        end

        turtle.back() -- Return to original position
        gpsLocate()
        logActivity("Facing calibrated: " .. currentFacing)
        return true
    end
    logActivity("Could not calibrate facing (blocked).", true)
    return false
end

--- Turn to face the desired direction (0-3).
local function turnToFacing(target)
    target = target % 4
    while currentFacing ~= target do
        local diff = (target - currentFacing) % 4
        if diff == 1 then
            turtle.turnRight()
            currentFacing = (currentFacing + 1) % 4
        elseif diff == 3 then
            turtle.turnLeft()
            currentFacing = (currentFacing - 1) % 4
        else
            turtle.turnRight()
            currentFacing = (currentFacing + 1) % 4
        end
    end
end

--- Move forward with entity-blocking retry logic.
local function moveForward()
    for i = 1, MOVE_RETRIES do
        if turtle.forward() then return true end
        logActivity("Blocked! Retry " .. i .. "/" .. MOVE_RETRIES)
        sleep(MOVE_RETRY_DELAY)
    end
    logActivity("Movement FAILED after retries!", true)
    return false
end

--- Move up with retry logic.
local function moveUp()
    for i = 1, MOVE_RETRIES do
        if turtle.up() then return true end
        sleep(MOVE_RETRY_DELAY)
    end
    return false
end

--- Move down with retry logic.
local function moveDown()
    for i = 1, MOVE_RETRIES do
        if turtle.down() then return true end
        sleep(MOVE_RETRY_DELAY)
    end
    return false
end

--- Navigate to target XYZ coordinates using axis-by-axis movement.
-- Moves Y first (vertical), then X, then Z to avoid ground obstacles.
local function moveTo(target)
    logActivity(string.format("Navigating to (%d, %d, %d)...", target.x, target.y, target.z))

    -- Re-read GPS for accuracy
    gpsLocate()

    -- Phase 1: Adjust Y (vertical)
    while currentPos.y < target.y do
        if not moveUp() then return false end
        currentPos.y = currentPos.y + 1
    end
    while currentPos.y > target.y do
        if not moveDown() then return false end
        currentPos.y = currentPos.y - 1
    end

    -- Phase 2: Adjust X
    if currentPos.x < target.x then
        turnToFacing(3) -- face east (+x)
        while currentPos.x < target.x do
            if not moveForward() then return false end
            currentPos.x = currentPos.x + 1
        end
    elseif currentPos.x > target.x then
        turnToFacing(1) -- face west (-x)
        while currentPos.x > target.x do
            if not moveForward() then return false end
            currentPos.x = currentPos.x - 1
        end
    end

    -- Phase 3: Adjust Z
    if currentPos.z < target.z then
        turnToFacing(0) -- face south (+z)
        while currentPos.z < target.z do
            if not moveForward() then return false end
            currentPos.z = currentPos.z + 1
        end
    elseif currentPos.z > target.z then
        turnToFacing(2) -- face north (-z)
        while currentPos.z > target.z do
            if not moveForward() then return false end
            currentPos.z = currentPos.z - 1
        end
    end

    logActivity(string.format("Arrived at (%d, %d, %d).", target.x, target.y, target.z))
    return true
end

--==============================================================================
-- Pickup & Delivery
--==============================================================================

--- Pick up items from the delivery depot.
local function pickupFood(direction)
    logActivity("Picking up food from depot (" .. direction .. ")...")
    turtle.select(1)
    local success = false
    for i = 1, MOVE_RETRIES do
        if direction == "top" then
            success = turtle.suckUp()
        elseif direction == "bottom" then
            success = turtle.suckDown()
        else
            success = turtle.suck()
        end
        if success then break end
        logActivity("Pickup retry " .. i)
        sleep(MOVE_RETRY_DELAY)
    end

    if success then
        local detail = turtle.getItemDetail(1)
        logActivity("Picked up: " .. (detail and detail.name or "item"))
    else
        logActivity("Failed to pick up food!", true)
    end
    return success
end

--- Drop all items at the current location (onto table depot).
local function deliverFood()
    logActivity("Delivering food to table...")
    local delivered = false
    for i = 1, 16 do
        turtle.select(i)
        if turtle.getItemCount(i) > 0 then
            -- Try dropping down first (onto depot/table surface)
            if not turtle.dropDown() then
                -- Try dropping forward
                if not turtle.drop() then
                    logActivity("Could not deliver slot " .. i, true)
                end
            end
            delivered = true
        end
    end
    turtle.select(1)
    return delivered
end

--==============================================================================
-- Delivery Order Handler
--==============================================================================

local function handleDeliveryOrder(serverId, message)
    local orderId = message.order_id
    local pickup = message.pickup         -- {x, y, z}
    local tableCoords = message.table_coords -- {x, y, z}
    local baseCoords = message.base_coords   -- {x, y, z}

    logActivity(string.format("=== DELIVERY: %s -> Table (%d,%d,%d) ===",
        orderId, tableCoords.x, tableCoords.y, tableCoords.z))

    -- Step 1: Navigate to pickup depot
    if pickup then
        if not moveTo(pickup) then
            logActivity("Failed to reach pickup depot!", true)
            rednet.send(serverId, {
                type = "delivery_failed", order_id = orderId,
                reason = "Could not reach pickup depot.",
            }, WAITER_PROTOCOL)
            return
        end
    end

    -- Step 2: Pick up the food
    local pickupDir = "front"
    if not pickupFood(pickupDir) then
        logActivity("No food to pick up for order " .. orderId, true)
        rednet.send(serverId, {
            type = "delivery_failed", order_id = orderId,
            reason = "No food at pickup depot.",
        }, WAITER_PROTOCOL)
        -- Return to base anyway
        if baseCoords then moveTo(baseCoords) end
        return
    end

    -- Step 3: Navigate to the table
    if not moveTo(tableCoords) then
        logActivity("Failed to reach table!", true)
        rednet.send(serverId, {
            type = "delivery_failed", order_id = orderId,
            reason = "Could not reach table.",
        }, WAITER_PROTOCOL)
        -- Try to return to base with the food
        if baseCoords then moveTo(baseCoords) end
        return
    end

    -- Step 4: Deliver the food
    deliverFood()

    -- Step 5: Return to base
    logActivity("Returning to base station...")
    if baseCoords then
        moveTo(baseCoords)
    end

    logActivity("=== DELIVERY " .. orderId .. " COMPLETE ===")
    rednet.send(serverId, {
        type = "delivery_complete",
        order_id = orderId,
    }, WAITER_PROTOCOL)
end

--==============================================================================
-- Main Program
--==============================================================================

local function main()
    term.clear(); term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== Drunken Bites Waiter Turtle v1.0 ===")
    term.setTextColor(colors.white)

    -- Load config
    local cfg = loadConfig()

    -- Find modem
    local modem = peripheral.find("modem")
    if not modem then
        printError("FATAL: No modem attached.")
        return
    end
    rednet.open(peripheral.getName(modem))

    -- Display info
    print("--- Configuration ---")
    print("My Computer ID: " .. os.getComputerID())
    print("Paired Server ID: " .. tostring(cfg.server_id or "NOT SET"))
    print("Pickup Direction: " .. (cfg.pickup_direction or "front"))
    print("---------------------")

    if not cfg.server_id then
        printError("No server_id set in waiter.conf!")
        printError("Edit waiter.conf and set server_id to the Restaurant Server's ID.")
        return
    end

    -- GPS calibration
    print("Calibrating GPS position...")
    if gpsLocate() then
        print("Calibrating facing direction...")
        calibrateFacing()
    else
        print("WARNING: GPS unavailable. Waiter will attempt GPS at delivery time.")
    end

    term.setTextColor(colors.lime)
    print("Waiter Turtle ONLINE. Awaiting delivery orders...")
    term.setTextColor(colors.white)

    -- Main listener loop
    while true do
        local senderId, message, proto = rednet.receive()
        if type(message) == "table" and message.type and proto == WAITER_PROTOCOL then
            if senderId == cfg.server_id then
                if message.type == "delivery_order" then
                    handleDeliveryOrder(senderId, message)
                elseif message.type == "ping" then
                    logActivity("Ping from server " .. senderId)
                    rednet.send(senderId, { type = "pong" }, WAITER_PROTOCOL)
                end
            else
                logActivity("Rejected from unauthorized ID: " .. senderId, true)
            end
        end
    end
end

-- Crash-safe wrapper
while true do
    local ok, err = pcall(main)
    if not ok then
        local f = fs.open("waiter_crash.log", "a")
        if f then f.writeLine(os.date() .. " - " .. tostring(err)); f.close() end
        printError("FATAL: " .. tostring(err))
        print("Restarting in 5s...")
        sleep(5)
        os.reboot()
    else
        break
    end
end
