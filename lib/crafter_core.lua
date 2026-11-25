-- lib/crafter_core.lua
-- Drunken OS - Drunken Crafter Core Engine
-- AE2 Pattern Provider + Create Mechanical Crafter Node with interactive 5x5 calibration,
-- zero-code wall recipe learning, subset-safe recipe matching, atomic item dispatch,
-- Redstone pulse triggering, and optional DRUNKEN_BASE_BUS Rednet telemetry/control.

local CrafterCore = {}
CrafterCore.__index = CrafterCore

CrafterCore.VERSION = "1.0.0"
CrafterCore.CONFIG_PATH = "/etc/drunken_crafter.cfg"
CrafterCore.RECIPES_PATH = "/etc/drunken_crafter_recipes.db"
CrafterCore.BASE_BUS_PROTOCOL = "DRUNKEN_BASE_BUS"
CrafterCore.NODE_TYPE = "MECHANICAL_CRAFTER"
CrafterCore.REDSTONE_SIDES = { "left", "right", "top", "bottom", "front", "back" }

CrafterCore.DEFAULT_CONFIG = {
    nodeId        = "CRAFTER-01",
    gridWidth     = 5,
    gridHeight    = 5,
    inputName     = "",
    outputName    = "",
    ae2Name       = "",
    triggerSide   = "right",
    relaySide     = nil,
    pollRate      = 0.5,
    pulseSec      = 0.15,
    rednetEnabled = true,
    gridMap       = {}
}

local function deepCopy(val)
    if type(val) ~= "table" then
        return val
    end
    local out = {}
    for k, v in pairs(val) do
        out[deepCopy(k)] = deepCopy(v)
    end
    return out
end

local function trimString(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isRedstoneSide(val)
    if type(val) ~= "string" then return false end
    local lower = val:lower()
    for _, side in ipairs(CrafterCore.REDSTONE_SIDES) do
        if lower == side then return true end
    end
    return false
end

local function ensureParentDir(path)
    if not (fs and fs.getDir and fs.makeDir) then return end
    local okDir, dir = pcall(fs.getDir, path)
    if okDir and dir and dir ~= "" and dir ~= "." then
        local exists = fs.exists and fs.exists(dir)
        if not exists then
            pcall(fs.makeDir, dir)
        end
    end
end

local function readSerializedTable(path)
    if not (fs and fs.exists and fs.open and textutils and textutils.unserialize) then
        return nil
    end
    local okEx, exists = pcall(fs.exists, path)
    if not (okEx and exists) then
        return nil
    end
    local okOpen, f = pcall(fs.open, path, "r")
    if not (okOpen and f) then
        return nil
    end
    local okRead, raw = pcall(f.readAll)
    pcall(f.close)
    if not (okRead and type(raw) == "string" and #raw > 0) then
        return nil
    end
    local okUn, data = pcall(textutils.unserialize, raw)
    if okUn and type(data) == "table" then
        return data
    end
    return nil
end

local function writeSerializedTable(path, tbl)
    if not (fs and fs.open and textutils and textutils.serialize) then
        return false, "fs or textutils unavailable"
    end
    ensureParentDir(path)
    local okSer, raw = pcall(textutils.serialize, tbl)
    if not (okSer and type(raw) == "string") then
        return false, "serialize failed"
    end
    local okOpen, f = pcall(fs.open, path, "w")
    if not (okOpen and f) then
        return false, "failed to open file for write: " .. tostring(path)
    end
    local okWrite, errW = pcall(f.write, raw)
    pcall(f.close)
    if not okWrite then
        return false, tostring(errW)
    end
    return true
end

local function safeEpochUtc()
    if os and os.epoch then
        local ok, ts = pcall(os.epoch, "utc")
        if ok and type(ts) == "number" then return ts end
    end
    if os and os.time then
        local ok, ts = pcall(os.time)
        if ok and type(ts) == "number" then return ts end
    end
    return 0
end

local function safeClock()
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and type(c) == "number" then return c end
    end
    return 0
end

local function safeComputerId()
    if os and os.getComputerID then
        local ok, id = pcall(os.getComputerID)
        if ok and id ~= nil then return id end
    end
    return 0
end

local function safeSleep(sec)
    if type(sleep) == "function" then
        pcall(sleep, sec)
    end
end

local function sortedNumericKeys(tbl)
    local keys = {}
    for k in pairs(tbl or {}) do
        if type(k) == "number" then
            table.insert(keys, k)
        end
    end
    table.sort(keys)
    return keys
end

local function callPeriph(name, method, ...)
    if not peripheral or type(name) ~= "string" or name == "" then
        return false, "no peripheral"
    end
    if peripheral.call then
        return pcall(peripheral.call, name, method, ...)
    end
    if peripheral.wrap then
        local okW, p = pcall(peripheral.wrap, name)
        if okW and type(p) == "table" and type(p[method]) == "function" then
            return pcall(p[method], ...)
        end
    end
    return false, "method unavailable: " .. tostring(method)
end

local function isPeriphPresent(name)
    if not peripheral or type(name) ~= "string" or name == "" then
        return false
    end
    if peripheral.isPresent then
        local ok, present = pcall(peripheral.isPresent, name)
        if ok then return present == true end
    end
    if peripheral.getNames then
        local ok, names = pcall(peripheral.getNames)
        if ok and type(names) == "table" then
            for _, n in ipairs(names) do
                if n == name then return true end
            end
        end
    end
    return false
end

local function getPeriphType(name)
    if not peripheral or type(name) ~= "string" or name == "" then
        return nil
    end
    if peripheral.getType then
        local ok, ptype = pcall(peripheral.getType, name)
        if ok and type(ptype) == "string" then
            return ptype
        end
    end
    return nil
end

local function hasPeriphType(name, targetType)
    if peripheral and peripheral.hasType then
        local ok, has = pcall(peripheral.hasType, name, targetType)
        if ok and has then return true end
    end
    local ptype = getPeriphType(name)
    return ptype == targetType
end

function CrafterCore.new(opts)
    opts = opts or {}
    local self = setmetatable({}, CrafterCore)

    self.configPath = opts.configPath or CrafterCore.CONFIG_PATH
    self.recipesPath = opts.recipesPath or CrafterCore.RECIPES_PATH
    self.cfg = deepCopy(CrafterCore.DEFAULT_CONFIG)
    self.recipes = {}

    self.paused = false
    self.status = "IDLE"
    self.totalCrafted = 0
    self.lastRecipe = nil
    self.lastCraftTs = nil
    self.lastError = nil
    self.lastAction = "Hazir"
    self.rednetModemName = nil
    self.lastHeartbeatClock = -999
    self.heartbeatInterval = 10.0

    if opts.autoLoad ~= false then
        self:loadConfig()
        self:loadRecipes()
    end

    if type(opts.config) == "table" then
        for k, v in pairs(opts.config) do
            if k == "gridMap" and type(v) == "table" then
                self.cfg.gridMap = deepCopy(v)
            else
                self.cfg[k] = deepCopy(v)
            end
        end
    end

    return self
end

function CrafterCore:loadConfig()
    local loaded = readSerializedTable(self.configPath)
    if type(loaded) == "table" then
        for k, v in pairs(loaded) do
            if k == "gridMap" and type(v) == "table" then
                local normalized = {}
                for slotK, periphName in pairs(v) do
                    local numSlot = tonumber(slotK)
                    if numSlot and type(periphName) == "string" and periphName ~= "" then
                        normalized[numSlot] = periphName
                    end
                end
                self.cfg.gridMap = normalized
            else
                self.cfg[k] = deepCopy(v)
            end
        end
        return true
    end
    return false
end

function CrafterCore:saveConfig()
    return writeSerializedTable(self.configPath, self.cfg)
end

function CrafterCore:loadRecipes()
    local loaded = readSerializedTable(self.recipesPath)
    if type(loaded) == "table" then
        local clean = {}
        for name, rec in pairs(loaded) do
            if type(rec) == "table" and type(rec.layout) == "table" then
                local rName = rec.name or tostring(name)
                local normLayout = {}
                for k, itemName in pairs(rec.layout) do
                    local numK = tonumber(k)
                    if numK and type(itemName) == "string" and itemName ~= "" then
                        normLayout[numK] = itemName
                    end
                end
                local normIngredients = {}
                local count = 0
                if type(rec.ingredients) == "table" then
                    for itemName, qty in pairs(rec.ingredients) do
                        local nQty = tonumber(qty) or 0
                        if nQty > 0 then
                            normIngredients[itemName] = nQty
                        end
                    end
                end
                for _, itemName in pairs(normLayout) do
                    count = count + 1
                    if not rec.ingredients then
                        normIngredients[itemName] = (normIngredients[itemName] or 0) + 1
                    end
                end
                clean[rName] = {
                    name = rName,
                    totalCount = tonumber(rec.totalCount) or count,
                    ingredients = normIngredients,
                    layout = normLayout
                }
            end
        end
        self.recipes = clean
        return true
    end
    return false
end

function CrafterCore:saveRecipes()
    return writeSerializedTable(self.recipesPath, self.recipes)
end

function CrafterCore:getGridSize()
    local w = math.max(1, math.floor(tonumber(self.cfg.gridWidth) or 5))
    local h = math.max(1, math.floor(tonumber(self.cfg.gridHeight) or 5))
    return w, h, w * h
end

function CrafterCore.isCrafterPeripheral(name)
    if type(name) ~= "string" or name == "" then return false end
    if hasPeriphType(name, "create:mechanical_crafter") then
        return true
    end
    local ptype = getPeriphType(name)
    if ptype and ptype:lower():find("mechanical_crafter", 1, true) then
        return true
    end
    if name:lower():find("mechanical_crafter", 1, true) then
        return true
    end
    return false
end

function CrafterCore:discoverPeripherals()
    local res = {
        crafters = {},
        inventories = {},
        ae2Providers = {},
        redstoneRelays = {},
        wirelessModems = {},
        monitors = {}
    }
    if not (peripheral and peripheral.getNames) then
        return res
    end
    local ok, names = pcall(peripheral.getNames)
    if not (ok and type(names) == "table") then
        return res
    end

    for _, name in ipairs(names) do
        local ptype = tostring(getPeriphType(name) or ""):lower()
        local lname = tostring(name):lower()

        if CrafterCore.isCrafterPeripheral(name) then
            table.insert(res.crafters, name)
        elseif ptype == "monitor" or hasPeriphType(name, "monitor") then
            table.insert(res.monitors, name)
        elseif ptype == "modem" or hasPeriphType(name, "modem") then
            local okW, isW = callPeriph(name, "isWireless")
            if okW and isW then
                table.insert(res.wirelessModems, name)
            end
        elseif ptype:find("redstone_relay", 1, true)
            or ptype:find("redstone_integrator", 1, true)
            or lname:find("redstone_relay", 1, true)
            or lname:find("redstone_integrator", 1, true) then
            table.insert(res.redstoneRelays, name)
        elseif ptype:find("pattern_provider", 1, true)
            or lname:find("pattern_provider", 1, true)
            or ptype:find("ae2", 1, true)
            or lname:find("ae2", 1, true) then
            table.insert(res.ae2Providers, name)
        else
            local okList = callPeriph(name, "list")
            local okSize = callPeriph(name, "size")
            if okList or okSize
                or ptype:find("barrel", 1, true)
                or ptype:find("chest", 1, true)
                or ptype:find("inventory", 1, true)
                or hasPeriphType(name, "inventory") then
                table.insert(res.inventories, name)
            end
        end
    end

    table.sort(res.crafters)
    table.sort(res.inventories)
    table.sort(res.ae2Providers)
    table.sort(res.redstoneRelays)
    table.sort(res.wirelessModems)
    table.sort(res.monitors)

    return res
end

function CrafterCore:getSlotItem(slotIdx)
    local periphName = self.cfg.gridMap and self.cfg.gridMap[slotIdx]
    if not periphName or periphName == "" then
        return nil, false
    end
    if not isPeriphPresent(periphName) then
        return nil, false
    end

    local okDet, detail = callPeriph(periphName, "getItemDetail", 1)
    if okDet and type(detail) == "table" and detail.name then
        return detail, true
    end

    local okList, listTbl = callPeriph(periphName, "list")
    if okList and type(listTbl) == "table" then
        local slot1 = listTbl[1]
        if type(slot1) == "table" and slot1.name then
            return slot1, true
        end
        for _, item in pairs(listTbl) do
            if type(item) == "table" and item.name and (tonumber(item.count) or 0) > 0 then
                return item, true
            end
        end
    end

    return nil, true
end

function CrafterCore:scanWallState()
    local _, _, totalSlots = self:getGridSize()
    local slots = {}
    local occupiedCount = 0
    local mappedCount = 0

    for slotIdx = 1, totalSlots do
        local periphName = self.cfg.gridMap and self.cfg.gridMap[slotIdx] or nil
        local item, online = nil, false
        if periphName and periphName ~= "" then
            mappedCount = mappedCount + 1
            item, online = self:getSlotItem(slotIdx)
            if item then
                occupiedCount = occupiedCount + 1
            end
        end
        slots[slotIdx] = {
            peripheral = periphName,
            item = item,
            online = online
        }
    end

    return {
        slots = slots,
        occupiedCount = occupiedCount,
        mappedCount = mappedCount,
        totalSlots = totalSlots
    }
end

function CrafterCore:isWallBusy()
    local _, _, totalSlots = self:getGridSize()
    for slotIdx = 1, totalSlots do
        local periphName = self.cfg.gridMap and self.cfg.gridMap[slotIdx]
        if periphName and periphName ~= "" and isPeriphPresent(periphName) then
            local okList, listTbl = callPeriph(periphName, "list")
            if okList and type(listTbl) == "table" then
                for _, item in pairs(listTbl) do
                    if type(item) == "table" and item.name and (tonumber(item.count) or 1) > 0 then
                        return true, slotIdx, item
                    end
                end
            end
            local okDet, detail = callPeriph(periphName, "getItemDetail", 1)
            if okDet and type(detail) == "table" and detail.name and (tonumber(detail.count) or 1) > 0 then
                return true, slotIdx, detail
            end
        end
    end
    return false, nil, nil
end

function CrafterCore:getInventoryCounts(periphName)
    local counts = {}
    local slots = {}
    local totalItems = 0

    if type(periphName) ~= "string" or periphName == "" or not isPeriphPresent(periphName) then
        return counts, slots, 0, false
    end

    local ok, listTbl = callPeriph(periphName, "list")
    if not ok or type(listTbl) ~= "table" then
        return counts, slots, 0, false
    end

    for slot, item in pairs(listTbl) do
        local numSlot = tonumber(slot)
        if numSlot and type(item) == "table" and type(item.name) == "string" then
            local cnt = tonumber(item.count) or 0
            if cnt > 0 then
                slots[numSlot] = { name = item.name, count = cnt }
                counts[item.name] = (counts[item.name] or 0) + cnt
                totalItems = totalItems + cnt
            end
        end
    end

    return counts, slots, totalItems, true
end

function CrafterCore:getPeripheralStatus()
    local _, inputCount, inputTotal, inputOk = self:getInventoryCounts(self.cfg.inputName)
    local _, _, outputTotal, outputOk = self:getInventoryCounts(self.cfg.outputName)
    local _ = inputCount
    local ae2Ok = isPeriphPresent(self.cfg.ae2Name)
    local _, _, totalSlots = self:getGridSize()
    local mappedCount = 0
    for slotIdx = 1, totalSlots do
        if self.cfg.gridMap and self.cfg.gridMap[slotIdx] and self.cfg.gridMap[slotIdx] ~= "" then
            mappedCount = mappedCount + 1
        end
    end
    return {
        inputOk = inputOk,
        inputCount = inputTotal,
        outputOk = outputOk,
        outputCount = outputTotal,
        ae2Ok = ae2Ok,
        mappedCount = mappedCount,
        totalSlots = totalSlots,
        baseBusOpen = self:isBaseBusOpen()
    }
end

local function crafterHasSlot1Item(periphName)
    if not isPeriphPresent(periphName) then return false end
    local okDet, detail = callPeriph(periphName, "getItemDetail", 1)
    if okDet and type(detail) == "table" and detail.name and (tonumber(detail.count) or 1) > 0 then
        return true, detail
    end
    local okList, listTbl = callPeriph(periphName, "list")
    if okList and type(listTbl) == "table" then
        local slot1 = listTbl[1]
        if type(slot1) == "table" and slot1.name and (tonumber(slot1.count) or 1) > 0 then
            return true, slot1
        end
        for _, item in pairs(listTbl) do
            if type(item) == "table" and item.name and (tonumber(item.count) or 1) > 0 then
                return true, item
            end
        end
    end
    return false, nil
end

function CrafterCore:takeCrafterSnapshot(crafterNames)
    local names = crafterNames or self:discoverPeripherals().crafters
    local snapshot = {}
    for _, name in ipairs(names) do
        local hasItem = crafterHasSlot1Item(name)
        snapshot[name] = hasItem == true
    end
    return snapshot
end

function CrafterCore:returnItemFromCrafter(crafterName, slot)
    slot = slot or 1
    local inputName = self.cfg.inputName
    if type(inputName) ~= "string" or inputName == "" or not isPeriphPresent(inputName) then
        return 0
    end
    local okPush, moved = callPeriph(crafterName, "pushItems", inputName, slot, 64)
    if okPush and tonumber(moved) and tonumber(moved) > 0 then
        return tonumber(moved)
    end
    local okPull, pulled = callPeriph(inputName, "pullItems", crafterName, slot, 64)
    if okPull and tonumber(pulled) and tonumber(pulled) > 0 then
        return tonumber(pulled)
    end
    return 0
end

function CrafterCore:calibrateNextSlot(slotIdx, opts)
    opts = opts or {}
    local crafterNames = opts.crafterNames or self:discoverPeripherals().crafters
    local baseline = opts.baseline or {}
    local pollInterval = tonumber(opts.pollInterval) or 0.15
    local timeout = tonumber(opts.timeout)
    local startClock = safeClock()

    local function checkOnce()
        for _, name in ipairs(crafterNames) do
            if not baseline[name] then
                local hasItem = crafterHasSlot1Item(name)
                if hasItem then
                    -- Keep 1-to-1 mapping across grid slots
                    for k, existing in pairs(self.cfg.gridMap) do
                        if existing == name then
                            self.cfg.gridMap[k] = nil
                        end
                    end
                    self.cfg.gridMap[slotIdx] = name
                    if opts.returnToInput ~= false then
                        self:returnItemFromCrafter(name, 1)
                    end
                    self:saveConfig()
                    return name
                end
            end
        end
        return nil
    end

    if opts.pollOnce then
        return checkOnce(), nil
    end

    while true do
        local matched = checkOnce()
        if matched then
            return matched, nil
        end
        if timeout and (safeClock() - startClock) >= timeout then
            return nil, "timeout"
        end
        safeSleep(pollInterval)
    end
end

function CrafterCore:clearSlotMapping(slotIdx)
    if self.cfg.gridMap then
        self.cfg.gridMap[slotIdx] = nil
        self:saveConfig()
    end
end

function CrafterCore:clearGridMap()
    self.cfg.gridMap = {}
    self:saveConfig()
end

function CrafterCore:learnRecipeFromWall(recipeName)
    local cleanName = trimString(recipeName)
    if cleanName == "" then
        return nil, "Tarif adi bos olamaz!"
    end

    local _, _, totalSlots = self:getGridSize()
    local layout = {}
    local ingredients = {}
    local totalCount = 0

    for slotIdx = 1, totalSlots do
        local periphName = self.cfg.gridMap and self.cfg.gridMap[slotIdx]
        if periphName and periphName ~= "" and isPeriphPresent(periphName) then
            local detail = nil
            local okDet, resDet = callPeriph(periphName, "getItemDetail", 1)
            if okDet and type(resDet) == "table" and resDet.name then
                detail = resDet
            else
                local okList, listTbl = callPeriph(periphName, "list")
                if okList and type(listTbl) == "table" then
                    detail = listTbl[1]
                end
            end

            if detail and type(detail.name) == "string" and detail.name ~= "" then
                layout[slotIdx] = detail.name
                ingredients[detail.name] = (ingredients[detail.name] or 0) + 1
                totalCount = totalCount + 1
            end
        end
    end

    if totalCount == 0 then
        return nil, "Duvarda hic esya bulunamadi!"
    end

    local recipe = {
        name = cleanName,
        totalCount = totalCount,
        ingredients = ingredients,
        layout = layout
    }
    self.recipes[cleanName] = recipe
    local okSave, errSave = self:saveRecipes()
    if not okSave and fs and fs.open then
        return recipe, errSave
    end
    self.lastAction = "Ogrenildi: " .. cleanName .. " (" .. tostring(totalCount) .. ")"
    return recipe, nil
end

function CrafterCore:deleteRecipe(recipeName)
    if not recipeName or not self.recipes[recipeName] then
        return false
    end
    self.recipes[recipeName] = nil
    self:saveRecipes()
    self.lastAction = "Silindi: " .. tostring(recipeName)
    return true
end

function CrafterCore:getSortedRecipes()
    local list = {}
    for _, rec in pairs(self.recipes) do
        table.insert(list, rec)
    end
    table.sort(list, function(a, b)
        local ca = tonumber(a.totalCount) or 0
        local cb = tonumber(b.totalCount) or 0
        if ca ~= cb then
            return ca > cb
        end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return list
end

function CrafterCore:returnOutputToAE2()
    local outName = self.cfg.outputName
    local ae2Name = self.cfg.ae2Name
    if type(outName) ~= "string" or outName == "" or type(ae2Name) ~= "string" or ae2Name == "" then
        return 0
    end
    if not (isPeriphPresent(outName) and isPeriphPresent(ae2Name)) then
        return 0
    end

    local _, slots, _, ok = self:getInventoryCounts(outName)
    if not ok then return 0 end

    local totalMoved = 0
    for _, slot in ipairs(sortedNumericKeys(slots)) do
        local item = slots[slot]
        if item and item.count > 0 then
            local okPush, moved = callPeriph(outName, "pushItems", ae2Name, slot, item.count)
            local m = (okPush and tonumber(moved)) or 0
            if m > 0 then
                totalMoved = totalMoved + m
            end
        end
    end

    if totalMoved > 0 then
        self.lastAction = "AE2 iade: " .. tostring(totalMoved) .. " esya"
    end
    return totalMoved
end

function CrafterCore:matchRecipe(invCounts)
    if type(invCounts) ~= "table" then return nil end
    local sorted = self:getSortedRecipes()
    for _, rec in ipairs(sorted) do
        local okIngredients = true
        for itemName, reqQty in pairs(rec.ingredients or {}) do
            if (invCounts[itemName] or 0) < (tonumber(reqQty) or 0) then
                okIngredients = false
                break
            end
        end

        if okIngredients then
            local okLayout = true
            local hasAnySlot = false
            for slotIdx in pairs(rec.layout or {}) do
                hasAnySlot = true
                local mapped = self.cfg.gridMap and self.cfg.gridMap[slotIdx]
                if not mapped or mapped == "" then
                    okLayout = false
                    break
                end
            end
            if hasAnySlot and okLayout then
                return rec
            end
        end
    end
    return nil
end

function CrafterCore:triggerPulse()
    local sideOrPeriph = self.cfg.triggerSide
    local pulseSec = tonumber(self.cfg.pulseSec) or 0.15
    if type(sideOrPeriph) ~= "string" or sideOrPeriph == "" then
        return false, "triggerSide tanimsiz"
    end

    if isRedstoneSide(sideOrPeriph) then
        if not (redstone and redstone.setOutput) then
            return false, "redstone API yok"
        end
        local okOn, errOn = pcall(redstone.setOutput, sideOrPeriph, true)
        if not okOn then
            return false, tostring(errOn)
        end
        safeSleep(pulseSec)
        local okOff, errOff = pcall(redstone.setOutput, sideOrPeriph, false)
        if not okOff then
            return false, tostring(errOff)
        end
        return true, nil
    end

    if isPeriphPresent(sideOrPeriph) then
        local sidesToPulse = {}
        if isRedstoneSide(self.cfg.relaySide) then
            sidesToPulse = { self.cfg.relaySide }
        else
            sidesToPulse = CrafterCore.REDSTONE_SIDES
        end

        local okOn = false
        for _, s in ipairs(sidesToPulse) do
            local ok = callPeriph(sideOrPeriph, "setOutput", s, true)
            if ok then okOn = true end
        end
        if not okOn then
            return false, "Redstone relay setOutput basarisiz: " .. tostring(sideOrPeriph)
        end
        safeSleep(pulseSec)
        for _, s in ipairs(sidesToPulse) do
            callPeriph(sideOrPeriph, "setOutput", s, false)
        end
        return true, nil
    end

    return false, "Tetikleme hatti bulunamadi: " .. tostring(sideOrPeriph)
end

function CrafterCore:dispatchRecipe(recipe)
    if type(recipe) ~= "table" or type(recipe.layout) ~= "table" then
        return false, "Gecersiz tarif"
    end

    local inputName = self.cfg.inputName
    if type(inputName) ~= "string" or inputName == "" or not isPeriphPresent(inputName) then
        self.status = "ERROR"
        self.lastError = "Input fici bagli degil"
        return false, self.lastError
    end

    local layoutSlots = sortedNumericKeys(recipe.layout)
    if #layoutSlots == 0 then
        return false, "Tarif yerlesimi bos"
    end

    -- Verify all required crafters are mapped and online before moving any items
    for _, gridSlot in ipairs(layoutSlots) do
        local targetName = self.cfg.gridMap and self.cfg.gridMap[gridSlot]
        if not targetName or targetName == "" or not isPeriphPresent(targetName) then
            self.status = "ERROR"
            self.lastError = "Eksik/Cevrimdisi Crafter slot " .. tostring(gridSlot)
            return false, self.lastError
        end
    end

    local _, invSlots, _, okInv = self:getInventoryCounts(inputName)
    if not okInv then
        self.status = "ERROR"
        self.lastError = "Input fici okunamadi"
        return false, self.lastError
    end

    local orderedInvSlots = sortedNumericKeys(invSlots)
    local pushedTargets = {}

    local function rollback()
        for _, pushed in ipairs(pushedTargets) do
            self:returnItemFromCrafter(pushed.crafter, 1)
        end
    end

    for _, gridSlot in ipairs(layoutSlots) do
        local reqItem = recipe.layout[gridSlot]
        local targetCrafter = self.cfg.gridMap[gridSlot]
        local chosenSrcSlot = nil

        for _, srcSlot in ipairs(orderedInvSlots) do
            local info = invSlots[srcSlot]
            if info and info.name == reqItem and info.count > 0 then
                chosenSrcSlot = srcSlot
                break
            end
        end

        if not chosenSrcSlot then
            rollback()
            self.status = "ERROR"
            self.lastError = "Malzeme yetersiz: " .. tostring(reqItem)
            return false, self.lastError
        end

        local okPush, moved = callPeriph(inputName, "pushItems", targetCrafter, chosenSrcSlot, 1, 1)
        if not okPush or (tonumber(moved) or 0) < 1 then
            rollback()
            self.status = "ERROR"
            self.lastError = "Slot " .. tostring(gridSlot) .. " aktarimi basarisiz"
            return false, self.lastError
        end

        invSlots[chosenSrcSlot].count = invSlots[chosenSrcSlot].count - 1
        table.insert(pushedTargets, { crafter = targetCrafter, gridSlot = gridSlot })
    end

    -- Verify every required slot is populated before pulsing
    for _, pushed in ipairs(pushedTargets) do
        local hasItem = crafterHasSlot1Item(pushed.crafter)
        if not hasItem then
            rollback()
            self.status = "ERROR"
            self.lastError = "Dogrulama hatasi: slot " .. tostring(pushed.gridSlot)
            return false, self.lastError
        end
    end

    local okPulse, pulseErr = self:triggerPulse()
    if not okPulse then
        self.status = "ERROR"
        self.lastError = "Redstone tetik hatasi: " .. tostring(pulseErr)
        return false, self.lastError
    end

    self.totalCrafted = self.totalCrafted + 1
    self.lastRecipe = recipe.name
    self.lastCraftTs = safeEpochUtc()
    self.lastError = nil
    self.status = "CRAFTING"
    self.lastAction = recipe.name .. " -> OK"

    self:broadcastCraftEvent(recipe.name)
    return true, nil
end

function CrafterCore:step()
    if self.paused then
        self.status = "PAUSED"
        return { action = "PAUSED", returned = 0 }
    end

    -- Priority 1: Return finished outputs to AE2 Pattern Provider so crafting lock releases
    local returned = self:returnOutputToAE2()

    -- Priority 2: Guard against dispatching while wall is still crafting
    if self:isWallBusy() then
        self.status = "CRAFTING"
        return { action = "BUSY", returned = returned }
    end

    -- Priority 3: Count input barrel & match recipe (largest totalCount first)
    local invCounts, _, totalItems, inputOk = self:getInventoryCounts(self.cfg.inputName)
    if not inputOk then
        self.status = "ERROR"
        self.lastError = "Input fici bagli degil"
        return { action = "ERROR", error = self.lastError, returned = returned }
    end

    if totalItems == 0 then
        self.status = "IDLE"
        self.lastError = nil
        return { action = "IDLE", returned = returned }
    end

    local matched = self:matchRecipe(invCounts)
    if not matched then
        self.status = "IDLE"
        self.lastError = nil
        return { action = "WAITING_ITEMS", returned = returned }
    end

    -- Priority 4 & 5: Atomic dispatch & Redstone pulse
    local okDispatch, errDispatch = self:dispatchRecipe(matched)
    if not okDispatch then
        return { action = "ERROR", recipe = matched.name, error = errDispatch, returned = returned }
    end

    return { action = "CRAFTED", recipe = matched.name, returned = returned }
end

--==============================================================================
-- Optional Non-Blocking Drunken Base Bus (DRUNKEN_BASE_BUS)
--==============================================================================

function CrafterCore:openBaseBus()
    if not self.cfg.rednetEnabled or not rednet then
        self.rednetModemName = nil
        return false
    end
    local modems = self:discoverPeripherals().wirelessModems
    if #modems == 0 then
        self.rednetModemName = nil
        return false
    end
    local chosen = modems[1]
    if rednet.open then
        local isOpen = rednet.isOpen and rednet.isOpen(chosen)
        if not isOpen then
            local ok = pcall(rednet.open, chosen)
            if not ok then
                self.rednetModemName = nil
                return false
            end
        end
    end
    self.rednetModemName = chosen
    return true
end

function CrafterCore:isBaseBusOpen()
    if not (self.cfg.rednetEnabled and rednet) then
        return false
    end
    if not self.rednetModemName then
        return false
    end
    if rednet.isOpen then
        local ok, open = pcall(rednet.isOpen, self.rednetModemName)
        if ok then return open == true end
    end
    return true
end

function CrafterCore:getEffectiveStatus()
    if self.paused then return "PAUSED" end
    if self.lastError then return "ERROR" end
    return self.status or "IDLE"
end

function CrafterCore:buildTelemetryPacket()
    local recipeCount = 0
    for _ in pairs(self.recipes) do
        recipeCount = recipeCount + 1
    end
    return {
        type         = "NODE_TELEMETRY",
        nodeType     = CrafterCore.NODE_TYPE,
        nodeId       = self.cfg.nodeId,
        computerId   = safeComputerId(),
        status       = self:getEffectiveStatus(),
        recipeCount  = recipeCount,
        totalCrafted = self.totalCrafted,
        lastRecipe   = self.lastRecipe,
        lastCraftTs  = self.lastCraftTs
    }
end

function CrafterCore:buildCraftEventPacket(recipeName)
    return {
        type         = "CRAFT_EVENT",
        nodeType     = CrafterCore.NODE_TYPE,
        nodeId       = self.cfg.nodeId,
        recipe       = recipeName,
        totalCrafted = self.totalCrafted,
        timestamp    = safeEpochUtc()
    }
end

function CrafterCore:broadcastTelemetry()
    if not (self:isBaseBusOpen() and rednet and rednet.broadcast) then
        return false
    end
    local pkt = self:buildTelemetryPacket()
    local ok = pcall(rednet.broadcast, pkt, CrafterCore.BASE_BUS_PROTOCOL)
    return ok == true
end

function CrafterCore:broadcastCraftEvent(recipeName)
    if not (self:isBaseBusOpen() and rednet and rednet.broadcast) then
        return false
    end
    local pkt = self:buildCraftEventPacket(recipeName)
    local ok = pcall(rednet.broadcast, pkt, CrafterCore.BASE_BUS_PROTOCOL)
    return ok == true
end

function CrafterCore:maybeBroadcastHeartbeat(nowClock)
    local now = nowClock or safeClock()
    if (now - (self.lastHeartbeatClock or -999)) >= (self.heartbeatInterval or 10.0) then
        self.lastHeartbeatClock = now
        return self:broadcastTelemetry()
    end
    return false
end

function CrafterCore:handleBaseBusMessage(senderId, msg, protocol)
    if protocol ~= CrafterCore.BASE_BUS_PROTOCOL or type(msg) ~= "table" then
        return false, nil
    end
    if msg.targetNode ~= nil and msg.targetNode ~= self.cfg.nodeId then
        return false, nil
    end

    local cmd = msg.type or msg.cmd
    if type(cmd) ~= "string" then
        return false, nil
    end

    local function reply(packet)
        if self:isBaseBusOpen() and rednet and rednet.send and senderId ~= nil then
            pcall(rednet.send, senderId, packet, CrafterCore.BASE_BUS_PROTOCOL)
        end
    end

    if cmd == "CMD_PING" or cmd == "CMD_GET_STATUS" then
        local pkt = self:buildTelemetryPacket()
        reply(pkt)
        return true, pkt
    elseif cmd == "CMD_PAUSE" then
        self.paused = true
        self.status = "PAUSED"
        self.lastAction = "Uzaktan Duraklatildi"
        local pkt = self:buildTelemetryPacket()
        reply(pkt)
        return true, pkt
    elseif cmd == "CMD_RESUME" then
        self.paused = false
        self.status = "IDLE"
        self.lastAction = "Uzaktan Devam"
        local pkt = self:buildTelemetryPacket()
        reply(pkt)
        return true, pkt
    elseif cmd == "CMD_LIST_RECIPES" then
        local items = {}
        for _, rec in ipairs(self:getSortedRecipes()) do
            table.insert(items, {
                name = rec.name,
                totalCount = rec.totalCount
            })
        end
        local pkt = {
            type       = "RECIPE_LIST",
            nodeType   = CrafterCore.NODE_TYPE,
            nodeId     = self.cfg.nodeId,
            computerId = safeComputerId(),
            recipes    = items
        }
        reply(pkt)
        return true, pkt
    end

    return false, nil
end

return CrafterCore
