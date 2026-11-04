-- /tune
-- Drunken OS PID & Flight Dynamics Autotuner CLI shortcut
local tArgs = { ... }
if fs.exists("apps/autotune.lua") then
    shell.run("apps/autotune.lua", table.unpack(tArgs))
elseif fs.exists("/apps/autotune.lua") then
    shell.run("/apps/autotune.lua", table.unpack(tArgs))
else
    print("Error: apps/autotune.lua not found.")
end
