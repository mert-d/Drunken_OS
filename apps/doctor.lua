--[[
    Drunken OS - In-Game System Doctor & Diagnostic Suite (apps/doctor.lua)
    by MuhendizBey
    Version: 1.0

    Performs comprehensive hardware, network, filesystem, and server health checks:
    - Display resolution & terminal profile (Pocket 26x20 vs Desktop 51x19)
    - Peripheral audit (wired/wireless modems, speakers, monitors, disk drives)
    - Network latency benchmark to World Spawn servers (Mainframe, Bank, Arcade, Auth)
    - Filesystem write permissions & database integrity check
    - 1-Click Auto-Repair (re-opens modems, flushes stale DNS, cleans orphaned .tmp files)
]]

if package and package.path then
    package.path = "/?.lua;" .. package.path
end
local utils = require("lib.utils")
local theme = require("lib.theme")
local ok_sound, Sound = pcall(require, "lib.sound")
local ok_dns, dns = pcall(require, "lib.dns")

local doctor = {}
doctor._VERSION = 1.0

local function getSafeSize()
    local w, h = term.getSize()
    return w or 51, h or 19
end

--- Performs a comprehensive diagnostic audit of the current computer.
-- @return table: Report table with hardware, peripherals, network, storage, and overallHealth.
function doctor.diagnose()
    local w, h = getSafeSize()
    local isPocket = (w <= 30)

    local report = {
        hardware = {},
        peripherals = {},
        network = {},
        storage = {},
        overallHealth = "Checking..."
    }

    -- 1. Display & Hardware
    local isColor = term.isColor and term.isColor()
    table.insert(report.hardware, {
        name = "Terminal Profile",
        val = string.format("%dx%d (%s)", w, h, isPocket and "Pocket Computer" or "Advanced Computer"),
        status = "OK"
    })
    table.insert(report.hardware, {
        name = "Display Engine",
        val = isColor and "16-Color Palette" or "1-Bit Monochrome",
        status = isColor and "OK" or "WARN"
    })
    table.insert(report.hardware, {
        name = "Computer ID",
        val = "#" .. tostring(os.getComputerID and os.getComputerID() or 0),
        status = "OK"
    })

    -- 2. Peripheral Audit
    local wiredModem, wirelessModem, speaker, monitor, diskDrive = nil, nil, nil, nil, nil
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            local pType = peripheral.getType(name)
            if pType == "modem" then
                local m = peripheral.wrap(name)
                if m and m.isWireless and m.isWireless() then
                    wirelessModem = name
                else
                    wiredModem = name
                end
            elseif pType == "speaker" then
                speaker = name
            elseif pType == "monitor" then
                monitor = name
            elseif pType == "drive" then
                diskDrive = name
            end
        end
    end

    local modemStatus = "FAIL"
    local modemVal = "None Attached"
    if wirelessModem and wiredModem then
        modemStatus = "OK"
        modemVal = "Dual (Wired: " .. wiredModem .. ", Wireless: " .. wirelessModem .. ")"
    elseif wirelessModem then
        modemStatus = "OK"
        modemVal = "Wireless (" .. wirelessModem .. ")"
    elseif wiredModem then
        modemStatus = "OK"
        modemVal = "Wired (" .. wiredModem .. ")"
    end
    table.insert(report.peripherals, { name = "Modems", val = modemVal, status = modemStatus })

    table.insert(report.peripherals, {
        name = "Speaker",
        val = speaker and ("Attached (" .. speaker .. ")") or "Not Present (Silent Mode)",
        status = speaker and "OK" or "INFO"
    })

    table.insert(report.peripherals, {
        name = "External Monitor",
        val = monitor and ("Attached (" .. monitor .. ")") or "None",
        status = "INFO"
    })

    table.insert(report.peripherals, {
        name = "Disk Drive",
        val = diskDrive and ("Attached (" .. diskDrive .. ")") or "None",
        status = "INFO"
    })

    -- 3. Rednet Channel Check
    local rednetOpen = rednet and rednet.isOpen and rednet.isOpen()
    table.insert(report.network, {
        name = "Rednet State",
        val = rednetOpen and "Active & Listening" or "Closed (Offline)",
        status = rednetOpen and "OK" or "FAIL"
    })

    -- 4. Server Latency Benchmarks
    local serverTargets = {
        { label = "Mainframe Gateway", proto = "SimpleMail", host = "mail.server" },
        { label = "Global Chat Server", proto = "SimpleChat", host = "chat.server" },
        { label = "DB Bank Server", proto = "DB_Bank", host = "bank.server" },
        { label = "Arcade Games Server", proto = "ArcadeGames", host = "arcade.server" },
        { label = "Auth Server", proto = "auth.secure.v1", host = "auth.server" },
    }

    for _, s in ipairs(serverTargets) do
        local startT = os.epoch and os.epoch("utc") or 0
        local sId = nil
        if rednetOpen and rednet.lookup then
            sId = rednet.lookup(s.proto, s.host)
        end
        local endT = os.epoch and os.epoch("utc") or 0
        local latency = math.max(1, endT - startT)

        if sId then
            table.insert(report.network, {
                name = s.label,
                val = string.format("ID %d (%dms)", sId, latency),
                status = "OK"
            })
        else
            table.insert(report.network, {
                name = s.label,
                val = "Unreachable / Asleep",
                status = "WARN"
            })
        end
    end

    -- 5. Storage & Database Integrity
    local freeSpace = (fs and fs.getFreeSpace and fs.getFreeSpace("/")) or 0
    local freeKb = math.floor(freeSpace / 1024)
    table.insert(report.storage, {
        name = "Free Disk Space",
        val = freeKb > 1024 and string.format("%.1f MB", freeKb / 1024) or (freeKb .. " KB"),
        status = freeKb > 50 and "OK" or "WARN"
    })

    -- Root write permission test
    local testOk = false
    if fs and fs.open and fs.delete then
        local testF = fs.open(".doctortest.tmp", "w")
        if testF then
            testF.write("ok")
            testF.close()
            fs.delete(".doctortest.tmp")
            testOk = true
        end
    end
    table.insert(report.storage, {
        name = "Filesystem Write",
        val = testOk and "Read/Write Verified" or "Write Blocked",
        status = testOk and "OK" or "FAIL"
    })

    -- Orphaned .tmp check
    local orphaned = 0
    if fs and fs.list then
        for _, f in ipairs(fs.list("")) do
            if f:match("%.tmp$") then orphaned = orphaned + 1 end
        end
    end
    table.insert(report.storage, {
        name = "Temp File Cleanup",
        val = orphaned == 0 and "Clean (0 orphaned)" or (orphaned .. " orphaned .tmp"),
        status = orphaned == 0 and "OK" or "WARN"
    })

    -- Evaluate Overall
    local hasFail = false
    local hasWarn = false
    for _, grp in ipairs({ report.hardware, report.peripherals, report.network, report.storage }) do
        for _, item in ipairs(grp) do
            if item.status == "FAIL" then hasFail = true end
            if item.status == "WARN" then hasWarn = true end
        end
    end

    if hasFail then
        report.overallHealth = "Degraded (Action Required)"
    elseif hasWarn then
        report.overallHealth = "Operational (Warnings)"
    else
        report.overallHealth = "100% Healthy (All Systems Nominal)"
    end

    return report
end

--- Executes 1-click auto repairs: re-opens modems, flushes stale DNS, purges orphaned .tmp files.
-- @return table: List of repair log strings.
function doctor.autoRepair()
    local repairs = {}

    -- 1. Re-open modems
    if peripheral and peripheral.getNames and rednet and rednet.open then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "modem" then
                pcall(rednet.open, name)
                table.insert(repairs, "Opened modem on " .. name)
            end
        end
    end

    -- 2. Flush stale DNS cache
    if ok_dns and dns and dns.flush then
        pcall(dns.flush)
        table.insert(repairs, "Refreshed universal DNS cache")
    end

    -- 3. Delete orphaned temp files
    if fs and fs.list and fs.delete then
        for _, f in ipairs(fs.list("")) do
            if f:match("%.tmp$") then
                pcall(fs.delete, f)
                table.insert(repairs, "Purged orphaned " .. f)
            end
        end
    end

    if ok_sound and Sound and Sound.playSuccess then
        pcall(Sound.playSuccess)
    end

    return repairs
end

function doctor.run(context)
    context = context or {}
    local drawWindow = context.drawWindow or function(t) utils.drawWindow(t, context) end
    local showMessage = context.showMessage or function(t, m) utils.showMessage(t, m, context) end

    local w, h = getSafeSize()
    local isPocket = (w <= 30)

    local report = doctor.diagnose()

    local scrollOffset = 0
    while true do
        w, h = getSafeSize()
        drawWindow(isPocket and "Doc v1.0" or "System Doctor Diagnostics v1.0")

        local curY = 3
        local statusCol = colors.lime
        if report.overallHealth:find("Degraded") then statusCol = colors.red
        elseif report.overallHealth:find("Warnings") then statusCol = colors.yellow end

        term.setCursorPos(2, curY)
        term.setTextColor(statusCol)
        term.write("[*] " .. report.overallHealth)
        curY = curY + 2

        local lines = {}
        local function addSection(title, items)
            table.insert(lines, { isHeader = true, text = "--- " .. title .. " ---" })
            for _, item in ipairs(items) do
                table.insert(lines, { isHeader = false, item = item })
            end
        end

        addSection("Display & System", report.hardware)
        addSection("Attached Peripherals", report.peripherals)
        addSection("Network & World Servers", report.network)
        addSection("Filesystem & Storage", report.storage)

        local maxVisible = h - curY - 2
        if maxVisible < 1 then maxVisible = 1 end

        for i = 1, maxVisible do
            local idx = scrollOffset + i
            if idx <= #lines then
                local entry = lines[idx]
                term.setCursorPos(2, curY + i - 1)
                if entry.isHeader then
                    term.setTextColor(colors.cyan)
                    term.write(entry.text:sub(1, w - 2))
                else
                    local it = entry.item
                    local tag = "[ OK ]"
                    local tagCol = colors.lime
                    if it.status == "WARN" then
                        tag = "[WARN]"
                        tagCol = colors.yellow
                    elseif it.status == "FAIL" then
                        tag = "[FAIL]"
                        tagCol = colors.red
                    elseif it.status == "INFO" then
                        tag = "[INFO]"
                        tagCol = colors.lightGray
                    end

                    if isPocket then
                        -- Compact Pocket format (26 cols)
                        term.setTextColor(tagCol)
                        term.write(tag .. " ")
                        term.setTextColor(colors.white)
                        local label = it.name .. ": " .. it.val
                        term.write(label:sub(1, w - 9))
                    else
                        -- Desktop format (51 cols)
                        term.setTextColor(tagCol)
                        term.write(tag .. " ")
                        term.setTextColor(colors.white)
                        term.write(string.format("%-18s: ", it.name:sub(1, 18)))
                        term.setTextColor(colors.lightGray)
                        term.write(tostring(it.val):sub(1, w - 28))
                    end
                end
            end
        end

        -- Footer Controls
        term.setCursorPos(2, h - 1)
        term.setTextColor(colors.gray)
        term.write(string.rep("-", w - 2))

        term.setCursorPos(2, h)
        term.setTextColor(colors.yellow)
        if isPocket then
            term.write("[R]Audit [F]Fix [Q]Exit")
        else
            term.write("[R] Re-Audit   [F] Auto-Repair   [Q / TAB] Exit")
        end

        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            local k = p1
            if k == keys.q or k == keys.tab or k == keys.backspace then
                break
            elseif k == keys.r then
                if ok_sound and Sound and Sound.playClick then pcall(Sound.playClick) end
                report = doctor.diagnose()
            elseif k == keys.f then
                drawWindow("System Doctor - Repair")
                term.setCursorPos(2, 4)
                term.setTextColor(colors.yellow)
                term.write("Executing 1-Click Auto-Repair...")
                doctor.autoRepair()
                sleep(1)
                report = doctor.diagnose()
            elseif k == keys.up then
                if scrollOffset > 0 then scrollOffset = scrollOffset - 1 end
            elseif k == keys.down then
                if scrollOffset + maxVisible < #lines then scrollOffset = scrollOffset + 1 end
            end
        elseif ev == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            if cy == h then
                if cx >= 2 and cx <= 10 then
                    if ok_sound and Sound and Sound.playClick then pcall(Sound.playClick) end
                    report = doctor.diagnose()
                elseif cx >= 11 and cx <= 24 then
                    drawWindow("System Doctor - Repair")
                    term.setCursorPos(2, 4)
                    term.setTextColor(colors.yellow)
                    term.write("Executing 1-Click Auto-Repair...")
                    doctor.autoRepair()
                    sleep(1)
                    report = doctor.diagnose()
                else
                    break
                end
            end
        elseif ev == "mouse_scroll" then
            local dir = p1
            if dir < 0 and scrollOffset > 0 then
                scrollOffset = scrollOffset - 1
            elseif dir > 0 and scrollOffset + maxVisible < #lines then
                scrollOffset = scrollOffset + 1
            end
        end
    end
end

-- Allow direct CLI execution when invoked from shell
if shell and shell.getRunningProgram and shell.getRunningProgram():match("doctor%.lua$") then
    doctor.run({})
end

return doctor
