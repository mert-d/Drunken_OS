--[[
    Drunken OS - Resilient Disk Installer (v1.3)
    by MuhendizBey

    Purpose:
    Placed on every installation disk. Discovers drive mount dynamically,
    copies files cleanly to hard drive root, configures startup, and reboots.
]]

local runSetupWizard

local function fatalError(title, details)
    pcall(function()
        if term.isColor and term.isColor() then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.red)
        end
        term.clear()
        term.setCursorPos(1, 2)
        print("========================================")
        print("     DRUNKEN OS INSTALLATION FAILED     ")
        print("========================================")
        if term.setTextColor then term.setTextColor(colors.white) end
        print("\n" .. tostring(title) .. "\n")
        if details then
            if term.setTextColor then term.setTextColor(colors.lightGray or colors.white) end
            print(tostring(details))
        end
        print("\nPlease take a screenshot or verify disk.")
        print("Press any key to reboot...")
        os.pullEvent("key")
        os.reboot()
    end)
end

local function ensureDir(path)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

local function findDiskPath()
    local running = (shell and shell.getRunningProgram and shell.getRunningProgram()) or ""
    local dir = fs.getDir(running)
    if dir and dir ~= "" and dir ~= "." and fs.exists(fs.combine(dir, "install_config.lua")) then
        return dir
    end
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "drive" then
                local mount = disk and disk.getMountPath and disk.getMountPath(name)
                if mount and fs.exists(fs.combine(mount, "install_config.lua")) then
                    return mount
                end
            end
        end
    end
    for _, candidate in ipairs({ "disk", "disk1", "disk2", "/" }) do
        if fs.exists(fs.combine(candidate, "install_config.lua")) then
            return candidate
        end
    end
    return (dir ~= "" and dir ~= ".") and dir or "disk"
end

local function doInstallation()
    local diskPath = findDiskPath()
    local configPath = fs.combine(diskPath, "install_config.lua")

    if not fs.exists(configPath) then
        fatalError("Configuration file not found!", "Looked for install_config.lua in: " .. tostring(configPath))
        return
    end

    local configFile = fs.open(configPath, "r")
    if not configFile then
        fatalError("Cannot read configuration file!", configPath)
        return
    end
    local configData = configFile.readAll()
    configFile.close()

    local config = textutils.unserialize(configData)
    if not config or not config.main_program or not config.files then
        fatalError("Configuration file is corrupted!", "Data length: " .. tostring(configData and #configData or 0) .. " bytes")
        return
    end

    local isColor = term.isColor and term.isColor()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    if isColor then term.setTextColor(colors.cyan) end
    print("========================================")
    print("      Drunken OS Installer (v1.3)       ")
    print("========================================")
    if isColor then term.setTextColor(colors.yellow) end
    print("Installing: " .. tostring(config.name))
    if isColor then term.setTextColor(colors.white) end
    print("Source: /" .. tostring(diskPath) .. " -> Target: /\n")

    for idx, filePath in ipairs(config.files) do
        local sourcePath = fs.combine(diskPath, filePath)
        local destPath = "/" .. filePath

        if isColor then term.setTextColor(colors.lightGray) end
        io.write(string.format("[%2d/%2d] %-30s ... ", idx, #config.files, fs.getName(filePath)))

        if fs.exists(sourcePath) then
            ensureDir(destPath)
            if fs.exists(destPath) then fs.delete(destPath) end
            local ok_copy, err_copy = pcall(fs.copy, sourcePath, destPath)
            if ok_copy then
                if isColor then term.setTextColor(colors.green) end
                print("OK")
            else
                if isColor then term.setTextColor(colors.red) end
                print("FAIL (" .. tostring(err_copy) .. ")")
            end
        else
            if isColor then term.setTextColor(colors.orange or colors.yellow) end
            print("MISSING")
        end
    end

    if config.needs_setup and runSetupWizard then
        print("")
        runSetupWizard(config.setup_type)
    end

    local pathFile = fs.open("/.program_path", "w")
    if pathFile then
        pathFile.write(config.main_program)
        pathFile.close()
    end

    if isColor then term.setTextColor(colors.yellow) end
    print("\nCreating startup file...")
    if config.type == "server" then
        local srvStartupPath = fs.combine(diskPath, "server_startup.lua")
        if not fs.exists(srvStartupPath) then
            fatalError("server_startup.lua is missing on installation disk!", srvStartupPath)
            return
        end
        local sf = fs.open(srvStartupPath, "r")
        local srvScript = sf.readAll()
        sf.close()
        local outStartup = fs.open("/startup.lua", "w")
        outStartup.write(srvScript)
        outStartup.close()
    else
        local outStartup = fs.open("/startup.lua", "w")
        outStartup.write('shell.run("' .. tostring(config.main_program) .. '")')
        outStartup.close()
    end

    if isColor then term.setTextColor(colors.green) end
    print("Installation complete! Ejecting disk...")

    local drive = peripheral.find("drive")
    if drive and drive.isDiskPresent and drive.isDiskPresent() then
        pcall(drive.ejectDisk)
    end

    sleep(2)
    os.reboot()
end

runSetupWizard = function(setup_type)
    local ATM_TURTLE_PROTOCOL = "DB_ATM_Turtle"
    if setup_type == "atm" then
        print("Configuring ATM...")
        local modem = peripheral.find("modem")
        if modem then rednet.open(peripheral.getName(modem)) end
        local turtleId, verified = nil, false
        while not verified do
            print("Enter Bank Clerk Turtle ID:")
            local input = read()
            turtleId = tonumber(input)
            if not turtleId then
                print("Invalid ID. Enter a number.")
            elseif not modem then
                verified = true
            else
                print("Pinging Turtle " .. turtleId .. "...")
                rednet.send(turtleId, { type = "ping" }, ATM_TURTLE_PROTOCOL)
                local sender, message = rednet.receive(ATM_TURTLE_PROTOCOL, 4)
                if sender == turtleId and type(message) == "table" and message.type == "pong" then
                    print("Handshake OK! Turtle online.")
                    verified = true
                else
                    print("No response. Retry? (y/n)")
                    if read():lower() ~= "y" then verified = true end
                end
            end
        end
        local f = fs.open("/atm.conf", "w")
        if f then f.write(textutils.serialize({ turtleClerkId = turtleId })); f.close() end
    elseif setup_type == "bank_server" or setup_type == "auditor" then
        local prompt = (setup_type == "bank_server") and "Auditor" or "Bank Server"
        print("Enter secret key for " .. prompt .. ":")
        local secret = read()
        local f = fs.open("/auditor_key.conf", "w")
        if f then f.write(secret); f.close() end
    end
end

local function main()
    local ok, err = pcall(doInstallation)
    if not ok then fatalError("Unexpected Installer Crash!", err) end
end

main()
