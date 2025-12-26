local utils = {}

-- Universal word-wrap
function utils.wordWrap(text, maxWidth)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        while #line > maxWidth do
            local breakPoint = maxWidth
            while breakPoint > 0 and line:sub(breakPoint, breakPoint) ~= " " do
                breakPoint = breakPoint - 1
            end
            if breakPoint == 0 then breakPoint = maxWidth end
            table.insert(lines, line:sub(1, breakPoint))
            line = line:sub(breakPoint + 1)
        end
        table.insert(lines, line)
    end
    return lines
end

function utils.printCentered(startY, message)
    local w, h = term.getSize()
    -- USE W-2 to maximize space, and 3 column/row padding for frame
    local lines = utils.wordWrap(message, w - 2)
    for i, line in ipairs(lines) do
        local x = math.floor((w - #line) / 2) + 1
        term.setCursorPos(x, startY + i - 1)
        term.write(line)
    end
end

return utils
