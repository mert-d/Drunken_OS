--[[
    Drunken OS - Service Guard & Supervisor Library (v2.0)
    Hot-plug peripherals, protected pcall dispatch, managed non-scrolling dashboard, zero-downtime watchdog.
]]

local ServiceGuard = {}
ServiceGuard._VERSION = 2.0

function ServiceGuard.initModems(filter)
    local res = { wired = nil, wireless = nil, count = 0, all = {} }
    if not peripheral or not peripheral.getNames then return res end
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local m = peripheral.wrap(name)
            local isWire = m and m.isWireless and m.isWireless()
            local ok = not filter or (filter == "wireless" and isWire) or (filter == "wired" and not isWire)
            if ok then
                if isWire then
                    if not res.wireless then res.wireless = name end
                else
                    if not res.wired then res.wired = name end
                end
                if rednet and rednet.open then pcall(rednet.open, name) end
                table.insert(res.all, name)
                res.count = res.count + 1
            end
        end
    end
    return res
end

function ServiceGuard.handlePeripheralEvent(event, name, hostRegistrations, logger, onMonitor)
    local log = logger or function() end
    if event == "peripheral" then
        if not peripheral or not peripheral.getType then return false end
        local pType = peripheral.getType(name)
        if pType == "modem" then
            local m = peripheral.wrap(name)
            local isW = m and m.isWireless and m.isWireless()
            if rednet and rednet.open then pcall(rednet.open, name) end
            if hostRegistrations and type(hostRegistrations) == "function" then
                pcall(hostRegistrations)
            end
            log("[HOT-PLUG] " .. (isW and "Wireless" or "Wired") .. " modem opened: " .. name)
            return true
        elseif pType == "monitor" then
            log("[HOT-PLUG] Monitor attached: " .. name)
            if onMonitor then pcall(onMonitor, name) end
            return true
        end
    elseif event == "peripheral_detach" then
        log("[PERIPHERAL] Detached: " .. tostring(name), true)
        return true
    end
    return false
end

function ServiceGuard.protectHandler(handlerName, func, logger, ...)
    local log = logger or function() end
    if type(func) ~= "function" then
        log("[ERROR] Handler '" .. tostring(handlerName) .. "' not callable", true)
        return false, "Invalid handler"
    end
    local res = { pcall(func, ...) }
    local ok = table.remove(res, 1)
    if not ok then
        local err = res[1] or "Unknown runtime error"
        log(string.format("[ERROR] Handler '%s' failed: %s", tostring(handlerName), tostring(err)), true)
        return false, err
    end
    return true, table.unpack(res)
end

local function writeDetailRow(lbl, val, col, y, w, isColor, clear)
    term.setCursorPos(1, y)
    if clear then term.clearLine() end
    term.setCursorPos(2, y)
    term.setTextColor(isColor and colors.cyan or colors.white)
    local lStr = string.format("%-14s: ", lbl or "")
    term.write(lStr)
    term.setTextColor(col or colors.white)
    local vStr = tostring(val or "")
    if #vStr > w - #lStr - 3 then vStr = vStr:sub(1, w - #lStr - 3) end
    term.write(vStr)
end

local function drawFooterBar(status, hint, h, w, isColor)
    term.setCursorPos(1, h)
    term.setBackgroundColor(isColor and colors.gray or colors.black)
    term.clearLine()
    term.setTextColor(colors.white)
    term.setCursorPos(2, h)
    local f = hint or "RUNNING | Ctrl+T to exit"
    if status and #status > 0 then f = "[" .. status .. "] " .. f end
    if #f > w - 2 then f = f:sub(1, w - 2) end
    term.write(f)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function ServiceGuard.drawServerDashboard(serverName, details, statusMessage, hintText)
    local w, h = term.getSize()
    local isColor = not term.isColor or term.isColor()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- 1. Title Bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(isColor and colors.blue or colors.black)
    term.clearLine()
    term.setTextColor(colors.white)
    local titleStr = " [*] " .. (serverName or "Drunken OS Server")
    if #titleStr > w - 14 then titleStr = titleStr:sub(1, w - 14) end
    term.write(titleStr)

    local rightParts = {}
    if os.getComputerID then table.insert(rightParts, "#" .. os.getComputerID()) end
    if rednet and rednet.isOpen and rednet.isOpen() then table.insert(rightParts, "[NET]") end
    if os.time and textutils and textutils.formatTime then
        pcall(function() table.insert(rightParts, textutils.formatTime(os.time(), false)) end)
    end
    local rStr = table.concat(rightParts, " ") .. " "
    if #rStr > 1 and w > #titleStr + #rStr then
        term.setCursorPos(w - #rStr + 1, 1)
        term.write(rStr)
    end

    -- 2. Metadata Details
    term.setBackgroundColor(colors.black)
    local curY = 3
    if details and type(details) == "table" then
        for _, item in ipairs(details) do
            if curY > h - 4 then break end
            writeDetailRow(item.label, item.value, item.color, curY, w, isColor, false)
            curY = curY + 1
        end
    end

    -- 3. Divider
    term.setCursorPos(1, curY)
    term.setTextColor(isColor and colors.gray or colors.white)
    term.write(string.rep("-", w))

    -- 4. Footer
    drawFooterBar(statusMessage, hintText, h, w, isColor)

    local logStartY = curY + 1
    local logEndY = h - 1
    term.setCursorPos(1, math.min(logEndY, logStartY))
    return { w = w, h = h, dividerY = curY, logStartY = logStartY, logEndY = logEndY }
end

function ServiceGuard.createDashboard(opts)
    opts = opts or {}
    local d = {
        serverName = opts.serverName or "Drunken OS Server",
        details = opts.details or {},
        status = opts.status or "ONLINE",
        hintText = opts.hintText or "RUNNING | Ctrl+T to exit",
        logs = {},
        maxLogs = opts.maxLogs or 100,
        dividerY = 10,
        logStartY = 11,
        logEndY = 18,
    }

    function d:getDetailsList()
        if type(self.details) == "function" then
            local ok, res = pcall(self.details)
            return ok and type(res) == "table" and res or {}
        end
        return type(self.details) == "table" and self.details or {}
    end

    function d:draw()
        local layout = ServiceGuard.drawServerDashboard(self.serverName, self:getDetailsList(), self.status, self.hintText)
        self.dividerY = layout.dividerY
        self.logStartY = layout.logStartY
        self.logEndY = layout.logEndY
        self:renderLogs()
    end

    function d:refreshDetails()
        local w, h = term.getSize()
        local isColor = not term.isColor or term.isColor()
        local curY = 3
        local detList = self:getDetailsList()
        local maxDetY = (self.dividerY and self.dividerY - 1) or math.max(3, h - 5)
        term.setBackgroundColor(colors.black)
        for _, item in ipairs(detList) do
            if curY > maxDetY then break end
            writeDetailRow(item.label, item.value, item.color, curY, w, isColor, true)
            curY = curY + 1
        end
        while curY <= maxDetY do
            term.setCursorPos(1, curY)
            term.clearLine()
            curY = curY + 1
        end
    end

    function d:setFooter(status, hint)
        if status ~= nil then self.status = status end
        if hint ~= nil then self.hintText = hint end
        local w, h = term.getSize()
        drawFooterBar(self.status, self.hintText, h, w, not term.isColor or term.isColor())
    end

    function d:renderLogs()
        local w, h = term.getSize()
        local isColor = not term.isColor or term.isColor()
        local startY = self.logStartY or (self.dividerY and self.dividerY + 1) or 10
        local endY = self.logEndY or (h - 1)
        if startY > endY then return end
        local visCount = endY - startY + 1
        local totalLogs = #self.logs
        local firstIdx = math.max(1, totalLogs - visCount + 1)

        for i = 1, visCount do
            local row = startY + i - 1
            term.setCursorPos(1, row)
            term.setBackgroundColor(colors.black)
            term.clearLine()
            local entryIdx = firstIdx + i - 1
            if entryIdx <= totalLogs then
                local item = self.logs[entryIdx]
                local text = item.text or tostring(item)
                if #text > w - 2 then text = text:sub(1, w - 2) end
                term.setCursorPos(2, row)
                term.setTextColor(item.isError and (isColor and colors.red or colors.white) or (isColor and colors.lightGray or colors.white))
                term.write(text)
            end
        end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end

    function d:log(message, isError)
        local str = tostring(message or "")
        if str:find("\n") then
            for line in str:gmatch("[^\r\n]+") do self:log(line, isError) end
            return
        end
        table.insert(self.logs, { text = str, isError = isError or false })
        if #self.logs > self.maxLogs then table.remove(self.logs, 1) end
        self:renderLogs()
    end

    function d:clearLogs()
        self.logs = {}
        self:renderLogs()
    end

    function d:getLogger(prefix)
        local p = prefix or ""
        return function(msg, isErr)
            self:log(p ~= "" and (p .. " " .. tostring(msg)) or tostring(msg), isErr)
        end
    end

    return d
end

function ServiceGuard.runSupervisor(serviceName, mainFunc, cleanupFunc, logger, delaySeconds)
    local log = logger or function(m, isErr) print((isErr and "[FATAL] " or "[INFO] ") .. m) end
    local backoff = delaySeconds or 2
    while true do
        local ok, err = pcall(mainFunc)
        if not ok then
            local errStr = tostring(err or "Unknown error")
            if errStr:find("Terminated") then
                if cleanupFunc then pcall(cleanupFunc) end
                log(serviceName .. " terminated by operator.", false)
                break
            end
            pcall(function()
                local logPath = fs.combine("logs", serviceName:lower():gsub("%s+", "_") .. "_crash.log")
                local f = fs.open(logPath, "a")
                if f then
                    f.writeLine(os.date("[%Y-%m-%d %H:%M:%S] ") .. serviceName .. " FATAL EXCEPTION: " .. errStr)
                    f.close()
                end
            end)
            log("CRASH in " .. serviceName .. ": " .. errStr, true)
            if cleanupFunc then pcall(cleanupFunc) end
            log(string.format("Auto-recovering in %ds (zero downtime)...", backoff), false)
            if sleep then sleep(backoff) end
        else
            if cleanupFunc then pcall(cleanupFunc) end
            break
        end
    end
end

return ServiceGuard
