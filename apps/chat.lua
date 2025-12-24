--[[
    Drunken OS - Chat Applet
    Modularized from drunken_os_apps.lua
]]

local chat = {}

local function getParent(context)
    return context.parent
end

function chat.run(context)
    context.drawWindow("General Chat")
    term.setCursorPos(2, 4)
    term.write("Fetching history...")
    rednet.send(getParent(context).mailServerId, {type = "get_chat_history"}, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 5)
    
    local history = (response and response.history) or {}
    local input = ""
    local lastMessage = ""

    local function redrawAll()
        context.drawWindow("General Chat")
        local w, h = context.getSafeSize()
        local line_y = h - 3
        for i = #history, 1, -1 do
            local wrapped = context.wordWrap(history[i], w - 2)
            for j = #wrapped, 1, -1 do
                if line_y < 2 then break end
                term.setCursorPos(2, line_y)
                term.write(wrapped[j])
                line_y = line_y - 1
            end
            if line_y < 2 then break end
        end
        local inputWidth = w - 4
        term.setBackgroundColor(context.theme.windowBg)
        term.setCursorPos(1, h - 2)
        term.write(string.rep(" ", w))
        term.setCursorPos(2, h - 2)
        term.setTextColor(context.theme.prompt)
        term.write("> ")
        term.setTextColor(context.theme.text)
        local textToDraw = #input > inputWidth and "..."..string.sub(input, -(inputWidth-3)) or input
        term.write(textToDraw)
    end

    local function redrawInputLineOnly()
        local w, h = context.getSafeSize()
        local inputWidth = w - 4
        term.setBackgroundColor(context.theme.windowBg)
        term.setCursorPos(1, h - 2)
        term.write(string.rep(" ", w))
        term.setCursorPos(2, h - 2)
        term.setTextColor(context.theme.prompt)
        term.write("> ")
        term.setTextColor(context.theme.text)
        local textToDraw = #input > inputWidth and "..."..string.sub(input, -(inputWidth-3)) or input
        term.write(textToDraw)
    end

    local function networkListener()
        while true do
            local _, message = rednet.receive("SimpleChat")
            if message and message.from and message.text then
                local formattedMessage = string.format("[%s]: %s", message.from, message.text)
                if formattedMessage ~= lastMessage then
                    table.insert(history, formattedMessage)
                    if #history > 100 then
                        table.remove(history, 1)
                    end
                    redrawAll()
                end
            end
        end
    end

    local function keyboardListener()
        while true do
            local event, p1 = os.pullEvent()
            if event == "key" then
                if p1 == keys.tab or p1 == keys.q then
                    break
                elseif p1 == keys.backspace then
                    if #input > 0 then
                        input = string.sub(input, 1, -2)
                        redrawInputLineOnly()
                    end
                elseif p1 == keys.enter then
                    if input ~= "" then
                        local messageToSend = { from = getParent(context).username, text = input }
                        rednet.send(getParent(context).chatServerId, messageToSend, "SimpleChat")
                        lastMessage = string.format("[%s]: %s", getParent(context).nickname, messageToSend.text)
                        table.insert(history, lastMessage)
                        if #history > 100 then
                            table.remove(history, 1)
                        end
                        input = ""
                        redrawAll()
                    end
                end
            elseif event == "char" then
                input = input .. p1
                redrawInputLineOnly()
            elseif event == "terminate" then
                break
            end
        end
    end

    redrawAll()
    parallel.waitForAny(keyboardListener, networkListener)
end

return chat
