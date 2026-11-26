-- lib/sequenced_core.lua
-- Drunken OS - Beltless Multi-Depot Sequenced Assembly Core Engine (v2.0)
-- Drives Create Sequenced Assembly recipes across networked Depots (Deployer, Press, Saw, Spout)
-- with #tag caching, subset-safe matching, NBT/component step completion tracking,
-- probabilistic scrap routing, and DRUNKEN_BASE_BUS Rednet telemetry.

local SequencedCore = {}
SequencedCore.__index = SequencedCore

SequencedCore.VERSION = "2.0.0"
SequencedCore.CONFIG_PATH = "/etc/drunken_crafter.cfg"
SequencedCore.RECIPES_PATH = "/etc/drunken_sequenced_recipes.db"
SequencedCore.DEFAULT_RECIPES_PATHS = {
    "/data/sequenced_recipes_default.db",
    "data/sequenced_recipes_default.db"
}
SequencedCore.BASE_BUS_PROTOCOL = "DRUNKEN_BASE_BUS"
SequencedCore.NODE_TYPE = "SEQUENCED_ASSEMBLER"
SequencedCore.DIRECT_SIDES = { "left", "right", "top", "bottom", "front", "back" }

SequencedCore.DEFAULT_CONFIG = {
    mode          = "SEQUENCED",
    nodeId        = "SEQ-01",
    inputName     = "",
    ae2Name       = "",
    trashName     = nil,
    stations      = {
        deployer      = nil,
        deployerDepot = nil,
        pressDepot    = nil,
        sawDepot      = nil,
        spouts        = {}
    },
    pollRate      = 0.15,
    stepTimeout   = 15.0,
    rednetEnabled = true
}

local unpackFn = table.unpack or unpack

local function deepCopy(val)
    if type(val) ~= "table" then return val end
    local out = {}
    for k, v in pairs(val) do
        out[deepCopy(k)] = deepCopy(v)
    end
    return out
end

local function isDirectSide(val)
    if type(val) ~= "string" then return false end
    local low = val:lower()
    for _, s in ipairs(SequencedCore.DIRECT_SIDES) do
        if low == s then return true end
    end
    return false
end

SequencedCore.isDirectSide = isDirectSide

local function runParallel(fns)
    if type(fns) ~= "table" or #fns == 0 then return end
    if #fns == 1 then fns[1](); return end
    if parallel and parallel.waitForAll then
        parallel.waitForAll(unpackFn(fns))
        return
    end
    for _, fn in ipairs(fns) do fn() end
end

local function sortedNumericKeys(tbl)
    local keys = {}
    for k in pairs(tbl or {}) do
        if type(k) == "number" then table.insert(keys, k) end
    end
    table.sort(keys)
    return keys
end

local function safeClock()
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and type(c) == "number" then return c end
    end
    return 0
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

local function safeComputerId()
    if os and os.getComputerID then
        local ok, id = pcall(os.getComputerID)
        if ok and id ~= nil then return id end
    end
    return 0
end

local function ensureParentDir(path)
    if not (fs and fs.getDir and fs.makeDir) then return end
    local okDir, dir = pcall(fs.getDir, path)
    if okDir and dir and dir ~= "" and dir ~= "." then
        if not (fs.exists and fs.exists(dir)) then
            pcall(fs.makeDir, dir)
        end
    end
end

local function readSerializedTable(path)
    if not (fs and fs.exists and fs.open and textutils and textutils.unserialize) then
        return nil
    end
    local okEx, exists = pcall(fs.exists, path)
    if not (okEx and exists) then return nil end
    local okOpen, f = pcall(fs.open, path, "r")
    if not (okOpen and f) then return nil end
    local okRead, raw = pcall(f.readAll)
    pcall(f.close)
    if not (okRead and type(raw) == "string" and #raw > 0) then return nil end
    local okUn, data = pcall(textutils.unserialize, raw)
    if okUn and type(data) == "table" then return data end
    return nil
end

local function writeSerializedTable(path, tbl)
    if not (fs and fs.open and textutils and textutils.serialize) then
        return false, "fs or textutils unavailable"
    end
    ensureParentDir(path)
    local okSer, raw = pcall(textutils.serialize, tbl)
    if not (okSer and type(raw) == "string") then return false, "serialize failed" end
    local okOpen, f = pcall(fs.open, path, "w")
    if not (okOpen and f) then return false, "failed to open: " .. tostring(path) end
    local okW, errW = pcall(f.write, raw)
    pcall(f.close)
    if not okW then return false, tostring(errW) end
    return true
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
    if not peripheral or type(name) ~= "string" or name == "" then return false end
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

local function getPeriphTypes(name)
    local out = {}
    if not (peripheral and peripheral.getType) or type(name) ~= "string" or name == "" then
        return out
    end
    local results = { pcall(peripheral.getType, name) }
    if results[1] then
        for i = 2, #results do
            if type(results[i]) == "string" and results[i] ~= "" then
                table.insert(out, results[i])
            end
        end
    end
    return out
end

local function hasPeriphType(name, targetType)
    if peripheral and peripheral.hasType then
        local ok, has = pcall(peripheral.hasType, name, targetType)
        if ok and has then return true end
    end
    for _, t in ipairs(getPeriphTypes(name)) do
        if t == targetType then return true end
    end
    return false
end

local function normalizeId(s)
    return (tostring(s or ""):lower():gsub("[_%s%-]", ""))
end

local function nameOrTypeContains(name, needle)
    local normNeedle = normalizeId(needle)
    if type(name) == "string" then
        local lname = name:lower()
        if lname:find(needle, 1, true) or normalizeId(lname):find(normNeedle, 1, true) then
            return true
        end
    end
    for _, t in ipairs(getPeriphTypes(name)) do
        local lt = t:lower()
        if lt:find(needle, 1, true) or normalizeId(lt):find(normNeedle, 1, true) then
            return true
        end
    end
    return false
end

local function normalizeSequencedRecipe(rawKey, rec)
    if type(rec) ~= "table" or type(rec.sequence) ~= "table" or #rec.sequence == 0 then
        return nil, nil
    end
    local rKey = tostring(rawKey or rec.result or rec.name or "")
    if rKey == "" or type(rec.baseIngredient) ~= "string" or rec.baseIngredient == "" then
        return nil, nil
    end
    local loops = math.max(1, math.floor(tonumber(rec.loops) or 1))
    local normSeq = {}
    local calcIngs = { [rec.baseIngredient] = 1 }
    local calcTotal = 1

    for _, st in ipairs(rec.sequence) do
        if type(st) == "table" and type(st.type) == "string" then
            local entry = { type = st.type }
            if st.type == "deploying" then
                if type(st.item) ~= "string" or st.item == "" then return nil, nil end
                entry.item = st.item
                if st.keepHeldItem then
                    entry.keepHeldItem = true
                else
                    calcIngs[st.item] = (calcIngs[st.item] or 0) + loops
                    calcTotal = calcTotal + loops
                end
            elseif st.type == "filling" then
                if type(st.fluid) ~= "string" or st.fluid == "" then return nil, nil end
                entry.fluid = st.fluid
            elseif st.type ~= "pressing" and st.type ~= "cutting" then
                return nil, nil
            end
            table.insert(normSeq, entry)
        end
    end
    if #normSeq == 0 then return nil, nil end

    local normIngs = {}
    if type(rec.ingredients) == "table" and next(rec.ingredients) ~= nil then
        for k, v in pairs(rec.ingredients) do
            local n = tonumber(v) or 0
            if n > 0 then normIngs[k] = n end
        end
    else
        normIngs = calcIngs
    end

    return rKey, {
        name             = rec.name or rKey,
        result           = rec.result or rKey,
        resultCount      = math.max(1, math.floor(tonumber(rec.resultCount) or 1)),
        chance           = tonumber(rec.chance) or 1.0,
        baseIngredient   = rec.baseIngredient,
        transitionalItem = rec.transitionalItem or "",
        loops            = loops,
        totalCount       = tonumber(rec.totalCount) or calcTotal,
        ingredients      = normIngs,
        sequence         = normSeq
    }
end

function SequencedCore.new(opts)
    opts = opts or {}
    local self = setmetatable({}, SequencedCore)

    self.configPath = opts.configPath or SequencedCore.CONFIG_PATH
    self.recipesPath = opts.recipesPath or SequencedCore.RECIPES_PATH
    self.cfg = deepCopy(SequencedCore.DEFAULT_CONFIG)
    self.recipes = {}
    self._sortedRecipes = nil
    self._sortedRecipesRef = nil
    self.tagCache = {}

    self.paused = false
    self.status = "IDLE"
    self.activeJob = nil
    self.totalCrafted = 0
    self.totalScraps = 0
    self.lastRecipe = nil
    self.lastCraftTs = nil
    self.lastError = nil
    self.lastAction = "Hazir"
    self.rednetModemName = nil
    self.lastHeartbeatClock = -999
    self.heartbeatInterval = 10.0
    self.autoImportedDefaultCount = 0
    self.lastStationStatus = nil

    if opts.autoLoad ~= false then
        self:loadConfig()
        self:loadRecipes()
    end

    if next(self.recipes) == nil and opts.autoImportDefault ~= false then
        local imported = self:importDefaultRecipes({ overwrite = false })
        if imported > 0 then
            self.autoImportedDefaultCount = imported
            self.lastAction = tostring(imported) .. " sequenced tarif yuklendi"
        end
    end

    if type(opts.config) == "table" then
        for k, v in pairs(opts.config) do
            if k == "stations" and type(v) == "table" then
                self.cfg.stations = deepCopy(SequencedCore.DEFAULT_CONFIG.stations)
                for sk, sv in pairs(v) do
                    self.cfg.stations[sk] = deepCopy(sv)
                end
            else
                self.cfg[k] = deepCopy(v)
            end
        end
    end
    self.cfg.mode = "SEQUENCED"
    self.cfg.stations = self.cfg.stations or deepCopy(SequencedCore.DEFAULT_CONFIG.stations)
    self.cfg.stations.spouts = self.cfg.stations.spouts or {}

    return self
end

function SequencedCore:loadConfig()
    local loaded = readSerializedTable(self.configPath)
    if type(loaded) == "table" then
        for k, v in pairs(loaded) do
            if k == "stations" and type(v) == "table" then
                self.cfg.stations = deepCopy(SequencedCore.DEFAULT_CONFIG.stations)
                for sk, sv in pairs(v) do
                    self.cfg.stations[sk] = deepCopy(sv)
                end
            else
                self.cfg[k] = deepCopy(v)
            end
        end
        self.cfg.mode = "SEQUENCED"
        self.cfg.stations = self.cfg.stations or deepCopy(SequencedCore.DEFAULT_CONFIG.stations)
        self.cfg.stations.spouts = self.cfg.stations.spouts or {}
        return true
    end
    return false
end

function SequencedCore:saveConfig()
    self.cfg.mode = "SEQUENCED"
    return writeSerializedTable(self.configPath, self.cfg)
end

function SequencedCore:loadRecipes()
    local loaded = readSerializedTable(self.recipesPath)
    if type(loaded) == "table" then
        local clean = {}
        for k, rec in pairs(loaded) do
            local rKey, norm = normalizeSequencedRecipe(k, rec)
            if rKey and norm then
                clean[rKey] = norm
            end
        end
        self.recipes = clean
        self._sortedRecipes = nil
        return true
    end
    return false
end

function SequencedCore:saveRecipes()
    return writeSerializedTable(self.recipesPath, self.recipes)
end

function SequencedCore:importDefaultRecipes(opts)
    opts = opts or {}
    local candidates = opts.path and { opts.path } or SequencedCore.DEFAULT_RECIPES_PATHS
    local sourceData, usedPath = nil, nil
    for _, path in ipairs(candidates) do
        local data = readSerializedTable(path)
        if type(data) == "table" then
            sourceData = data
            usedPath = path
            break
        end
    end
    if not sourceData then
        return 0, "Varsayilan veritabani bulunamadi (data/sequenced_recipes_default.db)"
    end

    local wasEmpty = (next(self.recipes) == nil)
    local imported = 0
    for rawKey, rec in pairs(sourceData) do
        local rKey, norm = normalizeSequencedRecipe(rawKey, rec)
        if rKey and norm then
            if opts.overwrite or self.recipes[rKey] == nil then
                self.recipes[rKey] = norm
                imported = imported + 1
            end
        end
    end

    if imported > 0 then
        self._sortedRecipes = nil
        local copied = false
        if wasEmpty and opts.overwrite ~= true and usedPath
            and fs and fs.copy and fs.exists and not fs.exists(self.recipesPath) then
            ensureParentDir(self.recipesPath)
            local okCopy = pcall(fs.copy, usedPath, self.recipesPath)
            copied = (okCopy == true)
        end
        if not copied then
            self:saveRecipes()
        end
        self.lastAction = tostring(imported) .. " sequenced tarif aktarildi"
    end
    return imported, nil, usedPath
end

function SequencedCore:deleteRecipe(keyOrName)
    if not keyOrName then return false end
    local targetKey = nil
    if self.recipes[keyOrName] then
        targetKey = keyOrName
    else
        for k, rec in pairs(self.recipes) do
            if rec.name == keyOrName then targetKey = k; break end
        end
    end
    if not targetKey then return false end
    local removedName = (self.recipes[targetKey] and self.recipes[targetKey].name) or tostring(targetKey)
    self.recipes[targetKey] = nil
    self._sortedRecipes = nil
    self:saveRecipes()
    self.lastAction = "Silindi: " .. tostring(removedName)
    return true
end

function SequencedCore:getSortedRecipes()
    local curCount = 0
    for _ in pairs(self.recipes) do
        curCount = curCount + 1
    end
    if self._sortedRecipes ~= nil and self._sortedRecipesRef == self.recipes and self._sortedRecipesCount == curCount then
        return self._sortedRecipes
    end
    local list = {}
    for _, rec in pairs(self.recipes) do
        table.insert(list, rec)
    end
    table.sort(list, function(a, b)
        local ca = tonumber(a.totalCount) or 0
        local cb = tonumber(b.totalCount) or 0
        if ca ~= cb then return ca > cb end
        local ac = tostring(a.result or ""):find("^create:") ~= nil
        local bc = tostring(b.result or ""):find("^create:") ~= nil
        if ac ~= bc then return ac end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    self._sortedRecipes = list
    self._sortedRecipesRef = self.recipes
    self._sortedRecipesCount = curCount
    return list
end

--==============================================================================
-- Peripheral Discovery & Calibration Helpers
--==============================================================================

function SequencedCore:discoverPeripherals()
    local res = {
        deployers = {},
        depots = {},
        inventories = {},
        ae2Providers = {},
        wirelessModems = {},
        monitors = {}
    }
    if not (peripheral and peripheral.getNames) then return res end
    local ok, names = pcall(peripheral.getNames)
    if not (ok and type(names) == "table") then return res end

    for _, name in ipairs(names) do
        local isCrafter = nameOrTypeContains(name, "mechanical_crafter")
        local isDeployer = nameOrTypeContains(name, "deployer")
        local isDepot = nameOrTypeContains(name, "depot")
        local isProvider = nameOrTypeContains(name, "pattern_provider")

        if hasPeriphType(name, "monitor") then
            table.insert(res.monitors, name)
        elseif hasPeriphType(name, "modem") then
            local okW, isW = callPeriph(name, "isWireless")
            if okW and isW then table.insert(res.wirelessModems, name) end
        elseif isDeployer then
            table.insert(res.deployers, name)
        elseif isDepot then
            table.insert(res.depots, name)
        elseif isProvider then
            table.insert(res.ae2Providers, name)
        elseif not isCrafter and not nameOrTypeContains(name, "redstone_relay") then
            local isInv = hasPeriphType(name, "inventory")
            if not isInv then
                local okL = callPeriph(name, "list")
                local okS = callPeriph(name, "size")
                isInv = (okL or okS) == true
            end
            if isInv then
                table.insert(res.inventories, name)
            end
        end
    end

    table.sort(res.deployers)
    table.sort(res.depots)
    table.sort(res.inventories)
    table.sort(res.ae2Providers, function(a, b)
        local da, db = isDirectSide(a), isDirectSide(b)
        if da ~= db then return not da end
        return a < b
    end)
    res.ae2DirectSideOnly = (#res.ae2Providers > 0 and isDirectSide(res.ae2Providers[1]))
    table.sort(res.wirelessModems)
    table.sort(res.monitors)
    return res
end

function SequencedCore:readDepotItem(depotName)
    if type(depotName) ~= "string" or depotName == "" or not isPeriphPresent(depotName) then
        return nil, nil, false
    end
    local okList, items = callPeriph(depotName, "list")
    if okList and type(items) == "table" then
        local slot1 = items[1]
        if type(slot1) == "table" and slot1.name and (tonumber(slot1.count) or 1) > 0 then
            return slot1, 1, true
        end
        for slot, item in pairs(items) do
            if type(item) == "table" and item.name and (tonumber(item.count) or 1) > 0 then
                return item, tonumber(slot) or slot, true
            end
        end
        return nil, nil, true
    end
    local okDet, det = callPeriph(depotName, "getItemDetail", 1)
    if okDet and type(det) == "table" and det.name and (tonumber(det.count) or 1) > 0 then
        return det, 1, true
    end
    return nil, nil, true
end

function SequencedCore:returnItemToInput(sourcePeriph, slot)
    slot = slot or 1
    local inputName = self.cfg.inputName
    if type(inputName) ~= "string" or inputName == "" or not isPeriphPresent(inputName) then
        return 0
    end
    local okPush, moved = callPeriph(sourcePeriph, "pushItems", inputName, slot, 64)
    if okPush and (tonumber(moved) or 0) > 0 then return tonumber(moved) end
    local okPull, pulled = callPeriph(inputName, "pullItems", sourcePeriph, slot, 64)
    if okPull and (tonumber(pulled) or 0) > 0 then return tonumber(pulled) end
    return 0
end

function SequencedCore:autoDetectDeployer(deployersList)
    local deployers = deployersList or self:discoverPeripherals().deployers
    local cur = self.cfg.stations and self.cfg.stations.deployer
    if cur and cur ~= "" and isPeriphPresent(cur) then
        return cur
    end
    if #deployers > 0 then
        self.cfg.stations.deployer = deployers[1]
        self:saveConfig()
        return deployers[1]
    end
    return nil
end

function SequencedCore:takeDepotSnapshot(depotNames)
    local names = depotNames or self:discoverPeripherals().depots
    local snap = {}
    local tasks = {}
    for _, name in ipairs(names) do
        local dname = name
        table.insert(tasks, function()
            local item = self:readDepotItem(dname)
            snap[dname] = item and (tostring(item.name) .. ":" .. tostring(item.nbt or "") .. ":" .. tostring(item.count or 1)) or ""
        end)
    end
    runParallel(tasks)
    return snap
end

function SequencedCore:calibrateDepotTarget(depotNames, baseline, returnToInput)
    local names = depotNames or self:discoverPeripherals().depots
    baseline = baseline or {}
    local scanned = {}
    local tasks = {}

    for _, name in ipairs(names) do
        local dname = name
        table.insert(tasks, function()
            local item, slot = self:readDepotItem(dname)
            local sig = item and (tostring(item.name) .. ":" .. tostring(item.nbt or "") .. ":" .. tostring(item.count or 1)) or ""
            scanned[dname] = { item = item, slot = slot or 1, sig = sig }
        end)
    end
    runParallel(tasks)

    local matched = nil
    for _, name in ipairs(names) do
        local info = scanned[name]
        if not info or info.sig == "" then
            baseline[name] = ""
        elseif not matched then
            local baseVal = baseline[name]
            local isNew = (baseVal == nil or baseVal == false or baseVal == "")
                or (type(baseVal) == "string" and baseVal ~= info.sig)
            if isNew then
                matched = name
                if returnToInput ~= false then
                    local ret = self:returnItemToInput(name, info.slot)
                    if ret > 0 then
                        local postItem = self:readDepotItem(name)
                        baseline[name] = postItem and (tostring(postItem.name) .. ":" .. tostring(postItem.nbt or "") .. ":" .. tostring(postItem.count or 1)) or ""
                    else
                        baseline[name] = info.sig
                    end
                else
                    baseline[name] = info.sig
                end
            end
        end
    end
    return matched
end

--==============================================================================
-- Inventory, Tag Cache & Recipe Matching
--==============================================================================

function SequencedCore:getInventoryCounts(periphName)
    local counts, slots, totalItems = {}, {}, 0
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
                slots[numSlot] = { name = item.name, count = cnt, nbt = item.nbt }
                counts[item.name] = (counts[item.name] or 0) + cnt
                totalItems = totalItems + cnt
            end
        end
    end
    return counts, slots, totalItems, true
end

function SequencedCore:ensureItemTags(periphName, slot, itemName)
    if type(itemName) ~= "string" or itemName == "" then return nil end
    if self.tagCache[itemName] ~= nil then return self.tagCache[itemName] end
    local tags = {}
    if type(periphName) == "string" and periphName ~= "" and slot then
        local okDet, detail = callPeriph(periphName, "getItemDetail", slot)
        if okDet and type(detail) == "table" and type(detail.tags) == "table" then
            for k, v in pairs(detail.tags) do
                if v then tags[k] = true end
            end
        end
    end
    self.tagCache[itemName] = tags
    return tags
end

function SequencedCore:cacheInventoryTags(periphName, invSlots)
    if type(invSlots) ~= "table" then return end
    for _, slot in ipairs(sortedNumericKeys(invSlots)) do
        local info = invSlots[slot]
        if info and info.name and self.tagCache[info.name] == nil then
            self:ensureItemTags(periphName, slot, info.name)
        end
    end
end

function SequencedCore:itemMatchesMatcher(itemName, matcher)
    if type(itemName) ~= "string" or type(matcher) ~= "string" then return false end
    if matcher:sub(1, 1) ~= "#" then
        return itemName == matcher
    end
    local tagName = matcher:sub(2)
    local cached = self.tagCache[itemName]
    return type(cached) == "table" and cached[tagName] == true
end

function SequencedCore:matchRecipe(invCounts)
    if type(invCounts) ~= "table" then return nil end
    local invItemNames = {}
    for itemName, cnt in pairs(invCounts) do
        if (tonumber(cnt) or 0) > 0 then table.insert(invItemNames, itemName) end
    end
    table.sort(invItemNames)

    local fallbackCandidate = nil
    for _, rec in ipairs(self:getSortedRecipes()) do
        local pool = {}
        for _, itemName in ipairs(invItemNames) do
            pool[itemName] = tonumber(invCounts[itemName]) or 0
        end

        local exactMatchers, tagMatchers = {}, {}
        for matcher, qty in pairs(rec.ingredients or {}) do
            local reqQty = tonumber(qty) or 0
            if reqQty > 0 then
                if type(matcher) == "string" and matcher:sub(1, 1) == "#" then
                    table.insert(tagMatchers, { matcher = matcher, qty = reqQty })
                else
                    table.insert(exactMatchers, { matcher = matcher, qty = reqQty })
                end
            end
        end
        table.sort(tagMatchers, function(a, b) return a.matcher < b.matcher end)

        local okIngredients = true
        for _, req in ipairs(exactMatchers) do
            local avail = pool[req.matcher] or 0
            if avail < req.qty then okIngredients = false; break end
            pool[req.matcher] = avail - req.qty
        end

        if okIngredients then
            for _, req in ipairs(tagMatchers) do
                local needed = req.qty
                for _, itemName in ipairs(invItemNames) do
                    local avail = pool[itemName] or 0
                    if avail > 0 and self:itemMatchesMatcher(itemName, req.matcher) then
                        local take = math.min(avail, needed)
                        pool[itemName] = avail - take
                        needed = needed - take
                        if needed <= 0 then break end
                    end
                end
                if needed > 0 then okIngredients = false; break end
            end
        end

        if okIngredients then
            local okSt = self:validateRecipeStations(rec)
            if okSt then
                return rec
            elseif not fallbackCandidate then
                fallbackCandidate = rec
            end
        end
    end
    return fallbackCandidate
end

--==============================================================================
-- Station Validation & Sequenced State Machine (step)
--==============================================================================

function SequencedCore:getDepotForStep(stepObj)
    if type(stepObj) ~= "table" then return nil, "Gecersiz adim" end
    local st = self.cfg.stations or {}
    if stepObj.type == "deploying" then
        if not (st.deployer and isPeriphPresent(st.deployer)) then
            return nil, "Deployer bagli degil!"
        end
        if not (st.deployerDepot and isPeriphPresent(st.deployerDepot)) then
            return nil, "Deployer Depot bagli degil!"
        end
        return st.deployerDepot, nil
    elseif stepObj.type == "pressing" then
        if not (st.pressDepot and isPeriphPresent(st.pressDepot)) then
            return nil, "Press Depot bagli degil!"
        end
        return st.pressDepot, nil
    elseif stepObj.type == "cutting" then
        if not (st.sawDepot and isPeriphPresent(st.sawDepot)) then
            return nil, "Saw Depot bagli degil!"
        end
        return st.sawDepot, nil
    elseif stepObj.type == "filling" then
        local spouts = st.spouts or {}
        local depot = spouts[stepObj.fluid]
        if not (depot and isPeriphPresent(depot)) then
            return nil, "Spout Depot eksik: " .. tostring(stepObj.fluid)
        end
        return depot, nil
    end
    return nil, "Desteklenmeyen adim: " .. tostring(stepObj.type)
end

function SequencedCore:validateRecipeStations(recipe)
    if type(recipe) ~= "table" or type(recipe.sequence) ~= "table" then
        return false, "Gecersiz tarif"
    end
    for _, stepObj in ipairs(recipe.sequence) do
        local depot, err = self:getDepotForStep(stepObj)
        if not depot then
            return false, err
        end
    end
    return true, nil
end

function SequencedCore:getStationStatus(cachedInputCount, cachedInputOk)
    local st = self.cfg.stations or {}
    local inputOk, inputCount = cachedInputOk, cachedInputCount
    if inputOk == nil then
        local _, _, cnt, ok = self:getInventoryCounts(self.cfg.inputName)
        inputOk, inputCount = ok, cnt
    end
    local spoutCount = 0
    local spoutOnline = 0
    for _, dName in pairs(st.spouts or {}) do
        if type(dName) == "string" and dName ~= "" then
            spoutCount = spoutCount + 1
            if isPeriphPresent(dName) then spoutOnline = spoutOnline + 1 end
        end
    end
    local status = {
        inputOk          = inputOk == true,
        inputCount       = tonumber(inputCount) or 0,
        ae2Ok            = isPeriphPresent(self.cfg.ae2Name),
        ae2IsDirectSide  = isDirectSide(self.cfg.ae2Name),
        trashOk          = (type(self.cfg.trashName) == "string" and self.cfg.trashName ~= "" and isPeriphPresent(self.cfg.trashName)) == true,
        deployerOk       = isPeriphPresent(st.deployer),
        deployerDepotOk  = isPeriphPresent(st.deployerDepot),
        pressOk          = isPeriphPresent(st.pressDepot),
        sawOk            = isPeriphPresent(st.sawDepot),
        spoutCount       = spoutCount,
        spoutOnline      = spoutOnline,
        baseBusOpen      = self:isBaseBusOpen()
    }
    self.lastStationStatus = status
    return status
end

function SequencedCore:findMatchingInputSlot(invSlots, matcher)
    for _, slot in ipairs(sortedNumericKeys(invSlots)) do
        local info = invSlots[slot]
        if info and info.count > 0 and self:itemMatchesMatcher(info.name, matcher) then
            return slot, info
        end
    end
    return nil, nil
end

function SequencedCore:resetActiveJob()
    self.activeJob = nil
    self.lastError = nil
    self.status = self.paused and "PAUSED" or "IDLE"
    self.lastAction = "Aktif is sifirlandi"
end

function SequencedCore:finishActiveJob()
    local job = self.activeJob
    if not job then return { action = "IDLE" } end

    local finalDepot = job.currentDepot or job.targetDepot
    local finalItem, finalSlot = self:readDepotItem(finalDepot)
    if not finalItem then
        self.activeJob = nil
        self.status = "ERROR"
        self.lastError = "Cikis urunu Depot'ta bulunamadi!"
        return { action = "ERROR", error = self.lastError }
    end

    local rec = job.recipe
    local ae2Name = self.cfg.ae2Name
    if finalItem.name == rec.result then
        if type(ae2Name) == "string" and ae2Name ~= "" and isPeriphPresent(ae2Name) then
            callPeriph(finalDepot, "pushItems", ae2Name, finalSlot, finalItem.count)
        end
        self.totalCrafted = self.totalCrafted + 1
        self.lastRecipe = rec.name
        self.lastCraftTs = safeEpochUtc()
        self.lastError = nil
        self.status = "IDLE"
        self.lastAction = rec.name .. " -> OK"
        self.activeJob = nil
        self:broadcastCraftEvent(rec.name)
        return { action = "FINISHED", recipe = rec.name, result = finalItem.name, scrap = false }
    else
        -- Probabilistic scrap handling
        local trashName = self.cfg.trashName
        local dest = nil
        if type(trashName) == "string" and trashName ~= "" and isPeriphPresent(trashName) then
            dest = trashName
        elseif type(ae2Name) == "string" and ae2Name ~= "" and isPeriphPresent(ae2Name) then
            dest = ae2Name
        end
        if dest then
            callPeriph(finalDepot, "pushItems", dest, finalSlot, finalItem.count)
        end
        self.totalScraps = self.totalScraps + 1
        self.lastError = nil
        self.status = "IDLE"
        local shortScrap = tostring(finalItem.name):gsub("^[^:]+:", "")
        self.lastAction = "UYARI: Sansli tarif hurda uretti! (" .. shortScrap .. ")"
        self.activeJob = nil
        return { action = "SCRAP", recipe = rec.name, result = finalItem.name, scrap = true, routedTo = dest }
    end
end

function SequencedCore:executeMoveToStation()
    local job = self.activeJob
    local rec = job.recipe
    local seqStep = rec.sequence[job.stepIdx]
    local targetDepot, stErr = self:getDepotForStep(seqStep)
    if not targetDepot then
        self.paused = true
        self.status = "ERROR"
        self.lastError = stErr
        return { action = "ERROR", error = stErr }
    end

    local inputName = self.cfg.inputName
    local _, invSlots, invTotal, invOk = self:getInventoryCounts(inputName)
    self:cacheInventoryTags(inputName, invSlots)
    self:getStationStatus(invTotal, invOk)

    -- 1. Place base item (Loop 1, Step 1) or transfer transitionalItem from currentDepot -> targetDepot
    if job.currentDepot == nil then
        local baseSlot, baseInfo = self:findMatchingInputSlot(invSlots, rec.baseIngredient)
        if not baseSlot or not baseInfo then
            self.activeJob = nil
            self.status = "ERROR"
            self.lastError = "Ana malzeme eksik: " .. tostring(rec.baseIngredient)
            return { action = "ERROR", error = self.lastError }
        end
        job.prevName = baseInfo.name
        job.prevNbt = baseInfo.nbt

        local okPush, moved = callPeriph(inputName, "pushItems", targetDepot, baseSlot, 1, 1)
        if not okPush or (tonumber(moved) or 0) < 1 then
            self.paused = true
            self.status = "ERROR"
            self.lastError = "Depot'a ana malzeme itilemedi: " .. tostring(targetDepot)
            return { action = "ERROR", error = self.lastError }
        end
        invSlots[baseSlot].count = invSlots[baseSlot].count - 1
        job.currentDepot = targetDepot
    else
        local curItem, curSlot = self:readDepotItem(job.currentDepot)
        if not curItem then
            self.paused = true
            self.status = "ERROR"
            self.lastError = "Ara urun kayip (" .. tostring(job.currentDepot) .. ")!"
            return { action = "ERROR", error = self.lastError }
        end
        job.prevName = curItem.name
        job.prevNbt = curItem.nbt

        if job.currentDepot ~= targetDepot then
            local okMove, moved = callPeriph(job.currentDepot, "pushItems", targetDepot, curSlot, 1, 1)
            if not okMove or (tonumber(moved) or 0) < 1 then
                self.paused = true
                self.status = "ERROR"
                self.lastError = "Istasyonlar arasi tasima hatasi -> " .. tostring(targetDepot)
                return { action = "ERROR", error = self.lastError }
            end
            job.currentDepot = targetDepot
        end
    end

    -- 2. If deploying step, feed 1 item to Deployer hand (unless keepHeldItem and already holding it)
    if seqStep.type == "deploying" then
        local deployerName = self.cfg.stations.deployer
        local needFeed = true
        if seqStep.keepHeldItem then
            local heldItem = self:readDepotItem(deployerName)
            if heldItem and self:itemMatchesMatcher(heldItem.name, seqStep.item) then
                needFeed = false
            end
        end
        if needFeed then
            local depSlot = self:findMatchingInputSlot(invSlots, seqStep.item)
            if not depSlot then
                self.paused = true
                self.status = "ERROR"
                self.lastError = "Deployer malzemesi eksik: " .. tostring(seqStep.item)
                return { action = "ERROR", error = self.lastError }
            end
            local okFeed, fed = callPeriph(inputName, "pushItems", deployerName, depSlot, 1, 1)
            if not okFeed or (tonumber(fed) or 0) < 1 then
                self.paused = true
                self.status = "ERROR"
                self.lastError = "Deployer eline malzeme itilemedi!"
                return { action = "ERROR", error = self.lastError }
            end
            invSlots[depSlot].count = invSlots[depSlot].count - 1
        end
    end

    job.targetDepot = targetDepot
    job.state = "WAITING_PROCESS"
    job.stepStartTime = safeClock()
    self.status = "CRAFTING"
    self.lastError = nil
    self.lastAction = string.format("%s [%d/%d | %d/%d]", rec.name, job.loop, rec.loops, job.stepIdx, #rec.sequence)
    return { action = "MOVED", recipe = rec.name, loop = job.loop, stepIdx = job.stepIdx }
end

function SequencedCore:step()
    if self.paused then
        self.status = "PAUSED"
        return { action = "PAUSED" }
    end

    -- 1. IDLE -> Match Recipe & Start Active Job
    if not self.activeJob then
        local invCounts, invSlots, totalItems, inputOk = self:getInventoryCounts(self.cfg.inputName)
        self:getStationStatus(totalItems, inputOk)

        if not inputOk then
            self.status = "ERROR"
            self.lastError = "Input fici bagli degil"
            return { action = "ERROR", error = self.lastError }
        end
        if totalItems == 0 then
            self.status = "IDLE"
            self.lastError = nil
            return { action = "IDLE" }
        end

        self:cacheInventoryTags(self.cfg.inputName, invSlots)
        local matched = self:matchRecipe(invCounts)
        if not matched then
            self.status = "IDLE"
            self.lastError = nil
            return { action = "WAITING_ITEMS" }
        end

        local okSt, stErr = self:validateRecipeStations(matched)
        if not okSt then
            self.status = "ERROR"
            self.lastError = stErr
            return { action = "MISSING_STATION", recipe = matched.name, error = stErr }
        end

        self.activeJob = {
            recipe        = matched,
            loop          = 1,
            stepIdx       = 1,
            state         = "MOVE_TO_STATION",
            currentDepot  = nil,
            targetDepot   = nil,
            prevName      = nil,
            prevNbt       = nil,
            stepStartTime = safeClock()
        }
        return self:executeMoveToStation()
    end

    local job = self.activeJob

    -- 2. MOVE_TO_STATION
    if job.state == "MOVE_TO_STATION" then
        return self:executeMoveToStation()
    end

    -- 3. WAITING_PROCESS
    if job.state == "WAITING_PROCESS" then
        local item = self:readDepotItem(job.targetDepot)
        local completed = false
        if item then
            if item.name ~= job.prevName or item.nbt ~= job.prevNbt then
                completed = true
            end
        end

        if completed then
            job.stepIdx = job.stepIdx + 1
            if job.stepIdx > #job.recipe.sequence then
                job.stepIdx = 1
                job.loop = job.loop + 1
            end
            if job.loop > job.recipe.loops then
                job.state = "FINISH_JOB"
                return self:finishActiveJob()
            else
                job.state = "MOVE_TO_STATION"
                return { action = "STEP_DONE", recipe = job.recipe.name, loop = job.loop, stepIdx = job.stepIdx }
            end
        end

        local timeout = tonumber(self.cfg.stepTimeout) or 15.0
        if (safeClock() - (job.stepStartTime or 0)) > timeout then
            self.paused = true
            self.status = "ERROR"
            self.lastError = "Istasyon donmuyor / Sivi eksik!"
            self.lastAction = self.lastError
            return { action = "TIMEOUT", recipe = job.recipe.name, error = self.lastError }
        end

        self.status = "CRAFTING"
        return { action = "WAITING_PROCESS", recipe = job.recipe.name, loop = job.loop, stepIdx = job.stepIdx }
    end

    -- 4. FINISH_JOB
    if job.state == "FINISH_JOB" then
        return self:finishActiveJob()
    end

    return { action = "IDLE" }
end

--==============================================================================
-- Optional Non-Blocking Drunken Base Bus (DRUNKEN_BASE_BUS)
--==============================================================================

function SequencedCore:openBaseBus()
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

function SequencedCore:isBaseBusOpen()
    if not (self.cfg.rednetEnabled and rednet and self.rednetModemName) then
        return false
    end
    if rednet.isOpen then
        local ok, open = pcall(rednet.isOpen, self.rednetModemName)
        if ok then return open == true end
    end
    return true
end

function SequencedCore:getEffectiveStatus()
    if self.paused then return "PAUSED" end
    if self.lastError then return "ERROR" end
    if self.activeJob then return "CRAFTING" end
    return self.status or "IDLE"
end

function SequencedCore:buildTelemetryPacket()
    local recipeCount = 0
    for _ in pairs(self.recipes) do recipeCount = recipeCount + 1 end
    return {
        type         = "NODE_TELEMETRY",
        nodeType     = SequencedCore.NODE_TYPE,
        nodeId       = self.cfg.nodeId,
        computerId   = safeComputerId(),
        status       = self:getEffectiveStatus(),
        recipeCount  = recipeCount,
        totalCrafted = self.totalCrafted,
        totalScraps  = self.totalScraps,
        lastRecipe   = self.lastRecipe,
        lastCraftTs  = self.lastCraftTs
    }
end

function SequencedCore:buildCraftEventPacket(recipeName)
    return {
        type         = "CRAFT_EVENT",
        nodeType     = SequencedCore.NODE_TYPE,
        nodeId       = self.cfg.nodeId,
        recipe       = recipeName,
        totalCrafted = self.totalCrafted,
        timestamp    = safeEpochUtc()
    }
end

function SequencedCore:broadcastTelemetry()
    if not (self:isBaseBusOpen() and rednet and rednet.broadcast) then return false end
    local ok = pcall(rednet.broadcast, self:buildTelemetryPacket(), SequencedCore.BASE_BUS_PROTOCOL)
    return ok == true
end

function SequencedCore:broadcastCraftEvent(recipeName)
    if not (self:isBaseBusOpen() and rednet and rednet.broadcast) then return false end
    local ok = pcall(rednet.broadcast, self:buildCraftEventPacket(recipeName), SequencedCore.BASE_BUS_PROTOCOL)
    return ok == true
end

function SequencedCore:maybeBroadcastHeartbeat(nowClock)
    local now = nowClock or safeClock()
    if (now - (self.lastHeartbeatClock or -999)) >= (self.heartbeatInterval or 10.0) then
        self.lastHeartbeatClock = now
        return self:broadcastTelemetry()
    end
    return false
end

function SequencedCore:handleBaseBusMessage(senderId, msg, protocol)
    if protocol ~= SequencedCore.BASE_BUS_PROTOCOL or type(msg) ~= "table" then
        return false, nil
    end
    if msg.targetNode ~= nil and msg.targetNode ~= self.cfg.nodeId then
        return false, nil
    end
    local cmd = msg.type or msg.cmd
    if type(cmd) ~= "string" then return false, nil end

    local function reply(packet)
        if self:isBaseBusOpen() and rednet and rednet.send and senderId ~= nil then
            pcall(rednet.send, senderId, packet, SequencedCore.BASE_BUS_PROTOCOL)
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
        self.status = self.activeJob and "CRAFTING" or "IDLE"
        self.lastAction = "Uzaktan Devam"
        local pkt = self:buildTelemetryPacket()
        reply(pkt)
        return true, pkt
    elseif cmd == "CMD_LIST_RECIPES" then
        local items = {}
        for _, rec in ipairs(self:getSortedRecipes()) do
            table.insert(items, { name = rec.name, totalCount = rec.totalCount })
        end
        local pkt = {
            type       = "RECIPE_LIST",
            nodeType   = SequencedCore.NODE_TYPE,
            nodeId     = self.cfg.nodeId,
            computerId = safeComputerId(),
            recipes    = items
        }
        reply(pkt)
        return true, pkt
    end
    return false, nil
end

return SequencedCore
