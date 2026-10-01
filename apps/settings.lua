--[[
    Drunken OS - System Settings Applet (v1.2)
    Configure Drunken OS Appearance with Touch & Scroll Support
]]

local settings_app = {}
local appVersion = 1.2

---
-- Main application entry point for the Settings control panel.
-- Provides theme customisation requiring a system reboot.
-- @param context table: OS app context.
function settings_app.run(context)
    local theme = require("lib.theme")
    local ok_sound, Sound = pcall(require, "lib.sound")
    if not ok_sound or type(Sound) ~= "table" then
        Sound = { playClick = function() end }
    end

    local options = {
        "Default (Blue)",
        "Red Alert",
        "Matrix",
        "Midnight"
    }

    local selected = 1

    local function applyTheme(choice)
        theme.save(choice)
        local w, h = term.getSize()
        term.setCursorPos(2, h - 2)
        term.setTextColor(colors.lime)
        term.clearLine()
        term.write(w <= 30 and "Saved! Rebooting..." or "Theme Saved! Rebooting...")
        os.sleep(1)
        os.reboot()
    end

    while true do
        local w, h = term.getSize()
        local isPocket = (w <= 30)
        context.drawWindow("System Settings")

        term.setCursorPos(2, 3)
        term.setTextColor(theme.text)
        term.write("Select a Theme:")

        local startY = 4
        for i, opt in ipairs(options) do
            term.setCursorPos(4, startY + i)
            if i == selected then
                term.setTextColor(theme.highlightText or colors.black)
                term.setBackgroundColor(theme.highlightBg or colors.cyan)
                term.write(" " .. opt .. " ")
            else
                term.setTextColor(theme.text or colors.white)
                term.setBackgroundColor(theme.bg or colors.black)
                term.write(" " .. opt .. " ")
            end
        end

        term.setBackgroundColor(theme.bg or colors.black)
        term.setCursorPos(2, h - 2)
        term.setTextColor(theme.accent or colors.yellow)
        if isPocket then
            term.write("[Enter:Apply & Reboot]")
        else
            term.write("Press ENTER to Apply. REBOOT required.")
        end

        term.setCursorPos(2, h - 1)
        term.setTextColor(theme.mutedText or colors.gray)
        term.write("[Q] Back")

        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local key = p1
            if key == keys.up then
                selected = (selected == 1) and #options or selected - 1
                if Sound and Sound.playClick then Sound.playClick() end
            elseif key == keys.down then
                selected = (selected == #options) and 1 or selected + 1
                if Sound and Sound.playClick then Sound.playClick() end
            elseif key == keys.enter then
                applyTheme(options[selected])
            elseif key == keys.q or key == keys.tab or key == keys.x then
                break
            end
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir < 0 then
                selected = (selected == 1) and #options or selected - 1
            else
                selected = (selected == #options) and 1 or selected + 1
            end
            if Sound and Sound.playClick then Sound.playClick() end
        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            local clickedIdx = cy - startY
            if clickedIdx >= 1 and clickedIdx <= #options then
                if selected == clickedIdx then
                    applyTheme(options[selected])
                else
                    selected = clickedIdx
                    if Sound and Sound.playClick then Sound.playClick() end
                end
            elseif cy == h - 2 then
                applyTheme(options[selected])
            elseif cy == h - 1 or (cy == 1 and cx >= w - 3) then
                break
            end
        end
    end
end

return settings_app
