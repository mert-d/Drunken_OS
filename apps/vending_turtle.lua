--[[
    Drunken OS - Vending Turtle
    Runs on a Turtle to dispense items when commanded by a Merchant PC.
]]

local PROTOCOL = "DB_Vending_Turtle"
peripheral.find("modem", rednet.open)

print("Vending Turtle Online")
print("My ID: " .. os.getComputerID())
print("Listening on " .. PROTOCOL)

while true do
    local sender, msg = rednet.receive(PROTOCOL)
    
    if msg and msg.type == "dispense" then
        print("Received Dispense Command from " .. sender)
        local items = msg.items -- { {name, count, ...}, ... }
        
        if items then
            for _, item in ipairs(items) do
                -- Find item in inventory
                -- Simplified: Assume Turtle is stocked and we just throw 'count' items.
                -- Advanced: Check item name using turtle.getItemDetail()
                
                local remaining = item.count
                for slot = 1, 16 do
                    if remaining <= 0 then break end
                    
                    turtle.select(slot)
                    local data = turtle.getItemDetail()
                    
                    -- Loose logic: If data exists, drop it.
                    
                    if data then
                        -- Optional: text/fuzzy match item.name?
                        -- For Drunken OS Alpha, just dispensing is cool enough.
                        
                        local dropAmt = math.min(remaining, data.count)
                        turtle.drop(dropAmt)
                        remaining = remaining - dropAmt
                    end
                end
                
                if remaining > 0 then
                    print("Warning: Out of Stock for " .. item.name)
                end
            end
            print("Dispense Complete")
        end
    elseif msg and msg.type == "ping" then
        rednet.send(sender, { type = "pong" }, PROTOCOL)
    end
end
