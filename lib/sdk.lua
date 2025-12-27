--[[
    DrunkenOS SDK (v1.0)
    
    The official API for developing applications on Drunken OS.
    This library provides stable, high-level access to OS features.
    
    Documentation: /docs/SDK_GUIDE.md
]]

local theme = require("lib.theme")
local p2p = require("lib.p2p_socket")
local DrunkenOS = { _VERSION = 1.0 }

--==============================================================================
-- UI MODULE: Easy Rendering
--==============================================================================
DrunkenOS.UI = {}

--- Draws a standard window frame and clears the screen.
-- @param title string: The window title.
function DrunkenOS.UI.drawWindow(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg)
    term.clear()
    term.setBackgroundColor(theme.titleBg)
    term.setTextColor(theme.titleText)
    term.setCursorPos(1, 1); term.write(string.rep(" ", w))
    term.setCursorPos(math.floor((w - #title)/2)+1, 1); term.write(title)
    term.setBackgroundColor(theme.bg)
end

--- Shows a modal message box.
-- @param title string: The dialog title.
-- @param message string: The message body.
function DrunkenOS.UI.showMessage(title, message)
    local w, h = term.getSize()
    local width = math.min(w - 4, 30)
    local height = 6
    local x = math.floor((w - width) / 2)
    local y = math.floor((h - height) / 2)
    
    -- Draw Box
    for i = 0, height do
        term.setCursorPos(x, y + i)
        term.setBackgroundColor(theme.windowBg)
        term.write(string.rep(" ", width))
    end
    
    term.setCursorPos(x + 1, y + 1)
    term.setTextColor(theme.highlightText)
    term.write(title)
    
    term.setCursorPos(x + 1, y + 3)
    term.setTextColor(theme.text)
    term.write(message:sub(1, width - 2))
    
    term.setCursorPos(x + 1, y + 5)
    term.setTextColor(theme.prompt)
    term.write("Press ENTER")
    while true do
        local e, k = os.pullEvent("key")
        if k == keys.enter then break end
    end
    -- Reset
    term.setBackgroundColor(theme.bg)
    term.clear()
end

--==============================================================================
-- NETWORK MODULE: Simplified Networking
--==============================================================================
DrunkenOS.Net = {}

--- Connects to the main network.
-- @return boolean: True if modem was found and opened.
function DrunkenOS.Net.connect()
    if not rednet.isOpen() then
        local m = peripheral.find("modem")
        if m then 
            rednet.open(peripheral.getName(m)) 
            return true
        end
        return false
    end
    return true
end

--- Wraps P2P Socket for easy Game Networking
-- @param gameId string: Unique ID for your game (e.g. "MyFloppyBird")
-- @return table: A P2P Socket instance
function DrunkenOS.Net.createGameSocket(gameId)
    return p2p.new(gameId, 1.0, gameId .. "_Proto")
end

--==============================================================================
-- SYSTEM MODULE: User & Environment
--==============================================================================
DrunkenOS.System = {}

--- Gets the current logged-in username (if available in environment)
-- @return string: Username or "Guest"
function DrunkenOS.System.getUsername()
    -- This relies on the bootloader setting a global or needing an API call
    -- Since we don't have a global state exposed yet, we return Guest for now.
    -- Future: Read from .session file safely.
    if fs.exists(".session") then
        local f = fs.open(".session", "r")
        local u = f.readAll()
        f.close()
        return u
    end
    return "Guest"
end

return DrunkenOS
