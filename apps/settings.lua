--[[
    Drunken OS - System Settings Applet (v1.1)
    Configure Drunken OS Appearance
]]

local settings_app = {}
local appVersion = 1.1

---
-- Main application entry point for the Settings control panel.
-- Provides theme customisation requiring a system reboot.
-- @param context table: OS app context.
function settings_app.run(context)
    local theme = require("lib.theme")
    local w, h = term.getSize()

    local options = {
        "Default (Blue)",
        "Red Alert",
        "Matrix",
        "Midnight"
    }

    local selected = 1

    while true do
        context.drawWindow("System Settings")

        term.setCursorPos(2, 3)
        term.setTextColor(theme.text)
        term.write("Select a Theme:")

        local startY = 4
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
        elseif key == keys.q or key == keys.tab then
            break
        end
    end
end

return settings_app
