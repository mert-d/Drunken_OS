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

local program_path = nil
if fs.exists("/.program_path") then
    local f = fs.open("/.program_path", "r")
    program_path = f.readAll():gsub("%s+", "") -- Strip any whitespace/newlines
    f.close()
end

if not program_path or program_path == "" then
    print("ERROR: Program path not found in /.program_path")
    return
end

-- Simply run the server program. 
-- Drunken OS Servers now handle their own monitor redirection if needed.

-- Run the server program with the modified terminal environment
local ok, err = pcall(shell.run, program_path)

if not ok then
    -- If the program crashes, print the error to the main terminal
    term.redirect(term.native())
    print("ERROR: " .. tostring(err))
end
