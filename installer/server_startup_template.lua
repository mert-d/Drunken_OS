--[[
    Drunken OS - Dynamic Server Startup Script (v1.0)
    by MuhendizBey

    Purpose:
    This script is used to start server programs. It automatically detects
    and uses an attached monitor if one is available.
]]

local program_path = "{{PROGRAM_PATH}}"

local monitor = peripheral.find("monitor")
if monitor then
    print("Monitor found. Redirecting output...")
    term.redirect(monitor)
    term.clear()
    term.setCursorPos(1, 1)
end

pcall(shell.run, program_path)
