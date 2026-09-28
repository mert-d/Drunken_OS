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
local CATEGORY_PACKAGES = {}

-- Human-readable metadata and hardware descriptions for each package
local PACKAGE_METADATA = {
    client = {
        category = "clients",
        badge = "[CLIENT]",
        hardware = "Pocket Computer or Advanced PC",
        desc = "Full OS: 10 apps, 14 games, Create tools & NetRadar",
        prompt = "PC: Insert Pocket Computer in drive and press ENTER."
    },
    remote_switch = {
        category = "clients",
        badge = "[SWITCH]",
        hardware = "Advanced Computer + Wireless Modem",
        desc = "Headless redstone node for base doors, sirens & machines",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    server = {
        category = "servers",
        badge = "[SERVER]",
        hardware = "Advanced PC + Wired & Wireless Modem",
        desc = "Mainframe Gateway: coordinates chat, auth, and app sync",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    auth_server = {
        category = "servers",
        badge = "[AUTH]",
        hardware = "Advanced PC + Wired Modem",
        desc = "Cryptographic authentication authority with SHA-1 tokens",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    hyperauth_server = {
        category = "servers",
        badge = "[HYPERAUTH]",
        hardware = "Command Computer + Wireless Modem",
        desc = "Minecraft tellraw 2FA code dispatcher & token authority",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    bank_server = {
        category = "servers",
        badge = "[BANK]",
        hardware = "Advanced PC + Wired Modem",
        desc = "Double-entry banking ledger, player accounts & stock market",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    mail_server = {
        category = "servers",
        badge = "[MAIL]",
        hardware = "Advanced PC + Wired Modem",
        desc = "Player email messaging and cloud document storage",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    arcade_server = {
        category = "servers",
        badge = "[ARCADE]",
        hardware = "Advanced PC + Wireless/Wired Modem",
        desc = "Arcade distributor & leaderboards (bundles all 14 arcade games!)",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    proxy_mainframe = {
        category = "servers",
        badge = "[PROXY]",
        hardware = "Advanced PC + Wired & Wireless Modem",
        desc = "Wireless-to-wired network bridge for Mainframe, Chat & Mail",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    proxy_bank = {
        category = "servers",
        badge = "[PROXY]",
        hardware = "Advanced PC + Wired & Wireless Modem",
        desc = "Secure network bridge isolating internal bank vault network",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    atm = {
        category = "commerce",
        badge = "[ATM]",
        hardware = "Advanced Computer + Monitor",
        desc = "Public ATM kiosk for PIN deposits, withdrawals & balance check",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    clerk = {
        category = "commerce",
        badge = "[CLERK]",
        hardware = "Advanced Computer (Bank staff desk)",
        desc = "Bank staff workstation for issuing customer accounts & cards",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    merchant_cashier = {
        category = "commerce",
        badge = "[CASHIER]",
        hardware = "Advanced Computer (Store counter)",
        desc = "Retail merchant checkout counter accepting customer bank cards",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    merchant_pos = {
        category = "commerce",
        badge = "[POS]",
        hardware = "Pocket Computer + Wireless Modem",
        desc = "Roaming handheld point-of-sale checkout terminal for vendors",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    auditor = {
        category = "turtles",
        badge = "[TURTLE]",
        hardware = "Advanced Turtle + Wired Modem",
        desc = "Bank sentinel verifying SHA-1 ledger hash chains in real time",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    bank_clerk_turtle = {
        category = "turtles",
        badge = "[TURTLE]",
        hardware = "Advanced Turtle (Bank vault)",
        desc = "Automated vault teller dispensing physical currency and items",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    vending_turtle = {
        category = "turtles",
        badge = "[TURTLE]",
        hardware = "Advanced Turtle + Chest",
        desc = "Autonomous shop fulfillment robot dispensing purchased goods",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    turtle_auth_terminal = {
        category = "turtles",
        badge = "[TURTLE]",
        hardware = "Advanced Turtle",
        desc = "Turtle-based authentication validation terminal",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    restaurant_server = {
        category = "restaurant",
        badge = "[FOOD]",
        hardware = "Advanced PC (Kitchen)",
        desc = "Drunken Bites kitchen queue manager coordinating food orders",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    chef_turtle = {
        category = "restaurant",
        badge = "[CHEF]",
        hardware = "Advanced Turtle + Furnaces",
        desc = "Automated cooking robot preparing food recipes in furnaces",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    },
    waiter_turtle = {
        category = "restaurant",
        badge = "[WAITER]",
        hardware = "Advanced Turtle + GPS",
        desc = "GPS-guided food delivery robot serving customer dining tables",
        prompt = "DISK: Insert blank floppy disk and press ENTER."
    }
}

local CATEGORY_DEFS = {
    {
        id = "clients",
        name = "Clients & Handhelds",
        desc = "Handheld Pocket OS, remote base switches, and desktop terminals"
    },
    {
        id = "servers",
        name = "Core Servers & Proxies",
        desc = "Central mainframe, auth, bank, mail, arcade (14 games) & proxies"
    },
    {
        id = "commerce",
        name = "Commerce & Banking Kiosks",
        desc = "Public ATM machines, merchant POS, and cashier counters"
    },
    {
        id = "turtles",
        name = "Autonomous Robots (Turtles)",
        desc = "Bank auditor sentinel, vault clerk, vending dispenser turtle"
    },
    {
        id = "restaurant",
        name = "Restaurant Automation",
        desc = "Drunken Bites kitchen queue manager, chef & waiter turtles"
    }
}

local function fetchManifest()
    local localPaths = { "installer/manifest.lua", "manifest.lua", "/disk/installer/manifest.lua", "/disk/manifest.lua" }

    if http and http.get then
        print("Fetching manifest from GitHub...")
        local url = GITHUB_REPO_URL .. MANIFEST_FILE .. "?t=" .. os.time()
        local ok_http, response = pcall(http.get, url)
        if ok_http and response and response.getResponseCode() == 200 then
            local content = response.readAll()
            response.close()
            local func, err = load(content, "manifest", "t", {})
            if func then
                manifest = func()
                print("Manifest loaded successfully via HTTP.")
                return true
            else
                print("Error parsing manifest Lua: " .. tostring(err))
            end
        else
            print("HTTP download unavailable. Checking local manifest...")
        end
    end

    -- Local/Disk Fallback
    for _, path in ipairs(localPaths) do
        if fs.exists(path) then
            local f = fs.open(path, "r")
            if f then
                local content = f.readAll()
                f.close()
                local func, err = load(content, "manifest", "t", {})
                if func then
                    manifest = func()
                    print("Manifest loaded from local file: " .. path)
                    return true
                end
            end
        end
    end

    print("Failed to load manifest (HTTP failed and no local manifest found).")
    return false
end

local function buildProgramList()
    INSTALLABLE_PROGRAMS = {}
    CATEGORY_PACKAGES = {}
    for _, cat in ipairs(CATEGORY_DEFS) do
        CATEGORY_PACKAGES[cat.id] = {}
    end

    if not manifest or not manifest.packages then return end

    -- Convert the key-value packages table into a sorted list
    for key, pkg in pairs(manifest.packages) do
        local meta = PACKAGE_METADATA[key] or {
            category = "misc",
            badge = "[PKG]",
            hardware = "ComputerCraft Machine",
            desc = pkg.name,
            prompt = "DISK: Insert blank floppy disk and press ENTER."
        }

        local entry = {
            id = key, -- Store the key for reference
            name = pkg.name,
            type = pkg.type,
            path = pkg.main,
            files = pkg.files or {},
            include_shared = pkg.include_shared,
            needs_setup = pkg.needs_setup,
            setup_type = pkg.setup_type,
            badge = meta.badge,
            hardware = meta.hardware,
            desc = meta.desc,
            prompt = meta.prompt,
            category = meta.category
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
        
        entry.full_file_list = allFiles
        
        table.insert(INSTALLABLE_PROGRAMS, entry)

        local catId = entry.category or "misc"
        if not CATEGORY_PACKAGES[catId] then
            CATEGORY_PACKAGES[catId] = {}
        end
        table.insert(CATEGORY_PACKAGES[catId], entry)
    end

    -- Sort by name
    table.sort(INSTALLABLE_PROGRAMS, function(a, b) return a.name < b.name end)
    for catId, list in pairs(CATEGORY_PACKAGES) do
        table.sort(list, function(a, b) return a.name < b.name end)
    end
end

--==============================================================================
-- Graphical UI & Theme
--==============================================================================

local isColor = term.isColor and term.isColor()
local theme = {
    bg = colors.black,
    text = colors.white,
    subText = isColor and colors.lightGray or colors.white,
    prompt = isColor and colors.yellow or colors.white,
    titleBg = isColor and colors.blue or colors.white,
    titleText = isColor and colors.white or colors.black,
    highlightBg = isColor and colors.cyan or colors.white,
    highlightText = isColor and colors.black or colors.black,
    badgeText = isColor and colors.yellow or colors.white,
    errorBg = isColor and colors.red or colors.white,
    errorText = colors.white,
}

local function showSplashScreen()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setTextColor(colors.yellow)
    local art = {
        "       _-_          ",
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

local function drawMenu(title, options, isCategoryMenu)
    local w, h = term.getSize()
    local selected = 1
    local scroll = 1
    local listHeight = math.max(4, h - 9)

    while true do
        drawWindow(title)

        -- Section Subtitle
        term.setCursorPos(4, 3)
        term.setTextColor(theme.prompt)
        term.write(isCategoryMenu and "SELECT CATEGORY:" or "SELECT PACKAGE TO INSTALL:")

        -- Handle scrolling
        if selected < scroll then scroll = selected
        elseif selected >= scroll + listHeight then scroll = selected - listHeight + 1 end

        for i = scroll, math.min(scroll + listHeight - 1, #options) do
            local opt = options[i]
            local y = 4 + (i - scroll)
            term.setCursorPos(4, y)

            local prefix = string.format("[%d] ", i)
            if opt.isBack then prefix = "[B] "
            elseif opt.isExit then prefix = "[Q] "
            elseif i > 9 then prefix = "    " end

            local badge = opt.badge or ""
            local maxNameLen = w - 10 - #prefix - #badge
            local name = opt.name
            if #name > maxNameLen then name = name:sub(1, maxNameLen - 3) .. "..." end

            local spacing = w - 8 - #prefix - #name - #badge
            if spacing < 1 then spacing = 1 end

            if i == selected then
                term.setBackgroundColor(theme.highlightBg)
                term.setTextColor(theme.highlightText)
                term.write(" > " .. prefix .. name .. string.rep(" ", spacing) .. badge .. " ")
            else
                term.setBackgroundColor(theme.bg)
                term.setTextColor(theme.prompt)
                term.write("   " .. prefix)
                term.setTextColor(theme.text)
                term.write(name)
                term.setCursorPos(w - 3 - #badge, y)
                term.setTextColor(theme.badgeText)
                term.write(badge)
            end
        end

        -- Detail info panel
        local cur = options[selected]
        if cur then
            -- Divider
            term.setBackgroundColor(theme.bg)
            term.setTextColor(colors.gray)
            term.setCursorPos(3, h - 5)
            term.write(string.rep("-", w - 4))

            -- Line h-4: Description
            local desc = cur.desc or ""
            if #desc > w - 6 then desc = desc:sub(1, w - 9) .. "..." end
            term.setCursorPos(3, h - 4)
            term.setTextColor(theme.subText)
            term.write(" " .. desc)

            -- Line h-3: Hardware target
            local hw = cur.hardware or ""
            if #hw > 0 then
                term.setCursorPos(3, h - 3)
                term.setTextColor(colors.cyan)
                term.write(" Target: " .. hw:sub(1, w - 12))
            end

            -- Line h-2: Action prompt
            local prompt = cur.prompt or (cur.name == "Drunken OS Client" and "PC: Insert Pocket Computer and ENTER." or (cur.isExit and "Press ENTER to exit." or (cur.isBack and "Press ENTER to return." or "DISK: Insert blank disk and ENTER.")))
            term.setCursorPos(3, h - 2)
            term.setTextColor(theme.prompt)
            term.write(" " .. prompt:sub(1, w - 6))
        end

        -- Bottom Bar
        term.setBackgroundColor(theme.titleBg)
        term.setTextColor(theme.titleText)
        term.setCursorPos(1, h)
        local footer = isCategoryMenu and " [1-6/Arrows] Select | [ENTER] Open | [Q] Exit" or " [1-9/Arrows] Select | [ENTER] Burn Disk | [B/Q] Back"
        term.write(footer .. string.rep(" ", math.max(0, w - #footer)))

        -- Pull event (keyboard + mouse)
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local key = p1
            if key == keys.up then
                selected = (selected == 1) and #options or selected - 1
            elseif key == keys.down then
                selected = (selected == #options) and 1 or selected + 1
            elseif key == keys.pageUp then
                selected = math.max(1, selected - listHeight)
            elseif key == keys.pageDown then
                selected = math.min(#options, selected + listHeight)
            elseif key == keys.home then
                selected = 1
            elseif key == keys["end"] or key == keys.bottom then
                selected = #options
            elseif key == keys.enter or key == keys.numPadEnter then
                term.setBackgroundColor(theme.bg)
                term.setTextColor(theme.text)
                return selected
            elseif key == keys.q or key == keys.b or key == keys.backspace or key == keys.left then
                return nil
            end
        elseif event == "char" then
            local ch = p1:lower()
            local num = tonumber(ch)
            if num and num >= 1 and num <= #options then
                selected = num
                term.setBackgroundColor(theme.bg)
                term.setTextColor(theme.text)
                return selected
            elseif ch == "q" or ch == "b" then
                return nil
            end
        elseif event == "mouse_click" then
            local button, cx, cy = p1, p2, p3
            if button == 1 then
                if cy >= 4 and cy < 4 + listHeight then
                    local clicked = scroll + (cy - 4)
                    if clicked >= 1 and clicked <= #options then
                        if selected == clicked then
                            term.setBackgroundColor(theme.bg)
                            term.setTextColor(theme.text)
                            return clicked
                        else
                            selected = clicked
                        end
                    end
                elseif cy == h then
                    if cx > w - 12 then return nil end
                end
            end
        elseif event == "mouse_scroll" then
            local dir = p1
            if dir == -1 then
                selected = math.max(1, selected - 1)
            elseif dir == 1 then
                selected = math.min(#options, selected + 1)
            end
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
    local url = GITHUB_REPO_URL .. path .. "?v=" .. tostring(os.epoch("utc"))
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

        local parentDir = fs.getDir(destPath)
        if parentDir and parentDir ~= "" and not fs.exists(parentDir) then
            fs.makeDir(parentDir)
        end
        local fileHandle, err = fs.open(destPath, "w")
        if not fileHandle then
            showMessage("Error", "Failed to write to pocket computer: " .. (err or "Unknown error"), true)
            return
        end
        fileHandle.write(fileCode)
        fileHandle.close()
    end

    -- Create the startup files on the pocket computer (modern + legacy)
    local mainProgramName = fs.getName(program.path)
    local startupCode = "shell.run('/" .. mainProgramName .. "')\n"
    local startupPath = mountPath .. "/startup.lua"
    local startupFile, err = fs.open(startupPath, "w")
    if not startupFile then
        showMessage("Error", "Failed to write startup file: " .. (err or "Unknown error"), true)
        return
    end
    startupFile.write(startupCode)
    startupFile.close()

    local startupLegacy = mountPath .. "/startup"
    local sLegacyFile = fs.open(startupLegacy, "w")
    if sLegacyFile then
        sLegacyFile.write(startupCode)
        sLegacyFile.close()
    end

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
    if not mountPath or (drive.isDiskPresent and not drive.isDiskPresent()) then
        showMessage("Disk Error", "No disk detected in the drive!\nPlease insert a floppy disk and try again.", true)
        return
    end

    if fs.isReadOnly and fs.isReadOnly(mountPath) then
        showMessage("Disk Error", "The inserted disk is write-protected or read-only!\nPlease insert a writable floppy disk.", true)
        return
    end

    -- Clean the disk
    print("Cleaning disk...")
    for _, file in ipairs(fs.list(mountPath)) do
        fs.delete(mountPath .. "/" .. file)
    end

    -- Pre-load installation scripts and serialize config BEFORE writing
    print("Preparing installer scripts...")
    local installScript = getFileContent("installer/install_template.lua")
    if not installScript then
        showMessage("Error", "Failed to get main installation script (installer/install_template.lua).", true)
        return
    end

    local serverStartupScript = nil
    if program.type == "server" then
        serverStartupScript = getFileContent("installer/server_startup_template.lua")
        if not serverStartupScript then
            showMessage("Error", "Failed to get server startup script (installer/server_startup_template.lua).", true)
            return
        end
    end

    local config = {
        name = program.name,
        type = program.type,
        main_program = program.path,
        files = allFiles,
        needs_setup = program.needs_setup or false,
        setup_type = program.setup_type or nil
    }
    local configSerialized = textutils.serialize(config)

    -- Accurate total size calculation
    local programFilesSize = 0
    for _, filePath in ipairs(allFiles) do
        local content = dependencies[filePath] or programCode
        programFilesSize = programFilesSize + #content
    end

    local installerScriptsSize = #installScript + (serverStartupScript and #serverStartupScript or 0) + #configSerialized
    local safetyMargin = 2048 -- 2 KB safe buffer for filesystem metadata
    local requiredTotal = programFilesSize + installerScriptsSize + safetyMargin

    local freeSpace = fs.getFreeSpace(mountPath)
    if requiredTotal > freeSpace then
        local reqKb = math.ceil(requiredTotal / 1024)
        local freeKb = math.ceil(freeSpace / 1024)
        local diffKb = reqKb - freeKb
        showMessage("Disk Full", string.format("Cannot create installer for '%s'.\nRequired: %d KB | Free: %d KB (%d KB short).\nPlease insert a higher-capacity floppy disk.", program.name, reqKb, freeKb, diffKb), true)
        return
    end

    -- Verified file writer function
    local function writeVerified(relPath, content)
        local destPath = mountPath .. "/" .. relPath
        local parentDir = fs.getDir(destPath)
        if parentDir and parentDir ~= "" and not fs.exists(parentDir) then
            fs.makeDir(parentDir)
        end
        local file, err = fs.open(destPath, "w")
        if not file then
            return false, "Cannot write " .. relPath .. ": " .. tostring(err or "disk error")
        end
        file.write(content)
        file.close()
        if fs.getSize(destPath) < #content then
            return false, "Write truncated on " .. relPath .. " (disk capacity exceeded)!"
        end
        return true
    end

    -- Write critical boot files FIRST so disk is never half-created without bootloader
    print("Writing installer boot files...")
    local ok_boot, err_boot = writeVerified("startup.lua", installScript)
    if not ok_boot then
        showMessage("Write Error", "Failed to write startup.lua:\n" .. tostring(err_boot), true)
        return
    end

    -- Legacy BIOS forwarder: supports computers looking for 'startup' without .lua extension
    local forwarderScript = 'local d = fs.getDir(shell and shell.getRunningProgram and shell.getRunningProgram() or ""); local t = fs.combine(d, "startup.lua"); if fs.exists(t) then shell.run("/" .. t) elseif fs.exists("disk/startup.lua") then shell.run("disk/startup.lua") else shell.run("startup.lua") end\n'
    local ok_boot2, err_boot2 = writeVerified("startup", forwarderScript)
    if not ok_boot2 then
        showMessage("Write Error", "Failed to write startup:\n" .. tostring(err_boot2), true)
        return
    end

    if program.type == "server" and serverStartupScript then
        local ok_srv, err_srv = writeVerified("server_startup.lua", serverStartupScript)
        if not ok_srv then
            showMessage("Write Error", "Failed to write server_startup.lua:\n" .. tostring(err_srv), true)
            return
        end
        local ok_srv2, err_srv2 = writeVerified("server_startup", 'shell.run("server_startup.lua")\n')
        if not ok_srv2 then
            showMessage("Write Error", "Failed to write server_startup:\n" .. tostring(err_srv2), true)
            return
        end
    end

    local ok_cfg, err_cfg = writeVerified("install_config.lua", configSerialized)
    if not ok_cfg then
        showMessage("Write Error", "Failed to write install_config.lua:\n" .. tostring(err_cfg), true)
        return
    end

    -- Write program files and dependencies
    print("Writing program files to disk...")
    for _, filePath in ipairs(allFiles) do
        local fileCode = dependencies[filePath] or programCode
        local destPath = mountPath .. "/" .. filePath

        -- Special Case: Preserve existing HyperAuth Configuration on disk, or seed fresh un-paired config
        if filePath == "HyperAuthClient/config.lua" and fs.exists(destPath) then
            print("Skipping existing config: " .. filePath)
        else
            if filePath == "HyperAuthClient/config.lua" then
                fileCode = [[return {
  PROTOCOL_NAME = "auth.secure.v1",

  CLIENT_ID     = "unpaired",
  SHARED_SECRET = "",

  KNOWN_SERVER_ID         = nil,
  DEFAULT_TIMEOUT_SECONDS = 6,
  PAIRED                  = false,
}
]]
            end
            local ok_f, err_f = writeVerified(filePath, fileCode)
            if not ok_f then
                showMessage("Write Error", "Failed writing " .. filePath .. ":\n" .. tostring(err_f), true)
                return
            end
        end
    end
    print("All program files written and verified.")

    -- Set the disk label
    print("Setting disk label...")
    drive.setDiskLabel(program.name .. " Installer")

    if program.id == "hyperauth_server" then
        showMessage("HyperAuth Disk Created", "Disk for " .. program.name .. " created!\n\nNOTE FOR COMMAND COMPUTER:\nMinecraft blocks floppy autorun on Command PCs.\nOn your Command PC, type:\n  disk/startup\nand press Enter to run the installer!", false)
    else
        showMessage("Success", "Installation disk for " .. program.name .. " created successfully.", false)
    end
    drive.ejectDisk()
end

local function mainMenu()
    while true do
        local catOptions = {}
        for i, cat in ipairs(CATEGORY_DEFS) do
            local count = CATEGORY_PACKAGES[cat.id] and #CATEGORY_PACKAGES[cat.id] or 0
            table.insert(catOptions, {
                name = cat.name,
                badge = string.format("[%2d pkgs]", count),
                desc = cat.desc,
                hardware = string.format("%d packages configured", count),
                prompt = "Press ENTER or [" .. i .. "] to view packages.",
                catId = cat.id
            })
        end

        -- Check for any unmapped misc packages
        if CATEGORY_PACKAGES["misc"] and #CATEGORY_PACKAGES["misc"] > 0 then
            table.insert(catOptions, {
                name = "Other Packages",
                badge = string.format("[%2d pkgs]", #CATEGORY_PACKAGES["misc"]),
                desc = "Additional or unclassified packages",
                hardware = "Miscellaneous packages",
                prompt = "Press ENTER to view packages.",
                catId = "misc"
            })
        end

        -- Option 6: Flat list of all packages
        table.insert(catOptions, {
            name = "View All Packages (Flat List)",
            badge = string.format("[%2d pkgs]", #INSTALLABLE_PROGRAMS),
            desc = "Browse all packages alphabetically without categories",
            hardware = "Complete system distribution catalog",
            prompt = "Press ENTER or [6] to browse full catalog.",
            catId = "all"
        })

        -- Exit Option
        table.insert(catOptions, {
            name = "Exit Installer",
            badge = "[EXIT]",
            desc = "Return to ComputerCraft command line shell",
            hardware = "Shutdown installer interface",
            prompt = "Press ENTER or [Q] to exit.",
            isExit = true
        })

        local choice = drawMenu("Drunken Master Installer (v16.8)", catOptions, true)
        if not choice or catOptions[choice].isExit then break end

        local selectedCat = catOptions[choice]

        -- Submenu loop for chosen category
        while true do
            local pkgList = {}
            if selectedCat.catId == "all" then
                pkgList = INSTALLABLE_PROGRAMS
            else
                pkgList = CATEGORY_PACKAGES[selectedCat.catId] or {}
            end

            local subOptions = {}
            for _, pkg in ipairs(pkgList) do
                table.insert(subOptions, pkg)
            end
            table.insert(subOptions, {
                name = "< Back to Categories",
                badge = "[BACK]",
                desc = "Return to the main category selection menu",
                hardware = "",
                prompt = "Press ENTER or [B] to return.",
                isBack = true
            })

            local subChoice = drawMenu(selectedCat.name, subOptions, false)
            if not subChoice or subOptions[subChoice].isBack then
                break
            end

            createInstallDisk(subOptions[subChoice])
        end
    end
end

--==============================================================================
-- Main Program Loop
--==============================================================================

---
-- Main application entry point for the Master Installer GUI.
-- Bootstraps the UI, fetches the latest manifest, and presents the installation options.
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
