-- Drunken OS Merchant Turtle (Vending/Fulfillment)
-- Runs on a turtle paired with the Cashier PC
-- Protocol: DB_Merchant_Turtle

local PROTOCOL = "DB_Merchant_Turtle"
rednet.open("right") -- Assume modem is on right, or find it
-- Quick peripheral check
if not peripheral.find("modem") then
    print("Error: No modem found.")
    return
end

local function findModem()
    for _, face in ipairs(bit.band(0,0) and {} or {"top","bottom","left","right","front","back"}) do 
        if peripheral.getType(face) == "modem" then return face end
    end
end
local modemSide = findModem()
if modemSide then rednet.open(modemSide) end

term.clear()
term.setCursorPos(1,1)
print("Merchant Turtle Active")
print("ID: " .. os.getComputerID())
print("Listening on "..PROTOCOL.."...")

while true do
    local sender, msg = rednet.receive(PROTOCOL)
    if sender and type(msg) == "table" then
        print("Cmd from #"..sender..": " .. (msg.cmd or "?"))
        
        if msg.cmd == "check_stock" then
            -- Check if slot has the correct item
            local slot = tonumber(msg.slot)
            local expected = msg.item
            
            if not slot or slot < 1 or slot > 16 then
                rednet.send(sender, { success = false, reason = "Invalid slot" }, PROTOCOL)
            else
                local detail = turtle.getItemDetail(slot)
                if detail then
                    -- If expected is provided, match it. Otherwise just return what's there.
                    -- Matching by name (e.g. "minecraft:diamond_sword")
                    if not expected or detail.name == expected then
                        rednet.send(sender, { success = true, item = detail, count = detail.count }, PROTOCOL)
                        print("Stock check OK: Slot "..slot)
                    else
                        rednet.send(sender, { success = false, reason = "Mismatch", detail = detail }, PROTOCOL)
                        print("Stock check FAIL: Slot "..slot.." is "..detail.name)
                    end
                else
                     rednet.send(sender, { success = false, reason = "Empty slot" }, PROTOCOL)
                     print("Stock check FAIL: Slot "..slot.." is empty")
                end
            end
            
        elseif msg.cmd == "dispense" then
             local slot = tonumber(msg.slot)
             if slot and slot >= 1 and slot <= 16 then
                 turtle.select(slot)
                 if turtle.drop() then
                     rednet.send(sender, { success = true }, PROTOCOL)
                     print("Dispensed from Slot "..slot)
                 else
                     rednet.send(sender, { success = false, reason = "Drop failed" }, PROTOCOL)
                     print("Dispense FAIL: Slot "..slot)
                 end
             else
                 rednet.send(sender, { success = false, reason = "Invalid slot" }, PROTOCOL)
             end
             
        elseif msg.cmd == "ping" then
            rednet.send(sender, { success = true, id = os.getComputerID() }, PROTOCOL)
        end
    end
end
