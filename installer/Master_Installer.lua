--[[
    Drunken OS - Master Installer (v1.0 - Initial Release)
    by Gemini Gem & MuhendizBey

    Purpose:
    This program provides a user-friendly interface to create installation
    disks for all components of the Drunken OS system. It downloads the
    latest versions of the programs from GitHub and bundles them with an
    installation script onto a floppy disk.
]]

--==============================================================================
-- Configuration
--==============================================================================

local GITHUB_REPO_URL = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/"

local INSTALLABLE_PROGRAMS = {
    { name = "Drunken OS Server", path = "servers/Drunken_OS_Server.lua", dependencies = { "lib/sha1_hmac.lua" } },
    { name = "Drunken OS Bank Server", path = "servers/Drunken_OS_BankServer.lua", dependencies = { "lib/sha1_hmac.lua" }, needs_setup = true, setup_type = "bank_server" },
    { name = "Drunken OS Client", path = "clients/Drunken_OS_Client.lua", dependencies = { "lib/sha1_hmac.lua" } },
    { name = "DB Bank ATM", path = "clients/DB_Bank_ATM.lua", dependencies = { "lib/sha1_hmac.lua" }, needs_setup = true, setup_type = "atm" },
    { name = "DB Bank Clerk Terminal", path = "clients/DB_Bank_Clerk_Terminal.lua", dependencies = { "lib/sha1_hmac.lua" } },
    { name = "DB Bank Clerk Turtle", path = "turtles/DB_Bank_Clerk.lua", dependencies = {} },
    { name = "Auditor Turtle", path = "turtles/Auditor.lua", dependencies = { "lib/sha1_hmac.lua" }, needs_setup = true, setup_type = "auditor" },
}

--==============================================================================
-- Graphical UI & Theme
--==============================================================================

local theme = {
    bg = colors.black,
    text = colors.white,
    border = colors.purple,
    titleBg = colors.magenta,
    titleText = colors.white,
    highlightBg = colors.yellow,
    highlightText = colors.black,
    errorBg = colors.red,
    errorText = colors.white,
}

local function drawFrame(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg); term.clear()
    term.setBackgroundColor(theme.border)
    for y=1,h do term.setCursorPos(1,y); term.write(" "); term.setCursorPos(w,y); term.write(" ") end
    for x=1,w do term.setCursorPos(x,1); term.write(" "); term.setCursorPos(x,h); term.write(" ") end
    term.setBackgroundColor(theme.titleBg); term.setTextColor(theme.titleText)
    local titleText = " " .. (title or "Drunken OS - Master Installer") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    term.setBackgroundColor(theme.bg); term.setTextColor(theme.text)
end

local function printCentered(startY, text)
    local w, h = term.getSize()
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, startY)
    term.write(text)
end

local function showMessage(title, message, isError)
    local w, h = term.getSize()
    local boxBg = isError and theme.errorBg or theme.titleBg
    local boxText = isError and theme.errorText or theme.titleText
    local boxW, boxH = math.floor(w * 0.8), math.floor(h * 0.7)
    local boxX, boxY = math.floor((w - boxW) / 2), math.floor((h - boxH) / 2)

    term.setBackgroundColor(boxBg)
    for y = boxY, boxY + boxH - 1 do
        term.setCursorPos(boxX, y); term.write(string.rep(" ", boxW))
    end

    term.setTextColor(boxText)
    local titleText = " " .. title .. " ";
    term.setCursorPos(math.floor((w - #titleText) / 2) + 1, boxY + 1); term.write(titleText)

    local lines = {}
    for line in message:gmatch("[^\n]+") do
        while #line > boxW - 4 do
            table.insert(lines, line:sub(1, boxW - 4))
            line = line:sub(boxW - 3)
        end
        table.insert(lines, line)
    end

    for i, line in ipairs(lines) do
        term.setCursorPos(boxX + 2, boxY + 3 + i)
        print(line)
    end

    local continueText = "Press any key to continue..."
    term.setCursorPos(math.floor((w - #continueText) / 2) + 1, boxY + boxH - 2)
    print(continueText)

    os.pullEvent("key")
end

local function drawMenu(title, options, help)
    local w, h = term.getSize()
    local selected = 1
    while true do
        drawFrame(title)
        for i, opt in ipairs(options) do
            term.setCursorPos(4, 4 + i)
            if i == selected then
                term.setBackgroundColor(theme.highlightBg)
                term.setTextColor(theme.highlightText)
            else
                term.setBackgroundColor(theme.bg)
                term.setTextColor(theme.text)
            end
            term.write(" " .. opt.name .. string.rep(" ", w - 6 - #opt.name) .. " ")
        end
        term.setBackgroundColor(theme.bg)
        term.setTextColor(colors.yellow)
        if help then
            printCentered(h - 2, help)
        end
        local _, key = os.pullEvent("key")
        if key == keys.up then selected = (selected == 1) and #options or selected - 1
        elseif key == keys.down then selected = (selected == #options) and 1 or selected + 1
        elseif key == keys.enter then
            term.setBackgroundColor(theme.bg)
            term.setTextColor(theme.text)
            return selected
        elseif key == keys.q or key == keys.tab then return nil
        end
    end
end

--==============================================================================
-- Core Application Logic
--==============================================================================

local function downloadFile(path)
    local url = GITHUB_REPO_URL .. path
    print("Downloading " .. path .. "...")
    local response = http.get(url)
    if response and response.getResponseCode() == 200 then
        return response.readAll()
    else
        return nil
    end
end

local function createInstallDisk(program)
    printCentered(10, "Downloading files...")
    local programCode = downloadFile(program.path)
    if not programCode then
        showMessage("Error", "Failed to download " .. program.path, true)
        return
    end

    local dependencies = {}
    for _, depPath in ipairs(program.dependencies) do
        local depCode = downloadFile(depPath)
        if not depCode then
            showMessage("Error", "Failed to download " .. depPath, true)
            return
        end
        dependencies[depPath] = depCode
    end

    local drive = peripheral.find("drive")
    if not drive or not drive.isDiskPresent() then
        showMessage("Error", "No disk in the drive. Please insert a disk and try again.", true)
        return
    end

    local mountPath = drive.getMountPath()
    if not mountPath then
        showMessage("Error", "Could not get disk mount path.", true)
        return
    end

    -- Clean the disk
    print("Cleaning disk...")
    for _, file in ipairs(fs.list(mountPath)) do
        fs.delete(mountPath .. "/" .. file)
    end

    -- Write the program and its dependencies
    print("Writing program files to disk...")
    local allFiles = { program.path }
    for _, dep in ipairs(program.dependencies) do
        table.insert(allFiles, dep)
    end

    for _, filePath in ipairs(allFiles) do
        local fileCode = dependencies[filePath] or programCode
        local destPath = mountPath .. "/" .. filePath
        fs.makeDir(fs.getDir(destPath))
        local file = fs.open(destPath, "w")
        file.write(fileCode)
        file.close()
    end
    print("Program files written.")

    -- Write the installation script
    print("Writing installation script...")
    local installScript = downloadFile("installer/install_template.lua")
    if not installScript then
        showMessage("Error", "Failed to download the installation script.", true)
        return
    end
    local startupFile = fs.open(mountPath .. "/startup.lua", "w")
    startupFile.write(installScript)
    startupFile.close()
    print("Installation script written.")

    -- Write the configuration file
    print("Writing configuration file...")
    local config = {
        name = program.name,
        main_program = program.path,
        files = allFiles,
        needs_setup = program.needs_setup or false,
        setup_type = program.setup_type or nil
    }
    local configFile = fs.open(mountPath .. "/install_config.lua", "w")
    configFile.write(textutils.serialize(config))
    configFile.close()
    print("Configuration file written.")

    -- Set the disk label
    print("Setting disk label...")
    drive.setDiskLabel(program.name .. " Installer")

    showMessage("Success", "Installation disk for " .. program.name .. " created successfully.", false)
end

local function mainMenu()
    while true do
        local options = INSTALLABLE_PROGRAMS
        table.insert(options, { name = "Exit" })
        local choice = drawMenu("Select a program to create an installation disk:", options, "Select a program and press Enter.")
        table.remove(options) -- remove exit

        if not choice or choice == #options + 1 then break end

        createInstallDisk(options[choice])
    end
end

--==============================================================================
-- Main Program Loop
--==============================================================================

local function main()
    mainMenu()
    drawFrame("Goodbye")
    printCentered(8, "Master Installer shutting down.")
    sleep(2)
end

main()
