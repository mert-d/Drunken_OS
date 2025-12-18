--[[
    Drunken OS - Admin Console (Standalone)
    
    Verified Authorization required.
]]

local args = {...}
local username = args[1]
local adminServerId = tonumber(args[2])

if not username or not adminServerId then
    print("Error: Invalid arguments.")
    print("Usage: Admin_Console <username> <server_id>")
    sleep(2)
    return
end

local function getSafeSize()
    local w, h = term.getSize()
    return w, h
end

local function drawWindow(title)
    local w, h = getSafeSize()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.clearLine()
    term.setCursorPos(math.floor((w - #title) / 2) + 1, 1)
    term.write(title)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function wordWrap(text, width)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        if #line <= width then
            table.insert(lines, line)
        else
            local currentLine = ""
            for word in line:gmatch("[^%s]+") do
                if #currentLine + #word + 1 > width then
                    table.insert(lines, currentLine)
                    currentLine = word
                else
                    currentLine = currentLine == "" and word or (currentLine .. " " .. word)
                end
            end
            table.insert(lines, currentLine)
        end
    end
    return lines
end

drawWindow("Remote Admin Console")
local history = {}
local input = ""
local w, h = getSafeSize()

local function redrawConsole()
    drawWindow("Remote Admin Console")
    local historyLines = {}
    for _, item in ipairs(history) do
        local prefix = item.type == "cmd" and "> " or ""
        -- Wrap text to fit window
        local wrapped = wordWrap(prefix .. item.text, w - 2)
        for _, line in ipairs(wrapped) do
            table.insert(historyLines, line)
        end
    end

    local displayHeight = h - 3
    local startLine = math.max(1, #historyLines - displayHeight + 1)
    for i = startLine, #historyLines do
        term.setCursorPos(2, 2 + (i - startLine))
        term.write(historyLines[i])
    end
end

local function redrawInputLine()
    local inputWidth = w - 4
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, h - 1)
    term.clearLine()
    term.setCursorPos(2, h - 1)
    term.setTextColor(colors.cyan)
    term.write("> ")
    term.setTextColor(colors.white)
    
    local textToDraw = #input > inputWidth and "..." .. string.sub(input, -inputWidth + 3) or input
    term.write(textToDraw)
end

redrawConsole()
while true do
    redrawInputLine()
    term.setCursorBlink(true)

    local event, p1 = os.pullEvent()
    term.setCursorBlink(false)

    if event == "key" then
        if p1 == keys.enter then
            if input == "exit" or input == "quit" then break end
            if input == "clear" then
                history = {}
            elseif input ~= "" then
                table.insert(history, {type="cmd", text=input})
                rednet.send(adminServerId, {
                    type = "execute_command",
                    user = username,
                    command = input
                }, "Drunken_Admin")
                
                redrawConsole()
                term.setCursorPos(1, h-1); term.clearLine()
                term.setCursorPos(2, h-1); term.write("Executing...")

                local _, response = rednet.receive("Drunken_Admin", 10)
                if response and response.output then
                    table.insert(history, {type="resp", text=response.output})
                else
                    table.insert(history, {type="resp", text="Error: Timed out or no response from server."})
                end
            end
            input = ""
            redrawConsole()
        elseif p1 == keys.backspace then
            input = string.sub(input, 1, -2)
        end
    elseif event == "char" then
        input = input .. p1
    elseif event == "terminate" then
        break
    end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
