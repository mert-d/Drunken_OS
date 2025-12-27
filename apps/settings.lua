--[[
    System Settings
    Configure Drunken OS Appearance
]]

local theme = require("lib.theme")
local w, h = term.getSize()

local options = {
    "Default (Blue)",
    "Red Alert",
    "Matrix",
    "Midnight"
}

local selected = 1

local function drawMenu()
    theme.clear()
    theme.drawTitleBar("System Settings")
    
    local startY = 4
    term.setCursorPos(2, 3)
    term.setTextColor(theme.text)
    term.write("Select a Theme:")
    
    for i, opt in ipairs(options) do
        term.setCursorPos(4, startY + i)
        if i == selected then
            term.setTextColor(theme.highlightText)
            term.setBackgroundColor(theme.highlightBg)
            term.write(" " .. opt .. " ")
        else
            term.setTextColor(theme.text)
            term.setBackgroundColor(theme.bg)
            term.write(" " .. opt .. " ")
        end
    end
    
    term.setBackgroundColor(theme.bg)
    term.setCursorPos(2, h-2)
    term.setTextColor(colors.gray)
    term.write("Press ENTER to Apply. REBOOT required.")
end

while true do
    drawMenu()
    
    local event, key = os.pullEvent("key")
    if key == keys.up then
        selected = selected - 1
        if selected < 1 then selected = #options end
    elseif key == keys.down then
        selected = selected + 1
        if selected > #options then selected = 1 end
    elseif key == keys.enter then
        local choice = options[selected]
        theme.save(choice)
        
        -- Flash Feedback
        term.setCursorPos(2, h-2)
        term.setTextColor(colors.lime)
        term.clearLine()
        term.write("Theme Saved! Rebooting...")
        os.sleep(1)
        os.reboot()
    elseif key == keys.q then
        break
    end
end
