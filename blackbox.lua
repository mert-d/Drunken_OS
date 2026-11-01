-- blackbox.lua
-- Drunken OS - Flight Data Recorder (Blackbox) CLI Shortcut
local args = { ... }
if fs.exists("apps/blackbox.lua") then
    shell.run("apps/blackbox.lua", table.unpack(args))
elseif fs.exists("/apps/blackbox.lua") then
    shell.run("/apps/blackbox.lua", table.unpack(args))
else
    print("HATA: apps/blackbox.lua bulunamadi!")
end
