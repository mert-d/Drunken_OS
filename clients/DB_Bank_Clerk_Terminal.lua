--[[
    Drunken Beard Bank - Clerk Terminal (v1.0)
    by MuhendizBey

    Purpose:
    Secured terminal for bank staff to manage customer accounts,
    verify transactions, and monitor security events.
]]

--==============================================================================
-- Configuration & Init
--==============================================================================

local version = 1.0
local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path

local function safeRequire(mod)
    local ok, res = pcall(require, mod)
    return ok and res or nil
end

local crypto = safeRequire("lib.sha1_hmac") or safeRequire("sha1_hmac")
if not crypto then
    print("Error: Missing 'sha1_hmac' library.")
    return
end

local BANK_PROTOCOL = "DB_Bank"
local AUDIT_PROTOCOL = "DB_Audit"
local bankServerId = nil

-- Clerk Auth Configuration
local CLERK_KEY_HASH = nil
local CLERK_CONF = "/clerk_auth.conf"

local function loadClerkAuth()
    if fs.exists(CLERK_CONF) then
        local file = fs.open(CLERK_CONF, "r")
        CLERK_KEY_HASH = file.readAll()
        file.close()
        return true
    end
    return false
end

local function saveClerkAuth(password)
    local hash = crypto.sha1(password)
    local file = fs.open(CLERK_CONF, "w")
    file.write(hash)
    file.close()
    CLERK_KEY_HASH = hash
end

--==============================================================================
-- UI Helpers
--==============================================================================

local function clear()
    term.clear()
    term.setCursorPos(1,1)
end

local function drawHeader(title)
    local w, h = term.getSize()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", w))
    term.setCursorPos(math.floor((w - #title) / 2) + 1, 1)
    term.write(title)
    term.setBackgroundColor(colors.black)
end

local function drawMenu(options, selected, startX, startY)
    for i, option in ipairs(options) do
        term.setCursorPos(startX, startY + i - 1)
        if i == selected then
            term.setTextColor(colors.black)
            term.setBackgroundColor(colors.yellow)
            term.write("> " .. option .. " ")
        else
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.black)
            term.write("  " .. option .. " ")
        end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function pause()
    term.setTextColor(colors.lightGray)
    print("\n[ Press any key to continue ]")
    term.setTextColor(colors.white)
    os.pullEvent("key")
end

--==============================================================================
-- Networking
--==============================================================================

local function findServer()
    print("Connecting to Mainframe...")
    bankServerId = rednet.lookup(BANK_PROTOCOL, "bank.server") or rednet.lookup(BANK_PROTOCOL)
    if not bankServerId then
        print("Error: Bank Server unreachable.")
        return false
    end
    print("Connected to Bank Server (ID: " .. bankServerId .. ")")
    sleep(1)
    return true
end

--==============================================================================
-- Features
--==============================================================================

local function lookupAccount()
    clear()
    drawHeader("Account Lookup")
    term.setCursorPos(1, 4)
    term.setTextColor(colors.yellow)
    write(" > User: ")
    term.setTextColor(colors.white)
    local user = read()
    
    rednet.send(bankServerId, { type = "clerk_get_account", user = user }, BANK_PROTOCOL)
    local _, response = rednet.receive(BANK_PROTOCOL, 5)
    
    if response and response.success then
        print("\n   [ ACCOUNT DETAILS ]")
        term.setTextColor(colors.cyan)
        print("   Username:   " .. user)
        term.setTextColor(colors.white)
        print("   Balance:    $" .. response.account.balance)
        print("   PIN Status: " .. (response.account.pin_hash and "SET" or "NOT SET"))
        print("   Account Type: " .. (response.account.is_merchant and "Merchant" or "Personal"))
    else
        term.setTextColor(colors.red)
        print("\n   Error: " .. (response and response.reason or "Record not found."))
        term.setTextColor(colors.white)
    end
    pause()
end

local function viewHistory()
    clear()
    drawHeader("Transaction History")
    term.setCursorPos(1, 4)
    term.setTextColor(colors.yellow)
    write(" > User: ")
    term.setTextColor(colors.white)
    local user = read()
    
    print("\n   Fetching ledger logs...")
    rednet.send(bankServerId, { type = "clerk_get_history", user = user }, BANK_PROTOCOL)
    local _, response = rednet.receive(BANK_PROTOCOL, 5)
    
    if response and response.success then
        if #response.history == 0 then
            print("   No transactions recorded.")
        else
            local w, h = term.getSize()
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            print(string.format(" %-12s | %-8s | %-15s", "Type", "Amt", "Details "))
            term.setBackgroundColor(colors.black)
            
            for i, entry in ipairs(response.history) do
                if i > (h - 8) then
                    term.setTextColor(colors.lightGray)
                    print("   ... (history truncated)")
                    break
                end
                
                local details = entry.details
                local detailStr = ""
                if type(details) == "table" then
                    if details.recipient then detailStr = "to " .. details.recipient 
                    elseif details.sender then detailStr = "fm " .. details.sender
                    elseif details.merchant then detailStr = "Pay " .. details.merchant
                    else detailStr = "Data" end
                else
                    detailStr = tostring(details or "")
                end
                
                local typeColor = colors.white
                if entry.type:find("DEPOSIT") or entry.type:find("IN") then typeColor = colors.green
                elseif entry.type:find("WITHDRAW") or entry.type:find("OUT") then typeColor = colors.red end
                
                term.setTextColor(typeColor)
                write(string.format(" %-12s", entry.type:sub(1,12)))
                term.setTextColor(colors.white)
                print(string.format(" | %-8s | %-15s", 
                    tostring(entry.amount or 0), 
                    detailStr:sub(1,15)
                ))
            end
        end
    else
        term.setTextColor(colors.red)
        print("\n   Error: " .. (response and response.reason or "No data."))
        term.setTextColor(colors.white)
    end
    pause()
end

local function liveMonitor()
    clear()
    drawHeader("Clerk Terminal - Live Security Monitor")
    print("\nListening for Audit Events (Press 'q' to exit)...")
    
    while true do
        local id, msg = rednet.receive(5)
        if id then
            if msg and msg.type == "security_event" then
                local prefix = msg.isAlert and "[!]" or "[i]"
                local color = msg.isAlert and colors.red or colors.white
                term.setTextColor(color)
                print(string.format("%s %s", prefix, msg.event))
                term.setTextColor(colors.white)
            end
        end
        
        local event, key = os.queueEvent("dummy") -- Non-blocking check hack
        os.pullEvent() -- Clear dummy
        
        -- Non-blocking input handling is hard without parallel API
        -- We will rely on built-in event loop for simplicity
        -- Actually, rednet.receive returns on keypress if we don't filter? No.
    end
end
-- To fix Live Monitor, we need parallel
local function runMonitor()
    clear()
    drawHeader("Live Security Monitor (Press 'Q' to quit)")
    
    local function listen()
        while true do
            local id, msg, proto = rednet.receive(AUDIT_PROTOCOL)
            if msg and type(msg) == "table" and msg.type == "security_event" then
                 local time = os.time()
                 local timestamp = textutils.formatTime(time, true)
                 local prefix = msg.isAlert and "[ALERT]" or "[INFO]"
                 
                 if msg.isAlert then term.setTextColor(colors.red) else term.setTextColor(colors.white) end
                 print(string.format("[%s] %s %s", timestamp, prefix, msg.event))
                 term.setTextColor(colors.white)
            end
        end
    end
    
    local function waitExit()
        while true do
            local event, key = os.pullEvent("key")
            if key == keys.q then return end
        end
    end
    
    parallel.waitForAny(listen, waitExit)
end

--==============================================================================
-- Main Loop
--==============================================================================

local function main()
    clear()
    print("Initializing Clerk Terminal...")
    
    local modem = peripheral.find("modem")
    if not modem then
        print("Error: No modem attached.")
        return
    end
    rednet.open(peripheral.getName(modem))
    
    if not findServer() then return end
    
    -- Auth
    if not loadClerkAuth() then
        clear()
        drawHeader("First Time Setup")
        term.setCursorPos(1, 4)
        print("No Clerk Password set.")
        write("Set New Clerk Password: ")
        local p1 = read("*")
        write("Confirm Password: ")
        local p2 = read("*")
        
        if p1 == p2 and p1 ~= "" then
            saveClerkAuth(p1)
            print("\nPassword Set Successfully.")
            sleep(1)
        else
            print("\nPasswords mismatch or empty. Exiting.")
            sleep(2)
            return
        end
    end

    clear()
    drawHeader("Security Check")
    term.setCursorPos(1, 4)
    write("Enter Clerk Password: ")
    local input = read("*")
    if crypto.sha1(input) ~= CLERK_KEY_HASH then
        print("\nAccess Denied.")
        sleep(2)
        return
    end
    
    while true do
        clear()
        drawHeader("Drunken Beard Bank - Clerk Dashboard")
        
        local options = {
            "Lookup Account",
            "View Transaction History",
            "Live Security Monitor",
            "Logout"
        }
        
        local selected = 1
        local choice = nil
        
        while true do
            drawMenu(options, selected, 2, 4)
            
            local event, key = os.pullEvent("key")
            if key == keys.up then
                selected = (selected == 1) and #options or selected - 1
            elseif key == keys.down then
                selected = (selected == #options) and 1 or selected + 1
            elseif key == keys.enter then
                choice = selected
                break
            elseif key == keys.q then
                choice = 4 -- Logout
                break
            end
        end
        
        if choice == 1 then lookupAccount()
        elseif choice == 2 then viewHistory()
        elseif choice == 3 then runMonitor()
        elseif choice == 4 then 
            clear()
            print("Logging out...")
            break 
        end
    end
end

main()
