--[[
    Drunken OS - Generic Installation Script (v1.0)
    by Gemini Gem & MuhendizBey

    Purpose:
    This script is placed on every installation disk. When run, it performs
    a permanent installation of the program onto the computer's hard drive,
    including creating a startup file.
]]

--==============================================================================
-- Helper Functions
--==============================================================================

local function showMessage(message)
    term.clear()
    term.setCursorPos(1, 1)
    print("Drunken OS Installer")
    print("--------------------")
    print(message)
    sleep(2)
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

local function main()
    -- This file will be created by the Master Installer
    if not fs.exists("install_config.lua") then
        print("FATAL: install_config.lua not found on this disk.")
        return
    end

    -- Load the configuration for this specific installation
    local configFile = fs.open("install_config.lua", "r")
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
        local sourcePath = "/" .. fs.getName(fs.getDrive()) .. "/" .. filePath
        local destPath = "/" .. filePath

        showMessage("Copying " .. filePath .. "...")

        ensureDir(destPath)
        fs.copy(sourcePath, destPath)
    end

    showMessage("Files copied successfully.")

    -- Run the setup wizard if needed
    if config.needs_setup then
        run_setup_wizard(config.setup_type)
    end
end

local function run_setup_wizard(setup_type)
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

    -- Create the startup file
    showMessage("Creating startup file...")
    local startupFile = fs.open("/startup.lua", "w")
    startupFile.write('shell.run("' .. config.main_program .. '")')
    startupFile.close()

    showMessage("Installation complete! Rebooting in 3 seconds...")
    sleep(3)
    os.reboot()
end

main()
