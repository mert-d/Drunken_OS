-- Drunken OS - Merchant Cashier PC
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
    term.setBackgroundColor(theme.bg); term.clear()
    term.setCursorPos(1,1); term.setBackgroundColor(theme.titleBg); term.setTextColor(theme.titleText)
    for i=1,w do term.write(" ") end -- clear header line
    term.setCursorPos(math.floor((w-#title)/2), 1)
    term.write(" " .. title .. " ")
    term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
end

function context.showMessage(title, msg)
    context.drawWindow(title)
    term.setCursorPos(2, 4)
    print(msg)
    term.setCursorPos(2, h-2)
    term.setTextColor(theme.prompt)
    print("Press any key...")
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
     -- Rudimentary wrap
     while #text > width do
        local space = text:sub(1,width):match(".*()%s") or width
        table.insert(lines, text:sub(1, space-1))
        text = text:sub(space+1)
     end
     table.insert(lines, text)
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
