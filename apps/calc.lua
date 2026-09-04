--[[
    Drunken OS - Calculator & Create Mod Gear Ratio Tool (apps/calc.lua)
    Version: 1.0
    
    Provides standard Minecraft math, stack division (x64), and rotational
    speed/gear ratio calculations for the Create mod.
]]

local app = {
    _VERSION = 1.0,
    name = "Calculator",
    author = "Drunken OS Team"
}

--- Safely evaluates a simple mathematical string expression.
function app.evaluateMath(expr)
    if not expr or #expr == 0 then return nil, "Empty expression" end
    -- Whitelist allowed math characters: digits, whitespace, operators +, -, *, /, %, ^, (, )
    local sanitized = expr:gsub("%s+", "")
    if sanitized:match("[^%d%+%-%%%*%/%%%^%(%)%.]") then
        return nil, "Invalid characters in expression"
    end
    
    local fn, err = load("return " .. sanitized)
    if not fn then return nil, "Syntax error" end
    
    local ok, res = pcall(fn)
    if not ok then return nil, "Evaluation error" end
    if type(res) ~= "number" then return nil, "Did not evaluate to a number" end
    return res
end

--- Converts an item count into Minecraft stacks (64 items) and remainder.
function app.toStacks(count)
    local n = math.floor(count)
    if n < 0 then return "0 items" end
    local stacks = math.floor(n / 64)
    local rem = n % 64
    if stacks == 0 then
        return string.format("%d items", rem)
    elseif rem == 0 then
        return string.format("%d stacks (%dx64)", stacks, stacks)
    else
        return string.format("%d stacks + %d (%dx64 + %d)", stacks, rem, stacks, rem)
    end
end

--- Calculates rotational gear ratio transitions for Create mod machinery.
-- @param sourceRpm number: Input speed (e.g. Water Wheel = 8, Windmill = 16, Motor = 32)
-- @param targetRpm number: Desired output speed (e.g. 128 RPM)
-- @return table: Analysis table { ratio, steps, description }
function app.calculateCreateRatio(sourceRpm, targetRpm)
    if sourceRpm <= 0 or targetRpm <= 0 then
        return { error = "RPM must be greater than 0" }
    end
    
    local ratio = targetRpm / sourceRpm
    local desc = ""
    local steps = {}
    
    if ratio == 1 then
        desc = "Direct shaft (1:1 ratio, no gearing needed)."
    elseif ratio > 1 then
        -- Speeding up
        local factor = ratio
        desc = string.format("Speed Up x%.2f.", factor)
        -- Check if power of 2 (Cogwheel pairs multiply by 2x)
        local pairsNeeded = math.log(factor) / math.log(2)
        if math.abs(pairsNeeded - math.floor(pairsNeeded + 0.001)) < 0.01 then
            local n = math.floor(pairsNeeded + 0.001)
            table.insert(steps, string.format("Use %d Large->Small Cogwheel pair(s) (each pair = 2x speed)", n))
        else
            table.insert(steps, string.format("Ratio: %.2f:1. Recommendation: Rotation Speed Controller or custom gear train.", factor))
        end
    else
        -- Slowing down
        local factor = 1 / ratio
        desc = string.format("Step Down 1/%.2f.", factor)
        local pairsNeeded = math.log(factor) / math.log(2)
        if math.abs(pairsNeeded - math.floor(pairsNeeded + 0.001)) < 0.01 then
            local n = math.floor(pairsNeeded + 0.001)
            table.insert(steps, string.format("Use %d Small->Large Cogwheel pair(s) (each pair = 1/2x speed)", n))
        else
            table.insert(steps, string.format("Ratio: 1:%.2f. Recommendation: Rotation Speed Controller or custom gear train.", factor))
        end
    end
    
    return {
        ratio = ratio,
        description = desc,
        steps = steps
    }
end

function app.run(context)
    local theme = (context and context.theme) or require("lib.theme")
    local w, h = term.getSize()
    local mode = "math" -- "math" or "create"
    local history = {}
    local inputStr = ""
    
    while true do
        context.drawWindow(mode == "math" and "Calculator" or "Create Mod RPM Calc")
        
        -- Header Tabs
        term.setCursorPos(2, 3)
        if mode == "math" then
            term.setTextColor(theme.highlightText or colors.yellow)
            term.write("[1. Math / Stacks]")
            term.setTextColor(theme.mutedText or colors.gray)
            term.write("  [2. Create RPM]")
        else
            term.setTextColor(theme.mutedText or colors.gray)
            term.write(" [1. Math / Stacks] ")
            term.setTextColor(theme.highlightText or colors.yellow)
            term.write(" [2. Create RPM]")
        end
        
        if mode == "math" then
            -- Math Mode UI
            term.setCursorPos(2, 5)
            term.setTextColor(theme.text or colors.white)
            term.write("Enter Expression (e.g. 64*4+16):")
            
            -- Input Box
            term.setCursorPos(2, 7)
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("> ")
            term.setTextColor(theme.highlightText or colors.white)
            term.write(inputStr)
            
            -- History
            local startH = 9
            for i = math.max(1, #history - (h - startH - 3)), #history do
                local entry = history[i]
                term.setCursorPos(2, startH)
                term.setTextColor(theme.mutedText or colors.lightGray)
                term.write(entry.expr .. " = ")
                term.setTextColor(theme.successText or colors.lime)
                term.write(tostring(entry.res))
                
                startH = startH + 1
                if entry.stacks and startH < h - 1 then
                    term.setCursorPos(4, startH)
                    term.setTextColor(theme.accent or colors.yellow)
                    term.write("↳ " .. entry.stacks)
                    startH = startH + 1
                end
            end
            
            term.setCursorPos(2, h - 1)
            term.setTextColor(theme.mutedText or colors.gray)
            term.write("[Tab] Switch Mode  [Q] Exit")
            
        else
            -- Create Mod RPM Mode UI
            term.setCursorPos(2, 5)
            term.setTextColor(theme.text or colors.white)
            term.write("Source RPM -> Target RPM")
            
            term.setCursorPos(2, 7)
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("Input: " .. inputStr)
            
            local startH = 9
            for i = math.max(1, #history - 3), #history do
                local entry = history[i]
                term.setCursorPos(2, startH)
                term.setTextColor(theme.highlightText or colors.yellow)
                term.write(string.format("%d RPM -> %d RPM", entry.src, entry.dst))
                startH = startH + 1
                
                term.setCursorPos(4, startH)
                term.setTextColor(theme.successText or colors.lime)
                term.write(entry.desc or "")
                startH = startH + 1
                
                if entry.steps then
                    for _, step in ipairs(entry.steps) do
                        if startH < h - 1 then
                            term.setCursorPos(4, startH)
                            term.setTextColor(theme.mutedText or colors.lightGray)
                            term.write("• " .. step)
                            startH = startH + 1
                        end
                    end
                end
            end
            
            term.setCursorPos(2, h - 1)
            term.setTextColor(theme.mutedText or colors.gray)
            term.write("[Tab] Switch Mode  [Q] Exit")
        end
        
        -- Event loop
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local k = p1
            if k == keys.tab then
                mode = (mode == "math") and "create" or "math"
                inputStr = ""
            elseif k == keys.q and #inputStr == 0 then
                break
            elseif k == keys.enter then
                if mode == "math" and #inputStr > 0 then
                    local res, err = app.evaluateMath(inputStr)
                    if res then
                        local st = app.toStacks(res)
                        table.insert(history, { expr = inputStr, res = res, stacks = st })
                        inputStr = ""
                    else
                        context.showMessage("Calc Error", err or "Invalid expression")
                    end
                elseif mode == "create" and #inputStr > 0 then
                    local src, dst = inputStr:match("(%d+)%s*[,%-%>]%s*(%d+)")
                    if not src then
                        src, dst = inputStr:match("(%d+)%s+(%d+)")
                    end
                    if src and dst then
                        local sN, dN = tonumber(src), tonumber(dst)
                        local ratioInfo = app.calculateCreateRatio(sN, dN)
                        if not ratioInfo.error then
                            table.insert(history, { src = sN, dst = dN, desc = ratioInfo.description, steps = ratioInfo.steps })
                            inputStr = ""
                        else
                            context.showMessage("Create Error", ratioInfo.error)
                        end
                    else
                        context.showMessage("Format", "Enter: 'Source, Target'\nExample: '16, 128'")
                    end
                end
            elseif k == keys.backspace then
                inputStr = inputStr:sub(1, -2)
            end
        elseif event == "char" then
            inputStr = inputStr .. p1
        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            if cy == 3 then
                -- Tap tabs to switch mode
                if cx <= 18 then mode = "math" else mode = "create" end
                inputStr = ""
            elseif cy == h - 1 and cx <= 10 then
                break -- Exit button
            end
        end
    end
    
    return true
end

return app
