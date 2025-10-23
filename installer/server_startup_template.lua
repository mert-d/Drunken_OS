--[[
    Drunken OS - Split Terminal Server Startup Script (v2.0)
    by MuhendizBey

    Purpose:
    This script starts a server program with a "split terminal" setup.
    It redirects all visual output (print, clear, etc.) to an attached
    monitor, while keeping all input (read) on the main computer terminal.
    This provides a clean GUI on the monitor without locking the user out
    of their main command prompt.
]]

local program_path = "__PROGRAM_PATH__"

if program_path == "__PROGRAM_PATH__" then
    print("ERROR: Program path not set in startup script.")
    return
end

local monitor = peripheral.find("monitor")

if monitor then
    print("Monitor found. Redirecting output...")

    -- Store the original terminal functions
    local native_term = term.native()
    local old_write = native_term.write
    local old_clear = native_term.clear
    local old_clearLine = native_term.clearLine
    local old_setCursorPos = native_term.setCursorPos
    local old_setCursorBlink = native_term.setCursorBlink
    local old_getSize = native_term.getSize
    local old_scroll = native_term.scroll
    local old_setTextColor = native_term.setTextColor
    local old_setBackgroundColor = native_term.setBackgroundColor

    -- Create a new terminal object for the monitor
    local monitor_term = peripheral.wrap(monitor)

    -- Override the global term functions
    term.write = function(...) monitor_term.write(...) end
    term.clear = function() monitor_term.clear() end
    term.clearLine = function() monitor_term.clearLine() end
    term.setCursorPos = function(...) monitor_term.setCursorPos(...) end
    term.setCursorBlink = function(...) monitor_term.setCursorBlink(...) end
    term.getSize = function() return monitor_term.getSize() end
    term.scroll = function(...) monitor_term.scroll(...) end
    term.setTextColor = function(...) monitor_term.setTextColor(...) end
    term.setBackgroundColor = function(...) monitor_term.setBackgroundColor(...) end

    -- The read function will remain the original one,
    -- so input is still taken from the main computer terminal.
end

-- Run the server program with the modified terminal environment
local ok, err = pcall(shell.run, program_path)

if not ok then
    -- If the program crashes, print the error to the main terminal
    term.redirect(term.native())
    print("ERROR: " .. tostring(err))
end
