-- Drunken OS - Merchant POS (v1.1 - UI & Proxy Update)
-- Wrapper for the Merchant POS application in drunken_os_apps library

local programDir = (shell and shell.getRunningProgram and fs.getDir(shell.getRunningProgram())) or ""
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. (programDir ~= "" and (fs.combine(programDir, "lib/?.lua") .. ";") or "") .. package.path

local apps = require("lib.drunken_os_apps")
local sharedTheme = require("lib.theme")
local utils = require("lib.utils")

-- Mock context if running standalone
local context = {
    programDir = programDir,
    parent = {
        mailServerId = nil,
        username = nil,
        nickname = nil
    }
}

-- Lightweight "OS Shell" in the wrapper that:
-- 1. Sets up Rednet
-- 2. Handles Login (essential for Merchant ID)
-- 3. Defines the UI functions
-- 4. Calls the app

local context = {}
context.programDir = programDir
context.theme = sharedTheme
context.parent = {
    mailServerId = nil,
    username = nil,
    nickname = nil
}

function context.getSafeSize() return w, h end

function context.drawWindow(title)
    utils.drawWindow(title or "Merchant POS", context)
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
    term.write(prompt)
    return read(secret and "*")
end

function context.drawMenu(options, selected, x, y)
    for i, opt in ipairs(options) do
        term.setCursorPos(x, y + i - 1)
        if i == selected then
            term.write("> " .. opt)
        else
            term.write("  " .. opt)
        end
    end
end

-- Networking & State
context.parent = {
    username = nil,
    nickname = nil,
    mailServerId = nil, -- Needs lookup
    balance = "???",
    userInfo = { is_merchant = true } -- Assume for this app
}

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

local MERCHANT_CONFIG_FILE = "merchant.conf"

---
-- Retrieves the registered merchant identity from local config.
-- @return string|nil: The merchant username, or nil if unconfigured.
local function getMerchantName()
    local path = fs.combine(programDir, MERCHANT_CONFIG_FILE)
    if fs.exists(path) then
        local handle, err = fs.open(path, "r")
        if not handle then return nil end
        local name = handle.readAll()
        handle.close()
        -- Return nil if the name is just whitespace or empty
        if name and not name:match("^%s*$") then
            return name
        end
    end
    return nil
end

local function setMerchantName(name)
    local path = fs.combine(programDir, MERCHANT_CONFIG_FILE)
    local handle = fs.open(path, "w")
    handle.write(name)
    handle.close()
end


-- Main Bootstrap
---
-- Bootstraps the terminal as a Merchant Point Of Sale node.
-- Prompts for initial merchant configuration if not present, and then
-- hands execution over to the drunken_os_apps POS interface.
local function main()
    -- Rednet
    local modem = peripheral.find("modem")
    if not modem then
        print("Error: No modem.")
        return
    end
    rednet.open(peripheral.getName(modem))
    
    -- Lookup Servers
    context.parent.mailServerId = rednet.lookup("SimpleMail", "mail.server")
    
    -- Setup Merchant Identity
    local merchantName = getMerchantName()
    if not merchantName then
        drawFrame("Merchant POS Setup")
        merchantName = context.readInput("Enter Merchant Name: ", 4)
        if not merchantName or merchantName:match("^%s*$") then
            print("Merchant name cannot be empty.")
            return
        end
        setMerchantName(merchantName)
        context.showMessage("Setup Complete", "Merchant name set to: " .. merchantName)
    end

    context.parent.username = merchantName
    context.parent.nickname = merchantName
    
    -- Run App
    apps.merchantPOS(context)
end

main()
