-- clients/Drunken_Crafter.lua
-- Drunken OS - Standalone AE2 + Create Mechanical Crafter Node Client
-- Runs independently on an Advanced Computer beside the Mechanical Crafter wall (or via startup.lua).
-- Supports live 5x5 grid visualization, external wall monitors, interactive 5x5 calibration wizard,
-- zero-code wall recipe learning, peripheral settings editor, and optional DRUNKEN_BASE_BUS telemetry.

if package and package.path then
    package.path = "/?.lua;/lib/?.lua;?.lua;lib/?.lua;" .. package.path
end

local function loadCrafterCore()
    local ok, mod = pcall(require, "lib.crafter_core")
    if ok and type(mod) == "table" then return mod end

    local ok2, mod2 = pcall(require, "crafter_core")
    if ok2 and type(mod2) == "table" then return mod2 end

    if fs and fs.exists then
        local candidates = {
            "/lib/crafter_core.lua",
            "lib/crafter_core.lua",
            "/crafter_core.lua",
            "crafter_core.lua"
        }
        for _, path in ipairs(candidates) do
            if fs.exists(path) then
                return dofile(path)
            end
        end
    end
    error("Drunken Crafter Core missing! Could not load lib.crafter_core: " .. tostring(mod))
end

local CrafterCore = loadCrafterCore()

local ITEM_SYMBOLS = { "X", "O", "*", "+", "#", "@", "=", "%" }
local function getItemColors()
    local c = colors or {}
    return {
        c.cyan,
        c.yellow,
        c.lime,
        c.orange,
        c.lightBlue,
        c.magenta,
        c.pink,
        c.white
    }
end

local function setColors(surf, fg, bg)
    if not surf then return end
    local isCol = surf.isColor and surf.isColor()
    if isCol then
        if fg and surf.setTextColor then surf.setTextColor(fg) end
        if bg and surf.setBackgroundColor then surf.setBackgroundColor(bg) end
    else
        local inv = (bg == colors.white or bg == colors.cyan or bg == colors.lime
            or bg == colors.yellow or bg == colors.orange or bg == colors.blue)
        if surf.setTextColor then surf.setTextColor(inv and colors.black or colors.white) end
        if surf.setBackgroundColor then surf.setBackgroundColor(inv and colors.white or colors.black) end
    end
end

local function writeAt(surf, x, y, text, fg, bg)
    if not surf then return end
    local w, h = surf.getSize()
    if y < 1 or y > h or x > w then return end
    setColors(surf, fg, bg)
    surf.setCursorPos(x, y)
    surf.write(tostring(text):sub(1, math.max(0, w - x + 1)))
end

local function clearLineAt(surf, y, bg)
    if not surf then return end
    local w, h = surf.getSize()
    if y < 1 or y > h then return end
    setColors(surf, colors.white, bg or colors.black)
    surf.setCursorPos(1, y)
    surf.write(string.rep(" ", w))
end

local function findExternalMonitors()
    local list = {}
    if not (peripheral and peripheral.getNames) then return list end
    local ok, names = pcall(peripheral.getNames)
    if not (ok and type(names) == "table") then return list end
    for _, name in ipairs(names) do
        local okT, ptype = pcall(peripheral.getType, name)
        if okT and ptype == "monitor" then
            local okW, m = pcall(peripheral.wrap, name)
            if okW and m then
                pcall(function()
                    if m.setTextScale then
                        m.setTextScale(1.0)
                        local w, _ = m.getSize()
                        if w < 48 then
                            m.setTextScale(0.5)
                        end
                    end
                end)
                table.insert(list, m)
            end
        end
    end
    return list
end

local function shortPeriphLabel(name, maxLen)
    maxLen = maxLen or 18
    local s = tostring(name or "")
    if s == "" then return "(YOK)" end
    s = s:gsub("^minecraft:", ""):gsub("^create:", ""):gsub("^ae2:", "")
    if #s <= maxLen then return s end
    return s:sub(1, maxLen - 2) .. ".."
end

local function buildItemStyleMap(wallSlots)
    local styles = {}
    local itemColors = getItemColors()
    local nextIdx = 1
    for _, slotInfo in ipairs(wallSlots or {}) do
        if slotInfo.item and slotInfo.item.name and not styles[slotInfo.item.name] then
            local sym = ITEM_SYMBOLS[((nextIdx - 1) % #ITEM_SYMBOLS) + 1]
            local col = itemColors[((nextIdx - 1) % #itemColors) + 1]
            styles[slotInfo.item.name] = { sym = sym, color = col }
            nextIdx = nextIdx + 1
        end
    end
    return styles
end

local function statusBadge(core)
    local eff = core:getEffectiveStatus()
    if eff == "PAUSED" then
        return "[DURAKLAT]", colors.black, colors.orange
    elseif eff == "ERROR" then
        return "[HATA]", colors.white, colors.red
    elseif eff == "CRAFTING" then
        return "[URETIM]", colors.black, colors.yellow
    else
        return "[AKTIF]", colors.black, colors.lime
    end
end

local function run(context)
    context = context or {}
    local parentTerm = context.term or context.parent or term.current()
    local core = context.core or CrafterCore.new()
    core:openBaseBus()

    local monitors = findExternalMonitors()
    local mode = "MAIN" -- "MAIN" | "LEARN" | "CALIBRATE" | "SETTINGS"
    local selectedRecipeIdx = 1
    local recipeScroll = 0
    local confirmDeleteName = nil
    local statusToast = "Drunken Crafter hazir."
    local running = true

    -- Learn Recipe Prompt state
    local learnInput = ""

    -- Calibration Wizard state
    local calSlot = 1
    local calWasPaused = false
    local calCrafters = {}
    local calBaseline = {}
    local calLastOkMsg = ""
    local calOccupiedCount = 0
    local calOccupiedSample = ""

    -- Settings Screen state
    local settingsCursor = 1
    local settingsEditing = false
    local settingsBuffer = ""
    local discovered = core:discoverPeripherals()

    -- Double-buffer & dirty-check state (prevents flicker and idle redraws)
    local surfaceBuffers = setmetatable({}, { __mode = "k" })
    local lastTermSig = nil
    local lastMonSigs = setmetatable({}, { __mode = "k" })
    local stepTimer = nil

    local function withBuffer(surf, drawFn)
        if not surf then return end
        if window and window.create then
            local w, h = surf.getSize()
            local entry = surfaceBuffers[surf]
            if not entry or entry.w ~= w or entry.h ~= h then
                local okWin, win = pcall(window.create, surf, 1, 1, w, h, false)
                if okWin and win then
                    entry = { win = win, w = w, h = h }
                    surfaceBuffers[surf] = entry
                else
                    entry = nil
                end
            end
            if entry and entry.win then
                if entry.win.setVisible then entry.win.setVisible(false) end
                drawFn(entry.win)
                if entry.win.setVisible then entry.win.setVisible(true) end
                return
            end
        end
        drawFn(surf)
    end

    local function setToast(msg)
        statusToast = tostring(msg or "")
    end

    local function getSettingsFields()
        return {
            { key = "nodeId",        label = "Dugum Adi (Node ID)",   kind = "string" },
            { key = "inputName",     label = "Input Fici (Barrel)",   kind = "periph", listKey = "inventories" },
            { key = "outputName",    label = "Output Fici (Barrel)",  kind = "periph", listKey = "inventories" },
            { key = "ae2Name",       label = "AE2 Pattern Provider",  kind = "periph", listKey = "ae2Providers" },
            { key = "triggerSide",   label = "Redstone Tetik Yonu",   kind = "trigger" },
            { key = "pollRate",      label = "Kontrol Araligi (sn)",  kind = "number", step = 0.1, min = 0.1, max = 5.0 },
            { key = "pulseSec",      label = "Darbe Suresi (sn)",     kind = "number", step = 0.05, min = 0.05, max = 1.0 },
            { key = "rednetEnabled", label = "Drunken Base Bus",      kind = "bool" },
            { key = "gridWidth",     label = "Izgara Genisligi",      kind = "int", min = 1, max = 5 },
            { key = "gridHeight",    label = "Izgara Yuksekligi",     kind = "int", min = 1, max = 5 }
        }
    end

    local function cycleOption(currentVal, options, dir)
        if #options == 0 then return currentVal end
        local idx = 0
        for i, v in ipairs(options) do
            if v == currentVal then
                idx = i
                break
            end
        end
        if idx == 0 then
            return (dir > 0) and options[1] or options[#options]
        end
        local nextIdx = ((idx - 1 + dir) % #options) + 1
        return options[nextIdx]
    end

    local function scheduleStepTimer()
        local interval = (mode == "CALIBRATE") and 0.15 or (tonumber(core.cfg.pollRate) or 0.5)
        if interval < 0.05 then interval = 0.05 end
        if os and os.startTimer then
            return os.startTimer(interval)
        end
        return nil
    end

    local function refreshCalibrationOccupancy()
        local occ = core:getOccupiedCrafters(calCrafters)
        calOccupiedCount = #occ
        calOccupiedSample = (occ[1] and occ[1].name) or ""
    end

    local function startCalibration()
        calWasPaused = core.paused
        core.paused = true
        calSlot = 1
        calLastOkMsg = ""
        discovered = core:discoverPeripherals()
        calCrafters = discovered.crafters
        calBaseline = core:takeCrafterSnapshot(calCrafters)
        refreshCalibrationOccupancy()
        mode = "CALIBRATE"
        setToast("Kalibrasyon basladi: Siradaki goze 1 esya koyun ([S]:Atla)")
        stepTimer = scheduleStepTimer()
    end

    local function finishCalibration(msg)
        mode = "MAIN"
        core.paused = calWasPaused
        setToast(msg or "Kalibrasyon tamamlandi.")
        stepTimer = scheduleStepTimer()
    end

    local function drawDashboard(surf, isMonitor)
        if not surf then return end
        local w, h = surf.getSize()
        setColors(surf, colors.white, colors.black)
        surf.clear()

        local wall = core:scanWallState()
        local pStat = core:getPeripheralStatus()
        local recipes = core:getSortedRecipes()
        if selectedRecipeIdx > #recipes then
            selectedRecipeIdx = math.max(1, #recipes)
        end

        local gw, gh, totalSlots = core:getGridSize()
        local badgeText, badgeFg, badgeBg = statusBadge(core)

        -- Compact External Monitor Mode (< 40 columns or < 14 rows)
        if isMonitor and (w < 40 or h < 14) then
            clearLineAt(surf, 1, colors.blue)
            writeAt(surf, 1, 1, ("CRAFTER " .. tostring(core.cfg.nodeId)):sub(1, w), colors.white, colors.blue)
            writeAt(surf, 1, 2, badgeText .. " T:" .. tostring(core.totalCrafted), badgeFg, badgeBg)
            local gridStartY = 3
            local styles = buildItemStyleMap(wall.slots)
            for r = 1, math.min(gh, math.max(1, h - 4)) do
                local rowStr = ""
                for c = 1, gw do
                    local idx = (r - 1) * gw + c
                    local sInfo = wall.slots[idx]
                    if sInfo and sInfo.item then
                        rowStr = rowStr .. "[" .. (styles[sInfo.item.name] and styles[sInfo.item.name].sym or "X") .. "]"
                    elseif sInfo and sInfo.peripheral then
                        rowStr = rowStr .. "[ ]"
                    else
                        rowStr = rowStr .. "[.]"
                    end
                end
                writeAt(surf, 1, gridStartY + r - 1, rowStr, colors.cyan, colors.black)
            end
            if h >= 9 then
                writeAt(surf, 1, h - 1, ("SON: " .. tostring(core.lastRecipe or "-")):sub(1, w), colors.yellow, colors.black)
                writeAt(surf, 1, h, string.format("IN:%d OUT:%d", pStat.inputCount, pStat.outputCount):sub(1, w), colors.lightGray, colors.black)
            end
            return
        end

        -- Header Bar
        clearLineAt(surf, 1, colors.blue)
        local title = string.format(" DRUNKEN CRAFTER [%s]", tostring(core.cfg.nodeId))
        writeAt(surf, 1, 1, title, colors.white, colors.blue)
        writeAt(surf, math.max(2, w - #badgeText), 1, badgeText, badgeFg, badgeBg)

        -- Column headers
        local leftW = math.max(20, math.min(26, math.floor(w * 0.50)))
        local divX = leftW + 1
        local rightX = divX + 2
        local rightW = math.max(10, w - rightX + 1)

        writeAt(surf, 2, 2, string.format("%dx%d CANLI IZGARA", gw, gh), colors.cyan, colors.black)
        writeAt(surf, divX, 2, "|", colors.gray, colors.black)
        writeAt(surf, rightX, 2, string.format("KAYITLI TARIFLER (%d)", #recipes), colors.cyan, colors.black)

        -- Left Pane: Live 5x5 Grid
        local styles = buildItemStyleMap(wall.slots)
        for r = 1, gh do
            local y = 2 + r
            if y < h - 4 then
                local x = 2
                for c = 1, gw do
                    local slotIdx = (r - 1) * gw + c
                    local sInfo = wall.slots[slotIdx]
                    local cell = "[.]"
                    local fg = colors.gray
                    if sInfo and sInfo.item then
                        local st = styles[sInfo.item.name]
                        cell = "[" .. (st and st.sym or "X") .. "]"
                        fg = st and st.color or colors.lime
                    elseif sInfo and sInfo.peripheral then
                        cell = "[ ]"
                        fg = sInfo.online and colors.white or colors.red
                    end
                    writeAt(surf, x, y, cell, fg, colors.black)
                    x = x + 3
                end
                writeAt(surf, divX, y, "|", colors.gray, colors.black)
            end
        end

        -- Right Pane: Recipe List
        local maxRecipeRows = math.max(3, math.min(6, h - 10))
        if selectedRecipeIdx < recipeScroll + 1 then
            recipeScroll = math.max(0, selectedRecipeIdx - 1)
        elseif selectedRecipeIdx > recipeScroll + maxRecipeRows then
            recipeScroll = selectedRecipeIdx - maxRecipeRows
        end

        if #recipes == 0 then
            writeAt(surf, rightX, 3, "(Tarif yok - [L] ile ogren)", colors.gray, colors.black)
        else
            for row = 1, maxRecipeRows do
                local idx = recipeScroll + row
                local y = 2 + row
                writeAt(surf, divX, y, "|", colors.gray, colors.black)
                if idx <= #recipes then
                    local rec = recipes[idx]
                    local isSel = (idx == selectedRecipeIdx)
                    local countTag = string.format(" (%d)", tonumber(rec.totalCount) or 0)
                    local maxNameLen = math.max(4, rightW - #countTag - 2)
                    local line = string.format("%s%s%s", isSel and "> " or "  ", tostring(rec.name):sub(1, maxNameLen), countTag)
                    writeAt(surf, rightX, y, line, isSel and colors.black or colors.white, isSel and colors.lime or colors.black)
                end
            end
        end

        -- Middle Status Block
        local infoY = math.max(8, 3 + gh + 1)
        if infoY <= h - 4 then
            writeAt(surf, 2, infoY, string.format("Input : %s (%d esya)", pStat.inputOk and "OK" or "YOK", pStat.inputCount), pStat.inputOk and colors.lime or colors.red, colors.black)
            writeAt(surf, divX, infoY, "|", colors.gray, colors.black)
            writeAt(surf, rightX, infoY, "SON ISLEM:", colors.yellow, colors.black)
        end
        if infoY + 1 <= h - 3 then
            writeAt(surf, 2, infoY + 1, string.format("Output: %s (%d esya)", pStat.outputOk and "OK" or "YOK", pStat.outputCount), pStat.outputOk and colors.lime or colors.red, colors.black)
            writeAt(surf, divX, infoY + 1, "|", colors.gray, colors.black)
            writeAt(surf, rightX, infoY + 1, tostring(core.lastAction or "-"):sub(1, rightW), colors.white, colors.black)
        end
        if infoY + 2 <= h - 2 then
            writeAt(surf, 2, infoY + 2, string.format("AE2   : %s | Map:%d/%d", pStat.ae2Ok and "BAGLI" or "YOK", pStat.mappedCount, totalSlots), pStat.ae2Ok and colors.cyan or colors.orange, colors.black)
            writeAt(surf, divX, infoY + 2, "|", colors.gray, colors.black)
            writeAt(surf, rightX, infoY + 2, string.format("Uretim: %d | Bus: %s", core.totalCrafted, pStat.baseBusOpen and "ACIK" or "YOK"), colors.lightGray, colors.black)
        end

        -- Toast + Footer
        if h >= 15 then
            writeAt(surf, 2, h - 3, string.rep("-", w - 2), colors.gray, colors.black)
        end
        if h >= 14 then
            local toastColor = core.lastError and colors.red or colors.yellow
            local toastStr = core.lastError and ("HATA: " .. tostring(core.lastError)) or statusToast
            writeAt(surf, 2, h - 2, (">> " .. toastStr):sub(1, w - 2), toastColor, colors.black)
        end
        if not isMonitor then
            writeAt(surf, 2, h - 1, "[P]:Duraklat [L]:Tarif Ogren [C]:Kalibre [D]:Sil", colors.cyan, colors.black)
            writeAt(surf, 2, h,     "[T]:Manuel Tetik [S]:Ayarlar [Up/Dn]:Sec [Q]:Cik", colors.lightGray, colors.black)
        else
            writeAt(surf, 2, h, string.format("Node:%s | Tetik:%s", tostring(core.cfg.nodeId), tostring(core.cfg.triggerSide)), colors.gray, colors.black)
        end
    end

    local function drawLearnScreen(surf)
        local w, h = surf.getSize()
        setColors(surf, colors.white, colors.black)
        surf.clear()

        clearLineAt(surf, 1, colors.blue)
        writeAt(surf, 2, 1, "SIFIR-KODLU TARIF OGRENICI (DUVARDAN OKU)", colors.white, colors.blue)

        local wall = core:scanWallState()
        local gw, gh = core:getGridSize()
        writeAt(surf, 2, 3, string.format("Duvarda tespit edilen dolu goz: %d", wall.occupiedCount), colors.cyan, colors.black)

        local styles = buildItemStyleMap(wall.slots)
        for r = 1, gh do
            local x = 2
            for c = 1, gw do
                local idx = (r - 1) * gw + c
                local sInfo = wall.slots[idx]
                local cell = "[ ]"
                local fg = colors.gray
                if sInfo and sInfo.item then
                    local st = styles[sInfo.item.name]
                    cell = "[" .. (st and st.sym or "X") .. "]"
                    fg = st and st.color or colors.lime
                end
                writeAt(surf, x, 4 + r, cell, fg, colors.black)
                x = x + 3
            end
        end

        writeAt(surf, 2, 11, "Yeni Tarif Adi:", colors.yellow, colors.black)
        clearLineAt(surf, 12, colors.gray)
        writeAt(surf, 2, 12, ("> " .. learnInput .. "_"):sub(1, w - 2), colors.white, colors.gray)

        writeAt(surf, 2, h - 2, statusToast:sub(1, w - 2), colors.orange, colors.black)
        writeAt(surf, 2, h, "[Enter]:Kaydet | [Backspace]:Sil | [Esc]:Iptal", colors.lightGray, colors.black)
    end

    local function drawCalibrationScreen(surf)
        local w, h = surf.getSize()
        setColors(surf, colors.white, colors.black)
        surf.clear()

        clearLineAt(surf, 1, colors.blue)
        writeAt(surf, 2, 1, "5x5 MODEM KALIBRASYON SIHIRBAZI", colors.white, colors.blue)

        local gw, gh, totalSlots = core:getGridSize()
        local targetRow = math.floor((calSlot - 1) / gw) + 1
        local targetCol = ((calSlot - 1) % gw) + 1

        writeAt(surf, 2, 3, string.format("HEDEF GOZ: Satir %d, Sutun %d (Slot %d/%d)", targetRow, targetCol, calSlot, totalSlots), colors.yellow, colors.black)
        writeAt(surf, 2, 4, "Elinize 1 blok (orn. Cobblestone) alip hedef goze sag tiklayin.", colors.white, colors.black)

        for r = 1, gh do
            local x = 2
            for c = 1, gw do
                local idx = (r - 1) * gw + c
                local mapped = core.cfg.gridMap and core.cfg.gridMap[idx]
                local cell = "[ ]"
                local fg, bg = colors.gray, colors.black
                if idx == calSlot then
                    cell = "[?]"
                    fg, bg = colors.black, colors.yellow
                elseif mapped and mapped ~= "" then
                    cell = "[#]"
                    fg = colors.lime
                end
                writeAt(surf, x, 5 + r, cell, fg, bg)
                x = x + 3
            end
        end

        local mappedCur = core.cfg.gridMap and core.cfg.gridMap[calSlot]
        writeAt(surf, 2, 12, "Mevcut Eslesme: " .. tostring(mappedCur or "(Bos)"), colors.cyan, colors.black)
        if calLastOkMsg ~= "" then
            writeAt(surf, 2, 13, calLastOkMsg:sub(1, w - 2), colors.lime, colors.black)
        end
        local occNote = (calOccupiedSample ~= "") and (" (" .. shortPeriphLabel(calOccupiedSample, 18) .. ")") or ""
        writeAt(surf, 2, 14, string.format("Ag: %d Crafter | Dolu: %d%s", #calCrafters, calOccupiedCount, occNote):sub(1, w - 2), colors.lightGray, colors.black)

        writeAt(surf, 2, h - 1, statusToast:sub(1, w - 2), colors.yellow, colors.black)
        writeAt(surf, 2, h, "[Enter]:Dolu Al [S]:Atla [R]:Basa Don [Esc/Q]:Bitir", colors.lightGray, colors.black)
    end

    local function drawSettingsScreen(surf)
        local w, h = surf.getSize()
        setColors(surf, colors.white, colors.black)
        surf.clear()

        clearLineAt(surf, 1, colors.blue)
        writeAt(surf, 2, 1, "DRUNKEN CRAFTER - DONANIM & DUGUM AYARLARI", colors.white, colors.blue)

        local fields = getSettingsFields()
        local maxRows = math.max(4, h - 6)
        local startIdx = math.max(1, math.min(settingsCursor - 3, math.max(1, #fields - maxRows + 1)))

        for i = startIdx, math.min(#fields, startIdx + maxRows - 1) do
            local f = fields[i]
            local rowY = 3 + (i - startIdx)
            local isSel = (i == settingsCursor)
            local valStr = tostring(core.cfg[f.key] == nil and "" or core.cfg[f.key])
            if f.kind == "bool" then
                valStr = core.cfg[f.key] and "ACIK" or "KAPALI"
            elseif f.kind == "periph" and valStr == "" then
                valStr = "(Secilmedi)"
            end
            if isSel and settingsEditing then
                valStr = settingsBuffer .. "_"
            end
            local line = string.format("%s %-21s : %s", isSel and ">" or " ", f.label, valStr)
            writeAt(surf, 2, rowY, line:sub(1, w - 2), isSel and colors.black or colors.white, isSel and colors.cyan or colors.black)
        end

        writeAt(surf, 2, h - 3, string.format("Ag: %d Crafter | %d Depo | %d AE2 | %d Relay | %d Modem",
            #discovered.crafters, #discovered.inventories, #discovered.ae2Providers,
            #discovered.redstoneRelays, #discovered.wirelessModems):sub(1, w - 2), colors.lightGray, colors.black)
        writeAt(surf, 2, h - 2, statusToast:sub(1, w - 2), colors.yellow, colors.black)
        writeAt(surf, 2, h - 1, "[Up/Dn]:Sec [Lt/Rt]:Degistir [Enter]:Elle Yaz", colors.cyan, colors.black)
        writeAt(surf, 2, h,     "[R]:Cihaz Tara | [Esc/Q]:Ana Ekrana Don", colors.lightGray, colors.black)
    end

    local function computeDashboardSignature(wall, pStat, recipes, includeTermOnly)
        local parts = {
            tostring(core.cfg.nodeId),
            tostring(core:getEffectiveStatus()),
            tostring(core.totalCrafted),
            tostring(core.lastRecipe),
            tostring(core.lastAction),
            tostring(core.cfg.triggerSide),
            tostring(pStat.inputOk), tostring(pStat.inputCount),
            tostring(pStat.outputOk), tostring(pStat.outputCount),
            tostring(pStat.ae2Ok), tostring(pStat.mappedCount), tostring(pStat.totalSlots),
            tostring(pStat.baseBusOpen),
            tostring(wall.occupiedCount), tostring(wall.mappedCount)
        }
        for i = 1, wall.totalSlots do
            local s = wall.slots[i]
            parts[#parts + 1] = (s and s.item and s.item.name) or (s and s.peripheral and (s.online and "1" or "0")) or "."
        end
        for _, r in ipairs(recipes) do
            parts[#parts + 1] = tostring(r.name) .. ":" .. tostring(r.totalCount)
        end
        if includeTermOnly then
            parts[#parts + 1] = tostring(selectedRecipeIdx)
            parts[#parts + 1] = tostring(recipeScroll)
            parts[#parts + 1] = tostring(confirmDeleteName)
            parts[#parts + 1] = tostring(core.lastError)
            parts[#parts + 1] = tostring(statusToast)
        end
        return table.concat(parts, "|")
    end

    local function computeTermSignature()
        if mode == "MAIN" then
            local wall = core:scanWallState()
            local pStat = core:getPeripheralStatus()
            local recipes = core:getSortedRecipes()
            return "MAIN|" .. computeDashboardSignature(wall, pStat, recipes, true), wall, pStat, recipes
        elseif mode == "CALIBRATE" then
            local gw, gh, totalSlots = core:getGridSize()
            local parts = {
                "CAL", tostring(gw), tostring(gh), tostring(calSlot),
                tostring(#calCrafters), tostring(calOccupiedCount), tostring(calOccupiedSample),
                tostring(calLastOkMsg), tostring(statusToast)
            }
            for i = 1, totalSlots do
                parts[#parts + 1] = tostring(core.cfg.gridMap and core.cfg.gridMap[i] or "")
            end
            return table.concat(parts, "|")
        elseif mode == "LEARN" then
            local wall = core:scanWallState()
            local parts = { "LEARN", tostring(learnInput), tostring(statusToast), tostring(wall.occupiedCount) }
            for i = 1, wall.totalSlots do
                local s = wall.slots[i]
                parts[#parts + 1] = (s and s.item and s.item.name) or ""
            end
            return table.concat(parts, "|")
        elseif mode == "SETTINGS" then
            local parts = {
                "SET", tostring(settingsCursor), tostring(settingsEditing), tostring(settingsBuffer),
                tostring(statusToast),
                tostring(#discovered.crafters), tostring(#discovered.inventories),
                tostring(#discovered.ae2Providers), tostring(#discovered.redstoneRelays),
                tostring(#discovered.wirelessModems)
            }
            for _, f in ipairs(getSettingsFields()) do
                parts[#parts + 1] = tostring(core.cfg[f.key])
            end
            return table.concat(parts, "|")
        end
        return tostring(mode)
    end

    local function renderMonitorsOnly(force, cachedWall, cachedStat, cachedRecipes)
        if #monitors == 0 then return end
        local wall = cachedWall or core:scanWallState()
        local pStat = cachedStat or core:getPeripheralStatus()
        local recipes = cachedRecipes or core:getSortedRecipes()
        local monSig = computeDashboardSignature(wall, pStat, recipes, false)
        for _, mon in ipairs(monitors) do
            if force or lastMonSigs[mon] ~= monSig then
                lastMonSigs[mon] = monSig
                pcall(withBuffer, mon, function(buf)
                    drawDashboard(buf, true)
                end)
            end
        end
    end

    local function renderAll(force)
        local termSig, wall, pStat, recipes = computeTermSignature()
        if force or termSig ~= lastTermSig then
            lastTermSig = termSig
            withBuffer(parentTerm, function(buf)
                if mode == "LEARN" then
                    drawLearnScreen(buf)
                elseif mode == "CALIBRATE" then
                    drawCalibrationScreen(buf)
                elseif mode == "SETTINGS" then
                    drawSettingsScreen(buf)
                else
                    drawDashboard(buf, false)
                end
            end)
        end
        renderMonitorsOnly(force, wall, pStat, recipes)
    end

    local function handleTick()
        if mode == "CALIBRATE" then
            local _, _, totalSlots = core:getGridSize()
            if calSlot <= totalSlots then
                local matched = core:calibrateNextSlot(calSlot, {
                    crafterNames = calCrafters,
                    baseline = calBaseline,
                    pollOnce = true
                })
                if matched then
                    calLastOkMsg = string.format("[OK] Slot %d -> %s", calSlot, shortPeriphLabel(matched, 22))
                    setToast(calLastOkMsg)
                    calBaseline = core:takeCrafterSnapshot(calCrafters)
                    calSlot = calSlot + 1
                    if calSlot > totalSlots then
                        finishCalibration("5x5 Kalibrasyon tamamlandi ve kaydedildi!")
                    end
                end
                refreshCalibrationOccupancy()
            else
                finishCalibration("5x5 Kalibrasyon tamamlandi!")
            end
            core:maybeBroadcastHeartbeat()
            renderAll(false)
        elseif mode == "SETTINGS" or mode == "LEARN" then
            if not core.paused then
                core:step()
            end
            core:maybeBroadcastHeartbeat()
            renderMonitorsOnly(false)
        else
            local res = core:step()
            if res and res.action == "CRAFTED" then
                setToast("Uretim tetiklendi: " .. tostring(res.recipe))
            elseif res and res.action == "ERROR" and res.error then
                setToast("HATA: " .. tostring(res.error))
            end
            core:maybeBroadcastHeartbeat()
            renderAll(false)
        end
    end

    renderAll(true)
    stepTimer = scheduleStepTimer()

    while running do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "timer" and p1 == stepTimer then
            handleTick()
            stepTimer = scheduleStepTimer()
        elseif ev == "rednet_message" then
            local handled = core:handleBaseBusMessage(p1, p2, p3)
            if handled then
                renderAll(false)
            end
        elseif ev == "peripheral" or ev == "peripheral_detach" then
            monitors = findExternalMonitors()
            discovered = core:discoverPeripherals()
            if mode == "CALIBRATE" then
                calCrafters = discovered.crafters
                refreshCalibrationOccupancy()
            end
            core:openBaseBus()
            renderAll(true)
        elseif ev == "char" then
            if mode == "LEARN" then
                learnInput = learnInput .. tostring(p1)
                renderAll(false)
            elseif mode == "SETTINGS" and settingsEditing then
                settingsBuffer = settingsBuffer .. tostring(p1)
                renderAll(false)
            end
        elseif ev == "key" then
            local key = p1

            if mode == "LEARN" then
                if key == keys.enter or key == keys.numPadEnter then
                    local rec, err = core:learnRecipeFromWall(learnInput)
                    if rec then
                        mode = "MAIN"
                        setToast(string.format("Tarif ogrenildi: %s (%d esya)", rec.name, rec.totalCount))
                    else
                        setToast(tostring(err or "Tarif ogrenilemedi!"))
                    end
                elseif key == keys.backspace then
                    learnInput = learnInput:sub(1, math.max(0, #learnInput - 1))
                elseif key == keys.escape then
                    mode = "MAIN"
                    setToast("Tarif ogrenme iptal edildi.")
                end
                renderAll(false)

            elseif mode == "CALIBRATE" then
                local _, _, totalSlots = core:getGridSize()
                if key == keys.enter or key == keys.numPadEnter then
                    local bound, errB = core:bindOccupiedCrafter(calSlot, calCrafters)
                    if bound then
                        calLastOkMsg = string.format("[OK] Slot %d -> %s", calSlot, shortPeriphLabel(bound, 22))
                        setToast(calLastOkMsg)
                        calBaseline = core:takeCrafterSnapshot(calCrafters)
                        calSlot = calSlot + 1
                        if calSlot > totalSlots then
                            finishCalibration("5x5 Kalibrasyon tamamlandi ve kaydedildi!")
                        end
                    else
                        setToast(tostring(errB or "Dolu crafter bulunamadi!"))
                    end
                    refreshCalibrationOccupancy()
                elseif key == keys.s then
                    core:clearSlotMapping(calSlot)
                    calLastOkMsg = string.format("[ATLANDI] Slot %d bos birakildi", calSlot)
                    calSlot = calSlot + 1
                    if calSlot > totalSlots then
                        finishCalibration("Kalibrasyon tamamlandi.")
                    end
                elseif key == keys.r then
                    calSlot = 1
                    calLastOkMsg = "Slot 1'den yeniden baslatildi."
                    calCrafters = core:discoverPeripherals().crafters
                    calBaseline = core:takeCrafterSnapshot(calCrafters)
                    refreshCalibrationOccupancy()
                elseif key == keys.escape or key == keys.q then
                    finishCalibration("Kalibrasyon kaydedilip cikildi.")
                end
                renderAll(false)

            elseif mode == "SETTINGS" then
                local fields = getSettingsFields()
                local f = fields[settingsCursor]
                if settingsEditing then
                    if key == keys.enter or key == keys.numPadEnter then
                        if f then
                            if f.kind == "number" or f.kind == "int" then
                                local n = tonumber(settingsBuffer)
                                if n then
                                    if f.kind == "int" then n = math.floor(n) end
                                    if f.min then n = math.max(f.min, n) end
                                    if f.max then n = math.min(f.max, n) end
                                    core.cfg[f.key] = n
                                end
                            elseif f.kind == "bool" then
                                local low = settingsBuffer:lower()
                                core.cfg[f.key] = (low == "true" or low == "1" or low == "acik" or low == "on")
                            else
                                core.cfg[f.key] = settingsBuffer
                            end
                            core:saveConfig()
                            if f.key == "rednetEnabled" then core:openBaseBus() end
                            setToast("Ayar kaydedildi: " .. f.label)
                        end
                        settingsEditing = false
                    elseif key == keys.backspace then
                        settingsBuffer = settingsBuffer:sub(1, math.max(0, #settingsBuffer - 1))
                    elseif key == keys.escape then
                        settingsEditing = false
                    end
                else
                    if key == keys.up then
                        settingsCursor = math.max(1, settingsCursor - 1)
                    elseif key == keys.down then
                        settingsCursor = math.min(#fields, settingsCursor + 1)
                    elseif key == keys.r then
                        discovered = core:discoverPeripherals()
                        setToast("Cevre birimleri yeniden tarandi.")
                    elseif key == keys.escape or key == keys.q then
                        mode = "MAIN"
                        setToast("Ayarlar kaydedildi.")
                    elseif key == keys.enter or key == keys.numPadEnter then
                        if f then
                            if f.kind == "bool" then
                                core.cfg[f.key] = not core.cfg[f.key]
                                core:saveConfig()
                                core:openBaseBus()
                            else
                                settingsEditing = true
                                settingsBuffer = tostring(core.cfg[f.key] or "")
                            end
                        end
                    elseif (key == keys.left or key == keys.right) and f then
                        local dir = (key == keys.right) and 1 or -1
                        if f.kind == "periph" then
                            local opts = {}
                            for _, n in ipairs(discovered[f.listKey] or {}) do
                                table.insert(opts, n)
                            end
                            if #opts > 0 then
                                core.cfg[f.key] = cycleOption(core.cfg[f.key], opts, dir)
                                core:saveConfig()
                            else
                                setToast("Bagli uygun cihaz bulunamadi!")
                            end
                        elseif f.kind == "trigger" then
                            local opts = {}
                            for _, s in ipairs(CrafterCore.REDSTONE_SIDES) do
                                table.insert(opts, s)
                            end
                            for _, r in ipairs(discovered.redstoneRelays or {}) do
                                table.insert(opts, r)
                            end
                            core.cfg[f.key] = cycleOption(core.cfg[f.key], opts, dir)
                            core:saveConfig()
                        elseif f.kind == "bool" then
                            core.cfg[f.key] = not core.cfg[f.key]
                            core:saveConfig()
                            core:openBaseBus()
                        elseif f.kind == "number" or f.kind == "int" then
                            local step = f.step or 1
                            local v = (tonumber(core.cfg[f.key]) or 0) + (dir * step)
                            if f.kind == "int" then v = math.floor(v + 0.5) end
                            if f.min then v = math.max(f.min, v) end
                            if f.max then v = math.min(f.max, v) end
                            core.cfg[f.key] = tonumber(string.format("%.2f", v))
                            core:saveConfig()
                        end
                    end
                end
                renderAll(false)

            else
                -- MAIN DASHBOARD KEYS
                local recipes = core:getSortedRecipes()
                if key ~= keys.d then
                    confirmDeleteName = nil
                end

                if key == keys.q then
                    running = false
                elseif key == keys.p then
                    core.paused = not core.paused
                    core.status = core.paused and "PAUSED" or "IDLE"
                    setToast(core.paused and "Uretim DURAKLATILDI (Tarif dizebilirsiniz)." or "Otomatik uretim AKTIF.")
                    core:broadcastTelemetry()
                elseif key == keys.l then
                    learnInput = ""
                    mode = "LEARN"
                    setToast("Duvardaki tarifi adlandirin.")
                elseif key == keys.c then
                    startCalibration()
                elseif key == keys.s then
                    discovered = core:discoverPeripherals()
                    settingsEditing = false
                    mode = "SETTINGS"
                elseif key == keys.t then
                    local okP, errP = core:triggerPulse()
                    setToast(okP and ("Manuel Redstone darbesi gonderildi (" .. tostring(core.cfg.triggerSide) .. ").")
                        or ("Tetikleme hatasi: " .. tostring(errP)))
                    stepTimer = scheduleStepTimer()
                elseif key == keys.d then
                    local sel = recipes[selectedRecipeIdx]
                    if sel then
                        if confirmDeleteName == sel.name then
                            core:deleteRecipe(sel.name)
                            confirmDeleteName = nil
                            setToast("Tarif silindi: " .. sel.name)
                        else
                            confirmDeleteName = sel.name
                            setToast("Silmek icin tekrar [D] basin: " .. sel.name)
                        end
                    else
                        setToast("Silinecek tarif secili degil.")
                    end
                elseif key == keys.up then
                    selectedRecipeIdx = math.max(1, selectedRecipeIdx - 1)
                elseif key == keys.down then
                    selectedRecipeIdx = math.min(math.max(1, #recipes), selectedRecipeIdx + 1)
                end
                renderAll(false)
            end
        elseif ev == "terminate" then
            running = false
        end
    end

    setColors(parentTerm, colors.white, colors.black)
    parentTerm.clear()
    parentTerm.setCursorPos(1, 1)
end

if ... == nil then
    run(nil)
end

return { run = run }
