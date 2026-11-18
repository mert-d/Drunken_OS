--[[
    Unit Test: Standalone AE2 (Quantum CPU) <-> Refined Storage (Unlimited Type Archive) Bridge
    Verifies config persistence (/storage_bridge.cfg), direction cycling ([F2]/[F3]),
    protected resource filtering, unified inventory scanning, bidirectional buffer transfers,
    AE2 type defragmentation (defragmentMETypesToRS), Quantum crafting (triggerQuantumCraft),
    and dual terminal + monitor interactive loop.
]]

package.path = "./?.lua;" .. package.path

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

local function assert_true(cond, desc)
    if not cond then
        error("FAILED [" .. desc .. "]: condition was false", 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Standalone AE2 <-> RS Storage Bridge Tests ===")

-- Save originals to avoid polluting shared test runner state
local orig_fs = _G.fs
local orig_textutils = _G.textutils
local orig_peripheral = _G.peripheral
local orig_term = _G.term
local orig_os = _G.os
local orig_colors = _G.colors
local orig_keys = _G.keys
local orig_shell = _G.shell

-- Virtual filesystem & textutils serializer for /storage_bridge.cfg tests
local virtualFiles = {}

_G.fs = {
    exists = function(path)
        return virtualFiles[path] ~= nil
    end,
    open = function(path, mode)
        if mode == "r" then
            local content = virtualFiles[path]
            if not content then return nil end
            return {
                readAll = function() return content end,
                close = function() end
            }
        elseif mode == "w" then
            local buf = ""
            return {
                write = function(s) buf = buf .. tostring(s) end,
                close = function() virtualFiles[path] = buf end
            }
        end
        return nil
    end
}

local function serializeLuaVal(val)
    if type(val) == "string" then
        return string.format("%q", val)
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    elseif type(val) == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local kStr = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
            table.insert(parts, kStr .. " = " .. serializeLuaVal(v))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    end
    return "nil"
end

_G.textutils = {
    serialize = serializeLuaVal,
    unserialize = function(str)
        local fn = load("return " .. tostring(str))
        if fn then return fn() end
        return nil
    end
}

_G.colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32,
    pink = 64, gray = 128, lightGray = 256, cyan = 512, purple = 1024,
    blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768
}

_G.keys = {
    escape = 1, tab = 15, enter = 28, numPadEnter = 156,
    up = 200, down = 208, left = 203, right = 205,
    pageUp = 201, pageDown = 209,
    c = 46, d = 32, a = 30, f = 33, q = 16,
    f2 = 60, f3 = 61, f5 = 63, backspace = 14
}

-- Helper to build simulated ME Bridge + RS Bridge + Buffer Barrel + optional Monitor
local function createMockNetwork(opts)
    opts = opts or {}
    local state = {
        meItems = opts.meItems or {},
        rsItems = opts.rsItems or {},
        barrel = opts.barrel or {},
        craftables = opts.craftables or {},
        craftCalls = {},
        exportLog = {},
        importLog = {},
        craftShouldFail = opts.craftShouldFail or false
    }

    local function toList(store, craftSet)
        local out = {}
        local craftMap = {}
        for _, c in ipairs(craftSet or {}) do
            craftMap[c.name] = true
        end
        for name, count in pairs(store) do
            if count > 0 then
                table.insert(out, {
                    name = name,
                    displayName = (opts.labels and opts.labels[name]) or name,
                    amount = count,
                    isCraftable = craftMap[name] or false
                })
            end
        end
        return out
    end

    local function exportFrom(sourceName, store, expectedDir, filter, dir)
        if dir ~= expectedDir then return 0 end
        local name = filter and filter.name
        local req = filter and filter.count or 0
        local avail = store[name] or 0
        local moved = math.min(avail, req, 64)
        if moved > 0 then
            store[name] = avail - moved
            state.barrel[name] = (state.barrel[name] or 0) + moved
            table.insert(state.exportLog, { side = sourceName, name = name, count = moved, dir = dir })
        end
        return moved
    end

    local function importInto(destName, store, expectedDir, filter, dir)
        if dir ~= expectedDir then return 0 end
        local name = filter and filter.name
        local req = filter and filter.count or 0
        local avail = state.barrel[name] or 0
        local moved = math.min(avail, req, 64)
        if moved > 0 then
            state.barrel[name] = avail - moved
            store[name] = (store[name] or 0) + moved
            table.insert(state.importLog, { side = destName, name = name, count = moved, dir = dir })
        end
        return moved
    end

    local meBridge = {
        listItems = function()
            return toList(state.meItems, state.craftables)
        end,
        listCraftableItems = function()
            local copy = {}
            for _, c in ipairs(state.craftables) do
                table.insert(copy, { name = c.name, displayName = c.displayName })
            end
            return copy
        end,
        craftItem = function(filter)
            table.insert(state.craftCalls, { name = filter.name, count = filter.count })
            if state.craftShouldFail then return false end
            return true
        end
    }

    local rsBridge = {
        listItems = function()
            return toList(state.rsItems, nil)
        end
    }

    if opts.legacyApi then
        meBridge.exportItem = function(filter, dir)
            return exportFrom("me", state.meItems, opts.meDir or "east", filter, dir)
        end
        meBridge.importItem = function(filter, dir)
            return importInto("me", state.meItems, opts.meDir or "east", filter, dir)
        end
        rsBridge.exportItem = function(filter, dir)
            return exportFrom("rs", state.rsItems, opts.rsDir or "west", filter, dir)
        end
        rsBridge.importItem = function(filter, dir)
            return importInto("rs", state.rsItems, opts.rsDir or "west", filter, dir)
        end
    else
        meBridge.exportItemToPeripheral = function(filter, dir)
            return exportFrom("me", state.meItems, opts.meDir or "east", filter, dir)
        end
        meBridge.importItemFromPeripheral = function(filter, dir)
            return importInto("me", state.meItems, opts.meDir or "east", filter, dir)
        end
        rsBridge.exportItemToPeripheral = function(filter, dir)
            return exportFrom("rs", state.rsItems, opts.rsDir or "west", filter, dir)
        end
        rsBridge.importItemFromPeripheral = function(filter, dir)
            return importInto("rs", state.rsItems, opts.rsDir or "west", filter, dir)
        end
    end

    return state, meBridge, rsBridge
end

local function createMockSurface(w, h)
    local written = {}
    local surface
    surface = {
        textScale = nil,
        written = written,
        getSize = function() return w or 51, h or 19 end,
        isColor = function() return true end,
        setTextScale = function(s) surface.textScale = s end,
        setBackgroundColor = function() end,
        setTextColor = function() end,
        clear = function() end,
        clearLine = function() end,
        setCursorPos = function() end,
        write = function(s) table.insert(written, tostring(s)) end
    }
    return surface
end

local function installPeripherals(meBridge, rsBridge, monitor)
    _G.peripheral = {
        find = function(ptype)
            if ptype == "meBridge" then return meBridge end
            if ptype == "rsBridge" then return rsBridge end
            if ptype == "monitor" then return monitor end
            return nil
        end
    }
end

local function installEventLoop(events)
    local idx = 0
    local nextTimerId = 100
    local startedTimers = {}
    _G.os = {
        clock = orig_os and orig_os.clock,
        time = orig_os and orig_os.time,
        startTimer = function(dur)
            nextTimerId = nextTimerId + 1
            table.insert(startedTimers, { id = nextTimerId, dur = dur })
            return nextTimerId
        end,
        pullEvent = function()
            idx = idx + 1
            local ev = events[idx]
            if not ev then return "terminate" end
            return ev[1], ev[2], ev[3], ev[4]
        end
    }
    return startedTimers
end

-- Ensure fresh load
package.loaded["apps.storage_bridge"] = nil
local SB = require("apps.storage_bridge")

-- 1. Config persistence & direction cycling
do
    local cfg = SB.getConfig()
    assert_eq(cfg.meBufferDir, "east", "Default meBufferDir is east")
    assert_eq(cfg.rsBufferDir, "west", "Default rsBufferDir is west")
    assert_eq(cfg.autoCleanME, true, "Default autoCleanME is true")
    assert_eq(cfg.cleanThreshold, 32, "Default cleanThreshold is 32")
    assert_eq(cfg.cleanInterval, 5.0, "Default cleanInterval is 5.0")

    assert_eq(SB.cycleDir("north"), "south", "cycleDir: north -> south")
    assert_eq(SB.cycleDir("east"), "west", "cycleDir: east -> west")
    assert_eq(SB.cycleDir("down"), "north", "cycleDir: down wraps -> north")
    assert_eq(SB.cycleDir("invalid"), "east", "cycleDir: invalid falls back to east")

    cfg.meBufferDir = "north"
    cfg.autoCleanME = false
    assert_eq(SB.saveConfig(), true, "saveConfig writes /storage_bridge.cfg")
    assert_true(virtualFiles["/storage_bridge.cfg"] ~= nil, "/storage_bridge.cfg created in fs")

    cfg.meBufferDir = "down"
    cfg.autoCleanME = true
    SB.loadConfig()
    assert_eq(cfg.meBufferDir, "north", "loadConfig restores saved meBufferDir = north")
    assert_eq(cfg.autoCleanME, false, "loadConfig restores saved autoCleanME = false")

    -- Reset cfg cleanly for remaining tests
    virtualFiles["/storage_bridge.cfg"] = nil
    SB.loadConfig()
    assert_eq(cfg.meBufferDir, "east", "loadConfig resets to default east when config file absent")
    assert_eq(cfg.autoCleanME, true, "loadConfig resets autoCleanME = true")
end

-- 2. Protected resource classification (isProtectedResource)
do
    -- Craftable items are ALWAYS protected regardless of count
    assert_eq(SB.isProtectedResource("minecraft:wooden_hoe", true, 1), true, "Craftable item protected even at count 1")
    -- High-stock items (> cleanThreshold 32) are protected
    assert_eq(SB.isProtectedResource("minecraft:saddle", false, 33), true, "High stock (>32) protected")
    assert_eq(SB.isProtectedResource("minecraft:saddle", false, 32), false, "Threshold boundary (<=32) non-resource is NOT protected")
    -- AE2 / MEGACells / AppFlux namespaces are protected
    assert_eq(SB.isProtectedResource("ae2:calculation_processor_press", false, 1), true, "ae2: namespace protected")
    assert_eq(SB.isProtectedResource("megacells:cell_component_1m", false, 1), true, "megacells: namespace protected")
    assert_eq(SB.isProtectedResource("appflux:flux_accessor", false, 1), true, "appflux: namespace protected")
    -- PROTECTED_KEYWORDS checks
    assert_eq(SB.isProtectedResource("minecraft:iron_ingot", false, 5), true, "Keyword 'ingot' protected")
    assert_eq(SB.isProtectedResource("minecraft:redstone", false, 2), true, "Keyword 'redstone' protected")
    assert_eq(SB.isProtectedResource("minecraft:quartz", false, 4), true, "Keyword 'quartz' protected")
    assert_eq(SB.isProtectedResource("ae2:logic_processor", false, 1), true, "Keyword 'processor' protected")
    assert_eq(SB.isProtectedResource("create:cogwheel", false, 3), true, "Keyword 'cogwheel' protected")
    -- Non-resource rare/single items are NOT protected (candidates for RS archival)
    assert_eq(SB.isProtectedResource("minecraft:enchanted_book", false, 1), false, "Enchanted book (1) is NOT protected")
    assert_eq(SB.isProtectedResource("minecraft:saddle", false, 2), false, "Saddle (2) is NOT protected")
    assert_eq(SB.isProtectedResource("minecraft:bow", false, 1), false, "Bow (1) is NOT protected")
end

-- 3. Unified inventory scanning, search filter, 0-stock craftables & sorting
do
    local _, me, rs = createMockNetwork({
        meItems = {
            ["minecraft:iron_ingot"] = 100,
            ["minecraft:enchanted_book"] = 1
        },
        rsItems = {
            ["minecraft:iron_ingot"] = 250,
            ["minecraft:saddle"] = 4,
            ["minecraft:oak_planks"] = 1200
        },
        craftables = {
            { name = "minecraft:iron_ingot", displayName = "Iron Ingot" },
            { name = "minecraft:hopper", displayName = "Hopper" } -- 0 stock pattern
        },
        labels = {
            ["minecraft:iron_ingot"] = "Iron Ingot",
            ["minecraft:enchanted_book"] = "Enchanted Book",
            ["minecraft:saddle"] = "Saddle",
            ["minecraft:oak_planks"] = "Oak Planks"
        }
    })
    installPeripherals(me, rs, nil)

    local list = SB.scanInventories("")
    assert_eq(#list, 5, "Unified list merges ME, RS, and 0-stock craftables (5 items)")
    assert_eq(list[1].name, "minecraft:iron_ingot", "Craftable item sorted 1st")
    assert_eq(list[1].meCount, 100, "Iron Ingot ME count = 100")
    assert_eq(list[1].rsCount, 250, "Iron Ingot RS count = 250")
    assert_eq(list[1].total, 350, "Iron Ingot total = 350")
    assert_eq(list[1].isCraftable, true, "Iron Ingot marked craftable")
    assert_eq(list[1].isProtected, true, "Iron Ingot marked protected")

    assert_eq(list[2].name, "minecraft:hopper", "0-stock craftable Hopper sorted 2nd")
    assert_eq(list[2].isCraftable, true, "Hopper marked craftable")
    assert_eq(list[2].isProtected, true, "Hopper marked protected")

    assert_eq(list[3].name, "minecraft:oak_planks", "Oak Planks (1200) sorted 3rd")
    assert_eq(list[4].name, "minecraft:saddle", "Saddle (4) sorted 4th")
    assert_eq(list[5].name, "minecraft:enchanted_book", "Enchanted Book (1) sorted 5th")
    assert_eq(list[5].isProtected, false, "Enchanted Book marked unprotected for archival")

    local filtered = SB.scanInventories("saddle")
    assert_eq(#filtered, 1, "Search 'saddle' narrows list to 1 item")
    assert_eq(filtered[1].name, "minecraft:saddle", "Filtered item matches Saddle")
end

-- 4. Bidirectional transferItem, legacy AP fallback & direction mismatch warning
do
    -- Missing bridges
    installPeripherals(nil, nil, nil)
    SB.scanInventories("")
    assert_eq(SB.transferItem("minecraft:iron_ingot", 64, "RS_TO_ME"), 0, "transferItem returns 0 when bridges absent")
    assert_true(SB.getStatus():find("bagli degil") ~= nil, "Missing bridges sets Turkish error status")

    -- Modern AP API
    local st, me, rs = createMockNetwork({
        meItems = { ["minecraft:redstone"] = 200 },
        rsItems = { ["minecraft:gold_ingot"] = 180 }
    })
    installPeripherals(me, rs, nil)
    SB.scanInventories("")

    local movedRS = SB.transferItem("minecraft:redstone", 150, "ME_TO_RS")
    assert_eq(movedRS, 150, "ME_TO_RS moved 150 redstone across 3 batches (64+64+22)")
    assert_eq(st.meItems["minecraft:redstone"], 50, "ME redstone = 50")
    assert_eq(st.rsItems["minecraft:redstone"], 150, "RS redstone = 150")
    assert_eq(st.barrel["minecraft:redstone"] or 0, 0, "Buffer barrel emptied")

    local movedME = SB.transferItem("minecraft:gold_ingot", 150, "RS_TO_ME")
    assert_eq(movedME, 150, "RS_TO_ME moved 150 gold_ingot across 3 batches")
    assert_eq(st.rsItems["minecraft:gold_ingot"], 30, "RS gold_ingot = 30")
    assert_eq(st.meItems["minecraft:gold_ingot"], 150, "ME gold_ingot = 150")

    -- Direction mismatch warning when no direction or barrel accepts export
    local stBad, meBad, rsBad = createMockNetwork({
        meDir = "none",
        rsDir = "none",
        meItems = { ["minecraft:redstone"] = 10 }
    })
    installPeripherals(meBad, rsBad, nil)
    SB.scanInventories("")
    local movedZero = SB.transferItem("minecraft:redstone", 10, "ME_TO_RS")
    assert_eq(movedZero, 0, "Unreachable barrel returns 0 items")
    assert_true(SB.getStatus():find("F2") ~= nil, "0-item transfer warns user to check [F2] Barrel directions")
    assert_eq(stBad.meItems["minecraft:redstone"], 10, "Items remain untouched in ME when no barrel is reachable")

    -- Restore modern network for legacy test cleanup
    installPeripherals(me, rs, nil)
    SB.getConfig().meBufferDir = "east"
    SB.getConfig().rsBufferDir = "west"

    -- Legacy AP API (exportItem / importItem)
    local stLeg, meLeg, rsLeg = createMockNetwork({
        legacyApi = true,
        meDir = "south",
        rsDir = "north",
        meItems = { ["minecraft:coal"] = 20 },
        rsItems = { ["minecraft:diamond"] = 90 }
    })
    installPeripherals(meLeg, rsLeg, nil)
    SB.getConfig().meBufferDir = "south"
    SB.getConfig().rsBufferDir = "north"
    SB.scanInventories("")

    local legMoved = SB.transferItem("minecraft:diamond", 70, "RS_TO_ME")
    assert_eq(legMoved, 70, "Legacy exportItem/importItem moved 70 diamonds")
    assert_eq(stLeg.meItems["minecraft:diamond"], 70, "ME received 70 diamonds via legacy API")
    assert_eq(stLeg.rsItems["minecraft:diamond"], 20, "RS has 20 diamonds left")

    SB.getConfig().meBufferDir = "east"
    SB.getConfig().rsBufferDir = "west"
end

-- 5. AE2 Type Defragmentation (defragmentMETypesToRS)
do
    local st, me, rs = createMockNetwork({
        meItems = {
            ["minecraft:enchanted_book"] = 1,   -- unprotected -> archive to RS
            ["minecraft:saddle"] = 3,           -- unprotected -> archive to RS
            ["minecraft:bow"] = 1,              -- unprotected -> archive to RS
            ["minecraft:iron_ingot"] = 12,      -- protected keyword -> stay in ME
            ["minecraft:wooden_hoe"] = 1,       -- craftable -> stay in ME
            ["minecraft:music_disc_cat"] = 40   -- > cleanThreshold (32) -> stay in ME
        },
        craftables = {
            { name = "minecraft:wooden_hoe", displayName = "Wooden Hoe" }
        }
    })
    installPeripherals(me, rs, nil)
    SB.scanInventories("")

    local typesFreed, itemsMoved = SB.defragmentMETypesToRS()
    assert_eq(typesFreed, 3, "Defragmentation freed exactly 3 unprotected ME item types")
    assert_eq(itemsMoved, 5, "Defragmentation moved 5 items total (1+3+1)")
    assert_eq(st.meItems["minecraft:enchanted_book"], 0, "Enchanted book removed from ME")
    assert_eq(st.rsItems["minecraft:enchanted_book"], 1, "Enchanted book archived in RS")
    assert_eq(st.meItems["minecraft:saddle"], 0, "Saddles removed from ME")
    assert_eq(st.rsItems["minecraft:saddle"], 3, "Saddles archived in RS")
    assert_eq(st.meItems["minecraft:bow"], 0, "Bow removed from ME")
    assert_eq(st.rsItems["minecraft:bow"], 1, "Bow archived in RS")
    assert_eq(st.meItems["minecraft:iron_ingot"], 12, "Protected iron_ingot stayed in ME")
    assert_eq(st.meItems["minecraft:wooden_hoe"], 1, "Craftable wooden_hoe stayed in ME")
    assert_eq(st.meItems["minecraft:music_disc_cat"], 40, "High-stock (>32) item stayed in ME")
    assert_true(SB.getStatus():find("ME TEMIZLENDI") ~= nil, "Status reports ME TEMIZLENDI")
end

-- 6. Quantum CPU Craft Trigger (triggerQuantumCraft)
do
    local st, me, rs = createMockNetwork({
        meItems = {},
        rsItems = { ["minecraft:chest"] = 80 },
        craftables = {
            { name = "minecraft:chest", displayName = "Chest" }
        }
    })
    installPeripherals(me, rs, nil)
    SB.scanInventories("")

    local entry = SB.getUnifiedList()[1]
    assert_eq(entry.name, "minecraft:chest", "Selected craftable entry is chest")
    local okCraft = SB.triggerQuantumCraft(entry, 10)
    assert_eq(okCraft, true, "triggerQuantumCraft succeeded")
    assert_eq(st.meItems["minecraft:chest"], 64, "Pulled up to 64 items from RS to ME when meCount == 0")
    assert_eq(st.rsItems["minecraft:chest"], 16, "RS chest reduced from 80 to 16")
    assert_eq(#st.craftCalls, 1, "me.craftItem invoked once")
    assert_eq(st.craftCalls[1].name, "minecraft:chest", "craftItem item matches chest")
    assert_eq(st.craftCalls[1].count, 10, "craftItem count matches 10")
    assert_true(SB.getStatus():find("QUANTUM CRAFT BASLADI") ~= nil, "Status confirms Quantum Craft started")

    -- Craft error path
    st.craftShouldFail = true
    local failCraft = SB.triggerQuantumCraft(entry, 5)
    assert_eq(failCraft, false, "triggerQuantumCraft returns false when CPU busy/missing materials")
    assert_true(SB.getStatus():find("CRAFT HATA") ~= nil, "Status reports CRAFT HATA")
end

-- 7. Full interactive main() loop with term + monitor, hotkeys, timer & search 'q'
do
    local st, me, rs = createMockNetwork({
        meItems = {
            ["minecraft:iron_ingot"] = 100,
            ["minecraft:enchanted_book"] = 2,
            ["minecraft:quartz"] = 10
        },
        rsItems = {
            ["minecraft:iron_ingot"] = 100
        },
        craftables = {
            { name = "minecraft:iron_ingot", displayName = "Iron Ingot" }
        },
        labels = {
            ["minecraft:iron_ingot"] = "Iron Ingot",
            ["minecraft:enchanted_book"] = "Enchanted Book",
            ["minecraft:quartz"] = "Nether Quartz"
        }
    })
    local mockMon = createMockSurface(79, 24)
    local mockTerm = createMockSurface(51, 19)
    _G.term = mockTerm
    installPeripherals(me, rs, mockMon)

    -- Reset config cleanly
    virtualFiles["/storage_bridge.cfg"] = nil
    SB.loadConfig()

    -- First timer ID inside main() will be 101
    local startedTimers = installEventLoop({
        { "key", _G.keys.right },       -- ME -> RS 64 iron_ingot (1st item, craftable): ME=36, RS=164
        { "key", _G.keys.left },        -- RS -> ME 64 iron_ingot: ME=100, RS=100
        { "key", _G.keys.c },           -- triggerQuantumCraft on iron_ingot (10x)
        { "key", _G.keys.d },           -- manual defragment: moves enchanted_book (2) to RS
        { "timer", 101 },               -- timer fires when autoCleanME = true -> re-arms timer 102
        { "key", _G.keys.a },           -- toggle autoCleanME OFF & saveConfig
        { "timer", 102 },               -- timer fires when autoCleanME = false -> skips defrag, re-arms 103
        { "key", _G.keys.f2 },          -- cycle meBufferDir: east -> west
        { "key", _G.keys.f3 },          -- cycle rsBufferDir: west -> up
        { "key", _G.keys.f5 },          -- manual refresh
        { "char", "q" },                -- typing 'q' for quartz must filter, NOT exit!
        { "key", _G.keys.backspace },   -- clear search
        { "key", _G.keys.down },        -- move selection down
        { "key", _G.keys.up },          -- move selection back up
        { "terminate" }                 -- terminate cleanly
    })

    local okMain = SB.main()
    assert_eq(okMain, true, "main() ran all scripted events and exited cleanly on terminate")
    assert_eq(mockMon.textScale, 0.5, "Attached monitor configured with setTextScale(0.5)")
    assert_true(#mockTerm.written > 0, "Terminal rendered dashboard UI")
    assert_true(#mockMon.written > 0, "Monitor rendered mirrored dashboard UI")
    assert_eq(#startedTimers, 3, "cleanTimer started initially and renewed twice")
    assert_eq(startedTimers[1].dur, 5.0, "cleanTimer uses cleanInterval = 5.0")

    assert_eq(st.meItems["minecraft:enchanted_book"], 0, "[D] defragment moved enchanted_book out of ME")
    assert_eq(st.rsItems["minecraft:enchanted_book"], 2, "[D] enchanted_book archived in RS")
    assert_eq(st.meItems["minecraft:quartz"], 10, "Protected quartz stayed in ME")
    assert_eq(#st.craftCalls, 1, "[C] triggered Quantum Craft once")
    assert_eq(st.craftCalls[1].count, 10, "[C] Quantum Craft requested 10x")

    local cfg = SB.getConfig()
    assert_eq(cfg.autoCleanME, false, "[A] toggled autoCleanME to false")
    assert_eq(cfg.meBufferDir, "west", "[F2] cycled meBufferDir east -> west")
    assert_eq(cfg.rsBufferDir, "up", "[F3] cycled rsBufferDir west -> up")
    assert_true(virtualFiles["/storage_bridge.cfg"] ~= nil, "[A]/[F2]/[F3] persisted config to /storage_bridge.cfg")

    -- Verify 'q' filtered to quartz (before backspace restored all 3)
    local sawQuartzOnly = false
    for _, line in ipairs(mockTerm.written) do
        if line:find("Ara:%[q%]") then
            sawQuartzOnly = true
            break
        end
    end
    assert_true(sawQuartzOnly, "Typing 'q' filtered search for 'quartz' without quitting")
end

-- 8. AP 1.20/1.21 snake_case peripheral discovery ("me_bridge"/"rs_bridge"),
--    Unified Storage API (getItems/getCraftableItems & table { count = N }),
--    Auto-direction probing & hardware diagnostic error reporting
do
    local meStock = { ["minecraft:iron_ingot"] = 96 }
    local rsStock = { ["minecraft:iron_ingot"] = 10 }
    local barrelInv = {}

    local modernME = {
        getItems = function(filter)
            return {
                { name = "minecraft:iron_ingot", displayName = "Iron Ingot", count = meStock["minecraft:iron_ingot"] }
            }
        end,
        getCraftableItems = function()
            return {
                { name = "minecraft:iron_ingot", displayName = "Iron Ingot" }
            }
        end,
        exportItem = function(filter, target)
            if target ~= "north" then return nil, "No inventory on side" end
            local moved = math.min(meStock[filter.name] or 0, filter.count or 0, 64)
            if moved > 0 then
                meStock[filter.name] = meStock[filter.name] - moved
                barrelInv[filter.name] = (barrelInv[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end,
        importItem = function(filter, target)
            if target ~= "north" then return { count = 0 } end
            local moved = math.min(barrelInv[filter.name] or 0, filter.count or 0, 64)
            if moved > 0 then
                barrelInv[filter.name] = barrelInv[filter.name] - moved
                meStock[filter.name] = (meStock[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end
    }

    local modernRS = {
        getItems = function()
            return {
                { name = "minecraft:iron_ingot", displayName = "Iron Ingot", count = rsStock["minecraft:iron_ingot"] }
            }
        end,
        importItem = function(filter, target)
            if target ~= "south" then return nil, "No inventory on side" end
            local moved = math.min(barrelInv[filter.name] or 0, filter.count or 0, 64)
            if moved > 0 then
                barrelInv[filter.name] = barrelInv[filter.name] - moved
                rsStock[filter.name] = (rsStock[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end,
        exportItem = function(filter, target)
            if target ~= "south" then return { count = 0 } end
            local moved = math.min(rsStock[filter.name] or 0, filter.count or 0, 64)
            if moved > 0 then
                rsStock[filter.name] = rsStock[filter.name] - moved
                barrelInv[filter.name] = (barrelInv[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end
    }

    -- Simulate snake_case wired modem peripheral names ("me_bridge_0", "rs_bridge_0")
    -- where peripheral.find only knows getNames/getType/wrap
    _G.peripheral = {
        getNames = function() return { "me_bridge_0", "rs_bridge_0", "drive_0" } end,
        getType = function(name)
            if name == "me_bridge_0" then return "me_bridge" end
            if name == "rs_bridge_0" then return "rs_bridge" end
            if name == "drive_0" then return "drive" end
            return nil
        end,
        wrap = function(name)
            if name == "me_bridge_0" then return modernME end
            if name == "rs_bridge_0" then return modernRS end
            return nil
        end
    }

    virtualFiles["/storage_bridge.cfg"] = nil
    SB.loadConfig() -- resets to east / west

    local list = SB.scanInventories("")
    assert_eq(#list, 1, "Snake-case me_bridge/rs_bridge + getItems() discovered 1 merged item")
    assert_eq(list[1].meCount, 96, "getItems() read ME count = 96")
    assert_eq(list[1].rsCount, 10, "getItems() read RS count = 10")
    assert_eq(list[1].isCraftable, true, "getCraftableItems() detected craftable pattern")

    -- Default config is east/west, but barrel is actually north (ME) / south (RS)
    local moved = SB.transferItem("minecraft:iron_ingot", 64, "ME_TO_RS")
    assert_eq(moved, 64, "Auto-probe found non-default north/south barrel and moved 64 items with { count = 64 }")
    assert_eq(meStock["minecraft:iron_ingot"], 32, "ME iron decremented to 32")
    assert_eq(rsStock["minecraft:iron_ingot"], 74, "RS iron incremented to 74")
    assert_eq(barrelInv["minecraft:iron_ingot"] or 0, 0, "Barrel emptied after auto-probed transfer")
    assert_eq(SB.getConfig().meBufferDir, "north", "Auto-probe updated meBufferDir = north")
    assert_eq(SB.getConfig().rsBufferDir, "south", "Auto-probe updated rsBufferDir = south")
    assert_true(virtualFiles["/storage_bridge.cfg"] ~= nil, "Auto-probe saved working directions to /storage_bridge.cfg")

    -- Diagnostic status when only drive_0 is visible (missing bridges)
    _G.peripheral = {
        getNames = function() return { "drive_0" } end,
        getType = function() return "drive" end,
        wrap = function() return {} end
    }
    SB.scanInventories("")
    assert_true(SB.getStatus():find("drive_0") ~= nil, "Missing bridges diagnostic lists attached peripherals")

    -- Diagnostic status when bridge returns network/power error
    local offlineME = {
        getItems = function() return nil, "ME network offline or missing channel" end
    }
    _G.peripheral = {
        getNames = function() return { "me_bridge_0", "rs_bridge_0" } end,
        getType = function(n) return n:match("me") and "me_bridge" or "rs_bridge" end,
        wrap = function(n) return n:match("me") and offlineME or modernRS end
    }
    SB.scanInventories("")
    assert_true(SB.getStatus():find("AG HATASI") ~= nil, "Bridge API error surfaces AG HATASI diagnostic")
    assert_true(SB.getStatus():find("offline") ~= nil, "Bridge API error includes underlying reason")
end

-- 9. 1.21 Bracket Stripping, 0ms In-Memory Filtering, [Tab] Views, [F] Search Focus (a/c/d),
--    [Enter] Custom Quantity Prompt & Mouse Scroll/Click
do
    local getItemsCalls = 0
    local meStock = {
        ["mekanism:dust_cadmium"] = 500,
        ["minecraft:glowstone_dust"] = 43078,
        ["minecraft:enchanted_book"] = 2
    }
    local rsStock = {
        ["minecraft:diamond"] = 300
    }
    local barrelInv = {}
    local craftCalls = {}

    local fastME = {
        getItems = function()
            getItemsCalls = getItemsCalls + 1
            return {
                { name = "mekanism:dust_cadmium", displayName = "[Cadmium Dust]", count = meStock["mekanism:dust_cadmium"] },
                { name = "minecraft:glowstone_dust", displayName = "[Glowstone Dust]", count = meStock["minecraft:glowstone_dust"] },
                { name = "minecraft:enchanted_book", displayName = "[Enchanted Book]", count = meStock["minecraft:enchanted_book"] }
            }
        end,
        getCraftableItems = function()
            return {
                { name = "minecraft:glowstone_dust", displayName = "[Glowstone Dust]" }
            }
        end,
        craftItem = function(filter)
            table.insert(craftCalls, filter)
            return true
        end,
        exportItem = function(filter, target)
            if target ~= "east" then return { count = 0 } end
            local moved = math.min(meStock[filter.name] or 0, filter.count or 0, 512)
            if moved > 0 then
                meStock[filter.name] = meStock[filter.name] - moved
                barrelInv[filter.name] = (barrelInv[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end,
        importItem = function(filter, target)
            if target ~= "east" then return { count = 0 } end
            local moved = math.min(barrelInv[filter.name] or 0, filter.count or 0, 512)
            if moved > 0 then
                barrelInv[filter.name] = barrelInv[filter.name] - moved
                meStock[filter.name] = (meStock[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end
    }

    local fastRS = {
        getItems = function()
            return {
                { name = "minecraft:diamond", displayName = "[Diamond]", count = rsStock["minecraft:diamond"] }
            }
        end,
        importItem = function(filter, target)
            if target ~= "west" then return { count = 0 } end
            local moved = math.min(barrelInv[filter.name] or 0, filter.count or 0, 512)
            if moved > 0 then
                barrelInv[filter.name] = barrelInv[filter.name] - moved
                rsStock[filter.name] = (rsStock[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end,
        exportItem = function(filter, target)
            if target ~= "west" then return { count = 0 } end
            local moved = math.min(rsStock[filter.name] or 0, filter.count or 0, 512)
            if moved > 0 then
                rsStock[filter.name] = rsStock[filter.name] - moved
                barrelInv[filter.name] = (barrelInv[filter.name] or 0) + moved
                return { count = moved }
            end
            return { count = 0 }
        end
    }

    _G.peripheral = {
        find = function(ptype)
            if ptype == "me_bridge" then return fastME end
            if ptype == "rs_bridge" then return fastRS end
            return nil
        end
    }
    virtualFiles["/storage_bridge.cfg"] = nil
    SB.loadConfig()

    local list = SB.scanInventories("")
    assert_eq(getItemsCalls, 1, "Initial scan called me.getItems() once")
    assert_eq(#list, 4, "4 items scanned")
    assert_eq(list[1].displayName, "Glowstone Dust", "Outer [ ] brackets stripped from 1.21 displayName")

    -- 0ms in-memory filtering & view modes without calling getItems() again
    local craftView = SB.applyFilter("", "CRAFT")
    assert_eq(#craftView, 1, "CRAFT view shows only 1 craftable item")
    local rsView = SB.applyFilter("", "RS")
    assert_eq(#rsView, 1, "RS view shows only Diamond")
    assert_eq(rsView[1].displayName, "Diamond", "Diamond brackets stripped")
    local arsivView = SB.applyFilter("", "ARSIV")
    assert_eq(#arsivView, 1, "ARSIV view shows only Enchanted Book")
    assert_eq(getItemsCalls, 1, "In-memory applyFilter triggered ZERO peripheral calls")

    -- Interactive UI test: [F] search focus + typing "cad" (contains c, a, d!) -> [Enter] -> [Enter] qty "128" -> [Right] -> [Tab] -> mouse_scroll
    local mockTerm9 = createMockSurface(51, 19)
    _G.term = mockTerm9
    installEventLoop({
        { "key", _G.keys.f },           -- focus search
        { "char", "f" },                -- trailing char from [F] MUST be skipped!
        { "char", "c" },                -- typing 'c' in search mode must NOT craft!
        { "char", "a" },                -- typing 'a' in search mode must NOT toggle autoClean!
        { "char", "d" },                -- typing 'd' in search mode must NOT defragment!
        { "key", _G.keys.enter },       -- exit search mode cleanly while keeping "cad" filter
        { "key", _G.keys.enter },       -- open custom quantity prompt on Cadmium Dust
        { "char", "1" },
        { "char", "2" },
        { "char", "8" },
        { "key", _G.keys.right },       -- transfer 128 Cadmium Dust ME -> RS in single batch!
        { "key", _G.keys.tab },         -- cycle view mode TUMU -> STOK
        { "mouse_scroll", 1 },          -- scroll down
        { "mouse_click", 1, 46, 1 },    -- click top-right [Tab:STOK] badge -> ME
        { "terminate" }
    })

    local ok9 = SB.main()
    assert_eq(ok9, true, "Interactive UX test exited cleanly")
    assert_eq(#craftCalls, 0, "Typing 'c' inside [F] search mode did NOT accidentally fire craftItem")
    assert_eq(SB.getConfig().autoCleanME, true, "Typing 'a' inside [F] search mode did NOT toggle autoCleanME")
    assert_eq(meStock["minecraft:enchanted_book"], 2, "Typing 'd' inside [F] search mode did NOT trigger defragment")
    assert_eq(meStock["mekanism:dust_cadmium"], 372, "[Enter] -> 128 -> [Right] moved 128 Cadmium Dust out of ME (500 -> 372)")
    assert_eq(rsStock["mekanism:dust_cadmium"], 128, "[Enter] -> 128 -> [Right] delivered 128 Cadmium Dust into RS")

    -- Verify 'cad' (without leading 'f') was the search query shown
    local sawCadQuery = false
    for _, line in ipairs(mockTerm9.written) do
        if line:find("Ara:%[cad%]") then
            sawCadQuery = true
            break
        end
    end
    assert_true(sawCadQuery, "Pressing [F] then 'cad' produced exact search 'cad' without 'f'")
end

-- Restore globals cleanly
_G.fs = orig_fs
_G.textutils = orig_textutils
_G.peripheral = orig_peripheral
_G.term = orig_term
_G.os = orig_os
_G.colors = orig_colors
_G.keys = orig_keys
_G.shell = orig_shell

print(">>> All Standalone AE2 <-> RS Storage Bridge tests passed successfully!\n")
return true
