-- Drunken OS - Merchant POS Launcher
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
        -- If username is missing, library usually handles it or we might need a mini-login wrapper here
        -- but usually this app is launched from Drunken_OS_Client which provides context.
        -- If launched standalone, it might fail some "getParent(context)" calls if not structured carefully.
        -- However, this is intended to be installed *alongside* the client libs.
        -- Let's check: apps.merchantPOS calls getParent(context).userInfo.is_merchant
        -- Realistically, this wrapper assumes it's running in an environment where it can access shared state or is bootstrapped.
        -- BUT, if installed as a "Program", it needs its own bootstrap.
    }
}

-- Wait, apps library functions like apps.merchantPOS(context) rely HEAVILY on 'context' being a robust object 
-- with drawWindow, readInput, theme, etc.
-- The Drunken_OS_Client.lua creates this context.
-- If I just call apps.merchantPOS(context) with a nil context, it will crash.
-- 
-- SOLUTION: 
-- These wrappers are likely intended to be run *within* the Drunken OS Client environment (as part of the app menu).
-- BUT the user wants them in the *Installer*. This implies they are standalone programs on a disk/computer.
-- If so, they need to implement the FULL context interface (UI helpers, etc) OR they are just separate *files* that Drunken_OS_Client can *import*?
-- 
-- The user said "Merchant Business Suite... applications".
-- If they are separate programs, they need to duplicate the UI logic or require a "framework" runner.
-- `Drunken_OS_Client.lua` seems to be the main "OS" runner.
-- 
-- Let's look at `clients/DB_Bank_Clerk_Terminal.lua`. It has its own `drawHeader`, `drawMenu`, `main`. It is standalone.
-- `lib/drunken_os_apps.lua` functions take `context`.
-- 
-- If I make a wrapper, I must provide the `context` dependencies (UI, Networking, State).
-- Since `Drunken_OS_Client.lua` is 22kb and contains the framework, maybe I should just bundle a "Mini Client" 
-- OR checking `Drunken_OS_Client.lua` to see if it can run specific apps?
-- 
-- Actually, the `Drunken_OS_Client.lua` *is* the OS. 
-- "Merchant POS" might just be a *mode* of the Client?
-- User asked: "Master Installer ... containing these apps".
-- If I install "Merchant POS", I probably want a program that starts up DIRECTLY into the POS screen.
-- 
-- So I need to copy/reference enough UI logic to make `apps.merchantPOS(ctx)` work.
-- OR I modify `Drunken_OS_Client.lua` to accept arguments to boot into specific apps.
-- 
-- Let's try the "Boot Argument" approach? No, that requires modifying the Client.
-- Let's try the "Context Mock" approach. I can copy the UI helper functions from `Drunken_OS_Client` 
-- into a `lib/ui_context.lua`? Or just put them in the wrapper.
-- 
-- `Master_Installer` bundles dependencies. 
-- If I assume `clients/Drunken_OS_Client.lua` is present? No, separate install.
-- 
-- I will create a `lib/drunken_framework.lua`? No, too big refactor.
-- I will replicate the minimal `context` object in `DB_Merchant_POS.lua`.
-- It needs: drawWindow, drawMenu, readInput, showMessage, getSafeSize, etc.
-- And: parent.username, parent.mailServerId (rednet lookup), etc.

-- OK, I will construct a lightweight "OS Shell" in the wrapper that:
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
    term.setBackgroundColor(theme.bg); term.clear()
    term.setCursorPos(1,1); term.setBackgroundColor(theme.titleBg); term.setTextColor(theme.titleText)
    termin.clearLine()
    term.write(" " .. title)
    term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
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
    term.setCursorPos(2, 4)
    print(msg)
    term.setCursorPos(2, h-2)
    print("Press any key...")
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
    -- Simplified wrapper for textutils or manual split
    -- ... (Omitting full implementation for brevity, relying on basic print/write where possible or simple implementation)
    local lines = {}
    while #text > width do
        table.insert(lines, text:sub(1, width))
        text = text:sub(width + 1)
    end
    table.insert(lines, text)
    return lines
end

context.clear = function() term.clear(); term.setCursorPos(1,1) end

-- Main Bootstrap
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
    -- context.parent.bankServerId = rednet.lookup("DB_Bank", "bank.server") -- Handled inside apps usually
    
    if not context.parent.mailServerId then
        -- Proceed anyway? might fail networking calls
    end
    
    -- Login (Simplified)
    -- Since this is a dedicated POS, we might hardcode or ask once.
    -- Re-using apps.loginOrRegister?
    if not apps.loginOrRegister(context) then
        return
    end
    
    -- Run App
    apps.merchantPOS(context)
end

main()
