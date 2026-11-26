--[[
    Unit Test: Drunken Crafter v2 — Beltless Multi-Depot Sequenced Assembly & Unified Mode Router
    Verifies:
      1. test_legacy_config_defaults_to_mechanical (zero breaking change on existing Mechanical config + wizard test)
      2. test_precision_mechanism_full_5_loops (5 loops x 3 deploying steps, NBT tracking, AE2 return, CRAFT_EVENT)
      3. test_probabilistic_scrap_routing (scrap routed to trashName barrel when present, fallback to AE2)
      4. test_spout_and_press_sequence (Sturdy Sheet: Lava Spout depot -> Press depot x2 using real default DB)
      5. test_timeout_calibration_tui_and_base_bus (stepTimeout guard, depot calibration, Base Bus, Sequenced TUI)
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

print("=== Running Drunken Crafter v2 Sequenced Assembly Tests ===")

local orig_fs = _G.fs
local orig_textutils = _G.textutils
local orig_peripheral = _G.peripheral
local orig_redstone = _G.redstone
local orig_rednet = _G.rednet
local orig_os = _G.os
local orig_sleep = _G.sleep
local orig_term = _G.term
local orig_window = _G.window
local orig_colors = _G.colors
local orig_keys = _G.keys
local orig_loaded_seq = package.loaded["lib.sequenced_core"]
local orig_loaded_mech = package.loaded["lib.crafter_core"]

local function restoreGlobals()
    _G.fs = orig_fs
    _G.textutils = orig_textutils
    _G.peripheral = orig_peripheral
    _G.redstone = orig_redstone
    _G.rednet = orig_rednet
    _G.os = orig_os
    _G.sleep = orig_sleep
    _G.term = orig_term
    _G.window = orig_window
    _G.colors = orig_colors
    _G.keys = orig_keys
    package.loaded["lib.sequenced_core"] = orig_loaded_seq
    package.loaded["lib.crafter_core"] = orig_loaded_mech
end

local function serializeLuaVal(val, indent)
    indent = indent or ""
    if type(val) == "string" then
        return string.format("%q", val)
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    elseif type(val) == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local kStr = (type(k) == "number") and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
            table.insert(parts, indent .. "  " .. kStr .. " = " .. serializeLuaVal(v, indent .. "  "))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

local function createSeqEnv(opts)
    opts = opts or {}
    local state = {
        files = {},
        dirs = { ["/"] = true },
        periphs = {},
        types = {},
        itemTags = opts.itemTags or {},
        rednetOpen = {},
        rednetBroadcasts = {},
        rednetSends = {},
        epochMs = 1700000000000,
        clockSec = 100.0,
        computerId = opts.computerId or 88
    }

    _G.fs = {
        exists = function(path)
            return state.files[path] ~= nil or state.dirs[path] == true
        end,
        getDir = function(path)
            return path:match("^(.*)/[^/]+$") or ""
        end,
        makeDir = function(dir)
            state.dirs[dir] = true
            return true
        end,
        copy = function(src, dst)
            assert(state.files[src] ~= nil, "copy missing src: " .. tostring(src))
            state.files[dst] = state.files[src]
        end,
        open = function(path, mode)
            if mode == "r" then
                local content = state.files[path]
                if not content then return nil end
                return { readAll = function() return content end, close = function() end }
            elseif mode == "w" then
                local buf = ""
                return {
                    write = function(s) buf = buf .. tostring(s) end,
                    close = function() state.files[path] = buf end
                }
            end
            return nil
        end
    }

    _G.textutils = {
        serialize = function(v) return serializeLuaVal(v) end,
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
    _G.window = nil

    _G.keys = {
        escape = 1, one = 2, two = 3, tab = 15, enter = 28, numPadEnter = 156, backspace = 14, delete = 211,
        up = 200, down = 208, left = 203, right = 205, pageUp = 201, pageDown = 209,
        c = 46, d = 32, i = 23, l = 38, m = 50, p = 25, q = 16, r = 19, s = 31, t = 20, x = 45
    }

    _G.sleep = function(sec)
        state.clockSec = state.clockSec + (tonumber(sec) or 0)
    end

    _G.redstone = { setOutput = function() end, getOutput = function() return false end }

    _G.rednet = {
        open = function(name) state.rednetOpen[name] = true end,
        isOpen = function(name)
            if name then return state.rednetOpen[name] == true end
            for _, v in pairs(state.rednetOpen) do if v then return true end end
            return false
        end,
        broadcast = function(msg, proto)
            table.insert(state.rednetBroadcasts, { msg = msg, protocol = proto })
        end,
        send = function(targetId, msg, proto)
            table.insert(state.rednetSends, { targetId = targetId, msg = msg, protocol = proto })
        end
    }

    _G.os = {
        getComputerID = function() return state.computerId end,
        epoch = function() return state.epochMs end,
        time = function() return state.epochMs / 1000 end,
        clock = function() return state.clockSec end,
        startTimer = function() return 1 end,
        pullEvent = function() return "terminate" end
    }

    local function makeInventory(name, ptype, initialSlots, optsInv)
        optsInv = optsInv or {}
        local slots = {}
        for k, v in pairs(initialSlots or {}) do
            slots[k] = { name = v.name, count = v.count, nbt = v.nbt }
        end
        local maxSlots = optsInv.maxSlots or 27

        local inv = { _slots = slots }
        function inv.size() return maxSlots end
        function inv.list()
            local out = {}
            for s, item in pairs(inv._slots) do
                if item and item.count > 0 then
                    out[s] = { name = item.name, count = item.count, nbt = item.nbt }
                end
            end
            return out
        end
        function inv.getItemDetail(slot)
            local item = inv._slots[slot]
            if item and item.count > 0 then
                return {
                    name = item.name,
                    count = item.count,
                    nbt = item.nbt,
                    maxCount = 64,
                    tags = state.itemTags[item.name]
                }
            end
            return nil
        end
        function inv.pushItems(targetName, fromSlot, limit, toSlot)
            local tgt = state.periphs[targetName]
            if not tgt or not tgt._slots then return 0 end
            local src = inv._slots[fromSlot]
            if not src or src.count <= 0 then return 0 end
            local toMove = math.min(src.count, limit or src.count)
            if toSlot then
                local ex = tgt._slots[toSlot]
                if ex and (ex.name ~= src.name or ex.nbt ~= src.nbt) then return 0 end
                if ex then
                    ex.count = ex.count + toMove
                else
                    tgt._slots[toSlot] = { name = src.name, count = toMove, nbt = src.nbt }
                end
            else
                local placed = false
                for i = 1, (tgt.size and tgt.size() or 27) do
                    local ex = tgt._slots[i]
                    if ex and ex.name == src.name and ex.nbt == src.nbt and ex.count < 64 then
                        local add = math.min(toMove, 64 - ex.count)
                        ex.count = ex.count + add
                        toMove = add
                        placed = true
                        break
                    end
                end
                if not placed then
                    for i = 1, (tgt.size and tgt.size() or 27) do
                        if not tgt._slots[i] then
                            tgt._slots[i] = { name = src.name, count = toMove, nbt = src.nbt }
                            placed = true
                            break
                        end
                    end
                end
                if not placed then return 0 end
            end
            src.count = src.count - toMove
            if src.count <= 0 then inv._slots[fromSlot] = nil end
            return toMove
        end
        function inv.pullItems(sourceName, fromSlot, limit, toSlot)
            local src = state.periphs[sourceName]
            if not src or not src.pushItems then return 0 end
            return src.pushItems(name, fromSlot, limit, toSlot)
        end

        state.periphs[name] = inv
        state.types[name] = ptype
        return inv
    end

    state.makeInventory = makeInventory

    _G.peripheral = {
        getNames = function()
            local out = {}
            for k in pairs(state.periphs) do table.insert(out, k) end
            table.sort(out)
            return out
        end,
        isPresent = function(name) return state.periphs[name] ~= nil end,
        getType = function(name)
            local t = state.types[name]
            if type(t) == "table" then return table.unpack(t) end
            return t
        end,
        hasType = function(name, t)
            local st = state.types[name]
            if type(st) == "table" then
                for _, v in ipairs(st) do if v == t then return true end end
                return false
            end
            return st == t
        end,
        wrap = function(name) return state.periphs[name] end,
        call = function(name, method, ...)
            local p = state.periphs[name]
            if not p then error("No peripheral: " .. tostring(name), 2) end
            return p[method](...)
        end
    }

    makeInventory("sophisticatedstorage:barrel_0", { "sophisticatedstorage:barrel", "inventory" }, {})
    makeInventory("sophisticatedstorage:barrel_trash", { "sophisticatedstorage:barrel", "inventory" }, {})
    makeInventory("extendedae:ex_pattern_provider_0", { "extendedae:ex_pattern_provider", "inventory" }, {})
    makeInventory("create:deployer_0", { "create:deployer", "inventory" }, {}, { maxSlots = 1 })
    makeInventory("create:depot_0", { "create:depot", "inventory" }, {}, { maxSlots = 1 })
    makeInventory("create:depot_1", { "create:depot", "inventory" }, {}, { maxSlots = 1 })
    makeInventory("create:depot_2", { "create:depot", "inventory" }, {}, { maxSlots = 1 })
    makeInventory("create:depot_3", { "create:depot", "inventory" }, {}, { maxSlots = 1 })

    state.periphs["top"] = { isWireless = function() return true end }
    state.types["top"] = "modem"

    return state
end

local okAll, errAll = pcall(function()
    -- 1. test_legacy_config_defaults_to_mechanical + First-Run Mode Wizard
    do
        print("[1] test_legacy_config_defaults_to_mechanical")
        local env = createSeqEnv()
        -- Legacy config WITHOUT `mode` field
        env.files["/etc/drunken_crafter.cfg"] = [[{
            nodeId = "CRAFTER-01",
            inputName = "sophisticatedstorage:barrel_0",
            outputName = "sophisticatedstorage:barrel_trash",
            ae2Name = "extendedae:ex_pattern_provider_0",
            gridMap = {}
        }]]

        package.loaded["lib.crafter_core"] = nil
        package.loaded["lib.sequenced_core"] = nil
        local clientChunk = assert(loadfile("clients/Drunken_Crafter.lua"))
        local clientMod = clientChunk("Drunken_Crafter")

        local fakeTerm = {
            getSize = function() return 51, 19 end,
            isColor = function() return true end,
            setTextColor = function() end,
            setBackgroundColor = function() end,
            setCursorPos = function() end,
            clear = function() end,
            write = function() end
        }
        _G.term = { current = function() return fakeTerm end }

        local resolved = clientMod.resolveInitialMode({}, fakeTerm, "/etc/drunken_crafter.cfg")
        assert_eq(resolved, "MECHANICAL", "Legacy config without `mode` defaults silently to MECHANICAL")

        -- Now test fresh system (no config file): wizard selects [2] Sequenced
        env.files["/etc/drunken_crafter.cfg"] = nil
        local wizEvents = { { "key", _G.keys.two } }
        local wizIdx = 0
        _G.os.pullEvent = function()
            wizIdx = wizIdx + 1
            local e = wizEvents[wizIdx]
            if not e then return "terminate" end
            return e[1], e[2]
        end
        local wizMode = clientMod.resolveInitialMode({}, fakeTerm, "/etc/drunken_crafter.cfg")
        assert_eq(wizMode, "SEQUENCED", "First-run wizard [2] selects SEQUENCED mode")
        local savedCfg = _G.textutils.unserialize(env.files["/etc/drunken_crafter.cfg"])
        assert_eq(savedCfg.mode, "SEQUENCED", "First-run wizard persisted mode = SEQUENCED")
    end

    -- 2. test_precision_mechanism_full_5_loops
    do
        print("[2] test_precision_mechanism_full_5_loops")
        local env = createSeqEnv({
            itemTags = {
                ["create:golden_sheet"]   = { ["c:plates/gold"] = true },
                ["minecraft:iron_nugget"] = { ["c:nuggets/iron"] = true }
            }
        })
        package.loaded["lib.sequenced_core"] = nil
        local SequencedCore = require("lib.sequenced_core")
        local core = SequencedCore.new({
            autoLoad = false,
            autoImportDefault = false,
            config = {
                nodeId = "SEQ-01",
                inputName = "sophisticatedstorage:barrel_0",
                ae2Name = "extendedae:ex_pattern_provider_0",
                trashName = "sophisticatedstorage:barrel_trash",
                stations = {
                    deployer = "create:deployer_0",
                    deployerDepot = "create:depot_0",
                    pressDepot = "create:depot_1"
                }
            }
        })
        core:openBaseBus()

        core.recipes["create:precision_mechanism"] = {
            name             = "Precision Mechanism",
            result           = "create:precision_mechanism",
            resultCount      = 1,
            chance           = 0.80,
            baseIngredient   = "#c:plates/gold",
            transitionalItem = "create:incomplete_precision_mechanism",
            loops            = 5,
            totalCount       = 16,
            ingredients      = {
                ["#c:plates/gold"]        = 1,
                ["create:cogwheel"]       = 5,
                ["create:large_cogwheel"] = 5,
                ["#c:nuggets/iron"]       = 5
            },
            sequence = {
                { type = "deploying", item = "create:cogwheel" },
                { type = "deploying", item = "create:large_cogwheel" },
                { type = "deploying", item = "#c:nuggets/iron" }
            }
        }

        local inputBarrel = env.periphs["sophisticatedstorage:barrel_0"]
        inputBarrel._slots[1] = { name = "create:golden_sheet", count = 1 }
        inputBarrel._slots[2] = { name = "create:cogwheel", count = 5 }
        inputBarrel._slots[3] = { name = "create:large_cogwheel", count = 5 }
        inputBarrel._slots[4] = { name = "minecraft:iron_nugget", count = 5 }

        local expectedHeldPerStep = { "create:cogwheel", "create:large_cogwheel", "minecraft:iron_nugget" }
        local dep = env.periphs["create:deployer_0"]
        local dDepot = env.periphs["create:depot_0"]

        for loop = 1, 5 do
            for sIdx = 1, 3 do
                -- Trigger MOVE_TO_STATION
                local moveRes = core:step()
                assert_eq(moveRes.action, "MOVED", string.format("L%d S%d moved to station", loop, sIdx))
                assert_true(dep._slots[1] ~= nil, string.format("L%d S%d fed Deployer hand", loop, sIdx))
                assert_eq(dep._slots[1].name, expectedHeldPerStep[sIdx], string.format("L%d S%d correct Deployer item", loop, sIdx))

                -- Before machine processes, step() must stay in WAITING_PROCESS
                local waitRes = core:step()
                assert_eq(waitRes.action, "WAITING_PROCESS", string.format("L%d S%d waits before NBT change", loop, sIdx))

                -- Simulate Create Deployer strike: consumes held item & updates depot item/NBT
                dep._slots[1] = nil
                if loop == 5 and sIdx == 3 then
                    dDepot._slots[1] = { name = "create:precision_mechanism", count = 1, nbt = nil }
                else
                    dDepot._slots[1] = {
                        name = "create:incomplete_precision_mechanism",
                        count = 1,
                        nbt = string.format("seq_hash_%d_%d", loop, sIdx)
                    }
                end

                -- Poll completion
                local doneRes = core:step()
                if loop == 5 and sIdx == 3 then
                    assert_eq(doneRes.action, "FINISHED", "Final step 15 completed and finished job")
                else
                    assert_eq(doneRes.action, "STEP_DONE", string.format("L%d S%d detected NBT/item change", loop, sIdx))
                end
            end
        end

        assert_eq(core.totalCrafted, 1, "totalCrafted == 1")
        assert_eq(core.activeJob, nil, "activeJob cleared after completion")
        assert_true(dDepot._slots[1] == nil, "Deployer depot emptied after AE2 return")
        assert_eq(env.periphs["extendedae:ex_pattern_provider_0"]._slots[1].name, "create:precision_mechanism", "Finished Precision Mechanism returned to AE2")
        assert_true(#env.rednetBroadcasts >= 1, "CRAFT_EVENT broadcast sent")
        assert_eq(env.rednetBroadcasts[1].msg.nodeType, "SEQUENCED_ASSEMBLER", "CRAFT_EVENT nodeType == SEQUENCED_ASSEMBLER")
    end

    -- 3. test_probabilistic_scrap_routing
    do
        print("[3] test_probabilistic_scrap_routing")
        local env = createSeqEnv()
        package.loaded["lib.sequenced_core"] = nil
        local SequencedCore = require("lib.sequenced_core")
        local core = SequencedCore.new({
            autoLoad = false,
            autoImportDefault = false,
            config = {
                nodeId = "SEQ-01",
                inputName = "sophisticatedstorage:barrel_0",
                ae2Name = "extendedae:ex_pattern_provider_0",
                trashName = "sophisticatedstorage:barrel_trash",
                stations = { pressDepot = "create:depot_1" }
            }
        })

        core.recipes["lucky_plate"] = {
            name = "Lucky Plate",
            result = "create:precision_mechanism",
            chance = 0.80,
            baseIngredient = "minecraft:gold_ingot",
            transitionalItem = "create:incomplete_precision_mechanism",
            loops = 1,
            totalCount = 1,
            ingredients = { ["minecraft:gold_ingot"] = 1 },
            sequence = { { type = "pressing" } }
        }

        env.periphs["sophisticatedstorage:barrel_0"]._slots[1] = { name = "minecraft:gold_ingot", count = 1 }
        assert_eq(core:step().action, "MOVED", "Moved gold_ingot to pressDepot")

        -- Simulate bad roll producing scrap (clock instead of precision_mechanism)
        env.periphs["create:depot_1"]._slots[1] = { name = "minecraft:clock", count = 1 }
        local res = core:step()
        assert_eq(res.action, "SCRAP", "Detected probabilistic scrap result")
        assert_eq(core.totalScraps, 1, "totalScraps incremented to 1")
        assert_eq(core.totalCrafted, 0, "totalCrafted stayed 0 on scrap")
        assert_eq(env.periphs["sophisticatedstorage:barrel_trash"]._slots[1].name, "minecraft:clock", "Scrap routed to trashName barrel")
        assert_true(env.periphs["extendedae:ex_pattern_provider_0"]._slots[1] == nil, "Scrap NOT pushed to AE2 when trash barrel exists")
    end

    -- 4. test_spout_and_press_sequence (Sturdy Sheet from real default DB)
    do
        print("[4] test_spout_and_press_sequence")
        local env = createSeqEnv({
            itemTags = {
                ["create:powdered_obsidian"] = { ["c:dusts/obsidian"] = true }
            }
        })
        local fReal = assert(io.open("data/sequenced_recipes_default.db", "r"), "data/sequenced_recipes_default.db exists")
        env.files["/data/sequenced_recipes_default.db"] = fReal:read("*a")
        fReal:close()

        package.loaded["lib.sequenced_core"] = nil
        local SequencedCore = require("lib.sequenced_core")
        local core = SequencedCore.new({
            autoLoad = true,
            config = {
                nodeId = "SEQ-01",
                inputName = "sophisticatedstorage:barrel_0",
                ae2Name = "extendedae:ex_pattern_provider_0",
                stations = {
                    pressDepot = "create:depot_1",
                    spouts = { ["minecraft:lava"] = "create:depot_2" }
                }
            }
        })
        assert_true(core.autoImportedDefaultCount >= 350, "Auto-imported FTB Skies 2 sequenced DB (" .. tostring(core.autoImportedDefaultCount) .. ")")

        env.periphs["sophisticatedstorage:barrel_0"]._slots[1] = { name = "create:powdered_obsidian", count = 1 }

        -- Step 1: Filling with minecraft:lava on depot_2
        local r1 = core:step()
        assert_eq(r1.action, "MOVED", "Sturdy Sheet Step 1 moved powdered_obsidian to Lava Spout depot_2")
        assert_eq(env.periphs["create:depot_2"]._slots[1].name, "create:powdered_obsidian", "Item is on Lava Spout depot_2")

        env.periphs["create:depot_2"]._slots[1] = { name = "create:unprocessed_obsidian_sheet", count = 1, nbt = "step1_lava" }
        assert_eq(core:step().action, "STEP_DONE", "Step 1 (Lava Filling) detected completion")

        -- Step 2: Pressing #1 -> moves from depot_2 to pressDepot (depot_1)
        local r2 = core:step()
        assert_eq(r2.action, "MOVED", "Sturdy Sheet Step 2 moved transitional item to Press depot_1")
        assert_true(env.periphs["create:depot_2"]._slots[1] == nil, "Lava Spout depot_2 emptied")
        assert_eq(env.periphs["create:depot_1"]._slots[1].name, "create:unprocessed_obsidian_sheet", "Transitional item arrived at Press depot_1")

        env.periphs["create:depot_1"]._slots[1] = { name = "create:unprocessed_obsidian_sheet", count = 1, nbt = "step2_press1" }
        assert_eq(core:step().action, "STEP_DONE", "Step 2 (Pressing #1) detected NBT progress update")

        -- Step 3: Pressing #2 -> stays on depot_1
        local r3 = core:step()
        assert_eq(r3.action, "MOVED", "Sturdy Sheet Step 3 kept item on Press depot_1")
        assert_eq(env.periphs["create:depot_1"]._slots[1].nbt, "step2_press1", "Item stayed on Press depot_1 without extra move")

        env.periphs["create:depot_1"]._slots[1] = { name = "create:sturdy_sheet", count = 1, nbt = nil }
        local rFin = core:step()
        assert_eq(rFin.action, "FINISHED", "Step 3 (Pressing #2) finished Sturdy Sheet")
        assert_eq(env.periphs["extendedae:ex_pattern_provider_0"]._slots[1].name, "create:sturdy_sheet", "Sturdy Sheet returned to AE2 Pattern Provider")
    end

    -- 5. test_timeout_calibration_tui_and_base_bus
    do
        print("[5] test_timeout_calibration_tui_and_base_bus")
        local env = createSeqEnv()
        package.loaded["lib.sequenced_core"] = nil
        local SequencedCore = require("lib.sequenced_core")
        local core = SequencedCore.new({
            autoLoad = false,
            autoImportDefault = false,
            config = {
                nodeId = "SEQ-01",
                inputName = "sophisticatedstorage:barrel_0",
                ae2Name = "extendedae:ex_pattern_provider_0",
                stepTimeout = 5.0,
                stations = { pressDepot = "create:depot_1" }
            }
        })
        core:openBaseBus()

        -- Auto-detect deployer & depot calibration
        assert_eq(core:autoDetectDeployer(), "create:deployer_0", "autoDetectDeployer finds create:deployer_0")
        local snap = core:takeDepotSnapshot({ "create:depot_0", "create:depot_1", "create:depot_2" })
        env.periphs["create:depot_2"]._slots[1] = { name = "minecraft:cobblestone", count = 1 }
        local calDepot = core:calibrateDepotTarget({ "create:depot_0", "create:depot_1", "create:depot_2" }, snap, true)
        assert_eq(calDepot, "create:depot_2", "calibrateDepotTarget detected newly placed block on create:depot_2")
        assert_true(env.periphs["create:depot_2"]._slots[1] == nil, "Calibration block returned to input barrel")
        env.periphs["sophisticatedstorage:barrel_0"]._slots = {}

        -- Timeout protection test
        core.recipes["press_test"] = {
            name = "Press Test",
            result = "minecraft:iron_Weighted",
            baseIngredient = "minecraft:iron_ingot",
            transitionalItem = "minecraft:iron_ingot",
            loops = 1,
            totalCount = 1,
            ingredients = { ["minecraft:iron_ingot"] = 1 },
            sequence = { { type = "pressing" } }
        }
        env.periphs["sophisticatedstorage:barrel_0"]._slots[1] = { name = "minecraft:iron_ingot", count = 1 }
        assert_eq(core:step().action, "MOVED", "Started Press Test job")
        env.clockSec = env.clockSec + 6.0
        local tRes = core:step()
        assert_eq(tRes.action, "TIMEOUT", "stepTimeout triggered TIMEOUT safely")
        assert_eq(core.paused, true, "Node auto-paused on timeout")
        assert_eq(env.periphs["create:depot_1"]._slots[1].name, "minecraft:iron_ingot", "Item preserved on depot after timeout")

        -- Base Bus telemetry & commands
        local tel = core:buildTelemetryPacket()
        assert_eq(tel.nodeType, "SEQUENCED_ASSEMBLER", "Telemetry nodeType == SEQUENCED_ASSEMBLER")
        core:handleBaseBusMessage(55, { type = "CMD_RESUME", targetNode = "SEQ-01" }, "DRUNKEN_BASE_BUS")
        assert_eq(core.paused, false, "CMD_RESUME resumed Sequenced node")

        -- Sequenced TUI smoke test (no idle redraws)
        core:resetActiveJob()
        local writes = 0
        local fakeTerm = {
            getSize = function() return 51, 19 end,
            isColor = function() return true end,
            setTextColor = function() end,
            setBackgroundColor = function() end,
            setCursorPos = function() end,
            clear = function() end,
            write = function() writes = writes + 1 end
        }
        _G.term = { current = function() return fakeTerm end }
        local writesAfter1 = nil
        local events = {
            { "timer", 1 },
            { "timer", 1 },
            { "key", _G.keys.q }
        }
        local idx = 0
        _G.os.pullEvent = function()
            idx = idx + 1
            if idx == 2 then writesAfter1 = writes
            elseif idx == 3 then assert_eq(writes, writesAfter1, "Sequenced TUI zero idle writes on unchanged tick") end
            local e = events[idx]
            if not e then return "terminate" end
            return e[1], e[2]
        end
        local clientMod = assert(loadfile("clients/Drunken_Crafter.lua"))("Drunken_Crafter")
        clientMod.run({ term = fakeTerm, core = core })
        assert_true(writes > 0, "Sequenced TUI rendered dashboard")

        -- Verify manifests include lib/sequenced_core.lua and data/sequenced_recipes_default.db
        local rootManifest = dofile("manifest.lua")
        local instManifest = dofile("installer/manifest.lua")
        local pkg = rootManifest.packages.drunken_crafter
        assert_true(pkg ~= nil, "manifest.lua defines drunken_crafter")
        assert_true(instManifest.packages.drunken_crafter ~= nil, "installer/manifest.lua defines drunken_crafter")
        local allListed = {}
        for _, p in ipairs(pkg.files or {}) do allListed[p] = true end
        for _, p in ipairs(pkg.remote_files or {}) do allListed[p] = true end
        assert_true(allListed["clients/Drunken_Crafter.lua"], "Manifest lists clients/Drunken_Crafter.lua")
        assert_true(allListed["lib/crafter_core.lua"], "Manifest lists lib/crafter_core.lua")
        assert_true(allListed["lib/sequenced_core.lua"], "Manifest lists lib/sequenced_core.lua")
        assert_true(allListed["data/crafter_recipes_default.db"], "Manifest lists data/crafter_recipes_default.db")
        assert_true(allListed["data/sequenced_recipes_default.db"], "Manifest lists data/sequenced_recipes_default.db")
    end
end)

restoreGlobals()

if not okAll then
    error(errAll, 0)
end

print(">>> All Drunken Crafter v2 Sequenced Assembly tests passed successfully!")
