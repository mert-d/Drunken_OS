--[[
    Drunken Beard Bank - Vault Clerk Turtle (v7.3 - Modular Pairing)
    by Gemini Gem & MuhendizBey

    Purpose:
    This version is designed for modular deployment. It no longer hosts a
    public rednet protocol, instead displaying its unique computer ID on
    startup so it can be paired with a specific ATM.

    Changelog:
    v7.3:
    - Removed 'rednet.host()'. The turtle is now a private agent.
    - Added a clear startup message that displays the turtle's ID for easy ATM pairing.
    v7.2:
    - Implemented universal 6-sided deposit logic.
]]

--==============================================================================
-- Configuration
--==============================================================================

local protocol = "DB_ATM_Turtle"
local depositBlockName = "minecraft:barrel"

-- A table to map a side to its opposite.
local opposite_sides = {
    top = "bottom", bottom = "top",
    left = "right", right = "left",
    front = "back", back = "front"
}

--==============================================================================
-- Core Functions
--==============================================================================

local function logActivity(msg, isError)
    local prefix = os.date("[%H:%M:%S] ")
    if isError then
        print(prefix .. "ERROR: " .. msg)
    else
        print(prefix .. msg)
    end
end

local function findPeripherals()
    logActivity("Scanning for peripherals...")
    
    local modem_side = peripheral.find("modem")
    if not modem_side then return nil, nil, nil, "No wireless modem attached." end
    modem_side = peripheral.getName(modem_side)

    local deposit_side = peripheral.find(depositBlockName)
    if not deposit_side then return nil, nil, nil, "Could not find Deposit Barrel." end
    deposit_side = peripheral.getName(deposit_side)

    local vault_side = nil
    for _, name in ipairs(peripheral.getNames()) do
        if name ~= modem_side and name ~= deposit_side then
            if peripheral.hasType(name, "inventory") then
                vault_side = name
                break
            end
        end
    end

    if not vault_side then
        return nil, nil, nil, "Could not find a valid vault inventory peripheral."
    end
    
    return modem_side, deposit_side, vault_side, nil
end

-- (Movement and basic inventory functions are unchanged)
local function turnTo(targetSide)
    if targetSide == "left" then turtle.turnLeft()
    elseif targetSide == "right" then turtle.turnRight()
    elseif targetSide == "back" then turtle.turnRight(); turtle.turnRight() end
end

local function turnToFront(originalSide)
    if originalSide == "left" then turtle.turnRight()
    elseif originalSide == "right" then turtle.turnLeft()
    elseif originalSide == "back" then turtle.turnLeft(); turtle.turnLeft() end
end

local function collectFromDeposit(deposit_side)
    logActivity("Collecting items from " .. deposit_side .. "...")
    if deposit_side == "top" then
        for i = 1, 16 do turtle.select(i); turtle.suckUp() end
    elseif deposit_side == "bottom" then
        for i = 1, 16 do turtle.select(i); turtle.suckDown() end
    else -- Horizontal
        turnTo(deposit_side)
        for i = 1, 16 do turtle.select(i); turtle.suck() end
        turnToFront(deposit_side)
    end
end

local function depositToVault(vault_side)
    logActivity("Depositing items to " .. vault_side .. "...")
    if vault_side == "top" then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 and not turtle.dropUp() then
                logActivity("Failed to drop item up into vault (is it full?)", true)
            end
        end
    elseif vault_side == "bottom" then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 and not turtle.dropDown() then
                logActivity("Failed to drop item down into vault (is it full?)", true)
            end
        end
    else -- Horizontal
        turnTo(vault_side)
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 and not turtle.drop() then
                logActivity("Failed to drop item into vault (is it full?)", true)
            end
        end
        turnToFront(vault_side)
    end
end

local function returnItemsToDeposit(deposit_side)
    logActivity("Returning items to " .. deposit_side .. "...")
    if deposit_side == "top" then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 then turtle.dropUp() end
        end
    elseif deposit_side == "bottom" then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 then turtle.dropDown() end
        end
    else -- Horizontal
        turnTo(deposit_side)
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 then turtle.drop() end
        end
        turnToFront(deposit_side)
    end
end

-- (handleDeposit is unchanged)
local function handleDeposit(atmId, deposit_side, vault_side)
    collectFromDeposit(deposit_side)
    local itemsInTurtle = {}
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then table.insert(itemsInTurtle, { name = item.name, count = item.count }) end
    end
    rednet.send(atmId, { type = "deposit_count", items = itemsInTurtle }, protocol)
    local _, message = rednet.receive(protocol, 15)
    if message and message.type == "confirm_deposit" then
        depositToVault(vault_side)
        rednet.send(atmId, { success = true, new_balance = message.new_balance }, protocol)
        logActivity("Successfully processed deposit.")
    else
        returnItemsToDeposit(deposit_side)
        rednet.send(atmId, { success = false, reason = "Deposit cancelled or timed out by ATM." }, protocol)
        logActivity("Deposit failed. Returned items to barrel.")
    end
end

local function depositToVault(vault_side)
    if vault_side == "top" then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 then turtle.dropUp() end
        end
    elseif vault_side == "bottom" then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 then turtle.dropDown() end
        end
    else -- Horizontal
        turnTo(vault_side)
        for i = 1, 16 do
            turtle.select(i)
            if turtle.getItemCount(i) > 0 then turtle.drop() end
        end
        turnToFront(vault_side)
    end
end

local function handleDispense(atmId, itemToDispense, count, vault_side, deposit_side)
    logActivity("Initiating 'Internal Shuffle' withdrawal for "..count.." "..itemToDispense)

    -- === Phase 1: Stock Verification ===
    logActivity("Scanning vault for available stock...")
    local available_stock = 0
    local source_slots = {}
    local vault_list = peripheral.call(vault_side, "list")
    for slot, item in pairs(vault_list) do
        if item.name == itemToDispense then
            available_stock = available_stock + item.count
            table.insert(source_slots, {slot=slot, count=item.count})
        end
    end
    logActivity("Found " .. available_stock .. " available in " .. #source_slots .. " stack(s).")

    if available_stock < count then
        rednet.send(atmId, { success = false, reason = "Insufficient stock in vault." }, protocol); return
    end

    -- === Phase 2: Preparation ===
    depositToVault(vault_side)
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            rednet.send(atmId, { success = false, reason = "Clerk inventory malfunction." }, protocol); return
        end
    end
    logActivity("Pre-flight check passed: Turtle inventory is empty.")

    -- === Phase 3: The "Internal Shuffle" and Collection Loop ===
    local remaining = count
    for _, source in ipairs(source_slots) do
        if remaining <= 0 then break end
        local amountToPull = math.min(remaining, source.count)

        -- 1. Move the items from their slot TO slot 1 within the vault.
        -- We are telling the vault to push items from source.slot into its own slot 1.
        peripheral.call(vault_side, "pushItems", vault_side, source.slot, amountToPull, 1)

        -- 2. Now that the correct item is in slot 1, suck it.
        local success = false
        if vault_side == "top" then success = turtle.suckUp(amountToPull)
        elseif vault_side == "bottom" then success = turtle.suckDown(amountToPull)
        else
            turnTo(vault_side)
            success = turtle.suck(amountToPull)
            turnToFront(vault_side)
        end
        
        if not success then
            logActivity("Failed to pull items after shuffling.", true)
            depositToVault(vault_side)
            rednet.send(atmId, { success = false, reason = "A vault hardware error occurred." }, protocol)
            return
        end
        
        remaining = remaining - amountToPull
    end

    -- === Phase 4: Final Verification and Dispense ===
    local pulledAmount = 0
    for i=1,16 do pulledAmount = pulledAmount + turtle.getItemCount(i) end

    if pulledAmount < count then
        logActivity("Verification failed. Did not collect enough items.", true)
        depositToVault(vault_side)
        rednet.send(atmId, { success = false, reason = "Item collection failed." }, protocol)
        return
    end

    returnItemsToDeposit(deposit_side)
    rednet.send(atmId, { success = true }, protocol)
    logActivity("Successfully dispensed " .. count .. " of " .. itemToDispense)
end
--==============================================================================
-- Main Program Loop
--==============================================================================

local function main()
    term.clear(); term.setCursorPos(1,1)
    local modem_side, deposit_side, vault_side, err = findPeripherals()
    if err then
        print("Fatal Error: " .. err); return
    end

    print("--- Configuration Report ---")
    print("Modem found on: " .. modem_side)
    print("Deposit Barrel found on: " .. deposit_side)
    print("Vault Inventory found on: " .. vault_side)
    print("----------------------------")
    
    rednet.open(modem_side)
    
    term.setTextColor(colors.yellow)
    print("Vault Clerk Module Online.")
    print("My Computer ID is: " .. os.getComputerID())
    term.setTextColor(colors.white)
    print("Waiting for commands from paired ATM...")

    while true do
        local senderId, message, proto = rednet.receive()
        if message and message.type and proto == protocol then
            if message.type == "request_deposit" then
                handleDeposit(senderId, deposit_side, vault_side)
            elseif message.type == "request_dispense" then
                handleDispense(senderId, message.item_name, message.count, vault_side, deposit_side)
            -- THE FIX: Respond to the ATM's setup ping.
            elseif message.type == "ping" then
                logActivity("Received setup ping from ID " .. senderId .. ". Responding.")
                rednet.send(senderId, { type = "pong" }, protocol)
            end
        end
    end
end

main()
