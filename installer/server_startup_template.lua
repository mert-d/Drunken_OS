-- Drunken OS - Server Startup Bootstrapper (v2.1)
local program_path = nil
if fs.exists("/.program_path") then
    local f = fs.open("/.program_path", "r")
    if f then
        program_path = f.readAll():gsub("%s+", "")
        f.close()
    end
end

if not program_path or program_path == "" then
    print("ERROR: Program path not found in /.program_path")
    return
end

local ok, err = pcall(shell.run, program_path)
if not ok then
    if term.redirect and term.native then
        pcall(term.redirect, term.native())
    end
    print("ERROR: " .. tostring(err))
end
