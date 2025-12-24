--[[
    Drunken Beard Bank - Auditor Turtle (v3.0 - Integrity Sentinel)
    by MuhendizBey

    Purpose:
    Real-time security monitor for the digital bank. 
    Periocially verifies the cryptographic integrity of the bank's ledger
    and ensures no unauthorized database modifications have occurred.
]]

--==============================================================================
-- API & Library Initialization
--==============================================================================

local version = 3.0
local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path

local function safeRequire(mod)
    local ok, res = pcall(require, mod)
    return ok and res or nil
end

local crypto = safeRequire("lib.sha1_hmac") or safeRequire("sha1_hmac")
local updater = safeRequire("lib.updater") or safeRequire("updater")

if not crypto then
    term.clear()
    print("Error: Missing library 'lib/sha1_hmac.lua'")
    return
end

--==============================================================================
-- Configuration
--==============================================================================

local AUDIT_PROTOCOL = "DB_Audit"
local BANK_PROTOCOL = "DB_Bank"
local SECRET_KEY = nil
local alerts = {}
local max_alerts = 10
local bankServerId = nil

-- Display Abstraction
local display = term
local isMonitor = false

local function initDisplay()
    local monitor = peripheral.find("monitor")
    if monitor then
        display = monitor
        isMonitor = true
        monitor.setTextScale(0.5) -- Optional: allow more text on small monitors
    else
        display = term
        isMonitor = false
    end
    
    local w, h = display.getSize()
    max_alerts = h - 5
end

--==============================================================================
-- UI Functions
--==============================================================================

local function drawDashboard(status)
    display.setBackgroundColor(colors.black)
    display.clear()
    display.setCursorPos(1, 1)
    
    local w, h = display.getSize()
    max_alerts = h - 4

    if status == "BREACH" then
        display.setBackgroundColor(colors.red)
        display.setTextColor(colors.white)
        display.write(string.format(" %-s ", "!!! SECURITY BREACH DETECTED !!!"):sub(1, w))
    elseif status == "VERIFYING" then
        display.setBackgroundColor(colors.orange)
        display.setTextColor(colors.white)
        display.write(string.format(" %-s ", "   Verifying Ledger Integrity...   "):sub(1, w))
    else
        display.setBackgroundColor(colors.blue)
        display.setTextColor(colors.white)
        local title = " BANK SENTINEL v" .. version .. " - SECURE "
        display.write(string.format(" %-s ", title):sub(1, w))
    end
    
    display.setBackgroundColor(colors.black)
    display.setCursorPos(1, 3)
    display.setTextColor(colors.cyan)
    display.write("--- Security Feed (" .. #alerts .. " events) ---")
    
    for i, alert in ipairs(alerts) do
        if i > max_alerts then break end
        display.setCursorPos(1, 3 + i)
        if alert.isHighValue then
            display.setTextColor(colors.red)
            display.write("[!] ")
        else
            display.setTextColor(colors.white)
            display.write("[ ] ")
        end
        display.write(alert.msg:sub(1, w - 4))
    end
end

local function addAlert(msg, isHighValue)
    local w, _ = display.getSize()
    table.insert(alerts, 1, { msg = msg:sub(1, w - 4), isHighValue = isHighValue })
    if #alerts > 50 then table.remove(alerts) end -- Keep a buffer larger than display
    drawDashboard()
    if isHighValue then
        -- Blink display
        for i=1, 3 do
            display.setBackgroundColor(colors.red)
            display.clear()
            sleep(0.1)
            display.setBackgroundColor(colors.black)
            display.clear()
            drawDashboard("BREACH")
            sleep(0.1)
        end
        -- Reset to normal unless persistent breach
        drawDashboard()
    end
end

--==============================================================================
-- Integrity Logic
--==============================================================================

---
-- Replays the entire banking ledger to calculate expected user balances.
-- This state-replay ensures that the current database balances match the 
-- sum of all historical transactions.
-- @param ledger {table} The transaction history list.
-- @return {table} A map of usernames to their calculated integer balances.
local function recomputeBalances(ledger)
    local balances = {}
    -- Genesis state assumed 0
    for _, entry in ipairs(ledger) do
        local user = entry.user
        local amount = tonumber(entry.amount) or 0
        local type = entry.type
        
        -- Helper to ensure 0 initialization
        local function add(u, amt) balances[u] = (balances[u] or 0) + amt end
        local function sub(u, amt) balances[u] = (balances[u] or 0) - amt end
        
        if type == "account_created" then
            if not balances[user] then balances[user] = 0 end
        elseif type == "DEPOSIT" then
            add(user, amount)
        elseif type == "WITHDRAW" or type == "withdrawal" then
            sub(user, amount)
        elseif type == "TRANSFER_OUT" or type == "PAYMENT_OUT" then
            sub(user, amount)
        elseif type == "TRANSFER_IN" or type == "PAYMENT_IN" then
            add(user, amount)
        end
    end
    return balances
end

---
-- Conducts a full security audit of the bank server.
-- Fetches the ledger and account data, verifies the cryptographic hash chain,
-- and compares the reported state against a local re-calculated replay.
local function performAudit()
    if not bankServerId then
        bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server") -- Attempt to find by hostname or protocol
        if not bankServerId then
             -- Try generic lookup
             local ids = {rednet.lookup(BANK_PROTOCOL)}
             if #ids > 0 then bankServerId = ids[1] end
        end
    end

    if not bankServerId then
        addAlert("Error: Bank Server Offline", true)
        return
    end

    drawDashboard("VERIFYING")

    -- Fetch Ledger
    rednet.send(bankServerId, { type = "get_ledger" }, BANK_PROTOCOL)
    local _, ledgerMsg = rednet.receive(BANK_PROTOCOL, 5)
    
    -- Fetch Accounts
    rednet.send(bankServerId, { type = "get_all_accounts" }, BANK_PROTOCOL)
    local _, accountsMsg = rednet.receive(BANK_PROTOCOL, 5)

    if not ledgerMsg or not ledgerMsg.ledger or not accountsMsg or not accountsMsg.accounts then
        addAlert("Error: Fetch Failed", false)
        drawDashboard()
        return
    end

    local ledger = ledgerMsg.ledger
    local accounts = accountsMsg.accounts
    local prevHash = "0000000000000000000000000000000000000000"
    
    -- 1. Verify Ledger Hash Chain
    for i, entry in ipairs(ledger) do
        if entry.prevHash ~= prevHash then
            addAlert("CRITICAL: BROKEN CHAIN @" .. i, true)
            return
        end
        
        -- Re-hash
        local detailsStr = type(entry.details) == "table" and textutils.serialize(entry.details) or tostring(entry.details)
        local trace = string.format("%s:%s:%s:%s:%s:%s:%s", 
            prevHash, entry.type, entry.user, tostring(entry.amount), tostring(entry.target or ""), tostring(entry.timestamp), detailsStr)
        
        local calculatedHash = crypto.sha1(trace)
        if calculatedHash ~= entry.hash then
            addAlert("CRITICAL: HASH MISMATCH @" .. i, true)
            return
        end
        
        prevHash = entry.hash
    end

    -- 2. Verify State (Replay)
    local calculatedBalances = recomputeBalances(ledger)
    
    for user, data in pairs(accounts) do
        local actualBalance = data.balance
        local expectedBalance = calculatedBalances[user] or 0
        -- Floating point tolerance unnecessary for integers but good practice
        if actualBalance ~= expectedBalance then
             addAlert("BREACH: " .. user .. " (Exp:" .. expectedBalance .. " Act:" .. actualBalance .. ")", true)
             return
        end
    end

    addAlert("Audit Complete: Verified", false)
    drawDashboard()
end


--==============================================================================
-- Main Program Loop
--==============================================================================

local function monitorLoop()
    while true do
        local senderId, message, protocol = rednet.receive(AUDIT_PROTOCOL)
        if message and message.type == "security_event" then
            -- Verify message authenticity
            local signature = crypto.hmac_hex(SECRET_KEY, message.event .. message.timestamp)
            if signature == message.signature then
                local isHigh = (message.amount and message.amount >= 1000) or message.isAlert
                addAlert(message.event, isHigh)
            else
                addAlert("SUSPICIOUS: Unsigned Msg", true)
            end
        end
    end
end

local function schedulerLoop()
    while true do
        sleep(60) -- Audit every 60 seconds
        performAudit()
    end
end

local function main()
    -- Enable Auto-Update
    if updater and updater.check("Auditor", version) then
        os.reboot()
    end

    if fs.exists("/auditor_key.conf") then
        local file = fs.open("/auditor_key.conf", "r")
        SECRET_KEY = file.readAll()
        file.close()
    else
        print("FATAL: /auditor_key.conf not found.")
        return
    end

    local modem = peripheral.find("modem")
    if not modem then error("No modem attached.") end
    rednet.open(peripheral.getName(modem))
    
    initDisplay()
    print("Sentinel Online. Initializing Display...")
    performAudit() -- Initial check
    
    parallel.waitForAny(monitorLoop, schedulerLoop)
end

main()
