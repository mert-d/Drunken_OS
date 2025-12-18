--[[
    Drunken Beard Bank - Auditor Turtle (v2.0 - Digital Monitor)
    by MuhendizBey

    Purpose:
    Real-time security monitor for the digital bank. Displays transaction
    feeds and alerts on suspicious activities. Now includes auto-update.
]]

--==============================================================================
-- API & Library Initialization
--==============================================================================

local version = 2.0
package.path = "/?.lua;" .. package.path
local crypto = require("lib.sha1_hmac")
local updater = require("lib.updater")

--==============================================================================
-- Configuration
--==============================================================================

local AUDIT_PROTOCOL = "DB_Audit"
local SECRET_KEY = nil
local alerts = {}
local max_alerts = 10

--==============================================================================
-- UI Functions
--==============================================================================

local function drawDashboard()
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    local w, _ = term.getSize()
    term.write(" BANK SEC-MON v" .. version .. string.rep(" ", w - 17))
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 3)
    term.setTextColor(colors.cyan)
    term.write("--- Activity Feed ---")
    
    for i, alert in ipairs(alerts) do
        term.setCursorPos(1, 4 + i)
        if alert.isHighValue then
            term.setTextColor(colors.red)
            term.write("[!] ")
        else
            term.setTextColor(colors.white)
            term.write("[ ] ")
        end
        term.write(alert.msg)
    end
end

local function addAlert(msg, isHighValue)
    table.insert(alerts, 1, { msg = msg:sub(1, 30), isHighValue = isHighValue })
    if #alerts > max_alerts then table.remove(alerts) end
    drawDashboard()
    if isHighValue then
        -- Blink shell
        for i=1, 3 do
            term.setBackgroundColor(colors.red)
            term.clear()
            sleep(0.1)
            term.setBackgroundColor(colors.black)
            term.clear()
            drawDashboard()
            sleep(0.1)
        end
    end
end

--==============================================================================
-- Main Program Loop
--==============================================================================

local function main()
    -- Enable Auto-Update
    if updater.check("Auditor", version) then
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
    
    print("Auditor Online. Monitoring Bank...")
    sleep(1)
    drawDashboard()

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

main()
