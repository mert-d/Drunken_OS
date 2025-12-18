--[[
    Drunken Beard Bank - Auditor Turtle (v1.2 - Refactored Crypto)
    by MuhendizBey

    Purpose:
    This version refactors the cryptographic functions into the new, separate
    `lib/sha1_hmac.lua` library.

    Key Changes:
    - Removed the embedded SHA1 & HMAC library block.
    - Added a `require()` call to the new `lib/sha1_hmac` library.
    - Updated HMAC signing calls to use the new crypto library.
]]

--==============================================================================
-- API & Library Initialization
--==============================================================================

-- Load our new, centralized cryptography library.
-- This file should be placed at "/lib/sha1_hmac.lua" on the computer.
package.path = "/?.lua;" .. package.path
local crypto = require("lib.sha1_hmac")

--==============================================================================
-- Configuration
--==============================================================================

-- The rednet protocol for communication with the main server.
local protocol = "DB_Audit"

-- How often, in seconds, the turtle should perform an audit and report.
local audit_interval = 300 -- 5 minutes

-- A secret key shared between this turtle and the main server for HMAC signing.
-- IMPORTANT: This MUST match the key in the server script!
local SECRET_KEY = nil

--==============================================================================
-- Core Functions
--==============================================================================

local function findModem()
    local modem_side = peripheral.find("modem")
    if modem_side then
        return peripheral.getName(modem_side)
    end
    return nil
end

local function performAudit(transaction_log)
    print("Performing audit of vault contents...")
    local actual_stock = {}
    local inventories = { peripheral.find("inventory") }

    for _, inv_peripheral in ipairs(inventories) do
        if inv_peripheral then
            local items = inv_peripheral.list()
            for _, item in pairs(items) do
                local current_stock = actual_stock[item.name] or 0
                actual_stock[item.name] = current_stock + item.count
            end
        end
    end

    local expected_stock = {}
    if transaction_log then
        for line in transaction_log:gmatch("[^\n]+") do
            local ok, transaction = pcall(textutils.unserializeJSON, line)
            if ok and transaction then
                for item, data in pairs(transaction.data) do
                    local current_stock = expected_stock[item] or 0
                    if transaction.type == "DEPOSIT" then
                        expected_stock[item] = current_stock + data.count
                    elseif transaction.type == "WITHDRAW" then
                        expected_stock[item] = current_stock - data.count
                    end
                end
            end
        end
    end
    
    local discrepancies = {}
    for item, count in pairs(actual_stock) do
        if expected_stock[item] ~= count then
            discrepancies[item] = { expected = expected_stock[item] or 0, actual = count }
        end
    end
    for item, count in pairs(expected_stock) do
        if not actual_stock[item] and count ~= 0 then
            discrepancies[item] = { expected = count, actual = 0 }
        end
    end

    return actual_stock, discrepancies
end

--==============================================================================
-- Main Program Loop
--==============================================================================

local function main()
    if fs.exists("/auditor_key.conf") then
        local file = fs.open("/auditor_key.conf", "r")
        SECRET_KEY = file.readAll()
        file.close()
    else
        print("FATAL: /auditor_key.conf not found. Please run the installer disk.")
        return
    end

    local modem_side = findModem()
    if not modem_side then
        print("Error: No wireless modem attached.")
        return
    end

    rednet.open(modem_side)
    
    local bankServerId = rednet.lookup("DB_Bank", "bank.server")
    if not bankServerId then
        print("Error: Could not find the main bank server.")
        rednet.close(modem_side)
        return
    end
    
    print("Auditor Turtle online. Connected to main server.")
    print("First audit in " .. audit_interval .. " seconds.")

    while true do
        local timestamp = os.time()
        local signature = crypto.hmac_hex(SECRET_KEY, timestamp)
        rednet.send(bankServerId, { type = "get_transaction_log", timestamp = timestamp, signature = signature }, protocol)
        local _, response = rednet.receive(protocol, 10)

        local transaction_log = nil
        if response and response.success then
            transaction_log = response.log
        else
            print("Could not retrieve transaction log. Auditing without verification.")
        end

        local stock_report, discrepancies = performAudit(transaction_log)
        
        local payload = {
            type = "stock_report",
            report = stock_report,
            discrepancies = discrepancies
        }
        
        -- Sign the report before sending using our new crypto library
        local messageToSign = textutils.serializeJSON(payload.report)
        payload.signature = crypto.hmac_hex(SECRET_KEY, messageToSign)
        
        rednet.send(bankServerId, payload, protocol)
        print("Sent signed stock report to server.")
        for item, count in pairs(stock_report) do
            print("- " .. item .. ": " .. count)
        end

        if next(discrepancies) then
            print("Discrepancies found!")
            for item, data in pairs(discrepancies) do
                print("- " .. item .. ": Expected " .. data.expected .. ", but found " .. data.actual)
            end
        end
        
        sleep(audit_interval)
    end
end

main()
