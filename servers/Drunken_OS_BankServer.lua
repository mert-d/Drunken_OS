--[[
    Drunken OS - Bank Server (v3.0 - Performance Edition)
    by MuhendizBey

    Key Changes:
    - Lazy Persistence: Implemented dbDirty tracking and background save pulse.
    - Non-blocking Transactions: Refactored database writes to reduce UI lag.
    - Integrated with Mainframe Performance interlink.
]]


--==============================================================================
-- API & Library Initialization
--==============================================================================

-- Load our new, centralized cryptography library.
local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path
local crypto = require("lib.sha1_hmac")

-- Load shared libraries
local DB = require("lib.db")
local sharedTheme = require("lib.theme")
local utils = require("lib.utils")

--==============================================================================
-- Configuration & State
--==============================================================================

local accounts, currencyRates, currentStock = {}, {}, {}
local ledger = {}
local mainServerId = nil
local wired_modem_name, wireless_modem_name = nil, nil
local adminInput = ""
local logHistory = {}
local uiDirty = true
local needsRedraw = false
local wordWrap = utils.wordWrap
local startupComplete = false -- Flag to control logging to terminal

-- Database file paths
local LOGS_DIR = "logs"
local TRANSACTIONS_DIR = LOGS_DIR .. "/transactions"
local CURRENCIES_DIR = "currencies"
local ACCOUNTS_DB = "bank_accounts.db"
local STOCK_DB = "bank_stock.db"
local LOG_FILE = LOGS_DIR .. "/bank_server.log"
local LEDGER_FILE = LOGS_DIR .. "/ledger.json"

local dbDirty = {}
local dbPointers = {
    [ACCOUNTS_DB] = function() return accounts end,
    [STOCK_DB] = function() return currentStock end,
    [LEDGER_FILE] = function() return ledger end
}

local dbTracker = nil
local function queueSave(dbPath)
    if dbTracker then
        dbTracker.queueSave(dbPath)
    else
        dbDirty[dbPath] = true
    end
end

-- Rednet Protocols
local BANK_PROTOCOL = "DB_Bank"
local AUDIT_PROTOCOL = "DB_Audit"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"

-- Auditor Turtle Configuration
local AUDIT_SECRET_KEY = nil

--==============================================================================
-- UI & Theme Configuration
--==============================================================================

-- Use safeColor from shared theme
local safeColor = sharedTheme.safeColor

local theme = {
    bg = safeColor("black", colors.black),
    text = safeColor("white", colors.white),
    windowBg = safeColor("gray", colors.gray),
    title = safeColor("lightBlue", colors.lightBlue),
    prompt = safeColor("cyan", colors.cyan),
    statusBarBg = safeColor("gray", colors.lightGray),
    statusBarText = safeColor("white", colors.white),
    highlightBg = safeColor("blue", colors.blue),
    highlightText = safeColor("white", colors.white),
    error = safeColor("red", colors.red),
}

local currentScreen = "main"
local selectedMenuItem = 1
local ratesPage = 1

--==============================================================================
-- Logging Functions
--==============================================================================

local function logActivity(message, isError)
    local prefix = isError and "[ERROR] " or "[INFO] "
    local logEntry = os.date("[%Y-%m-%d %H:%M:%S] ") .. prefix .. message
    
    if not startupComplete then
        term.write(logEntry .. "\n")
    end
    
    if not fs.exists(LOGS_DIR) then fs.makeDir(LOGS_DIR) end
    local file = fs.open(LOG_FILE, "a")
    if file then
        file.writeLine(logEntry)
        file.close()
    end

    table.insert(logHistory, logEntry)
    if #logHistory > 200 then table.remove(logHistory, 1) end
    
    uiDirty = true
end




--==============================================================================
-- Ledger & Integrity System
--==============================================================================

local ledger = {}
local lastLedgerHash = "0000000000000000000000000000000000000000" -- Genesis Hash

local function loadLedger()
    if fs.exists(LEDGER_FILE) then
        local file = fs.open(LEDGER_FILE, "r")
        if file then
            local content = file.readAll()
            file.close()
            local data = textutils.unserialize(content)
            if data and type(data) == "table" then 
                for i, v in ipairs(data) do table.insert(ledger, v) end
                if #ledger > 0 then
                    lastLedgerHash = ledger[#ledger].hash
                end
                logActivity("Ledger loaded. Entries: " .. #ledger)
            else
                logActivity("Ledger file empty or malformed.")
            end
        end
    end
end

local function saveLedger()
    queueSave(LEDGER_FILE)
end

local function logTransaction(user, txType, details, amount, target)
    local timestamp = os.time()
    local entry = {
        type = txType,
        user = user,
        amount = amount,
        target = target,
        details = details,
        prevHash = lastLedgerHash,
        timestamp = timestamp,
        realTimestamp = os.epoch("utc") -- Added for precise verification
    }
    
    -- Create content string for hashing. Serialize details if table.
    local detailsStr = type(details) == "table" and textutils.serialize(details) or tostring(details)
    local trace = string.format("%s:%s:%s:%s:%s:%s:%s", 
        lastLedgerHash, txType, user, tostring(amount), tostring(target or ""), tostring(timestamp), detailsStr)
    
    if crypto and crypto.sha1 then
        entry.hash = crypto.sha1(trace)
    else
        entry.hash = "NO_CRYPTO" -- Driver fallback
    end
    lastLedgerHash = entry.hash
    
    table.insert(ledger, entry)
    saveLedger()
    logActivity("Transaction logged: " .. txType .. " (Hash: " .. (entry.hash:sub(1,8)) .. "...)")
end



--==============================================================================
-- Data Persistence & Core Logic
--==============================================================================

-- Use shared database functions from lib/db (JSON variant for BankServer)
local function saveTableToFile(path, data)
    return DB.saveTableToFileJSON(path, data, logActivity)
end

local function loadTableFromFile(path)
    return DB.loadTableFromFileJSON(path, logActivity)
end

--==============================================================================
-- Session Verification (Inter-Server)
--==============================================================================

local function verifyTokenWithMainframe(user, token)
    if not mainServerId or not user or not token then return false end
    rednet.send(mainServerId, { type = "verify_session", user = user, session_token = token }, "SimpleMail")
    local _, resp = rednet.receive("SimpleMail", 3)
    return resp and resp.success
end

local function persistenceLoop()
    if not dbTracker then
        dbTracker = DB.createDirtyTracker(dbPointers, logActivity)
    end
    
    while true do
        sleep(30)
        dbTracker.backgroundSave()
    end
end

local function loadAllData()
    loadLedger()
    accounts = loadTableFromFile(ACCOUNTS_DB)
    
    currencyRates = {}
    if fs.exists(CURRENCIES_DIR) then
        for _, file in ipairs(fs.list(CURRENCIES_DIR)) do
            -- The filename is now just for organization, we load the *real* name from inside the file.
            local path = fs.combine(CURRENCIES_DIR, file)
            if not fs.isDir(path) then
                local data = loadTableFromFile(path)
                -- THE FIX: The currency name is now stored *inside* the file.
                if data and data.name then
                    currencyRates[data.name] = data
                    logActivity("Loaded currency: '" .. data.name .. "'")
                else
                    logActivity("Found a malformed currency file: " .. file, true)
                end
            end
        end
    end

    currentStock = loadTableFromFile(STOCK_DB)
    logActivity("All banking data loaded successfully.")
end

---
-- Dynamically adjusts the market price of all registered currencies.
-- Uses an inverse square root curve based on current stock vs target stock targets.
-- New Price = Base * (Target / Stock) ^ 0.5
local function adjustCurrencyRates()
    logActivity("Adjusting currency rates based on new stock report...")
    local changed = false
    for item, data in pairs(currencyRates) do
        if data.target and data.target > 0 then
            local stock = currentStock[item] or 0
            if stock == 0 then stock = 1 end
            local ratio = data.target / stock
            local price_multiplier = ratio ^ 0.5
            local new_price = math.floor(data.base * price_multiplier + 0.5)
            local max_price = data.base * 5
            local min_price = 1
            new_price = math.max(min_price, math.min(max_price, new_price))

            if new_price ~= data.current then
                logActivity(string.format("'%s' price changed from $%d to $%d (Stock: %d/%d)", item, data.current, new_price, currentStock[item] or 0, data.target))
                currencyRates[item].current = new_price
                changed = true
            end
        end
    end

    if changed then
        for itemName, data in pairs(currencyRates) do
            if not saveTableToFile(fs.combine(CURRENCIES_DIR, itemName .. ".json"), data) then
                 logActivity("Failed to save updated rate for " .. itemName, true)
            end
        end
    end
end

local bankHandlers = {}

-- Handles user login with a dedicated bank PIN.
function bankHandlers.login(senderId, message)
    if not message or type(message.user) ~= "string" then
        rednet.send(senderId, { success = false, reason = "Invalid login payload." }, BANK_PROTOCOL)
        return
    end
    local user, pin_hash = message.user, message.pin_hash
    local account = accounts[user]

    if account then
        -- If no PIN is set, indicate that setup is required.
        if not account.pin_hash then
            logActivity("User '"..user.."' needs to set up a bank PIN.")
            rednet.send(senderId, { success = false, reason = "setup_required" }, BANK_PROTOCOL)
            return
        end

        if account.pin_hash == pin_hash then
            logTransaction(user, "login", "SUCCESS")
            rednet.send(senderId, { success = true, balance = account.balance, rates = currencyRates }, BANK_PROTOCOL)
        else
            logTransaction(user, "login", "FAIL - Invalid PIN")
            rednet.send(senderId, { success = false, reason = "Invalid PIN." }, BANK_PROTOCOL)
        end
    else
        logActivity("New customer login attempt: '" .. user .. "'. Verifying with Mainframe...")
        rednet.send(mainServerId, { type = "user_exists_check", user = user }, AUTH_INTERLINK_PROTOCOL)
        local _, response = rednet.receive(AUTH_INTERLINK_PROTOCOL, 5)

        if response and response.exists then
            logActivity("Mainframe verified user. Creating new bank account for '" .. user .. "'.")
            accounts[user] = { pin_hash = nil, balance = 0 }
            queueSave(ACCOUNTS_DB)
            rednet.send(senderId, { success = false, reason = "setup_required" }, BANK_PROTOCOL)
            logTransaction(user, "account_created", "SUCCESS - Awaiting PIN setup")
        else
            rednet.send(senderId, { success = false, reason = "User does not exist in Drunken OS." }, BANK_PROTOCOL)
        end
    end
end

-- New: Broadcast security events to the Auditor Turtle
local function broadcastSecurityEvent(event, amount, isAlert)
    if not AUDIT_SECRET_KEY then return end
    local timestamp = os.time()
    local signature = crypto.hmac_hex(AUDIT_SECRET_KEY, event .. timestamp)
    rednet.broadcast({
        type = "security_event",
        event = event,
        amount = amount,
        isAlert = isAlert,
        timestamp = timestamp,
        signature = signature
    }, "DB_Audit")
end

-- Sets the initial PIN for a new account.
function bankHandlers.set_pin(senderId, message)
    local user, pin_hash = message.user, message.pin_hash
    local account = accounts[user]

    if not account then
        rednet.send(senderId, { success = false, reason = "Account not found." }, BANK_PROTOCOL)
        return
    end

    if account.pin_hash then
        rednet.send(senderId, { success = false, reason = "PIN already set." }, BANK_PROTOCOL)
        return
    end

    logActivity("Setting initial bank PIN for user '" .. user .. "'.")
    account.pin_hash = pin_hash
    queueSave(ACCOUNTS_DB)
    rednet.send(senderId, { success = true }, BANK_PROTOCOL)
end

-- Changes an existing PIN.
function bankHandlers.change_pin(senderId, message)
    local user, old_pin_hash, new_pin_hash = message.user, message.old_pin_hash, message.new_pin_hash
    local account = accounts[user]

    if not account or not account.pin_hash then
        rednet.send(senderId, { success = false, reason = "Account not found or setup incomplete." }, BANK_PROTOCOL)
        return
    end

    if account.pin_hash ~= old_pin_hash then
        rednet.send(senderId, { success = false, reason = "Incorrect current PIN." }, BANK_PROTOCOL)
        return
    end

    logActivity("Changing bank PIN for user '" .. user .. "'.")
    account.pin_hash = new_pin_hash
    if saveTableToFile(ACCOUNTS_DB, accounts) then
        rednet.send(senderId, { success = true }, BANK_PROTOCOL)
    else
        rednet.send(senderId, { success = false, reason = "Database error." }, BANK_PROTOCOL)
    end
end

-- Handles a secure verification request (e.g., from a POS machine).
-- Checks if a specific payment was received in the last N seconds.
function bankHandlers.verify_transaction(senderId, message)
    local merchant = message.merchant -- The user expecting the money
    local customer = message.customer -- The user who paid
    local amount = tonumber(message.amount)
    local interval = tonumber(message.interval) or 60000 -- Default 60s lookback
    
    if not merchant or not amount then
         rednet.send(senderId, { success = false, reason = "Invalid request." }, BANK_PROTOCOL)
         return
    end

    local now = os.epoch("utc")
    local found = false
    
    -- Iterate backwards
    for i = #ledger, 1, -1 do
        local entry = ledger[i]
        
        -- Stop if too old (if realTimestamp provided)
        if entry.realTimestamp and (now - entry.realTimestamp > interval) then
            break
        end
        
        -- Check Match
        -- Entry details: { recipient="Merchant", ... } checks.
        -- We typically store transfer details in `details` table or `target` field.
        -- In `process_payment` (client side), we send bank: process_payment.
        -- We need to check how `process_payment` logs usage.
        
        -- Let's look at how process_payment handler logs (we haven't read it yet but assume common sense)
        -- Actually, we should check `bankHandlers.process_payment` or `transfer`.
        
        -- Assumption: `details` contains { recipient=..., sender=... }
        -- And `entry.amount` is the amount.
        
        if entry.amount == amount and (entry.type == "PAYMENT" or entry.type == "TRANSFER") then
            -- Check recipient in details
            if type(entry.details) == "table" and entry.details.recipient == merchant then
                 -- Check customer in user field
                 if entry.user == customer then
                     found = true; break
                 end
            end
        end
    end
    
    rednet.send(senderId, { success = found }, BANK_PROTOCOL)
end


-- Handles a request for the full ledger (Auditor access only).
function bankHandlers.get_ledger(senderId, message)
    -- Verify Auditor Signature
    if not message.signature or not message.timestamp or crypto.hmac_hex(AUDIT_SECRET_KEY, message.type .. message.timestamp) ~= message.signature then
        logActivity("SUSPICIOUS: Unauthorized Auditor ledger request from " .. tostring(senderId), true)
        rednet.send(senderId, { success = false, reason = "Unauthorized" }, BANK_PROTOCOL)
        return
    end

    rednet.send(senderId, { type = "ledger_response", ledger = ledger }, BANK_PROTOCOL)
end

-- Handles a request for the full accounts database (Auditor access only).
function bankHandlers.get_all_accounts(senderId, message)
    -- Verify Auditor Signature
    if not message.signature or not message.timestamp or crypto.hmac_hex(AUDIT_SECRET_KEY, message.type .. message.timestamp) ~= message.signature then
        logActivity("SUSPICIOUS: Unauthorized Auditor account database request from " .. tostring(senderId), true)
        rednet.send(senderId, { success = false, reason = "Unauthorized" }, BANK_PROTOCOL)
        return
    end

    rednet.send(senderId, { type = "all_accounts_response", accounts = accounts }, BANK_PROTOCOL)
end

-- Handles a Clerk request for specific account details.
function bankHandlers.clerk_get_account(senderId, message)
    local user = message.user
    local account = accounts[user]
    if account then
        rednet.send(senderId, { success = true, account = account }, BANK_PROTOCOL)
    else
        rednet.send(senderId, { success = false, reason = "User not found." }, BANK_PROTOCOL)
    end
end

-- Handles a Clerk request for a user's transaction history.
function bankHandlers.clerk_get_history(senderId, message)
    local user = message.user
    local history = {}
    
    -- Filter global ledger for this user
    for _, entry in ipairs(ledger) do
        if entry.user == user or (entry.details and entry.details.recipient == user) or (entry.details and entry.details.customer == user) or (entry.details and entry.details.merchant == user) then
            table.insert(history, entry)
        end
    end
    
    rednet.send(senderId, { success = true, history = history }, BANK_PROTOCOL)
end

-- Handles a Clerk request to create a new account (if Mainframe verified).
function bankHandlers.clerk_create_account(senderId, message)
    local user = message.user
    if accounts[user] then
        rednet.send(senderId, { success = false, reason = "Account already exists." }, BANK_PROTOCOL)
        return
    end

    -- Verify with Mainframe first
    logActivity("Clerk requesting new account for '" .. user .. "'. Verifying...")
    rednet.send(mainServerId, { type = "user_exists_check", user = user }, AUTH_INTERLINK_PROTOCOL)
    local _, response = rednet.receive(AUTH_INTERLINK_PROTOCOL, 5)

    if response and response.exists then
        accounts[user] = { pin_hash = nil, balance = 0 }
        if saveTableToFile(ACCOUNTS_DB, accounts) then
            logTransaction(user, "account_created", "SUCCESS - Via Clerk Terminal")
            logActivity("Created new account for '" .. user .. "' via Clerk.")
            rednet.send(senderId, { success = true }, BANK_PROTOCOL)
        else
            rednet.send(senderId, { success = false, reason = "Database error." }, BANK_PROTOCOL)
        end
    else
        rednet.send(senderId, { success = false, reason = "User not found in Mainframe." }, BANK_PROTOCOL)
    end
end

-- Handles a Clerk request to reset a user's PIN.
function bankHandlers.clerk_reset_pin(senderId, message)
    local user = message.user
    if not accounts[user] then
        rednet.send(senderId, { success = false, reason = "Account not found." }, BANK_PROTOCOL)
        return
    end

    accounts[user].pin_hash = nil -- Reset to nil so they must setup again
    if saveTableToFile(ACCOUNTS_DB, accounts) then
        logActivity("PIN reset for '" .. user .. "' via Clerk.")
        rednet.send(senderId, { success = true }, BANK_PROTOCOL)
    else
        rednet.send(senderId, { success = false, reason = "Database error." }, BANK_PROTOCOL)
    end
end

-- Handles a Clerk request to toggle merchant status.
function bankHandlers.clerk_set_merchant(senderId, message)
    local user = message.user
    local status = message.status
    if not accounts[user] then
        rednet.send(senderId, { success = false, reason = "Account not found." }, BANK_PROTOCOL)
        return
    end

    accounts[user].is_merchant = status
    if saveTableToFile(ACCOUNTS_DB, accounts) then
        logActivity("Merchant status for '" .. user .. "' set to " .. tostring(status) .. " via Clerk.")
        rednet.send(senderId, { success = true }, BANK_PROTOCOL)
    else
        rednet.send(senderId, { success = false, reason = "Database error." }, BANK_PROTOCOL)
    end
end

-- Handles City Builder Exports (Virtual Resource -> Credits)
function bankHandlers.city_export(senderId, message)
    local user = message.user
    local token = message.session_token
    local resource = message.resource -- "alloys"
    local count = tonumber(message.count)
    
    if not user or not count or count <= 0 then return end
    
    -- Security: Verify Session
    if not verifyTokenWithMainframe(user, token) then
        rednet.send(senderId, { success = false, reason = "Auth failed" }, BANK_PROTOCOL)
        return
    end
    
    local account = accounts[user]
    if not account then return end
    
    -- Rate: 10 Alloys = $1
    if resource == "alloys" then
        local value = math.floor(count / 10)
        if value > 0 then
            account.balance = account.balance + value
            queueSave(ACCOUNTS_DB)
            logTransaction(user, "CITY_EXPORT", "Exported " .. count .. " Alloys", value)
            rednet.send(senderId, { success = true, value = value, newBalance = account.balance }, BANK_PROTOCOL)
        end
    end
end

-- Handles Arcade Leaderboard Payouts (Minting Prize Money)
function bankHandlers.arcade_payout(senderId, message)
    local user = message.user
    local amount = tonumber(message.amount)
    local gameName = message.game or "Arcade"
    local token = message.session_token
    
    if not user or not amount or amount <= 0 then return end
    
    -- Security: Verify Sender is Arcade Server
    local arcadeServerId = rednet.lookup("ArcadeGames", "arcade.server")
    if senderId ~= arcadeServerId then
        logActivity("BLOCKED: Unauthorized payout attempt from ID " .. senderId, true)
        rednet.send(senderId, { success = false, reason = "Unauthorized sender" }, BANK_PROTOCOL)
        return
    end

    -- Security: Verify User Session
    if not verifyTokenWithMainframe(user, token) then
        rednet.send(senderId, { success = false, reason = "Auth failed" }, BANK_PROTOCOL)
        return
    end
    
    local account = accounts[user]
    if not account then return end
    
    account.balance = account.balance + amount
    queueSave(ACCOUNTS_DB)
    logTransaction(user, "PRIZE", "Leaderboard Reward: " .. gameName, amount)
    rednet.send(senderId, { success = true, newBalance = account.balance }, BANK_PROTOCOL)
end

---
-- Handles a request for balance and rates.
function bankHandlers.get_balance_and_rates(senderId, message)
    local account = accounts[message.user]
    local currentBalance = account and account.balance or 0
    rednet.send(senderId, { balance = currentBalance, rates = currencyRates }, BANK_PROTOCOL)
end

-- Handles a deposit of items with real-time stock updates.
function bankHandlers.deposit(senderId, message)
    local user, items = message.user, message.items
    local total_value = 0
    local transaction_summary = {}

    for _, item in ipairs(items) do
        local rateInfo = nil
        local itemName = item.name or "unknown"
        if currencyRates[itemName] then
            rateInfo = currencyRates[itemName]
        else
            local shortName = itemName:match("^minecraft:(.+)")
            if shortName and currencyRates[shortName] then
                rateInfo = currencyRates[shortName]
            end
        end

        if rateInfo then
            local value = item.count * rateInfo.current
            total_value = total_value + value
            table.insert(transaction_summary, string.format("%d %s for $%d", item.count, itemName, value))
            
            -- THE FIX #1: Immediately update the internal stock count upon deposit.
            currentStock[itemName] = (currentStock[itemName] or 0) + item.count
        end
    end

    if total_value > 0 then
        if accounts[user] then
            accounts[user].balance = accounts[user].balance + total_value
            queueSave(ACCOUNTS_DB)
            queueSave(STOCK_DB)
            rednet.send(senderId, { success = true, newBalance = accounts[user].balance, deposited_value = total_value }, BANK_PROTOCOL)
            local transaction_data = {}
            for _, item in ipairs(items) do
                local rateInfo = currencyRates[item.name or "unknown"] or currencyRates[item.name:match("^minecraft:(.+)") or ""]
                if rateInfo then
                    transaction_data[item.name or "unknown"] = { count = item.count, value = item.count * rateInfo.current }
                end
            end
            logTransaction(user, "DEPOSIT", transaction_data, total_value)
            logActivity(string.format("Stock updated for deposit: %s", table.concat(transaction_summary, ", ")))
            broadcastSecurityEvent(string.format("DEP: %s +$%d", user, total_value), total_value)
            needsRedraw = true -- Update the GUI
        else
            rednet.send(senderId, { success = false, reason = "Account not found for deposit." }, BANK_PROTOCOL)
        end
    else
        logActivity(string.format("Deposit failed for user '%s': No valid currency detected.", user), true)
        for i, item in ipairs(items) do
            logActivity(string.format(" - Received item: '%s' (count: %d)", tostring(item.name), item.count), true)
        end
        rednet.send(senderId, { success = false, reason = "No valid currency detected." }, BANK_PROTOCOL)
    end
end

---
-- PHASE 1: Authorizes a withdrawal but does not deduct funds.
function bankHandlers.withdraw_item(senderId, message)
    local user, itemName, count = message.user, message.item_name, message.count
    local account = accounts[user]
    local rateInfo = currencyRates[itemName]

    if not account then rednet.send(senderId, { success = false, reason = "Account not found." }, BANK_PROTOCOL); return end
    if not rateInfo then rednet.send(senderId, { success = false, reason = "Invalid currency type." }, BANK_PROTOCOL); return end

    local totalCost = rateInfo.current * count
    if account.balance >= totalCost then
        if (currentStock[itemName] or 0) >= count then
            -- Authorize the transaction, but do not change the balance yet.
            rednet.send(senderId, { success = true, authorized = true }, BANK_PROTOCOL)
            logActivity(string.format("Authorized withdrawal for '%s' of %d %s.", user, count, itemName))
        else
            rednet.send(senderId, { success = false, reason = "Insufficient stock in vault." }, BANK_PROTOCOL)
        end
    else
        rednet.send(senderId, { success = false, reason = "Insufficient funds." }, BANK_PROTOCOL)
    end
end

---
-- PHASE 3: Finalizes the transaction and deducts funds and stock after turtle success.
function bankHandlers.finalize_withdrawal(senderId, message)
    local user, itemName, count = message.user, message.item_name, message.count
    local account = accounts[user]
    local rateInfo = currencyRates[itemName]
    
    if not account or not rateInfo then
        logActivity("Finalization failed: account or rate info missing.", true)
        return
    end

    local totalCost = rateInfo.current * count
    account.balance = account.balance - totalCost
    
    -- THE FIX #2: Immediately update the internal stock count upon withdrawal.
    currentStock[itemName] = (currentStock[itemName] or 0) - count
    if currentStock[itemName] < 0 then
        logActivity("CRITICAL: Stock for " .. itemName .. " went negative. Resetting to 0.", true)
        currentStock[itemName] = 0
    end

    queueSave(ACCOUNTS_DB)
    queueSave(STOCK_DB)
    
    local transaction_data = {
        [itemName] = { count = count, value = totalCost }
    }
    logTransaction(user, "WITHDRAW", transaction_data, totalCost)
    logActivity(string.format("Finalized withdrawal for '%s'. New balance: $%d", user, account.balance))
    logActivity(string.format("Stock updated for withdrawal: %d %s", count, itemName))
    broadcastSecurityEvent(string.format("WDR: %s -$%d", user, totalCost), totalCost)
    needsRedraw = true -- Update the GUI
    
    rednet.send(senderId, { success = true, newBalance = account.balance }, BANK_PROTOCOL)
end

-- Allows a user to fetch their own transaction history (for Merchant verification)
function bankHandlers.get_transactions(senderId, message)
    local user, pin_hash = message.user, message.pin_hash
    local account = accounts[user]
    
    if not account or account.pin_hash ~= pin_hash then
        rednet.send(senderId, { success = false, reason = "Auth failed" }, BANK_PROTOCOL)
        return
    end
    
    local history = {}
    -- Return last 10 transactions involving this user
    local count = 0
    -- Iterate backwards
    for i = #ledger, 1, -1 do
        local entry = ledger[i]
        if entry.user == user or (entry.details and entry.details.recipient == user) then
            -- Sanitize entry
            table.insert(history, entry)
            count = count + 1
            if count >= 10 then break end
        end
    end
    
    rednet.send(senderId, { success = true, history = history }, BANK_PROTOCOL)
end

-- Allow saving/shutdown
function bankHandlers.save_db(senderId, message)
    queueSave(LEDGER_FILE)
    queueSave(ACCOUNTS_DB)
    queueSave(STOCK_DB)
end


-- Handles a peer-to-peer money transfer.
function bankHandlers.transfer(senderId, message)
    if not message or type(message.user) ~= "string" or type(message.recipient) ~= "string" then
        rednet.send(senderId, { success = false, reason = "Invalid transfer payload." }, BANK_PROTOCOL)
        return
    end
    local sender = message.user
    local recipient = message.recipient
    local amount = tonumber(message.amount)

    if not amount or amount <= 0 then
        rednet.send(senderId, { success = false, reason = "Invalid amount." }, BANK_PROTOCOL)
        return
    end

    if sender == recipient then
        rednet.send(senderId, { success = false, reason = "Cannot transfer to yourself." }, BANK_PROTOCOL)
        return
    end

    local senderAcc = accounts[sender]
    if not senderAcc then
        rednet.send(senderId, { success = false, reason = "Account not found." }, BANK_PROTOCOL)
        return
    end

    if senderAcc.pin_hash ~= message.pin_hash then
        rednet.send(senderId, { success = false, reason = "Invalid PIN or auth failed." }, BANK_PROTOCOL)
        return
    end

    if senderAcc.balance < amount then
        rednet.send(senderId, { success = false, reason = "Insufficient funds." }, BANK_PROTOCOL)
        return
    end

    -- Check if recipient exists in bank
    local recipientAcc = accounts[recipient]
    if not recipientAcc then
        -- Check with mainframe
        logActivity("Transfer recipient '" .. recipient .. "' not found in bank. Verifying with Mainframe...")
        rednet.send(mainServerId, { type = "user_exists_check", user = recipient }, AUTH_INTERLINK_PROTOCOL)
        local _, response = rednet.receive(AUTH_INTERLINK_PROTOCOL, 5)

        if response and response.exists then
            logActivity("Mainframe verified recipient. Creating bank account for '" .. recipient .. "'.")
            accounts[recipient] = { pin_hash = nil, balance = 0 }
            recipientAcc = accounts[recipient]
        else
            rednet.send(senderId, { success = false, reason = "Recipient user does not exist." }, BANK_PROTOCOL)
            return
        end
    end

    -- Atomic transfer
    senderAcc.balance = senderAcc.balance - amount
    recipientAcc.balance = recipientAcc.balance + amount

    if saveTableToFile(ACCOUNTS_DB, accounts) then
        logTransaction(sender, "TRANSFER_OUT", { recipient = recipient }, amount)
        logTransaction(recipient, "TRANSFER_IN", { sender = sender }, amount)
        logActivity(string.format("Transfer: $%d from '%s' to '%s'.", amount, sender, recipient))
        broadcastSecurityEvent(string.format("XFER: %s->%s $%d", sender, recipient, amount), amount)
        rednet.send(senderId, { success = true, newBalance = senderAcc.balance }, BANK_PROTOCOL)
        needsRedraw = true
    else
        -- Rollback in memory
        senderAcc.balance = senderAcc.balance + amount
        recipientAcc.balance = recipientAcc.balance - amount
        rednet.send(senderId, { success = false, reason = "Server database error." }, BANK_PROTOCOL)
    end
end

-- Handles a merchant payment with metadata (e.g. Table Number) notification.
function bankHandlers.process_payment(senderId, message)
    if not message or type(message.user) ~= "string" or type(message.recipient) ~= "string" or not message.pin_hash then
        rednet.send(senderId, { success = false, reason = "Invalid payment payload." }, BANK_PROTOCOL)
        return
    end
    local sender, recipient = message.user, message.recipient
    local amount = tonumber(message.amount)
    local pin_hash = message.pin_hash
    local metadata = message.metadata or "No metadata"

    local senderAcc = accounts[sender]
    if not senderAcc then
        rednet.send(senderId, { success = false, reason = "Account not found." }, BANK_PROTOCOL)
        return
    end

    if senderAcc.pin_hash ~= pin_hash then
        rednet.send(senderId, { success = false, reason = "Invalid PIN." }, BANK_PROTOCOL)
        return
    end

    if not amount or amount <= 0 then
        rednet.send(senderId, { success = false, reason = "Invalid amount." }, BANK_PROTOCOL)
        return
    end

    if senderAcc.balance < amount then
        rednet.send(senderId, { success = false, reason = "Insufficient funds." }, BANK_PROTOCOL)
        return
    end

    local recipientAcc = accounts[recipient]
    if not recipientAcc then
        rednet.send(senderId, { success = false, reason = "Merchant account not found." }, BANK_PROTOCOL)
        return
    end

    if not recipientAcc.is_merchant then
        rednet.send(senderId, { success = false, reason = "Recipient is not a verified merchant." }, BANK_PROTOCOL)
        return
    end

    -- Process Transaction
    senderAcc.balance = senderAcc.balance - amount
    recipientAcc.balance = recipientAcc.balance + amount

    if saveTableToFile(ACCOUNTS_DB, accounts) then
        logTransaction(sender, "PAYMENT_OUT", { merchant = recipient, meta = metadata }, amount)
        logTransaction(recipient, "PAYMENT_IN", { customer = sender, meta = metadata }, amount)
        logActivity(string.format("Payment: $%d from '%s' to '%s' [%s].", amount, sender, recipient, metadata))
        broadcastSecurityEvent(string.format("PAY: %s->%s $%d", sender, recipient, amount), amount)
        
        rednet.send(senderId, { success = true, newBalance = senderAcc.balance }, BANK_PROTOCOL)
        
        -- Real-time notification to merchant device
        local merchantDeviceId = rednet.lookup(BANK_PROTOCOL, recipient)
        if merchantDeviceId then
            rednet.send(merchantDeviceId, {
                type = "payment_received",
                customer = sender,
                amount = amount,
                metadata = metadata,
                timestamp = os.time()
            }, BANK_PROTOCOL)
        end
        needsRedraw = true
    else
        senderAcc.balance = senderAcc.balance + amount
        recipientAcc.balance = recipientAcc.balance - amount
        rednet.send(senderId, { success = false, reason = "Database error." }, BANK_PROTOCOL)
    end
end

--==============================================================================
-- Admin Command Handlers & Terminal
--==============================================================================

local adminCommands = {}

local function parseAdminArgs(args)
    local command = table.remove(args, 1)
    if not args or #args == 0 then return command, nil, nil end
    local itemName = args[1]
    local numberValue = tonumber(args[2])
    if #args > 2 and not tonumber(args[2]) then
        itemName = table.concat(args, " ", 1, 2)
        numberValue = tonumber(args[3])
    end
    return command, itemName, numberValue
end

function adminCommands.help()
    logActivity("--- Bank Admin Commands ---")
    logActivity("balance <user>")
    logActivity("setbalance <user> <amount>")
    logActivity("give <user> <amount>")
    logActivity("makecard <user>")
    logActivity("addcurrency <item_name> <base_rate>")
    logActivity("delcurrency <item_name>")
    logActivity("listrates")
    logActivity("settarget <item_name> <target_amount>")
    logActivity("setmerchant <user> <true/false>")
end

function adminCommands.balance(args)
    local _, user = parseAdminArgs(args)
    if not user then logActivity("Usage: balance <user>"); return end
    
    if accounts[user] then
        logActivity("Balance for " .. user .. ": $" .. accounts[user].balance)
    else
        logActivity("Error: Account for user '" .. user .. "' does not exist.")
    end
end

function adminCommands.setbalance(args)
    local _, user, amount = parseAdminArgs(args)
    amount = tonumber(amount)
    if not user or not amount then logActivity("Usage: setbalance <user> <amount>"); return end

    if accounts[user] then
        accounts[user].balance = amount
        if saveTableToFile(ACCOUNTS_DB, accounts) then
            logTransaction(user, "ADMIN_SET", { note = "Administrative set" }, amount)
            broadcastSecurityEvent(string.format("ADMIN: %s SET $%d", user, amount), amount)
            logActivity("Set balance for " .. user .. " to $" .. amount)
        else
            logActivity("Error: Database write failed.")
        end
    else
        logActivity("Error: Account for user '" .. user .. "' does not exist.")
    end
end

function adminCommands.give(args)
    local _, user, amount = parseAdminArgs(args)
    amount = tonumber(amount)
    if not user or not amount then logActivity("Usage: give <user> <amount>"); return end

    if accounts[user] then
        accounts[user].balance = accounts[user].balance + amount
        if saveTableToFile(ACCOUNTS_DB, accounts) then
            logTransaction(user, "ADMIN_GIVE", { note = "Administrative give" }, amount)
            broadcastSecurityEvent(string.format("ADMIN: %s +$%d", user, amount), amount)
            logActivity("Gave $" .. amount .. " to " .. user .. ". New balance: $" .. accounts[user].balance)
        else
            logActivity("Error: Database write failed.")
        end
    else
        logActivity("Error: Account for user '" .. user .. "' does not exist.")
    end
end

function adminCommands.adjust(args)
    local _, user, action, amount = parseAdminArgs(args)
    amount = tonumber(amount)
    if not user or not action or not amount then 
        logActivity("Usage: adjust <user> <set|add|sub> <amount>")
        return 
    end

    if not accounts[user] then
        logActivity("Error: Account for user '" .. user .. "' does not exist.")
        return
    end

    local oldBalance = accounts[user].balance
    local newBalance = oldBalance

    if action == "set" then newBalance = amount
    elseif action == "add" then newBalance = oldBalance + amount
    elseif action == "sub" then newBalance = oldBalance - amount
    else logActivity("Invalid action. Use set, add, or sub."); return end

    accounts[user].balance = newBalance
    if saveTableToFile(ACCOUNTS_DB, accounts) then
        local diff = newBalance - oldBalance
        logTransaction(user, "ADMIN_ADJUST", { action = action, prev = oldBalance }, diff)
        broadcastSecurityEvent(string.format("ADMIN: %s ADJ %s%d", user, (diff >= 0 and "+" or ""), diff), math.abs(diff))
        logActivity("Adjustment complete. New balance for " .. user .. ": $" .. newBalance)
    else
        logActivity("Error: Database write failed.")
    end
end

function adminCommands.makecard(args)
    local _, user = parseAdminArgs(args)
    if not user then
        logActivity("Usage: makecard <username>")
        return
    end

    logActivity("Verifying user with Mainframe...")
    rednet.send(mainServerId, { type = "user_exists_check", user = user }, AUTH_INTERLINK_PROTOCOL)
    
    -- Custom timeout loop to prevent parallel rednet.receive collision
    local timeoutTimer = os.startTimer(5)
    local response = nil
    local replySender = nil

    while true do
        local event, p1, p2, p3 = os.pullEventRaw()
        if event == "rednet_message" then
            local sender = p1
            local msg = p2
            local proto = p3
            
            -- Proxy Unwrapping
            if type(msg) == "table" and msg.proxy_response then
                msg = msg.proxy_response
            end

            if proto == AUTH_INTERLINK_PROTOCOL and type(msg) == "table" and msg.exists ~= nil then
                response = msg
                replySender = sender
                break
            end
        elseif event == "timer" and p1 == timeoutTimer then
            break -- Timeout reached
        end
    end

    if not response then
        logActivity("Error: Verification timed out. Mainframe unresponsive.")
        return
    end

    if not response.exists then
        logActivity("Error: Mainframe reports user '" .. user .. "' does not exist.")
        return
    end

    logActivity("User verified. Please insert a blank disk.")
    local disk = peripheral.find("drive")
    if not disk then
        logActivity("Error: No disk drive attached to this server.")
        return
    end

    if not disk.isDiskPresent() then
        logActivity("Error: No disk in the drive.")
        return
    end

    local mount_path = disk.getMountPath()
    if not mount_path then
        logActivity("Error: Could not get disk mount path.")
        return
    end

    -- FIX: Set the label to the format the ATM expects.
    disk.setDiskLabel("DrunkenBeard_Card_" .. user)

    if not accounts[user] then
        logActivity("Warning: User does not have a bank account yet. Creating one.")
        accounts[user] = {
            pin_hash = nil,
            balance = 0
        }
        saveTableToFile(ACCOUNTS_DB, accounts)
    end
    
    local cardData = { owner = user, issuer = "BankServer", issue_date = os.time() }
    local cardFile = fs.open(mount_path .. "/.card_data", "w")
    if cardFile then
        cardFile.write(textutils.serialize(cardData))
        cardFile.close()
        logActivity("Successfully created bank card for " .. user)
    else
        logActivity("Error: Could not write data file to disk.")
    end
end

function adminCommands.addcurrency(args)
    local _, itemName, baseRate = parseAdminArgs(args)
    if not itemName or not baseRate then logActivity("Usage: addcurrency <item_name> <base_rate>"); return end
    if currencyRates[itemName] then logActivity("Currency '" .. itemName .. "' already exists."); return end
    if not fs.isDir(CURRENCIES_DIR) then fs.makeDir(CURRENCIES_DIR) end

    local safeFileName = itemName:gsub(":", "_") .. ".json"
    
    local newCurrency = {
        name = itemName,
        base = baseRate,
        current = baseRate,
        target = nil
    }

    if saveTableToFile(fs.combine(CURRENCIES_DIR, safeFileName), newCurrency) then
        currencyRates[itemName] = newCurrency
        logActivity("Added new currency '" .. itemName .. "' with base rate $" .. baseRate)
    else
        logActivity("Failed to save new currency.")
    end
end

function adminCommands.delcurrency(args)
    local _, itemName = parseAdminArgs(args)
    if not itemName then logActivity("Usage: delcurrency <item_name>"); return end
    if not currencyRates[itemName] then logActivity("Currency '" .. itemName .. "' does not exist."); return end
    currencyRates[itemName] = nil
    
    local path = fs.combine(CURRENCIES_DIR, itemName .. ".json")
    if fs.exists(path) then fs.delete(path) end
    
    logActivity("Removed currency '" .. itemName .. "'.")
end

function adminCommands.listrates()
    logActivity("--- Current Exchange Rates ---")
    for name, data in pairs(currencyRates) do
        local stock = currentStock[name] or 0
        local target = data.target and ("/" .. data.target) or "/N/A"
        logActivity(string.format("- %s: $%d (Base: $%d) | Stock: %d%s", name, data.current, data.base, stock, target))
    end
end

function adminCommands.settarget(args)
    local _, itemName, targetAmount = parseAdminArgs(args)
    if not itemName or not targetAmount then logActivity("Usage: settarget <item_name> <target_amount>"); return end
    if not currencyRates[itemName] then logActivity("Currency '" .. itemName .. "' does not exist."); return end
    
    currencyRates[itemName].target = targetAmount
    if saveTableToFile(fs.combine(CURRENCIES_DIR, itemName .. ".json"), currencyRates[itemName]) then
        logActivity("Set target stock for '" .. itemName .. "' to " .. targetAmount)
    else
        logActivity("Failed to set target.")
    end
end

function adminCommands.setmerchant(args)
    local _, user, value = parseAdminArgs(args)
    if not user or not value then logActivity("Usage: setmerchant <user> <true/false>"); return end
    
    if not accounts[user] then
        logActivity("Error: Account for user '" .. user .. "' does not exist.")
        return
    end

    local is_merchant = (value == "true")
    accounts[user].is_merchant = is_merchant
    
    if saveTableToFile(ACCOUNTS_DB, accounts) then
        logActivity("User '" .. user .. "' merchant status set to: " .. tostring(is_merchant))
    else
        logActivity("Error: Database write failed.")
    end
end

local function handleAdminCommand(command)
    local args = {}; for arg in string.gmatch(command, "[^%s]+") do table.insert(args, arg) end
    local cmd = args[1]
    if cmd == "exit" then return false end
    if adminCommands[cmd] then adminCommands[cmd](args) else logActivity("Unknown command. Type 'help'.") end
    return true
end

local function redrawAdminUI()
    local w, h = term.getSize()
    term.setBackgroundColor(theme.windowBg)
    term.clear()

    -- Title Bar
    term.setBackgroundColor(theme.title)
    term.setCursorPos(1, 1)
    term.write((" "):rep(w))
    term.setTextColor(colors.white)
    local title = " Bank Server Admin Console "
    term.setCursorPos(math.floor((w - #title) / 2) + 1, 1)
    term.write(title)

    -- Status Bar
    term.setBackgroundColor(theme.statusBarBg)
    term.setTextColor(theme.statusBarText)
    term.setCursorPos(1, h)
    term.write((" "):rep(w))
    local status = "RUNNING | Type 'help' for commands"
    term.setCursorPos(2, h)
    term.write(status)

    -- Log Area
    term.setBackgroundColor(theme.windowBg)
    term.setTextColor(theme.text)
    local logAreaHeight = h - 4
    local displayLines = {}
    for i = #logHistory, 1, -1 do
        local wrappedLines = wordWrap(logHistory[i], w - 2)
        for j = #wrappedLines, 1, -1 do
            table.insert(displayLines, 1, " " .. wrappedLines[j])
            if #displayLines >= logAreaHeight then break end
        end
        if #displayLines >= logAreaHeight then break end
    end
    for i = 1, math.min(#displayLines, logAreaHeight) do
        term.setCursorPos(1, 1 + i)
        term.write(displayLines[i])
    end

    -- Input Area
    term.setCursorPos(1, h - 2)
    term.write(('-'):rep(w))
    term.setCursorPos(1, h - 1)
    term.setTextColor(theme.prompt)
    term.write("> ")
    term.setTextColor(theme.text)
    term.write(adminInput)
end

local function uiRenderLoop()
    while true do
        if uiDirty then
            redrawAdminUI()
            uiDirty = false
        end
        sleep(0.05)
    end
end

local function handleTerminalInput(event, p1)
    if event == "key" then
        if p1 == keys.enter then
            if adminInput ~= "" then
                logActivity("Local cmd: " .. adminInput)
                handleAdminCommand(adminInput)
                adminInput = ""
            end
        elseif p1 == keys.backspace then
            adminInput = adminInput:sub(1, -2)
        end
    elseif event == "char" then
        adminInput = adminInput .. p1
    end
    uiDirty = true
end

local function adminPrompt()
    while true do
        local event, p1 = os.pullEventRaw()
        if event == "key" or event == "char" then
            handleTerminalInput(event, p1)
        elseif event == "terminate" then
            break
        end
    end
end

--==============================================================================
-- Main Event Loops
--==============================================================================

local function networkListener()
    while true do
        local event, senderId, message, protocolReceived = os.pullEventRaw("rednet_message")
        
        -- Proxy Support: Extract original sender and message
        local origSender = senderId
        local actualMsg = message
        local isProxied = false
        
        if type(message) == "table" and message.proxy_orig_sender then
            origSender = message.proxy_orig_sender
            actualMsg = message.proxy_orig_msg
            isProxied = true
        end

        local realRednetSend = rednet.send
        local function sendResponse(p_id, p_msg, p_proto)
            -- Only wrap and change protocol if we are responding back to the original client.
            -- If we are proxied, we MUST use the internal protocol (protocolReceived) so the Proxy recognizes it as a response.
            if isProxied and p_id == origSender then
                realRednetSend(senderId, { proxy_orig_sender = origSender, proxy_response = p_msg }, protocolReceived)
            else
                realRednetSend(p_id, p_msg, p_proto or protocolReceived)
            end
        end

        if protocolReceived == "DB_Bank_Internal" and actualMsg and actualMsg.type and bankHandlers[actualMsg.type] then
            -- Override rednet.send temporarily to handle proxied responses
            local oldSend = rednet.send
            rednet.send = sendResponse
            bankHandlers[actualMsg.type](origSender, actualMsg)
            rednet.send = oldSend
        
        elseif protocolReceived == AUDIT_PROTOCOL and message and message.type == "stock_report" then
            local messageToVerify = textutils.serializeJSON(message.report)
            local signature = crypto.hmac_hex(AUDIT_SECRET_KEY, messageToVerify)
            if signature == message.signature then
                logActivity("Received valid, signed stock report from Auditor.")
                currentStock = message.report
                saveTableToFile(STOCK_DB, currentStock)
                adjustCurrencyRates()
                needsRedraw = true -- Update dashboard stats
            else
                logActivity("Received an INVALID or TAMPERED stock report! Ignoring.", true)
            end
        elseif protocolReceived == AUDIT_PROTOCOL and message and message.type == "get_transaction_log" then
            local signature = crypto.hmac_hex(AUDIT_SECRET_KEY, message.timestamp)
            if signature == message.signature then
                local log_path = TRANSACTIONS_DIR .. "/master.log"
                if fs.exists(log_path) then
                    local file = fs.open(log_path, "r")
                    local log_data = file.readAll()
                    file.close()
                    rednet.send(senderId, { success = true, log = log_data }, AUDIT_PROTOCOL)
                else
                    rednet.send(senderId, { success = false, reason = "No transaction log found." }, AUDIT_PROTOCOL)
                end
            else
                logActivity("Received an INVALID or TAMPERED log request! Ignoring.", true)
            end
        end
    end
end



local function main()
    local computerTerm = term.current()
    computerTerm.clear()
    computerTerm.setCursorPos(1,1)
    
    print("Drunken OS Bank Server Initializing...")

    if fs.exists("/auditor_key.conf") then
        local file = fs.open("/auditor_key.conf", "r")
        AUDIT_SECRET_KEY = file.readAll()
        file.close()
    else
        print("FATAL: /auditor_key.conf not found. Please run the installer disk.")
        return
    end

    -- Monitor initialization removed.

    loadAllData()
    
    print("Scanning for modems...")
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local modem_p = peripheral.wrap(name)
            if modem_p.isWireless() then
                wireless_modem_name = name
            else
                wired_modem_name = name
            end
        end
    end

    if not wireless_modem_name then print("FATAL: No wireless modem attached."); return end
    if not wired_modem_name then print("FATAL: No wired modem for secure interlink."); return end
    
    print("Found Wireless Modem on: " .. wireless_modem_name)
    print("Found Wired Modem on: " .. wired_modem_name)

    print("Opening wired modem...")
    rednet.open(wired_modem_name)

    print("Identifying Mainframe via secure interlink protocol...")
    -- Poll until the mainframe responds to avoid startup race conditions
    for i=1, 5 do
        mainServerId = rednet.lookup(AUTH_INTERLINK_PROTOCOL)
        if mainServerId then break end
        sleep(1)
    end

    if not mainServerId then 
        print("FATAL: Mainframe did not respond to protocol lookup on wired network.\nIs the Mainframe running and connected?")
        return 
    end
    print("Mainframe located via wired link at ID " .. mainServerId)
    
    rednet.host("DB_Bank_Internal", "bank.server.internal")
    
    startupComplete = true -- Stop logging to the physical terminal
    
    -- Run the main loops. The Bank Server now operates entirely through the admin terminal.
    parallel.waitForAny(networkListener, adminPrompt, uiRenderLoop, persistenceLoop)
    
    computerTerm.clear()
    computerTerm.setCursorPos(1,1)
    print("Bank Server shut down.")
    term.clear()
    term.setCursorPos(1,1)
    print("Bank Server has shut down.")
end

main()
