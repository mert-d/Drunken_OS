--[[
    Drunken OS - Calculator & Create Mod Engineering Tool (apps/calc.lua)
    Version: 2.0
    
    Features:
    1. Math & Stack Conversion (Minecraft x64 math)
    2. Create Mod Gear Ratios (Source RPM -> Target RPM transitions)
    3. Create Mod Stress Units (SU Capacity & Machine Stress Impact)
]]

local app = {
    _VERSION = 2.0,
    name = "Calculator & Create Tool",
    author = "Drunken OS Team"
}

-- Machine Base Stress Impact per RPM in Create Mod
local MACHINE_IMPACTS = {
    press = { name = "Mechanical Press", su = 8 },
    mixer = { name = "Mechanical Mixer", su = 8 },
    crusher = { name = "Crushing Wheels", su = 16 },
    millstone = { name = "Millstone", su = 4 },
    saw = { name = "Mechanical Saw", su = 4 },
    drill = { name = "Mechanical Drill", su = 4 },
    fan = { name = "Encased Fan", su = 4 },
    crafter = { name = "Mechanical Crafter", su = 2 },
    cuckoo = { name = "Cuckoo Clock", su = 1 },
    spout = { name = "Spout", su = 4 }
}

--- Safely evaluates a simple mathematical string expression.
function app.evaluateMath(expr)
    if not expr or #expr == 0 then return nil, "Empty expression" end
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
function app.calculateCreateRatio(sourceRpm, targetRpm)
    if not sourceRpm or not targetRpm or sourceRpm <= 0 or targetRpm <= 0 then
        return { error = "RPM must be greater than 0" }
    end
    
    local ratio = targetRpm / sourceRpm
    local desc = ""
    local steps = {}
    
    if ratio == 1 then
        desc = "Direct shaft (1:1 ratio, no gearing needed)."
    elseif ratio > 1 then
        local factor = ratio
        desc = string.format("Speed Up x%.2f.", factor)
        local pairsNeeded = math.log(factor) / math.log(2)
        if math.abs(pairsNeeded - math.floor(pairsNeeded + 0.001)) < 0.01 then
            local n = math.floor(pairsNeeded + 0.001)
            table.insert(steps, string.format("Use %d Large->Small Cogwheel pair(s) (2x per pair)", n))
        else
            table.insert(steps, string.format("Ratio: %.2f:1. Recommendation: Speed Controller.", factor))
        end
    else
        local factor = 1 / ratio
        desc = string.format("Step Down 1/%.2f.", factor)
        local pairsNeeded = math.log(factor) / math.log(2)
        if math.abs(pairsNeeded - math.floor(pairsNeeded + 0.001)) < 0.01 then
            local n = math.floor(pairsNeeded + 0.001)
            table.insert(steps, string.format("Use %d Small->Large Cogwheel pair(s) (1/2x per pair)", n))
        else
            table.insert(steps, string.format("Ratio: 1:%.2f. Recommendation: Speed Controller.", factor))
        end
    end
    
    return {
        ratio = ratio,
        description = desc,
        steps = steps
    }
end

--- Calculates Create Mod Stress Units (Capacity or Impact).
function app.calculateCreateSU(inputStr)
    if not inputStr or #inputStr == 0 then
        return nil, "Empty input"
    end
    
    local clean = inputStr:lower():gsub("^%s*(.-)%s*$", "%1")
    
    -- 1. Water Wheel
    if clean:match("^ww") or clean:match("^waterwheel") then
        local rpm = tonumber(clean:match("%d+")) or 8
        local su = rpm * 32
        return {
            title = string.format("Water Wheel @ %d RPM", rpm),
            res = string.format("Capacity: %d SU", su),
            detail = string.format("32 SU/RPM * %d RPM", rpm)
        }
    end
    
    -- 2. Large Water Wheel
    if clean:match("^lww") or clean:match("^largewaterwheel") then
        local rpm = tonumber(clean:match("%d+")) or 4
        local su = rpm * 128
        return {
            title = string.format("Large Water Wheel @ %d RPM", rpm),
            res = string.format("Capacity: %d SU", su),
            detail = string.format("128 SU/RPM * %d RPM", rpm)
        }
    end
    
    -- 3. Windmill: windmill <sails>
    if clean:match("^wind") then
        local sails = tonumber(clean:match("(%d+)")) or 8
        if sails < 8 then sails = 8 end
        if sails > 128 then sails = 128 end
        local su = sails * 512
        return {
            title = string.format("Windmill (%d Sails)", sails),
            res = string.format("Capacity: %d SU", su),
            detail = string.format("512 SU/sail * %d sails (16 RPM)", sails)
        }
    end
    
    -- 4. Steam Engine: steam <level> [engines]
    if clean:match("^steam") then
        local lvl, count = clean:match("steam%s+(%d+)%s*(%d*)")
        lvl = tonumber(lvl) or 1
        count = tonumber(count) or 1
        if count < 1 then count = 1 end
        local perEngine = 2048
        if lvl == 2 then perEngine = 16384
        elseif lvl >= 3 then perEngine = 65536 end
        local totalSu = perEngine * count
        return {
            title = string.format("Steam Boiler L%d (%dx Engines)", lvl, count),
            res = string.format("Capacity: %d SU", totalSu),
            detail = string.format("%d SU/engine * %d (64 RPM)", perEngine, count)
        }
    end
    
    -- 5. Machine Impact: [count] <machine_name> <rpm>
    for key, data in pairs(MACHINE_IMPACTS) do
        if clean:match(key) then
            local count, rpm = clean:match("(%d+)%s+" .. key .. "%s+(%d+)")
            if not count then
                rpm = clean:match(key .. "%s+(%d+)")
                count = 1
            end
            count = tonumber(count) or 1
            rpm = tonumber(rpm) or 16
            local totalImpact = count * data.su * rpm
            return {
                title = string.format("%dx %s @ %d RPM", count, data.name, rpm),
                res = string.format("Impact: %d SU", totalImpact),
                detail = string.format("%d SU/RPM * %d RPM * %d machines", data.su, rpm, count)
            }
        end
    end
    
    -- 6. Math evaluation for capacity vs headroom: e.g. 2048 / (8 * 128)
    local mathRes = app.evaluateMath(clean)
    if mathRes then
        return {
            title = "Custom SU Calculation",
            res = string.format("Result: %.2f", mathRes),
            detail = clean .. " = " .. tostring(mathRes)
        }
    end
    
    return nil, "Format: 'press 128', 'ww 8', 'wind 16', 'steam 1 2'"
end

--- Main application entry point for the Calculator & Create Tool.
function app.run(context)
    local theme = (context and context.theme) or require("lib.theme")
    local w, h = term.getSize()
    local isPocket = (w <= 30)
    
    local mode = "math" -- "math", "rpm", "su"
    local mathHistory = {}
    local rpmHistory = {}
    local suHistory = {}
    local inputStr = ""
    
    while true do
        w, h = term.getSize()
        isPocket = (w <= 30)
        
        local windowTitle = "Calculator"
        if mode == "rpm" then windowTitle = "Create RPM Calc"
        elseif mode == "su" then windowTitle = "Create SU Calc" end
        context.drawWindow(windowTitle)
        
        -- Header Tabs (Responsive)
        term.setCursorPos(2, 3)
        if isPocket then
            -- Pocket 26x20 width
            local function drawTab(id, label, isSel)
                if isSel then
                    term.setTextColor(theme.highlightText or colors.yellow)
                    term.write("[" .. id .. "." .. label .. "]")
                else
                    term.setTextColor(theme.mutedText or colors.gray)
                    term.write(" " .. id .. "." .. label .. " ")
                end
            end
            drawTab("1", "Math", mode == "math")
            term.write(" ")
            drawTab("2", "RPM", mode == "rpm")
            term.write(" ")
            drawTab("3", "SU", mode == "su")
        else
            -- Desktop 51x19 width
            local function drawTab(id, label, isSel)
                if isSel then
                    term.setTextColor(theme.highlightText or colors.yellow)
                    term.write("[" .. id .. ". " .. label .. "]")
                else
                    term.setTextColor(theme.mutedText or colors.gray)
                    term.write("  " .. id .. ". " .. label .. "  ")
                end
            end
            drawTab("1", "Math / Stacks", mode == "math")
            term.write("  ")
            drawTab("2", "Create Gear RPM", mode == "rpm")
            term.write("  ")
            drawTab("3", "Create Stress Units", mode == "su")
        end
        
        -- Screen Content per Mode
        if mode == "math" then
            term.setCursorPos(2, 5)
            term.setTextColor(theme.text or colors.white)
            term.write(isPocket and "Expr (e.g. 64*4+16):" or "Enter Expression (e.g. 64*4+16):")
            
            term.setCursorPos(2, 7)
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("> ")
            term.setTextColor(theme.highlightText or colors.white)
            term.write(inputStr)
            
            local startH = 9
            local maxEntries = math.max(1, math.floor((h - startH - 2) / 2))
            local startIdx = math.max(1, #mathHistory - maxEntries + 1)
            for i = startIdx, #mathHistory do
                local entry = mathHistory[i]
                if startH < h - 2 then
                    term.setCursorPos(2, startH)
                    term.setTextColor(theme.mutedText or colors.lightGray)
                    term.write(entry.expr .. " = ")
                    term.setTextColor(theme.successText or colors.lime)
                    term.write(tostring(entry.res))
                    startH = startH + 1
                    
                    if entry.stacks and startH < h - 2 then
                        term.setCursorPos(4, startH)
                        term.setTextColor(theme.accent or colors.yellow)
                        term.write("-> " .. entry.stacks)
                        startH = startH + 1
                    end
                end
            end
            
        elseif mode == "rpm" then
            term.setCursorPos(2, 5)
            term.setTextColor(theme.text or colors.white)
            term.write(isPocket and "Source, Target RPM:" or "Source RPM -> Target RPM (e.g. 16, 128):")
            
            term.setCursorPos(2, 7)
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("> ")
            term.setTextColor(theme.highlightText or colors.white)
            term.write(inputStr)
            
            local startH = 9
            local maxEntries = math.max(1, math.floor((h - startH - 2) / 3))
            local startIdx = math.max(1, #rpmHistory - maxEntries + 1)
            for i = startIdx, #rpmHistory do
                local entry = rpmHistory[i]
                if startH < h - 2 then
                    term.setCursorPos(2, startH)
                    term.setTextColor(theme.highlightText or colors.yellow)
                    term.write(string.format("%d -> %d RPM", entry.src, entry.dst))
                    startH = startH + 1
                    
                    term.setCursorPos(4, startH)
                    term.setTextColor(theme.successText or colors.lime)
                    term.write(entry.desc or "")
                    startH = startH + 1
                    
                    if entry.steps then
                        for _, step in ipairs(entry.steps) do
                            if startH < h - 2 then
                                term.setCursorPos(4, startH)
                                term.setTextColor(theme.mutedText or colors.lightGray)
                                term.write("* " .. step:sub(1, w - 5))
                                startH = startH + 1
                            end
                        end
                    end
                end
            end
            
        elseif mode == "su" then
            term.setCursorPos(2, 5)
            term.setTextColor(theme.text or colors.white)
            term.write(isPocket and "e.g. 'press 128', 'ww 8':" or "Machine/Gen (e.g. 'press 128', 'ww 8', 'wind 16'):")
            
            term.setCursorPos(2, 7)
            term.setTextColor(theme.prompt or colors.cyan)
            term.write("> ")
            term.setTextColor(theme.highlightText or colors.white)
            term.write(inputStr)
            
            local startH = 9
            local maxEntries = math.max(1, math.floor((h - startH - 2) / 3))
            local startIdx = math.max(1, #suHistory - maxEntries + 1)
            for i = startIdx, #suHistory do
                local entry = suHistory[i]
                if startH < h - 2 then
                    term.setCursorPos(2, startH)
                    term.setTextColor(theme.highlightText or colors.yellow)
                    term.write(entry.title:sub(1, w - 3))
                    startH = startH + 1
                    
                    term.setCursorPos(4, startH)
                    term.setTextColor(theme.successText or colors.lime)
                    term.write(entry.res:sub(1, w - 5))
                    startH = startH + 1
                    
                    if entry.detail and startH < h - 2 then
                        term.setCursorPos(4, startH)
                        term.setTextColor(theme.mutedText or colors.lightGray)
                        term.write(entry.detail:sub(1, w - 5))
                        startH = startH + 1
                    end
                end
            end
        end
        
        -- Footer hints
        term.setCursorPos(2, h - 1)
        term.setTextColor(theme.mutedText or colors.gray)
        term.write(isPocket and "[Tab] Mode  [Q] Exit" or "[Tab] Switch Mode  [Q] Exit")
        
        -- Event Loop
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local k = p1
            if k == keys.tab then
                if mode == "math" then mode = "rpm"
                elseif mode == "rpm" then mode = "su"
                else mode = "math" end
                inputStr = ""
            elseif (k == keys.q or k == keys.x) and #inputStr == 0 then
                break
            elseif k == keys.enter then
                if #inputStr > 0 then
                    if mode == "math" then
                        local res, err = app.evaluateMath(inputStr)
                        if res then
                            local st = app.toStacks(res)
                            table.insert(mathHistory, { expr = inputStr, res = res, stacks = st })
                            inputStr = ""
                        else
                            context.showMessage("Calc Error", err or "Invalid expression")
                        end
                    elseif mode == "rpm" then
                        local src, dst = inputStr:match("(%d+)%s*[,%-%>]%s*(%d+)")
                        if not src then
                            src, dst = inputStr:match("(%d+)%s+(%d+)")
                        end
                        if src and dst then
                            local sN, dN = tonumber(src), tonumber(dst)
                            local ratioInfo = app.calculateCreateRatio(sN, dN)
                            if not ratioInfo.error then
                                table.insert(rpmHistory, { src = sN, dst = dN, desc = ratioInfo.description, steps = ratioInfo.steps })
                                inputStr = ""
                            else
                                context.showMessage("RPM Error", ratioInfo.error)
                            end
                        else
                            context.showMessage("Format Error", "Enter: 'Source, Target'\nExample: '16, 128'")
                        end
                    elseif mode == "su" then
                        local suData, err = app.calculateCreateSU(inputStr)
                        if suData then
                            table.insert(suHistory, suData)
                            inputStr = ""
                        else
                            context.showMessage("SU Error", err or "Invalid SU format")
                        end
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
                -- Tap tab header
                if isPocket then
                    if cx <= 8 then mode = "math"
                    elseif cx <= 16 then mode = "rpm"
                    else mode = "su" end
                else
                    if cx <= 18 then mode = "math"
                    elseif cx <= 36 then mode = "rpm"
                    else mode = "su" end
                end
                inputStr = ""
            elseif cy == h - 1 and cx <= 10 then
                break
            end
        end
    end
    
    return true
end

return app
