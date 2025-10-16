--[[ 
    Drunken OS - Unified UI Library (v1.2) 
    by Gemini Gem

    Purpose:
    This library provides a centralized, consistent set of functions for
    creating text-based user interfaces across all Drunken OS applications.
    It supports theming to allow different visual styles.

    Changelog:
    v1.2: Added windowBg to bank theme to fix a bug.
    v1.1: Added getTheme() function to expose the current theme table.
]]

local ui = {}

--==============================================================================
-- Configuration & State
--==============================================================================

local hasColor = term.isColor and term.isColor()

local themes = {
    drunken_os = {
        bg = hasColor and colors.black or colors.black,
        text = hasColor and colors.white or colors.white,
        windowBg = hasColor and colors.darkGray or colors.gray,
        border = hasColor and colors.lightGray or colors.white,
        title = hasColor and colors.green or colors.lime,
        prompt = hasColor and colors.cyan or colors.cyan,
        highlightBg = hasColor and colors.blue or colors.blue,
        highlightText = hasColor and colors.white or colors.white,
        statusBarBg = hasColor and colors.gray or colors.lightGray,
        statusBarText = hasColor and colors.white or colors.white,
        errorBg = hasColor and colors.red or colors.red,
        errorText = hasColor and colors.white or colors.white,
    },
    bank = {
        bg = colors.black,
        text = colors.white,
        border = colors.brown,
        titleBg = colors.orange,
        titleText = colors.white,
        windowBg = hasColor and colors.darkGray or colors.gray,
        highlightBg = colors.yellow,
        highlightText = colors.brown,
        errorBg = colors.red,
        errorText = colors.white,
        statusBarBg = colors.gray,
        statusBarText = colors.white,
        prompt = colors.yellow,
    }
}

local currentTheme = themes.drunken_os

--==============================================================================
-- Core Utility & UI Functions
--==============================================================================

--- Sets the active theme for all subsequent UI drawing functions.
-- @param themeName {string} The name of the theme to activate (e.g., "drunken_os", "bank").
function ui.setTheme(themeName)
    if themes[themeName] then
        currentTheme = themes[themeName]
    else
        error("Attempted to set non-existent theme: " .. tostring(themeName))
    end
end

--- Returns the currently active theme table.
-- @return {table} The active theme table.
function ui.getTheme()
    return currentTheme
end

--- Gets the current terminal dimensions safely.
-- @return {number}, {number} The width and height of the terminal.
function ui.getSafeSize()
    local w, h = term.getSize()
    while not w or not h do
        sleep(0.05)
        w, h = term.getSize()
    end
    return w, h
end

--- Wraps long lines of text to fit within a specified width.
-- @param text {string} The string to wrap.
-- @param width {number} The maximum width of each line.
-- @return {table} A table of strings, each representing a wrapped line.
function ui.wordWrap(text, width)
    local lines = {}
    text = text or ""
    for line in text:gmatch("[^\r\n]+") do
        while #line > width do
            local space = line:sub(1, width + 1):match(".+ ")
            local len = space and #space or width
            table.insert(lines, line:sub(1, len - 1))
            line = line:sub(len):match("^%s*(.*)")
        end
        table.insert(lines, line)
    end
    return lines
end

--- Clears the entire screen with the theme's background color.
function ui.clear()
    term.setBackgroundColor(currentTheme.bg)
    term.clear()
    term.setCursorPos(1, 1)
end

--- Draws a standard window with a title bar.
-- @param title {string} The text to display in the title bar.
function ui.drawWindow(title)
    ui.clear()
    local w, h = ui.getSafeSize()
    term.setBackgroundColor(currentTheme.windowBg)
    for y = 1, h do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", w))
    end

    term.setBackgroundColor(currentTheme.title)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", w))
    term.setTextColor(colors.white)
    local titleText = " " .. (title or "Window") .. " "
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, 1)
    term.write(titleText)
    
    term.setBackgroundColor(currentTheme.windowBg)
    term.setTextColor(currentTheme.text)
end

--- Draws a bordered frame, like in the ATM.
-- @param title {string} The text to display in the title bar.
function ui.drawFrame(title)
    local w, h = ui.getSafeSize()
    term.setBackgroundColor(currentTheme.bg); term.clear()
    term.setBackgroundColor(currentTheme.border)
    for y=1,h do term.setCursorPos(1,y); term.write(" "); term.setCursorPos(w,y); term.write(" ") end
    for x=1,w do term.setCursorPos(x,1); term.write(" "); term.setCursorPos(x,h); term.write(" ") end
    term.setBackgroundColor(currentTheme.titleBg); term.setTextColor(currentTheme.titleText)
    local titleText = " " .. (title or "Drunken Beard Bank") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    term.setBackgroundColor(currentTheme.bg); term.setTextColor(currentTheme.text)
end


--- Draws a vertical menu and handles selection.
-- @param options {table} A list of strings for the menu items.
-- @param selectedIndex {number} The currently selected index.
-- @param startX {number} The starting X coordinate.
-- @param startY {number} The starting Y coordinate.
-- @param unreadCount {number} (Optional) A number to display next to a "Mail" or "Inbox" option.
function ui.drawMenu(options, selectedIndex, startX, startY, unreadCount)
    for i, option in ipairs(options) do
        local text = option
        if (option:match("Mail") or option:match("Inbox")) and unreadCount and unreadCount > 0 then
            text = text .. " [" .. unreadCount .. "]"
        end
        term.setCursorPos(startX, startY + i - 1)
        if i == selectedIndex then
            term.setBackgroundColor(currentTheme.highlightBg)
            term.setTextColor(currentTheme.highlightText)
            term.write("> " .. text .. string.rep(" ", 25 - #text))
        else
            term.setBackgroundColor(currentTheme.windowBg)
            term.setTextColor(currentTheme.text)
            term.write("  " .. text .. string.rep(" ", 25 - #text))
        end
    end
    term.setBackgroundColor(currentTheme.windowBg)
end

--- Displays a modal message box.
-- @param title {string} The title of the message box.
-- @param message {string} The message content.
-- @param isError {boolean} (Optional) If true, uses the error theme colors.
function ui.showMessage(title, message, isError)
    local w, h = ui.getSafeSize()
    local boxBg = isError and currentTheme.errorBg or currentTheme.titleBg
    local boxText = isError and currentTheme.errorText or currentTheme.titleText
    local boxW, boxH = math.floor(w * 0.8), math.floor(h * 0.7)
    local boxX, boxY = math.floor((w - boxW) / 2), math.floor((h - boxH) / 2)

    term.setBackgroundColor(boxBg)
    for y = boxY, boxY + boxH - 1 do
        term.setCursorPos(boxX, y); term.write(string.rep(" ", boxW))
    end
    
    term.setTextColor(boxText)
    local titleText = " " .. title .. " ";
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, boxY + 1); term.write(titleText)
    
    local lines = ui.wordWrap(message, boxW - 4)

    for i, line in ipairs(lines) do
        term.setCursorPos(boxX + 3, boxY + 3 + i - 1)
        term.write(line)
    end

    local continueText = "Press any key to continue..."
    term.setCursorPos(math.floor((w - #continueText) / 2) + 1, boxY + boxH - 2)
    term.write(continueText)
    
    os.pullEvent("key")
end

--- Prompts the user for input.
-- @param prompt {string} The prompt to display.
-- @param y {number} The Y coordinate for the prompt.
-- @param hideText {boolean} (Optional) If true, masks the input with asterisks.
-- @return {string} The user's input.
function ui.readInput(prompt, y, hideText)
    local x = 2
    term.setTextColor(currentTheme.prompt)
    term.setCursorPos(x, y)
    term.write(prompt)
    term.setTextColor(currentTheme.text)
    term.setCursorPos(x + #prompt, y)
    term.setCursorBlink(true)
    local input = hideText and read("*") or read()
    term.setCursorBlink(false)
    return input
end

--- Prints text centered on the screen, with word wrapping.
-- @param startY {number} The Y coordinate to start printing at.
-- @param text {string} The text to print.
function ui.printCentered(startY, text)
    local w, h = ui.getSafeSize()
    local lines = ui.wordWrap(text, w - 4)

    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, startY + i - 1)
        term.write(line)
    end
end

return ui