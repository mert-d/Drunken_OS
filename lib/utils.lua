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
    local t = (context and context.theme) or theme
    local isColor = not term.isColor or term.isColor()
    
    local bgCol = isColor and (t.bg or colors.black) or colors.black
    local textCol = isColor and (t.text or colors.white) or colors.white
    local titleBg = isColor and (t.titleBg or colors.blue) or colors.black
    local titleText = isColor and (t.titleText or colors.white) or colors.white
    
    term.setBackgroundColor(bgCol)
    term.clear()
    
    -- 1. Top Status Bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(titleBg)
    term.clearLine()
    term.setTextColor(titleText)
    
    -- Calculate Clock
    local timeStr = ""
    if os.time and textutils and textutils.formatTime then
        pcall(function() timeStr = textutils.formatTime(os.time(), false) end)
    elseif os.date then
        pcall(function() timeStr = os.date("%H:%M") end)
    end
    
    -- Unread Mail Badge
    local unread = (context and context.unreadMails) or (context and context.state and context.state.unreadMails) or 0
    local badgeStr = (unread > 0) and (" (" .. unread .. ")") or ""
    
    if w <= 30 then
        -- Pocket Screen (26x20) Layout
        local rightInfo = timeStr .. badgeStr
        local maxTitleLen = w - #rightInfo - 2
        local displayTitle = (title or "Drunken OS")
        if #displayTitle > maxTitleLen and maxTitleLen > 3 then
            displayTitle = displayTitle:sub(1, maxTitleLen - 2) .. ".."
        end
        term.setCursorPos(1, 1)
        term.write(" " .. displayTitle)
        if #rightInfo > 0 then
            term.setCursorPos(w - #rightInfo, 1)
            term.write(rightInfo .. " ")
        end
    else
        -- Desktop Screen (51x19) Layout
        term.setCursorPos(2, 1)
        term.write("[*] " .. (title or "Drunken OS"))
        
        local rightParts = {}
        if rednet and rednet.isOpen and rednet.isOpen() then
            table.insert(rightParts, "[NET]")
        end
        if context and context.location and context.location.x then
            table.insert(rightParts, string.format("GPS:%d,%d", math.floor(context.location.x), math.floor(context.location.z or 0)))
        end
        if #badgeStr > 0 then
            table.insert(rightParts, "Mail" .. badgeStr)
        end
        if #timeStr > 0 then
            table.insert(rightParts, timeStr)
        end
        
        local rightInfo = table.concat(rightParts, " ") .. " "
        if #rightInfo > 1 then
            term.setCursorPos(w - #rightInfo, 1)
            term.write(rightInfo)
        end
    end
    
    -- 2. Bottom Toast / Status Bar
    term.setCursorPos(1, h)
    term.setBackgroundColor(titleBg)
    term.clearLine()
    
    local toast = context and (context.toast or context.statusMessage)
    if toast and #toast > 0 then
        term.setTextColor(isColor and (t.highlightText or colors.yellow) or colors.white)
        term.setCursorPos(1, h)
        local displayToast = " " .. toast .. " "
        if #displayToast > w then displayToast = displayToast:sub(1, w) end
        term.write(displayToast)
    else
        term.setTextColor(isColor and (t.mutedText or colors.lightGray) or colors.white)
        term.setCursorPos(2, h)
        if w <= 30 then
            term.write("Tap or Arrows to navigate")
        else
            term.write("Drunken OS - Press [Q] or [Enter]")
        end
    end
    
    -- Reset to default body colors
    term.setBackgroundColor(bgCol)
    term.setTextColor(textCol)
end

---
---
-- Splits a string by a delimiter (default newline).
-- Preserves empty tokens (e.g. consecutive newlines).
-- @param text string: Input text to split.
-- @param delimiter string: Delimiter character or string (default "\n").
-- @return table: Array of split segments.
function utils.split(text, delimiter)
    delimiter = delimiter or "\n"
    local result = {}
    local pos = 1
    while true do
        local startIdx, endIdx = text:find(delimiter, pos, true)
        if not startIdx then
            table.insert(result, text:sub(pos))
            break
        end
        table.insert(result, text:sub(pos, startIdx - 1))
        pos = endIdx + 1
    end
    return result
end

---
-- Trims leading and trailing whitespace from a string.
-- @param str string: Input string.
-- @return string: Trimmed string.
function utils.trim(str)
    if not str then return "" end
    return str:match("^%s*(.-)%s*$") or ""
end

---
-- Formats long strings into an array of lines wrapped safely at word boundaries.
-- Preserves existing line breaks and empty lines.
-- @param text string: Input text to wrap.
-- @param maxWidth number: Maximum characters allowed per line string.
-- @return table: Array of strings.
function utils.wordWrap(text, maxWidth)
    if not text then return {} end
    maxWidth = math.max(1, maxWidth or 20)
    local rawLines = utils.split(text, "\n")
    local lines = {}

    for _, rawLine in ipairs(rawLines) do
        local line = rawLine
        if #line <= maxWidth then
            table.insert(lines, line)
        else
            while #line > maxWidth do
                local breakPoint = maxWidth
                while breakPoint > 0 and line:sub(breakPoint, breakPoint) ~= " " do
                    breakPoint = breakPoint - 1
                end

                if breakPoint == 0 then
                    -- Hard split when a single word exceeds maxWidth
                    breakPoint = maxWidth
                    table.insert(lines, line:sub(1, breakPoint))
                    line = line:sub(breakPoint + 1)
                else
                    table.insert(lines, line:sub(1, breakPoint - 1))
                    -- Skip the space delimiter at breakPoint
                    line = line:sub(breakPoint + 1):gsub("^%s+", "")
                end
            end
            table.insert(lines, line)
        end
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
