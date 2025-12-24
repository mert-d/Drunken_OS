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
    context.showMessage("POS", "Mobile POS active.")
end

function merchant.run(context)
    merchant.cashier(context)
end

return merchant
