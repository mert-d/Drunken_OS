--[[
    Drunken OS - Master Installer (v1.6 - UI Overhaul)
    by MuhendizBey

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

local MANIFEST_FILE = "installer/manifest.lua"
local manifest = nil
local INSTALLABLE_PROGRAMS = {}

local function fetchManifest()
    print("Fetching manifest from GitHub...")
    local url = GITHUB_REPO_URL .. MANIFEST_FILE .. "?t=" .. os.time()
    local response = http.get(url)
    if response and response.getResponseCode() == 200 then
        local content = response.readAll()
        response.close()
        -- Safely load the manifest table
        local func, err = load(content, "manifest", "t", {})
        if func then
            manifest = func()
            print("Manifest loaded successfully.")
            return true
        else
            print("Error loading manifest Lua: " .. tostring(err))
        end
    else
        print("Failed to download manifest.")
    end
    return false
end

local function buildProgramList()
    INSTALLABLE_PROGRAMS = {}
    if not manifest or not manifest.packages then return end

    -- Convert the key-value packages table into a sorted list
    for key, pkg in pairs(manifest.packages) do
        local entry = {
            id = key, -- Store the key for reference
            name = pkg.name,
            type = pkg.type,
            path = pkg.main,
            files = pkg.files or {},
            include_shared = pkg.include_shared,
            needs_setup = pkg.needs_setup,
            setup_type = pkg.setup_type
        }
        
        -- Resolve full dependency list including shared files
        local allFiles = {}
        -- Add package specific files
        for _, f in ipairs(entry.files) do table.insert(allFiles, f) end
        
        -- Add shared files if requested
        if entry.include_shared and manifest.shared then
            for _, f in ipairs(manifest.shared) do
                -- Check for duplicates (simple check)
                local exists = false
                for _, existing in ipairs(allFiles) do
                    if existing == f then exists = true; break end
                end
                if not exists then table.insert(allFiles, f) end
            end
        end
        
        -- We store the resolved file list as 'dependencies' for compatibility with existing installer logic
        -- But wait, the existing logic expects 'dependencies' to NOT include the main file usually, 
        -- or it handles it. Let's check createInstallDisk.
        -- createInstallDisk: local allFiles = { program.path }; join dependencies...
        
        -- So 'dependencies' should be everything EXCEPT the main path? 
        -- Or I can just override the logic later.
        -- Let's just create a 'full_file_list' property and update createInstallDisk to use it.
        entry.full_file_list = allFiles
        
        table.insert(INSTALLABLE_PROGRAMS, entry)
    end

    -- Sort by name
    table.sort(INSTALLABLE_PROGRAMS, function(a, b) return a.name < b.name end)
end

--==============================================================================
-- Graphical UI & Theme
--==============================================================================

local theme = {
    bg = colors.black,
    text = colors.white,
    prompt = colors.yellow,
    titleBg = colors.blue,
    titleText = colors.white,
    highlightBg = colors.cyan,
    highlightText = colors.black,
    errorBg = colors.red,
    errorText = colors.white,
}

local function showSplashScreen()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setTextColor(colors.yellow)
    local art = {
        "      _-_          ",
        "    /~~   ~~\\      ",
        " /~~         ~~\\   ",
        "{               }  ",
        " \\  _-     -_  /   ",
        "   ~  \\\\ //  ~     ",
        "_- -   | | _- _    ",
        "  _ -  | |   -_    ",
        "      // \\\\        "
    }
    local title = "Drunken Master Installer"
    local startY = math.floor(h / 2) - math.floor(#art / 2) - 1
    for i, line in ipairs(art) do
        term.setCursorPos(math.floor(w / 2 - #line / 2), startY + i)
        term.write(line)
    end
    term.setCursorPos(math.floor(w / 2 - #title / 2), startY + #art + 2)
    term.write(title)
    sleep(1)
end

local function drawWindow(title)
    local w, h = term.getSize()
    term.setBackgroundColor(theme.bg)
    term.clear()
    
    -- Draw title and bottom borders
    term.setBackgroundColor(theme.titleBg)
    term.setCursorPos(1, 1); term.write(string.rep(" ", w))
    term.setCursorPos(1, h); term.write(string.rep(" ", w))
    -- Draw side borders
    for i = 2, h - 1 do
        term.setCursorPos(1, i); term.write(" ")
        term.setCursorPos(w, i); term.write(" ")
    end

    -- Render the centered title text
    term.setCursorPos(1, 1)
    term.setTextColor(theme.titleText)
    local titleText = " " .. (title or "Master Installer") .. " "
    local titleStart = math.floor((w - #titleText) / 2) + 1
    term.setCursorPos(titleStart, 1)
    term.write(titleText)
    
    term.setBackgroundColor(theme.bg)
    term.setTextColor(theme.text)
end

local function printCentered(startY, text)
    local w, h = term.getSize()
    local maxWidth = w - 6 -- Padding for the side borders
    
    if #text > maxWidth then
        local words = {}
        for word in text:gmatch("%S+") do table.insert(words, word) end
        
        local lines = {}
        local currentLine = ""
        for _, word in ipairs(words) do
            if #currentLine + #word + 1 <= maxWidth then
                currentLine = currentLine == "" and word or (currentLine .. " " .. word)
            else
                table.insert(lines, currentLine)
                currentLine = word
            end
        end
        table.insert(lines, currentLine)
        
        -- Center the lines vertically around startY if there are many?
        -- For now, just print downwards from startY.
        for i, line in ipairs(lines) do
            local x = math.floor((w - #line) / 2) + 1
            term.setCursorPos(x, startY + i - 1)
            term.write(line)
        end
    else
        local x = math.floor((w - #text) / 2) + 1
        term.setCursorPos(x, startY)
        term.write(text)
    end
end

local function showMessage(title, message, isError)
    drawWindow(title)
    local w, h = term.getSize()
    
    if isError then
        term.setTextColor(theme.errorBg)
        printCentered(4, "!!! ERROR !!!")
        term.setTextColor(theme.text)
    end
    
    printCentered(6, message)
    
    local continueText = "Press any key to continue..."
    term.setCursorPos(math.floor((w - #continueText) / 2) + 1, h - 1)
    term.setTextColor(colors.gray)
    term.write(continueText)
    
    os.pullEvent("key")
end

local function drawMenu(title, options)
    local w, h = term.getSize()
    local selected = 1
    local scroll = 1
    local listHeight = h - 6

    while true do
        drawWindow(title)
        
        -- Handle scrolling
        if selected < scroll then scroll = selected
        elseif selected >= scroll + listHeight then scroll = selected - listHeight + 1 end
        for i = scroll, math.min(scroll + listHeight - 1, #options) do
            local opt = options[i]
            local y = 4 + (i - scroll)
            term.setCursorPos(4, y)

            local name = opt.name
            if #name > w - 10 then name = name:sub(1, w - 13) .. "..." end
            
            if i == selected then
                term.setBackgroundColor(theme.highlightBg)
                term.setTextColor(theme.highlightText)
                term.write(" > " .. name .. string.rep(" ", w - 10 - #name) .. " ")
            else
                term.setBackgroundColor(theme.bg)
                term.setTextColor(theme.text)
                term.write("   " .. name)
            end
        end

        term.setBackgroundColor(theme.bg)
        term.setTextColor(theme.prompt)
        local current_selection = options[selected]
        if current_selection.name == "Drunken OS Client" then
            printCentered(h - 2, "PC: Insert Pocket Computer and ENTER.")
        elseif current_selection.name == "Exit" then
            printCentered(h - 2, "Press ENTER to exit.")
        else
            printCentered(h - 2, "DISK: Insert blank disk and ENTER.")
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

local function getFileContent(path)
    -- Try local file first (Bundling)
    if fs.exists(path) then
        print("Reading local file " .. path .. "...")
        local file = fs.open(path, "r")
        local content = file.readAll()
        file.close()
        return content
    end

    -- Fallback to remote download
    local url = GITHUB_REPO_URL .. path
    print("Downloading " .. path .. "...")
    local response = http.get(url)
    if response and response.getResponseCode() == 200 then
        return response.readAll()
    else
        return nil
    end
end

local function installToPocketComputer(program, drive)
    if program.type ~= "client" then
        showMessage("Error", "Only client programs can be installed to a Pocket Computer.", true)
        return
    end

    showMessage("Pocket Computer detected.", "Starting direct installation...", false)

    local mountPath = drive.getMountPath()
    if not mountPath then
        showMessage("Error", "Could not get pocket computer mount path.", true)
        return
    end

    print("Cleaning pocket computer...")
    for _, file in ipairs(fs.list(mountPath)) do
        fs.delete(mountPath .. "/" .. file)
    end

    local allFiles = program.full_file_list or { program.path }
    if not program.full_file_list and program.dependencies then
         for _, dep in ipairs(program.dependencies) do table.insert(allFiles, dep) end
    end

    for _, filePath in ipairs(allFiles) do
        local fileCode = getFileContent(filePath)
        if not fileCode then
            showMessage("Error", "Failed to get content for " .. filePath, true)
            return
        end

        -- Determine the destination path:
        -- 1. If it's the main program, put it in the root.
        -- 2. If it's a library or app, keep its relative structure (lib/, apps/).
        local destPath
        if filePath == program.path then
            destPath = mountPath .. "/" .. fs.getName(filePath)
        else
            -- We want to preserve the 'lib/' or 'apps/' folder structure
            destPath = mountPath .. "/" .. filePath
        end

        fs.makeDir(fs.getDir(destPath))
        local fileHandle, err = fs.open(destPath, "w")
        if not fileHandle then
            showMessage("Error", "Failed to write to pocket computer: " .. (err or "Unknown error"), true)
            return
        end
        fileHandle.write(fileCode)
        fileHandle.close()
    end

    -- Create the startup file on the pocket computer
    local mainProgramName = fs.getName(program.path)
    local startupCode = "shell.run('/" .. mainProgramName .. "')"
    local startupPath = mountPath .. "/startup.lua"
    local startupFile, err = fs.open(startupPath, "w")
    if not startupFile then
        showMessage("Error", "Failed to write startup file: " .. (err or "Unknown error"), true)
        return
    end
    startupFile.write(startupCode)
    startupFile.close()

    showMessage("Success", "Installation to Pocket Computer complete.", false)
end

local function createInstallDisk(program)
    printCentered(10, "Gathering files...")
    local programCode = getFileContent(program.path)
    if not programCode then
        showMessage("Error", "Failed to get content for " .. program.path, true)
        return
    end

    local dependencies = {}
    
    -- If we have full_file_list, gathering dependencies is slightly different because
    -- we want to key them by path, and 'programCode' is already fetched above (though maybe unnecessary if it's in the list).
    -- Actually, let's just use allFiles for everything.
    local allFiles = program.full_file_list or { program.path }
    if not program.full_file_list and program.dependencies then
        for _, dep in ipairs(program.dependencies) do table.insert(allFiles, dep) end
    end

     for _, filePath in ipairs(allFiles) do
        -- Skip the main program if we fetched it separately, or just overwrite it, doesn't matter.
        -- We store everything in dependencies map for the disk installer logic below
        local code = getFileContent(filePath)
        if not code then
            showMessage("Error", "Failed to get content for " .. filePath, true)
            return
        end
        dependencies[filePath] = code
    end

    local drive = peripheral.find("drive")
    if not drive then
        showMessage("Error", "No disk drive attached.", true)
        return
    end

    local peripheralType = peripheral.getType(drive)

    if program.name == "Drunken OS Client" then
        -- Force direct installation for client, as it's likely a pocket computer
        -- or intended to become a bootable disk.
        installToPocketComputer(program, drive)
        return
    end

    -- For other programs, we might want to prevent installation on pocket computers
    -- but distinguishing them from disks is hard. For now, we assume if it's not
    -- the client, we make an installer disk.

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
    -- allFiles is already defined and populated above

    -- Check total size
    local totalSize = 0
    for _, filePath in ipairs(allFiles) do
        local content = dependencies[filePath] or programCode
        totalSize = totalSize + #content
    end
    
    local freeSpace = fs.getFreeSpace(mountPath)
    local safetyBuffer = 5120 -- 5 KB buffer for installer scripts
    if (totalSize + safetyBuffer) > freeSpace then
        showMessage("Error", string.format("Disk full! Required: %d KB, Free: %d KB.\nPlease use a blank or larger disk.", math.ceil((totalSize + safetyBuffer)/1024), math.ceil(freeSpace/1024)), true)
        return
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

    -- Write the installation script(s)
    print("Writing installation script(s)...")
    local installScript = getFileContent("installer/install_template.lua")
    if not installScript then
        showMessage("Error", "Failed to get main installation script.", true)
        return
    end

    if program.type == "server" then
        local serverStartupScript = getFileContent("installer/server_startup_template.lua")
        if not serverStartupScript then
            showMessage("Error", "Failed to download the server startup script.", true)
            return
        end
        local serverStartupFile = fs.open(mountPath .. "/server_startup.lua", "w")
        if not serverStartupFile then
            showMessage("Error", "Could not write server startup script. Disk full?", true)
            return
        end
        serverStartupFile.write(serverStartupScript)
        serverStartupFile.close()
    end

    local startupFile = fs.open(mountPath .. "/startup.lua", "w")
    if not startupFile then
        showMessage("Error", "Could not write installer startup script. Disk full?", true)
        return
    end
    startupFile.write(installScript)
    startupFile.close()
    print("Installation script written.")

    -- Write the configuration file
    print("Writing configuration file...")
    local config = {
        name = program.name,
        type = program.type, -- Added missing type
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
    drive.ejectDisk()
end

local function mainMenu()
    while true do
        local options = {}
        for _, v in ipairs(INSTALLABLE_PROGRAMS) do table.insert(options, v) end
        table.insert(options, { name = "Exit" })
        
        local choice = drawMenu("Select a program to install:", options)

        if not choice or options[choice].name == "Exit" then break end

        createInstallDisk(options[choice])
    end
end

--==============================================================================
-- Main Program Loop
--==============================================================================

local function main()
    showSplashScreen()
    if not fetchManifest() then
        drawWindow("Error")
        printCentered(8, "Could not fetch manifest!")
        printCentered(10, "Check internet connection.")
        sleep(3)
        return
    end
    buildProgramList()
    mainMenu()
    drawWindow("Goodbye")
    printCentered(8, "Master Installer shutting down.")
    sleep(1)
end

main()
