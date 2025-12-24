--[[
    Drunken OS - Generic Installation Script (v1.2 - Modular Sync)
    by MuhendizBey

    Purpose:
    This script is placed on every installation disk. When run, it performs
    a permanent installation of the program onto the computer's hard drive,
    including creating a startup file.
]]

--==============================================================================
-- Helper Functions
--==============================================================================

local run_setup_wizard -- Forward declaration

local function showMessage(message)
    term.clear()
    term.setCursorPos(1, 1)
    print("Drunken OS Installer v1.1")
    print("--------------------")
    print(message)
    sleep(1.5)
end

-- Ensures a directory exists, creating it if necessary.
local function ensureDir(path)
    local dir = fs.getDir(path)
    if not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

--==============================================================================
-- Main Installation Logic
--==============================================================================

local function doInstallation()
    local diskPath = fs.getDir(shell.getRunningProgram())
    if diskPath == "" or diskPath == "." then diskPath = "/" end
    
    local configPath = fs.combine(diskPath, "install_config.lua")
    
    print("Installer path: " .. shell.getRunningProgram())
    print("Disk path: " .. diskPath)
    print("Config path: " .. configPath)
    
    -- This file will be created by the Master Installer
    if not fs.exists(configPath) then
        print("FATAL: install_config.lua not found.")
        print("Search path: " .. configPath)
        return
    end

    -- Load the configuration for this specific installation
    local configFile = fs.open(configPath, "r")
    local configData = configFile.readAll()
    configFile.close()
    local config = textutils.unserialize(configData)
    if not config or not config.main_program or not config.files then
        print("FATAL: install_config.lua is corrupt.")
        return
    end

    showMessage("Starting installation of " .. config.name .. "...")

    -- Copy all files from the disk to the computer's hard drive
    for _, filePath in ipairs(config.files) do
        local sourcePath = fs.combine(diskPath, filePath)
        local destPath = "/" .. filePath

        showMessage("Copying " .. filePath .. "...")

        print("Source: " .. sourcePath)
        print("Source Exists: " .. tostring(fs.exists(sourcePath)))
        print("Dest: " .. destPath)
        ensureDir(destPath)
        if fs.exists(destPath) then
            fs.delete(destPath)
        end
        fs.copy(sourcePath, destPath)
    end

    showMessage("Files copied successfully.")

    -- Run the setup wizard if needed
    if config.needs_setup then
        run_setup_wizard(config.setup_type)
    end

    -- Create the startup file
    showMessage("Creating startup file...")
    
    -- Write the program path to a hidden file for the startup script to read
    local pathFile = fs.open("/.program_path", "w")
    pathFile.write(config.main_program)
    pathFile.close()

    if config.type == "server" then
        local serverStartupPath = fs.combine(diskPath, "server_startup.lua")
        if not fs.exists(serverStartupPath) then
            print("FATAL: server_startup.lua missing on disk!")
            return
        end
        
        local serverStartupFile = fs.open(serverStartupPath, "r")
        local serverStartupScript = serverStartupFile.readAll()
        serverStartupFile.close()

        -- No more gsub here, serverStartupScript now reads /.program_path
        local startupFile = fs.open("/startup.lua", "w")
        startupFile.write(serverStartupScript)
        startupFile.close()
    else
        local startupFile = fs.open("/startup.lua", "w")
        startupFile.write('shell.run("' .. tostring(config.main_program) .. '")')
        startupFile.close()
    end

    showMessage("Installation complete! Rebooting in 3 seconds...")
    
    -- Eject the disk if present
    local drive = peripheral.find("drive")
    if drive and drive.isDiskPresent() then
        drive.ejectDisk()
    end

    sleep(3)
    os.reboot()
end

run_setup_wizard = function(setup_type)
    if setup_type == "atm" then
        showMessage("Running ATM setup wizard...")
        print("Please enter the ID of the Bank Clerk Turtle:")
        local turtleId = read()
        local config = { turtleClerkId = tonumber(turtleId) }
        local file = fs.open("/atm.conf", "w")
        file.write(textutils.serialize(config))
        file.close()
        showMessage("ATM configured successfully.")
    elseif setup_type == "bank_server" then
        showMessage("Running Bank Server setup wizard...")
        print("Please enter a secret key for the Auditor turtle:")
        local secretKey = read()
        -- The bank server will read this file on startup
        local file = fs.open("/auditor_key.conf", "w")
        file.write(secretKey)
        file.close()
        showMessage("Bank Server configured successfully.")
    elseif setup_type == "auditor" then
        showMessage("Running Auditor setup wizard...")
        print("Please enter the secret key for the Bank Server:")
        local secretKey = read()
        -- The auditor turtle will read this file on startup
        local file = fs.open("/auditor_key.conf", "w")
        file.write(secretKey)
        file.close()
        showMessage("Auditor configured successfully.")
    end
end

local function main()
    local ok, err = pcall(doInstallation)
    if not ok then
        print("INSTALLATION FAILED:")
        print(tostring(err))
        print("Please take a screenshot and report this error.")
        print("Press any key to reboot.")
        os.pullEvent("key")
        os.reboot()
    end
end

main()
