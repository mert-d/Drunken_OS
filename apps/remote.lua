--[[
    Drunken Remote (v1.0)
    Part of Drunken OS Base Automation Suite

    Purpose:
    Pocket Computer touch application for wirelessly toggling and pulsing
    base machinery, blast gates, clutches, pumps, and sirens.
]]

package.path = "/?.lua;" .. package.path
local utils = require("lib.utils")
local theme = require("lib.theme")

local PROTOCOL = "DrunkenRemote"
local CACHE_FILE = ".remote_cache.db"

local remoteApp = {}

local function loadCachedSwitches()
    if fs.exists(CACHE_FILE) then
        local f = fs.open(CACHE_FILE, "r")
        if f then
            local data = f.readAll()
            f.close()
            if textutils and textutils.unserialize then
                local t = textutils.unserialize(data)
                if type(t) == "table" then return t end
            end
        end
    end
    return {}
end

local function saveCachedSwitches(switches)
    local f = fs.open(CACHE_FILE, "w")
    if f then
        f.write(textutils.serialize(switches))
        f.close()
    end
end

function remoteApp.run(context)
    context = context or {}
    local username = (context.parent and context.parent.username) or "Player"
    local drawWindow = context.drawWindow or function(t) utils.drawWindow(t, context) end

    -- Check and open modem
    local modem = peripheral.find("modem")
    if not modem then
        if context.showMessage then
            context.showMessage("Remote Error", "A Wireless Modem is required to use Drunken Remote.")
        else
            print("Error: Wireless Modem required.")
            sleep(2)
        end
        return
    end

    if not rednet.isOpen() then
        rednet.open(peripheral.getName(modem))
    end

    local switches = loadCachedSwitches()
    local selectedIndex = 1
    local scrollOffset = 0
    local statusMsg = "Scanning airwaves..."

    local function scanForSwitches()
        statusMsg = "Scanning..."
        drawWindow("Drunken Remote")
        term.setCursorPos(2, 4)
        term.setTextColor(theme.prompt or colors.yellow)
        term.write("Pinging nearby switches...")

        rednet.broadcast({ type = "scan", user = username }, PROTOCOL)
        
        local timer = os.startTimer(0.8)
        local foundCount = 0
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "rednet_message" and p3 == PROTOCOL then
                local sender = p1
                local msg = p2
                if type(msg) == "table" and msg.type == "switch_info" then
                    -- Update or add switch
                    local existingIndex = nil
                    for idx, sw in ipairs(switches) do
                        if sw.id == msg.id then
                            existingIndex = idx
                            break
                        end
                    end

                    local swEntry = {
                        id = msg.id,
                        name = msg.name or ("Switch #" .. msg.id),
                        side = msg.side or "back",
                        mode = msg.mode or "toggle",
                        pulseDuration = msg.pulseDuration or 2,
                        state = msg.state == true,
                        isPublic = msg.isPublic ~= false,
                        owner = msg.owner or "Public",
                        online = true,
                        lastSeen = os.epoch("utc")
                    }

                    if existingIndex then
                        switches[existingIndex] = swEntry
                    else
                        table.insert(switches, swEntry)
                    end
                    foundCount = foundCount + 1
                end
            elseif event == "timer" and p1 == timer then
                break
            end
        end

        saveCachedSwitches(switches)
        statusMsg = string.format("Found %d switch%s", foundCount, foundCount == 1 and "" or "es")
    end

    -- Initial scan
    scanForSwitches()

    local function toggleSwitch(idx)
        local sw = switches[idx]
        if not sw then return end

        statusMsg = "Signaling #" .. sw.id .. "..."
        rednet.send(sw.id, { type = "toggle", user = username }, PROTOCOL)
        
        local timer = os.startTimer(1.0)
        local gotReply = false
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "rednet_message" and p1 == sw.id and p3 == PROTOCOL then
                local msg = p2
                if type(msg) == "table" and msg.type == "switch_update" then
                    if msg.success then
                        sw.state = (msg.state == true)
                        sw.online = true
                        statusMsg = sw.name .. ": " .. (sw.state and "ACTIVE" or "OFF")
                    else
                        statusMsg = "Failed: " .. (msg.error or "Denied")
                    end
                    gotReply = true
                    break
                end
            elseif event == "timer" and p1 == timer then
                break
            end
        end

        if not gotReply then
            sw.online = false
            statusMsg = sw.name .. " unreachable"
        end
        saveCachedSwitches(switches)
    end

    local function manualAddSwitch()
        drawWindow("Add Remote Switch")
        term.setCursorPos(2, 4)
        term.setTextColor(theme.prompt or colors.yellow)
        term.write("Enter Target Computer ID:")
        term.setCursorPos(2, 6)
        term.setTextColor(colors.white)
        term.write("ID: ")
        term.setCursorBlink(true)
        local input = read()
        term.setCursorBlink(false)
        local targetId = tonumber(input)
        if targetId then
            rednet.send(targetId, { type = "scan", user = username }, PROTOCOL)
            local sender, msg = rednet.receive(PROTOCOL, 1.2)
            if sender == targetId and type(msg) == "table" and msg.type == "switch_info" then
                local swEntry = {
                    id = msg.id,
                    name = msg.name or ("Switch #" .. msg.id),
                    side = msg.side or "back",
                    mode = msg.mode or "toggle",
                    pulseDuration = msg.pulseDuration or 2,
                    state = msg.state == true,
                    isPublic = msg.isPublic ~= false,
                    owner = msg.owner or "Public",
                    online = true,
                    lastSeen = os.epoch("utc")
                }
                table.insert(switches, swEntry)
                saveCachedSwitches(switches)
                statusMsg = "Added " .. swEntry.name
            else
                statusMsg = "No response from ID " .. targetId
            end
        end
    end

    local running = true
    while running do
        local w, h = term.getSize()
        drawWindow("Drunken Remote")

        -- Status Banner
        term.setCursorPos(2, 3)
        term.setTextColor(theme.accent or colors.cyan)
        term.write(statusMsg:sub(1, w - 4))

        local maxVisible = math.max(1, h - 8)
        if #switches == 0 then
            term.setCursorPos(2, 5)
            term.setTextColor(colors.gray)
            term.write("No switches in range.")
            term.setCursorPos(2, 6)
            term.write("Place down a computer running")
            term.setCursorPos(2, 7)
            term.setTextColor(colors.yellow)
            term.write("'remote_switch' next to redstone.")
        else
            for i = 1, maxVisible do
                local idx = i + scrollOffset
                if idx > #switches then break end
                local sw = switches[idx]
                local rowY = 4 + (i - 1) * 2

                -- Row box
                term.setCursorPos(2, rowY)
                if idx == selectedIndex then
                    term.setTextColor(colors.yellow)
                    term.write("▶")
                else
                    term.write(" ")
                end

                -- Label
                term.setTextColor(idx == selectedIndex and (theme.highlightText or colors.white) or (theme.text or colors.white))
                local nameStr = string.format("[%d] %s", idx, sw.name)
                term.setCursorPos(4, rowY)
                term.write(nameStr:sub(1, w - 16))

                -- State Tag
                local tagX = w - 10
                term.setCursorPos(tagX, rowY)
                if not sw.online then
                    term.setBackgroundColor(colors.gray)
                    term.setTextColor(colors.lightGray or colors.white)
                    term.write(" [OFFLINE] ")
                elseif sw.mode == "pulse" then
                    term.setBackgroundColor(colors.purple)
                    term.setTextColor(colors.white)
                    term.write(string.format(" [⚡ %ds] ", sw.pulseDuration or 2))
                elseif sw.state then
                    term.setBackgroundColor(colors.green)
                    term.setTextColor(colors.white)
                    term.write(" [  ACTIVE ] ")
                else
                    term.setBackgroundColor(colors.red)
                    term.setTextColor(colors.white)
                    term.write(" [ INACTIVE ] ")
                end
                term.setBackgroundColor(theme.windowBg or theme.bg or colors.black)
            end
        end

        -- Bottom Touch Buttons
        local btnY = h - 2
        term.setCursorPos(2, btnY)
        term.setTextColor(colors.yellow)
        term.write("[R]Scan ")
        term.setTextColor(colors.cyan)
        term.write("[+]Add ")
        term.setTextColor(colors.orange or colors.red)
        term.write("[Q]Quit")

        term.setCursorPos(2, h - 1)
        term.setTextColor(colors.gray)
        term.write("Tap row or 1-9 to toggle")

        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local k = p1
            if k == keys.q then
                running = false
            elseif k == keys.r then
                scanForSwitches()
            elseif k == keys.plus or k == keys.numPadAdd or k == keys.a then
                manualAddSwitch()
            elseif k == keys.up then
                selectedIndex = math.max(1, selectedIndex - 1)
                if selectedIndex <= scrollOffset then scrollOffset = selectedIndex - 1 end
            elseif k == keys.down then
                selectedIndex = math.min(#switches, selectedIndex + 1)
                if selectedIndex > scrollOffset + maxVisible then scrollOffset = selectedIndex - maxVisible end
            elseif k == keys.enter or k == keys.space then
                if switches[selectedIndex] then
                    toggleSwitch(selectedIndex)
                end
            elseif k >= keys.one and k <= keys.nine then
                local numIdx = k - keys.one + 1
                if switches[numIdx] then
                    selectedIndex = numIdx
                    toggleSwitch(numIdx)
                end
            end
        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            -- Check row clicks
            local clickedRow = false
            for i = 1, maxVisible do
                local rowY = 4 + (i - 1) * 2
                if (cy == rowY or cy == rowY + 1) and cx >= 2 and cx <= w - 2 then
                    local targetIdx = i + scrollOffset
                    if switches[targetIdx] then
                        selectedIndex = targetIdx
                        toggleSwitch(targetIdx)
                        clickedRow = true
                        break
                    end
                end
            end

            -- Check bottom buttons
            if not clickedRow and cy == btnY then
                if cx >= 2 and cx <= 9 then
                    scanForSwitches()
                elseif cx >= 10 and cx <= 16 then
                    manualAddSwitch()
                elseif cx >= 17 and cx <= 24 then
                    running = false
                end
            end
        end
    end
end

return remoteApp
