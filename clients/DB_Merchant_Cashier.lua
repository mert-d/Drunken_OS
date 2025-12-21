-- Drunken OS - Merchant Cashier PC (v1.1 - UI & Proxy Update)
-- Wrapper for the Merchant Cashier application in drunken_os_apps library

local programDir = fs.getDir(shell.getRunningProgram())
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. fs.combine(programDir, "lib/?.lua;") .. package.path

local apps = require("drunken_os_apps")

-- Minimal UI Context Framework
local w, h = term.getSize()
local theme = {
    bg = colors.black,
    text = colors.white,
    titleBg = colors.green,
    titleText = colors.black,
    prompt = colors.yellow,
    highlightBg = colors.white,
    highlightText = colors.black,
    windowBg = colors.black
}

local context = {}
context.programDir = programDir
context.theme = theme

function context.getSafeSize() return w, h end

function context.drawWindow(title)
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
    local titleText = " " .. (title or "Merchant Cashier") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    
    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
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
    local x,y,z = gps.locate(2)
    if x then context.parent.location = {x=x,y=y,z=z} end

    -- Login
    if not apps.loginOrRegister(context) then
        return
    end
    
    -- Run App
    apps.merchantCashier(context)
end

main()
