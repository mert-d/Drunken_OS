--[[
    DrunkenOS SDK (v1.0)
    
    The official API for developing applications on Drunken OS.
    This library provides stable, high-level access to OS features.
    
    Documentation: /docs/SDK_GUIDE.md
]]

local theme = require("lib.theme")
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

local function wrapMessage(text, maxW)
    local lines = {}
    for rawLine in tostring(text or ""):gmatch("[^\r\n]+") do
        local current = ""
        for word in rawLine:gmatch("%S+") do
            if #current == 0 then
                current = word:sub(1, maxW)
            elseif #current + 1 + #word <= maxW then
                current = current .. " " .. word
            else
                table.insert(lines, current)
                current = word:sub(1, maxW)
            end
        end
        if #current > 0 then
            table.insert(lines, current)
        end
    end
    if #lines == 0 then table.insert(lines, "") end
    return lines
end

--- Shows a modal message box responsive to both Pocket (26x20) and Desktop (51x19) displays.
-- @param title string: The dialog title.
-- @param message string: The message body.
function DrunkenOS.UI.showMessage(title, message)
    local w, h = term.getSize()
    local isPocket = (w <= 26)
    local width = isPocket and math.max(18, w - 2) or math.min(w - 4, 34)
    local innerW = width - 2
    local msgLines = wrapMessage(message, innerW)
    local maxDisplayLines = math.min(#msgLines, isPocket and 4 or 6)
    local height = math.max(6, maxDisplayLines + 4)
    local x = math.max(1, math.floor((w - width) / 2) + 1)
    local y = math.max(2, math.floor((h - height) / 2) + 1)
    
    -- Draw Box
    for i = 0, height do
        term.setCursorPos(x, y + i)
        term.setBackgroundColor(theme.windowBg)
        term.write(string.rep(" ", width))
    end
    
    -- Title
    term.setCursorPos(x + 1, y + 1)
    term.setTextColor(theme.highlightText)
    term.write(title:sub(1, innerW))
    
    -- Message lines
    term.setTextColor(theme.text)
    for i = 1, maxDisplayLines do
        term.setCursorPos(x + 1, y + 1 + i)
        term.write(msgLines[i]:sub(1, innerW))
    end
    
    -- Action button
    local btnText = isPocket and "[ OK (Tap) ]" or "Press ENTER or Tap"
    local btnX = x + math.max(0, math.floor((width - #btnText) / 2))
    local btnY = y + height - 1
    term.setCursorPos(btnX, btnY)
    term.setTextColor(theme.prompt)
    term.write(btnText)

    while true do
        local e, p1 = os.pullEvent()
        if e == "key" and (p1 == keys.enter or p1 == keys.space or p1 == keys.esc) then
            break
        elseif e == "mouse_click" then
            break
        end
    end

    pcall(function()
        local sound = require("lib.sound")
        sound.playClick()
    end)

    -- Reset
    term.setBackgroundColor(theme.bg)
    term.clear()
end

--- Draws a vertical menu and handles user selection via Keyboard or Mouse/Touch.
-- @param options table: List of menu options (strings).
-- @param selected number: Initial selected index (default 1).
-- @param x number: X position (default 2).
-- @param y number: Y position (default 2).
-- @return number: The index of the selected option.
function DrunkenOS.UI.drawMenu(options, selected, x, y)
    selected = selected or 1
    x = x or 2
    y = y or 2
    local w, h = term.getSize()

    local maxLen = 0
    for _, opt in ipairs(options) do
        if #opt > maxLen then maxLen = #opt end
    end
    local maxItemWidth = math.min(maxLen, w - x - 2)

    while true do
        for i, opt in ipairs(options) do
            term.setCursorPos(x, y + i - 1)
            if i == selected then
                term.setTextColor(theme.highlightText)
                term.setBackgroundColor(theme.highlightBg)
            else
                term.setTextColor(theme.text)
                term.setBackgroundColor(theme.bg)
            end
            local display = opt:sub(1, maxItemWidth)
            local line = " " .. display .. string.rep(" ", maxItemWidth - #display + 1)
            term.write(line)
        end

        -- Reset colors after drawing
        term.setTextColor(theme.text)
        term.setBackgroundColor(theme.bg)

        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local key = p1
            if key == keys.up then
                selected = selected - 1
                if selected < 1 then selected = #options end
            elseif key == keys.down then
                selected = selected + 1
                if selected > #options then selected = 1 end
            elseif key == keys.enter then
                pcall(function() require("lib.sound").playClick() end)
                return selected
            end
        elseif event == "mouse_click" then
            local button, clickX, clickY = p1, p2, p3
            local clickedIdx = clickY - y + 1
            if clickedIdx >= 1 and clickedIdx <= #options then
                if clickX >= x and clickX <= (x + maxItemWidth + 3) then
                    pcall(function() require("lib.sound").playClick() end)
                    return clickedIdx
                end
            end
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir < 0 then
                selected = selected - 1
                if selected < 1 then selected = #options end
            else
                selected = selected + 1
                if selected > #options then selected = 1 end
            end
        end
    end
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
    local p2p = require("lib.p2p_socket")
    return p2p.new(gameId, 1.0, gameId .. "_Proto")
end

--==============================================================================
-- SYSTEM MODULE: User & Environment
--==============================================================================
DrunkenOS.System = {}

--- Gets the current logged-in username (if available in environment)
-- @return string: Username or "Guest"
function DrunkenOS.System.getUsername()
    if fs.exists(".session") then
        local f = fs.open(".session", "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data and data.username or "Guest"
    end
    return "Guest"
end

--- Gets the current secure session token
-- @return string|nil: The session string or nil
function DrunkenOS.System.getSessionToken()
    if fs.exists(".session") then
        local f = fs.open(".session", "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data and data.session_token or nil
    end
    return nil
end

return DrunkenOS
