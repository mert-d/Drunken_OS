-- Drunken OS - Merchant POS (v1.1 - UI & Proxy Update)
-- Wrapper for the Merchant POS application in drunken_os_apps library

local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path

local apps = require("drunken_os_apps")

-- Mock context if running standalone
local context = {
    programDir = programDir,
    parent = {
        -- Minimum required parent properties for standalone run
        username = nil, 
        -- If username is missing, library usually handles it.
        -- This wrapper is intended to be installed alongside the client libs.
    }
}

-- Lightweight "OS Shell" in the wrapper that:
-- 1. Sets up Rednet
-- 2. Handles Login (essential for Merchant ID)
-- 3. Defines the UI functions
-- 4. Calls the app

local w, h = term.getSize()
local theme = {
    bg = colors.black,
    text = colors.white,
    titleBg = colors.blue,
    titleText = colors.white,
    prompt = colors.yellow
}

local function drawFrame(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg)
    term.clear()
    
    -- Draw subtle frame/border
    term.setBackgroundColor(theme.titleBg)
    term.setCursorPos(1, 1); term.write(string.rep(" ", w))
    term.setCursorPos(1, h); term.write(string.rep(" ", w))
    for i = 2, h - 1 do
        term.setCursorPos(1, i); term.write(" ")
        term.setCursorPos(w, i); term.write(" ")
    end

    term.setCursorPos(1, 1)
    term.setTextColor(theme.titleText)
    local titleText = " " .. (title or "Merchant POS") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    
    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
end

local context = {}
context.programDir = programDir
context.theme = theme

function context.getSafeSize() return w, h end

function context.drawWindow(title)
    drawFrame(title)
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
