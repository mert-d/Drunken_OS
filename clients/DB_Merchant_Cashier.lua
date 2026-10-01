-- Drunken OS - Merchant Cashier PC (v1.1 - UI & Proxy Update)
-- Wrapper for the Merchant Cashier application in drunken_os_apps library

local programDir = (shell and shell.getRunningProgram and fs.getDir(shell.getRunningProgram())) or ""
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. (programDir ~= "" and (fs.combine(programDir, "lib/?.lua") .. ";") or "") .. package.path

local apps = require("lib.drunken_os_apps")
local sharedTheme = require("lib.theme")
local utils = require("lib.utils")

-- Minimal UI Context Framework
local w, h = term.getSize()
local context = {}
context.programDir = programDir
context.theme = sharedTheme
context.parent = {
    mailServerId = nil,
    username = nil,
    nickname = nil,
    location = nil
}

function context.getSafeSize() return w, h end

function context.drawWindow(title)
    utils.drawWindow(title or "Merchant Cashier", context)
end

function context.showMessage(title, msg)
    context.drawWindow(title)
    local w, h = term.getSize()
    local lines = context.wordWrap(msg, w - 2)
    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, 4 + i - 1)
        term.write(line)
    end
    term.setCursorPos(math.floor((w - 16) / 2) + 1, h - 1)
    term.setTextColor(colors.gray)
    term.write("Press any key...")
    os.pullEvent("key")
end

function context.readInput(prompt, y, secret)
    term.setCursorPos(2, y)
    term.setTextColor(theme.prompt)
    term.write(prompt)
    term.setTextColor(theme.text)
    return read(secret and "*")
end

function context.drawMenu(options, selected, x, y)
    -- Helper for simple lists if needed, though Cashier app has custom UI
    for i, opt in ipairs(options) do
        term.setCursorPos(x, y + i - 1)
        if i == selected then
            term.write("> " .. opt)
        else
            term.write("  " .. opt)
        end
    end
end

function context.wordWrap(text, width)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        while #line > width do
            local breakPoint = width
            while breakPoint > 0 and line:sub(breakPoint, breakPoint) ~= " " do
                breakPoint = breakPoint - 1
            end
            if breakPoint == 0 then breakPoint = width end
            table.insert(lines, line:sub(1, breakPoint))
            line = line:sub(breakPoint + 1)
        end
        table.insert(lines, line)
    end
    return lines
end

context.clear = function() term.clear(); term.setCursorPos(1,1) end

-- Networking & State
context.parent = {
    username = nil,
    nickname = nil,
    mailServerId = nil, 
    location = {x=0,y=0,z=0}, -- Mock location for broadcasts
    userInfo = { is_merchant = true }
}

-- Main Bootstrap
---
-- Bootstraps the terminal as a Merchant Cashier node.
-- Connects to Rednet, geolocates the terminal, and hands execution over
-- to the drunken_os_apps Merchant Cashier interface.
local function main()
    term.clear()
    local modem = peripheral.find("modem")
    if not modem then
        print("Error: Merchant Console requires a modem.")
        sleep(2)
        return
    end
    rednet.open(peripheral.getName(modem))
    
    -- Lookup
    context.parent.mailServerId = rednet.lookup("SimpleMail", "mail.server")
    
    -- GPS
    local x, y, z = nil, nil, nil
    if gps and gps.locate then
        x, y, z = gps.locate(2)
    end
    if x then context.parent.location = {x=x,y=y,z=z} end

    -- Login
    if not apps.loginOrRegister(context) then
        return
    end
    
    -- Run App
    apps.merchantCashier(context)
end

main()
