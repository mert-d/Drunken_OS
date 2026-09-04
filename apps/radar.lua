--[[
    NetRadar (v1.0)
    Part of Drunken OS Network Diagnostics Suite

    Purpose:
    Scans wireless airwaves to detect nearby players, active turtles, and base computers.
    Monitors central World Spawn servers (Bank, Arcade, Mail) and calculates round-trip latency.
]]

package.path = "/?.lua;" .. package.path
local utils = require("lib.utils")
local theme = require("lib.theme")

local RADAR_PROTO = "DrunkenRadar"

local radarApp = {}

local function getLocalGps()
    if gps and gps.locate then
        local x, y, z = gps.locate(0.5)
        if x and y and z then
            return { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
        end
    end
    return nil
end

function radarApp.run(context)
    context = context or {}
    local username = (context.parent and context.parent.username) or "Player"
    local drawWindow = context.drawWindow or function(t) utils.drawWindow(t, context) end

    -- Check and open modem
    local modem = peripheral.find("modem")
    if not modem then
        if context.showMessage then
            context.showMessage("Radar Error", "A Wireless Modem is required to operate NetRadar.")
        else
            print("Error: Wireless Modem required.")
            sleep(2)
        end
        return
    end

    if not rednet.isOpen() then
        rednet.open(peripheral.getName(modem))
    end

    local currentTab = 1 -- 1 = Devices, 2 = Server Health
    local detectedDevices = {}
    local serverStats = {
        { name = "Bank Server", proto = "DB_Bank", host = "bank.server", online = false, ping = 0 },
        { name = "Arcade Server", proto = "ArcadeGames", host = "arcade.server", online = false, ping = 0 },
        { name = "Mail Server", proto = "MailServer", host = "mail.server", online = false, ping = 0 }
    }
    local statusText = "Ready to scan."

    local function scanDevices()
        statusText = "Sweeping airwaves..."
        local myGps = getLocalGps()
        detectedDevices = {}

        drawWindow("NetRadar")
        term.setCursorPos(2, 4)
        term.setTextColor(theme.prompt or colors.yellow)
        term.write("📡 Scanning Rednet frequencies...")

        rednet.broadcast({
            type = "radar_ping",
            user = username,
            id = os.getComputerID(),
            gps = myGps
        }, RADAR_PROTO)

        local timer = os.startTimer(1.0)
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "rednet_message" and p3 == RADAR_PROTO then
                local sender = p1
                local msg = p2
                if type(msg) == "table" and msg.type == "radar_pong" and sender ~= os.getComputerID() then
                    local distStr = "In Range"
                    local distNum = 9999
                    if myGps and msg.gps and msg.gps.x and msg.gps.y and msg.gps.z then
                        local dx = msg.gps.x - myGps.x
                        local dy = msg.gps.y - myGps.y
                        local dz = msg.gps.z - myGps.z
                        distNum = math.floor(math.sqrt(dx*dx + dy*dy + dz*dz))
                        distStr = tostring(distNum) .. "m"
                    end

                    -- Check duplicates
                    local found = false
                    for _, dev in ipairs(detectedDevices) do
                        if dev.id == sender then
                            dev.distNum = distNum
                            dev.distStr = distStr
                            dev.user = msg.user
                            found = true
                            break
                        end
                    end

                    if not found then
                        table.insert(detectedDevices, {
                            id = sender,
                            user = msg.user or "Unknown",
                            device = msg.device or "Device",
                            label = msg.label or ("#" .. sender),
                            distNum = distNum,
                            distStr = distStr
                        })
                    end
                end
            elseif event == "timer" and p1 == timer then
                break
            end
        end

        -- Sort by proximity
        table.sort(detectedDevices, function(a, b) return a.distNum < b.distNum end)
        statusText = string.format("Detected %d device%s", #detectedDevices, #detectedDevices == 1 and "" or "s")
    end

    local function pingServers()
        statusText = "Pinging servers..."
        drawWindow("NetRadar")
        term.setCursorPos(2, 4)
        term.setTextColor(theme.prompt or colors.yellow)
        term.write("Testing World Spawn servers...")

        for _, s in ipairs(serverStats) do
            local t0 = os.epoch("utc")
            local id = rednet.lookup(s.proto, s.host)
            if id then
                rednet.send(id, { type = "ping" }, s.proto)
                local rId, _ = rednet.receive(s.proto, 0.8)
                local elapsed = os.epoch("utc") - t0
                if rId == id or elapsed < 800 then
                    s.online = true
                    s.ping = math.max(1, elapsed)
                else
                    s.online = false
                    s.ping = 0
                end
            else
                s.online = false
                s.ping = 0
            end
        end
        statusText = "Server ping complete."
    end

    -- Initial scan
    scanDevices()

    local running = true
    while running do
        local w, h = term.getSize()
        drawWindow("NetRadar")

        -- Tab Bar
        term.setCursorPos(2, 3)
        if currentTab == 1 then
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            term.write(" [1] Nearby Devices ")
            term.setBackgroundColor(theme.windowBg or theme.bg or colors.black)
            term.setTextColor(colors.gray)
            term.write(" [2] Servers ")
        else
            term.setBackgroundColor(theme.windowBg or theme.bg or colors.black)
            term.setTextColor(colors.gray)
            term.write(" [1] Devices ")
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            term.write(" [2] Server Health ")
        end
        term.setBackgroundColor(theme.windowBg or theme.bg or colors.black)

        -- Status line
        term.setCursorPos(2, 4)
        term.setTextColor(theme.accent or colors.cyan)
        term.write(statusText:sub(1, w - 3))

        local maxRows = math.max(1, h - 8)

        if currentTab == 1 then
            -- Devices Tab
            if #detectedDevices == 0 then
                term.setCursorPos(2, 6)
                term.setTextColor(colors.gray)
                term.write("No active devices found.")
                term.setCursorPos(2, 7)
                term.write("Other Drunken OS devices")
                term.setCursorPos(2, 8)
                term.write("will reply when in range.")
            else
                for i = 1, math.min(#detectedDevices, maxRows) do
                    local dev = detectedDevices[i]
                    local rowY = 5 + (i - 1) * 2

                    -- Icon based on device type
                    local icon = "[?]"
                    if dev.device == "Pocket" then icon = "[P]"
                    elseif dev.device == "Turtle" then icon = "[T]"
                    elseif dev.device == "Server" then icon = "[S]"
                    elseif dev.device == "Desktop" then icon = "[D]" end

                    term.setCursorPos(2, rowY)
                    term.setTextColor(colors.yellow)
                    term.write(icon)

                    term.setTextColor(theme.text or colors.white)
                    local nameStr = string.format(" %s (#%d)", dev.user or dev.label, dev.id)
                    term.write(nameStr:sub(1, w - 14))

                    -- Distance Tag
                    local distTag = string.format("[%s]", dev.distStr)
                    term.setCursorPos(w - #distTag, rowY)
                    term.setTextColor(colors.lime)
                    term.write(distTag)
                end
            end
        else
            -- Server Health Tab
            term.setCursorPos(2, 6)
            term.setTextColor(colors.lightGray or colors.gray)
            term.write("World Spawn Infrastructure:")

            for i, s in ipairs(serverStats) do
                local rowY = 7 + (i - 1) * 2
                term.setCursorPos(2, rowY)
                term.setTextColor(colors.white)
                term.write(s.name)

                term.setCursorPos(w - 14, rowY)
                if s.online then
                    term.setBackgroundColor(colors.green)
                    term.setTextColor(colors.white)
                    term.write(string.format(" %3dms OK ", s.ping))
                else
                    term.setBackgroundColor(colors.red)
                    term.setTextColor(colors.white)
                    term.write(" ASLEEP/OFF ")
                end
                term.setBackgroundColor(theme.windowBg or theme.bg or colors.black)
            end

            term.setCursorPos(2, 14)
            term.setTextColor(colors.gray)
            term.write("Tip: Servers at World Spawn")
            term.setCursorPos(2, 15)
            term.write("stay loaded 24/7.")
        end

        -- Bottom Touch Buttons
        local btnY = h - 2
        term.setCursorPos(2, btnY)
        term.setTextColor(colors.yellow)
        term.write("[R]Scan ")
        term.setTextColor(colors.cyan)
        term.write("[Tab]Switch ")
        term.setTextColor(colors.orange or colors.red)
        term.write("[Q]Quit")

        term.setCursorPos(2, h - 1)
        term.setTextColor(colors.gray)
        term.write("Touch button or press hotkey")

        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local k = p1
            if k == keys.q then
                running = false
            elseif k == keys.r then
                if currentTab == 1 then scanDevices() else pingServers() end
            elseif k == keys.tab or k == keys.space then
                currentTab = (currentTab == 1) and 2 or 1
                if currentTab == 2 then pingServers() end
            elseif k == keys.one then
                currentTab = 1
                scanDevices()
            elseif k == keys.two then
                currentTab = 2
                pingServers()
            end
        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            -- Tab bar clicks
            if cy == 3 then
                if cx >= 2 and cx <= 18 then
                    currentTab = 1
                    scanDevices()
                elseif cx >= 19 and cx <= 25 then
                    currentTab = 2
                    pingServers()
                end
            elseif cy == btnY then
                if cx >= 2 and cx <= 9 then
                    if currentTab == 1 then scanDevices() else pingServers() end
                elseif cx >= 10 and cx <= 20 then
                    currentTab = (currentTab == 1) and 2 or 1
                    if currentTab == 2 then pingServers() end
                elseif cx >= 21 and cx <= 26 then
                    running = false
                end
            end
        end
    end
end

return radarApp
