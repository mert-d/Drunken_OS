local utils = {}
utils._VERSION = 1.1
local theme = require("lib.theme")

---
-- Returns a color that's safe to use on the current terminal.
-- Delegates to theme.safeColor (canonical implementation).
-- @deprecated Use theme.safeColor() directly.
function utils.safeColor(colorName, fallback)
    return theme.safeColor(colorName, fallback)
end

---
-- Displays a simple loading indicator with a message.
-- Can be used while waiting for network operations.
-- @param message string: The loading message to display.
-- @param context table: Optional context with theme/term overrides.
function utils.showLoading(message, context)
    local w, h = term.getSize()
    local t = (context and context.theme) or theme
    
    term.setBackgroundColor(t.bg or colors.black)
    term.clear()
    
    -- Title bar
    term.setBackgroundColor(t.titleBg or colors.blue)
    term.setCursorPos(1, 1)
    term.clearLine()
    
    -- Message centered
    term.setBackgroundColor(t.bg or colors.black)
    term.setTextColor(t.text or colors.white)
    local displayMsg = message or "Loading..."
    term.setCursorPos(math.floor((w - #displayMsg) / 2) + 1, math.floor(h / 2))
    term.write(displayMsg)
end

---
-- Clears the screen and draws a generic window shell wrapper with a title bar.
-- Similar to DrunkenOS.UI.drawWindow, but works purely on passed context.
-- @param title string: Text string to embed inside the Title bar.
-- @param context table: Execution context containing theme configuration.
function utils.drawWindow(title, context)
    local w, h = term.getSize()
    local t = (context and context.theme) or theme  -- Respect passed theme, fall back to module default
    term.setBackgroundColor(t.bg)
    term.clear()
    
    -- Title Bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.titleBg)
    term.clearLine()
    term.setTextColor(t.titleText)
    
    local titleText = " " .. (title or "Window") .. " "
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, 1)
    term.write(titleText)
    
    -- Footer/Status Bar (Optional, mimic standard look)
    term.setCursorPos(1, h)
    term.setBackgroundColor(t.titleBg)
    term.clearLine()
    
    -- Reset
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.text)
end

---
-- Formats long strings into an array of lines wrapped perfectly safely 
-- at spaces without fragmenting words.
-- @param text string: Input text to wrap.
-- @param maxWidth number: Maximum characters allowed per line string.
-- @return table: Array of strings.
function utils.wordWrap(text, maxWidth)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        while #line > maxWidth do
            local breakPoint = maxWidth
            while breakPoint > 0 and line:sub(breakPoint, breakPoint) ~= " " do
                breakPoint = breakPoint - 1
            end
            if breakPoint == 0 then breakPoint = maxWidth end
            table.insert(lines, line:sub(1, breakPoint))
            line = line:sub(breakPoint + 1)
        end
        table.insert(lines, line)
    end
    return lines
end

---
-- Syntactic sugar to automatically text-wrap a generic message, calculate line offsets,
-- and render it visually centered blockwise onto the terminal.
-- @param startY number: Absolute Y coordinate position to start drawing the block.
-- @param message string: The long text message to center.
function utils.printCentered(startY, message)
    local w, h = term.getSize()
    -- USE W-2 to maximize space, and 3 column/row padding for frame
    local lines = utils.wordWrap(message, w - 2)
    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, startY + i - 1)
        term.write(line)
    end
end

return utils
