--[[
    Unit Test: Drunken Crafter (AE2 Pattern Provider + Create Mechanical Crafter Node)
    Verifies zero-code wall recipe learning, subset-safe recipe priority,
    atomic 1-item dispatch + Redstone pulse (side & relay), AE2 output return,
    busy wall guard, interactive 5x5 calibration wizard, DRUNKEN_BASE_BUS telemetry/commands,
    and standalone client + manifest integrity.
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

print("=== Running Drunken Crafter Unit Tests ===")

-- Save original globals
local orig_fs = _G.fs
local orig_textutils = _G.textutils
local orig_peripheral = _G.peripheral
local orig_redstone = _G.redstone
local orig_rednet = _G.rednet
local orig_os = _G.os
local orig_sleep = _G.sleep
local orig_term = _G.term
local orig_colors = _G.colors
local orig_keys = _G.keys
local orig_loaded_lib = package.loaded["lib.crafter_core"]
local orig_loaded_short = package.loaded["crafter_core"]

local function restoreGlobals()
    _G.fs = orig_fs
    _G.textutils = orig_textutils
    _G.peripheral = orig_peripheral
    _G.redstone = orig_redstone
    _G.rednet = orig_rednet
    _G.os = orig_os
    _G.sleep = orig_sleep
    _G.term = orig_term
    _G.colors = orig_colors
    _G.keys = orig_keys
    package.loaded["lib.crafter_core"] = orig_loaded_lib
    package.loaded["crafter_core"] = orig_loaded_short
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

local function createEnv(opts)
    opts = opts or {}
    local state = {
        files = {},
        dirs = { ["/"] = true },
        periphs = {},
        types = {},
        redstoneLog = {},
        redstoneState = {},
        sleepLog = {},
        rednetOpen = {},
        rednetBroadcasts = {},
        rednetSends = {},
        epochMs = 1700000000000,
        clockSec = 100.0,
        computerId = opts.computerId or 42
    }

    _G.fs = {
        exists = function(path)
            return state.files[path] ~= nil or state.dirs[path] == true
        end,
        getDir = function(path)
            local dir = path:match("^(.*)/[^/]+$")
            return dir or ""
        end,
        makeDir = function(dir)
            state.dirs[dir] = true
            return true
        end,
        open = function(path, mode)
            if mode == "r" then
                local content = state.files[path]
                if not content then return nil end
                return {
                    readAll = function() return content end,
                    close = function() end
                }
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

    _G.keys = {
        escape = 1, tab = 15, enter = 28, numPadEnter = 156, backspace = 14,
        up = 200, down = 208, left = 203, right = 205,
        c = 46, d = 32, l = 38, p = 25, q = 16, r = 19, s = 31, t = 20
    }

    _G.sleep = function(sec)
        table.insert(state.sleepLog, sec)
        state.clockSec = state.clockSec + (tonumber(sec) or 0)
        state.epochMs = state.epochMs + math.floor((tonumber(sec) or 0) * 1000)
    end

    _G.redstone = {
        setOutput = function(side, val)
            state.redstoneState[side] = val
            table.insert(state.redstoneLog, { side = side, val = val })
        end,
        getOutput = function(side)
            return state.redstoneState[side] == true
        end
    }

    _G.rednet = {
        open = function(name)
            state.rednetOpen[name] = true
        end,
        isOpen = function(name)
            if name then return state.rednetOpen[name] == true end
            for _, v in pairs(state.rednetOpen) do
                if v then return true end
            end
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
            slots[k] = { name = v.name, count = v.count }
        end
        local maxSlots = optsInv.maxSlots or 27

        local inv = {}
        inv._slots = slots
        function inv.size()
            return maxSlots
        end
        function inv.list()
            local out = {}
            for s, item in pairs(slots) do
                if item and item.count > 0 then
                    out[s] = { name = item.name, count = item.count }
                end
            end
            return out
        end
        function inv.getItemDetail(slot)
            local item = slots[slot]
            if item and item.count > 0 then
                return { name = item.name, count = item.count, maxCount = 64 }
            end
            return nil
        end
        function inv.pushItems(targetName, fromSlot, limit, toSlot)
            local tgt = state.periphs[targetName]
            if not tgt or not tgt._slots then return 0 end
            local src = slots[fromSlot]
            if not src or src.count <= 0 then return 0 end
            local toMove = math.min(src.count, limit or src.count)
            local destSlot = toSlot
            if destSlot then
                local existing = tgt._slots[destSlot]
                if existing and existing.name ~= src.name then
                    return 0
                end
                if existing then
                    existing.count = existing.count + toMove
                else
                    tgt._slots[destSlot] = { name = src.name, count = toMove }
                end
            else
                local placed = false
                for i = 1, (tgt.size and tgt.size() or 27) do
                    local ex = tgt._slots[i]
                    if ex and ex.name == src.name and ex.count < 64 then
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
                            tgt._slots[i] = { name = src.name, count = toMove }
                            placed = true
                            break
                        end
                    end
                end
                if not placed then return 0 end
            end
            src.count = src.count - toMove
            if src.count <= 0 then
                slots[fromSlot] = nil
            end
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
        isPresent = function(name)
            return state.periphs[name] ~= nil
        end,
        getType = function(name)
            return state.types[name]
        end,
        hasType = function(name, t)
            return state.types[name] == t
        end,
        wrap = function(name)
            return state.periphs[name]
        end,
        call = function(name, method, ...)
            local p = state.periphs[name]
            if not p then error("No peripheral: " .. tostring(name), 2) end
            local fn = p[method]
            if type(fn) ~= "function" then error("No method: " .. tostring(method), 2) end
            return fn(...)
        end
    }

    -- Default 25x Mechanical Crafter + input/output Barrels + AE2 Pattern Provider
    local gridMap = {}
    for i = 1, 25 do
        local name = "create:mechanical_crafter_" .. tostring(i)
        makeInventory(name, "create:mechanical_crafter", {}, { maxSlots = 1 })
        gridMap[i] = name
    end
    makeInventory("minecraft:barrel_0", "minecraft:barrel", {})
    makeInventory("minecraft:barrel_1", "minecraft:barrel", {})
    makeInventory("ae2:pattern_provider_0", "ae2:pattern_provider", {})

    if opts.withWirelessModem ~= false then
        state.periphs["top"] = {
            isWireless = function() return true end
        }
        state.types["top"] = "modem"
    end

    state.defaultGridMap = gridMap
    return state
end

local function loadCore(env)
    package.loaded["lib.crafter_core"] = nil
    local CrafterCore = require("lib.crafter_core")
    local core = CrafterCore.new({
        autoLoad = false,
        config = {
            nodeId = "CRAFTER-01",
            inputName = "minecraft:barrel_0",
            outputName = "minecraft:barrel_1",
            ae2Name = "ae2:pattern_provider_0",
            triggerSide = "right",
            pollRate = 0.5,
            pulseSec = 0.15,
            rednetEnabled = true,
            gridMap = env.defaultGridMap
        }
    })
    return CrafterCore, core
end

local okAll, errAll = pcall(function()
    -- 1. test_learn_recipe_from_wall
    do
        print("[1] test_learn_recipe_from_wall")
        local env = createEnv()
        local CrafterCore, core = loadCore(env)

        -- Crushing Wheel 5x5 layout (21 items, center stone at slot 13)
        local crushingLayout = {
            [2]  = "create:andesite_alloy", [3]  = "create:andesite_alloy", [4]  = "create:andesite_alloy",
            [6]  = "create:andesite_alloy", [7]  = "minecraft:oak_planks",    [8]  = "minecraft:oak_planks",    [9]  = "minecraft:oak_planks",    [10] = "create:andesite_alloy",
            [11] = "create:andesite_alloy", [12] = "minecraft:oak_planks",    [13] = "minecraft:stone",         [14] = "minecraft:oak_planks",    [15] = "create:andesite_alloy",
            [16] = "create:andesite_alloy", [17] = "minecraft:oak_planks",    [18] = "minecraft:oak_planks",    [19] = "minecraft:oak_planks",    [20] = "create:andesite_alloy",
            [22] = "create:andesite_alloy", [23] = "create:andesite_alloy", [24] = "create:andesite_alloy"
        }
        for slotIdx, itemName in pairs(crushingLayout) do
            env.periphs[env.defaultGridMap[slotIdx]]._slots[1] = { name = itemName, count = 1 }
        end

        local recipe, err = core:learnRecipeFromWall("Crushing Wheel")
        assert_true(recipe ~= nil and err == nil, "learnRecipeFromWall succeeded")
        assert_eq(recipe.totalCount, 21, "Crushing Wheel totalCount == 21")
        assert_eq(recipe.layout[13], "minecraft:stone", "Crushing Wheel layout[13] == minecraft:stone")
        assert_eq(recipe.ingredients["create:andesite_alloy"], 12, "andesite_alloy ingredient count == 12")
        assert_eq(recipe.ingredients["minecraft:oak_planks"], 8, "oak_planks ingredient count == 8")
        assert_eq(recipe.ingredients["minecraft:stone"], 1, "stone ingredient count == 1")

        -- Verify persisted reload
        core:saveConfig()
        local reloaded = CrafterCore.new({ autoLoad = true })
        assert_true(reloaded.recipes["Crushing Wheel"] ~= nil, "Persisted recipe reloaded from disk")
        assert_eq(reloaded.recipes["Crushing Wheel"].totalCount, 21, "Reloaded recipe totalCount == 21")
    end

    -- 2. test_subset_recipe_priority
    do
        print("[2] test_subset_recipe_priority")
        local env = createEnv()
        local _, core = loadCore(env)

        core.recipes["Small Iron"] = {
            name = "Small Iron",
            totalCount = 3,
            ingredients = { ["minecraft:iron_ingot"] = 3 },
            layout = { [1] = "minecraft:iron_ingot", [2] = "minecraft:iron_ingot", [3] = "minecraft:iron_ingot" }
        }
        core.recipes["Reinforced Tool"] = {
            name = "Reinforced Tool",
            totalCount = 5,
            ingredients = { ["minecraft:iron_ingot"] = 3, ["minecraft:oak_planks"] = 2 },
            layout = {
                [1] = "minecraft:iron_ingot", [2] = "minecraft:iron_ingot", [3] = "minecraft:iron_ingot",
                [7] = "minecraft:oak_planks", [12] = "minecraft:oak_planks"
            }
        }

        local matched = core:matchRecipe({
            ["minecraft:iron_ingot"] = 3,
            ["minecraft:oak_planks"] = 2
        })
        assert_true(matched ~= nil, "matchRecipe returned a recipe")
        assert_eq(matched.name, "Reinforced Tool", "Larger superset recipe selected over 3-iron subset")
    end

    -- 3. test_atomic_dispatch_and_pulse
    do
        print("[3] test_atomic_dispatch_and_pulse")
        local env = createEnv()
        local _, core = loadCore(env)
        core:openBaseBus()

        core.recipes["Mini Gear"] = {
            name = "Mini Gear",
            totalCount = 3,
            ingredients = { ["minecraft:iron_ingot"] = 2, ["minecraft:oak_planks"] = 1 },
            layout = {
                [1] = "minecraft:iron_ingot",
                [2] = "minecraft:oak_planks",
                [6] = "minecraft:iron_ingot"
            }
        }
        env.periphs["minecraft:barrel_0"]._slots[1] = { name = "minecraft:iron_ingot", count = 2 }
        env.periphs["minecraft:barrel_0"]._slots[2] = { name = "minecraft:oak_planks", count = 1 }

        local res = core:step()
        assert_eq(res.action, "CRAFTED", "step() dispatched recipe")
        assert_eq(res.recipe, "Mini Gear", "step() crafted Mini Gear")
        assert_eq(core.totalCrafted, 1, "totalCrafted incremented to 1")

        -- Verify exact 1-item pushes into grid slots 1, 2, 6
        assert_eq(env.periphs["create:mechanical_crafter_1"]._slots[1].name, "minecraft:iron_ingot", "Slot 1 received iron_ingot")
        assert_eq(env.periphs["create:mechanical_crafter_1"]._slots[1].count, 1, "Slot 1 received exactly 1 item")
        assert_eq(env.periphs["create:mechanical_crafter_2"]._slots[1].name, "minecraft:oak_planks", "Slot 2 received oak_planks")
        assert_eq(env.periphs["create:mechanical_crafter_6"]._slots[1].name, "minecraft:iron_ingot", "Slot 6 received iron_ingot")
        assert_true(env.periphs["minecraft:barrel_0"]._slots[1] == nil, "Input barrel slot 1 emptied")
        assert_true(env.periphs["minecraft:barrel_0"]._slots[2] == nil, "Input barrel slot 2 emptied")

        -- Verify Redstone pulse sequence
        assert_eq(#env.redstoneLog, 2, "Redstone pulsed ON then OFF")
        assert_eq(env.redstoneLog[1].side, "right", "Redstone side is right")
        assert_eq(env.redstoneLog[1].val, true, "Redstone first state is true")
        assert_eq(env.redstoneLog[2].val, false, "Redstone second state is false")
        assert_eq(env.sleepLog[1], 0.15, "Redstone pulse slept pulseSec = 0.15")

        -- Verify CRAFT_EVENT emitted on DRUNKEN_BASE_BUS
        assert_true(#env.rednetBroadcasts >= 1, "CRAFT_EVENT broadcast emitted")
        local evt = env.rednetBroadcasts[1]
        assert_eq(evt.protocol, "DRUNKEN_BASE_BUS", "Broadcast uses DRUNKEN_BASE_BUS protocol")
        assert_eq(evt.msg.type, "CRAFT_EVENT", "Broadcast packet type is CRAFT_EVENT")
        assert_eq(evt.msg.recipe, "Mini Gear", "CRAFT_EVENT recipe matches")

        -- Verify Redstone Relay peripheral trigger support
        local relayCalls = {}
        env.periphs["redstone_relay_0"] = {
            setOutput = function(side, val)
                table.insert(relayCalls, { side = side, val = val })
            end
        }
        env.types["redstone_relay_0"] = "redstone_relay"
        core.cfg.triggerSide = "redstone_relay_0"
        core.cfg.relaySide = "front"
        local okRelay = core:triggerPulse()
        assert_true(okRelay, "triggerPulse supports redstone_relay peripheral")
        assert_eq(#relayCalls, 2, "Redstone relay pulsed ON then OFF")
        assert_eq(relayCalls[1].side, "front", "Relay pulsed configured relaySide")
        assert_eq(relayCalls[1].val, true, "Relay turned ON")
        assert_eq(relayCalls[2].val, false, "Relay turned OFF")
    end

    -- 4. test_output_return_to_ae2
    do
        print("[4] test_output_return_to_ae2")
        local env = createEnv()
        local _, core = loadCore(env)

        env.periphs["minecraft:barrel_1"]._slots[1] = { name = "create:crushing_wheel", count = 2 }
        local res = core:step()
        assert_eq(res.returned, 2, "Returned 2 finished items from output barrel")
        assert_true(env.periphs["minecraft:barrel_1"]._slots[1] == nil, "Output barrel emptied")
        assert_eq(env.periphs["ae2:pattern_provider_0"]._slots[1].name, "create:crushing_wheel", "AE2 Pattern Provider received finished product")
        assert_eq(env.periphs["ae2:pattern_provider_0"]._slots[1].count, 2, "AE2 Pattern Provider received count 2")
    end

    -- 5. test_busy_wall_guard
    do
        print("[5] test_busy_wall_guard")
        local env = createEnv()
        local _, core = loadCore(env)

        core.recipes["Single Stone"] = {
            name = "Single Stone",
            totalCount = 1,
            ingredients = { ["minecraft:stone"] = 1 },
            layout = { [1] = "minecraft:stone" }
        }
        -- Wall is still busy in slot 13
        env.periphs["create:mechanical_crafter_13"]._slots[1] = { name = "minecraft:cobblestone", count = 1 }
        env.periphs["minecraft:barrel_0"]._slots[1] = { name = "minecraft:stone", count = 4 }

        local res = core:step()
        assert_eq(res.action, "BUSY", "step() detected busy wall and refused dispatch")
        assert_eq(core.status, "CRAFTING", "Status reports CRAFTING while wall busy")
        assert_eq(env.periphs["minecraft:barrel_0"]._slots[1].count, 4, "Input barrel stone untouched while busy")
        assert_eq(#env.redstoneLog, 0, "No Redstone pulse fired while busy")
    end

    -- 6. test_base_bus_telemetry_and_commands
    do
        print("[6] test_base_bus_telemetry_and_commands")
        -- First test silent no-op without wireless modem
        local envNoModem = createEnv({ withWirelessModem = false })
        local _, coreNoModem = loadCore(envNoModem)
        assert_eq(coreNoModem:openBaseBus(), false, "openBaseBus silently returns false without wireless modem")
        assert_eq(coreNoModem:broadcastTelemetry(), false, "broadcastTelemetry is safe no-op without modem")

        -- Now test with wireless modem
        local env = createEnv({ withWirelessModem = true, computerId = 77 })
        local _, core = loadCore(env)
        assert_eq(core:openBaseBus(), true, "openBaseBus opens wireless modem")

        core.recipes["Test Recipe"] = {
            name = "Test Recipe",
            totalCount = 4,
            ingredients = { ["minecraft:stone"] = 4 },
            layout = { [1] = "minecraft:stone", [2] = "minecraft:stone", [3] = "minecraft:stone", [4] = "minecraft:stone" }
        }

        local tel = core:buildTelemetryPacket()
        assert_eq(tel.type, "NODE_TELEMETRY", "Telemetry packet type == NODE_TELEMETRY")
        assert_eq(tel.nodeType, "MECHANICAL_CRAFTER", "Telemetry nodeType == MECHANICAL_CRAFTER")
        assert_eq(tel.nodeId, "CRAFTER-01", "Telemetry nodeId == CRAFTER-01")
        assert_eq(tel.computerId, 77, "Telemetry computerId == 77")
        assert_eq(tel.recipeCount, 1, "Telemetry recipeCount == 1")

        -- Ignore command targeting another node
        local ignored = core:handleBaseBusMessage(99, { type = "CMD_PAUSE", targetNode = "CRAFTER-99" }, "DRUNKEN_BASE_BUS")
        assert_eq(ignored, false, "Ignores CMD_PAUSE targeted at another nodeId")
        assert_eq(core.paused, false, "Remains unpaused when command targets another node")

        -- CMD_PAUSE
        local okPause = core:handleBaseBusMessage(99, { type = "CMD_PAUSE", targetNode = "CRAFTER-01" }, "DRUNKEN_BASE_BUS")
        assert_true(okPause, "Handled CMD_PAUSE for CRAFTER-01")
        assert_eq(core.paused, true, "Node paused after CMD_PAUSE")
        local pausedStep = core:step()
        assert_eq(pausedStep.action, "PAUSED", "step() returns PAUSED while paused")

        -- CMD_RESUME
        local okResume = core:handleBaseBusMessage(99, { type = "CMD_RESUME" }, "DRUNKEN_BASE_BUS")
        assert_true(okResume, "Handled broadcast CMD_RESUME (targetNode == nil)")
        assert_eq(core.paused, false, "Node resumed after CMD_RESUME")

        -- CMD_PING / CMD_GET_STATUS
        local okPing = core:handleBaseBusMessage(105, { type = "CMD_PING" }, "DRUNKEN_BASE_BUS")
        assert_true(okPing, "Handled CMD_PING")
        assert_eq(env.rednetSends[#env.rednetSends].targetId, 105, "CMD_PING replied to senderId 105")
        assert_eq(env.rednetSends[#env.rednetSends].msg.type, "NODE_TELEMETRY", "CMD_PING replied with NODE_TELEMETRY")

        -- CMD_LIST_RECIPES
        local okList = core:handleBaseBusMessage(105, { type = "CMD_LIST_RECIPES" }, "DRUNKEN_BASE_BUS")
        assert_true(okList, "Handled CMD_LIST_RECIPES")
        local listMsg = env.rednetSends[#env.rednetSends].msg
        assert_eq(listMsg.type, "RECIPE_LIST", "CMD_LIST_RECIPES replied with RECIPE_LIST")
        assert_eq(#listMsg.recipes, 1, "RECIPE_LIST contains 1 recipe")
        assert_eq(listMsg.recipes[1].name, "Test Recipe", "RECIPE_LIST entry name matches")
        assert_eq(listMsg.recipes[1].totalCount, 4, "RECIPE_LIST entry totalCount matches")
    end

    -- 7. test_interactive_calibration_wizard
    do
        print("[7] test_interactive_calibration_wizard")
        local env = createEnv()
        local _, core = loadCore(env)
        core.cfg.gridMap = {}

        local crafters = core:discoverPeripherals().crafters
        assert_eq(#crafters, 25, "Discovered all 25 Mechanical Crafters")

        local baseline = core:takeCrafterSnapshot(crafters)
        local noneYet = core:calibrateNextSlot(1, { crafterNames = crafters, baseline = baseline, pollOnce = true })
        assert_eq(noneYet, nil, "calibrateNextSlot returns nil before user places item")

        -- User places 1 cobblestone into mechanical_crafter_14
        env.periphs["create:mechanical_crafter_14"]._slots[1] = { name = "minecraft:cobblestone", count = 1 }
        local matched = core:calibrateNextSlot(1, { crafterNames = crafters, baseline = baseline, pollOnce = true })
        assert_eq(matched, "create:mechanical_crafter_14", "Detected newly placed item in mechanical_crafter_14")
        assert_eq(core.cfg.gridMap[1], "create:mechanical_crafter_14", "Mapped slot 1 -> mechanical_crafter_14")
        assert_true(env.periphs["create:mechanical_crafter_14"]._slots[1] == nil, "Cleared calibration item from crafter")
        assert_eq(env.periphs["minecraft:barrel_0"]._slots[1].name, "minecraft:cobblestone", "Returned calibration item to input barrel")
    end

    -- 8. test_client_and_manifest_integrity
    do
        print("[8] test_client_and_manifest_integrity")
        local env = createEnv()
        local _, core = loadCore(env)

        -- Mock term & scripted event queue to run Drunken_Crafter TUI end-to-end
        local writes = {}
        local fakeTerm = {
            getSize = function() return 51, 19 end,
            isColor = function() return true end,
            setTextColor = function() end,
            setBackgroundColor = function() end,
            setCursorPos = function() end,
            clear = function() end,
            write = function(s) table.insert(writes, s) end
        }
        _G.term = { current = function() return fakeTerm end }

        local events = {
            { "timer", 1 },
            { "key", _G.keys.p },
            { "key", _G.keys.q }
        }
        local evIdx = 0
        _G.os.pullEvent = function()
            evIdx = evIdx + 1
            local e = events[evIdx]
            if not e then return "terminate" end
            return e[1], e[2], e[3], e[4]
        end

        local clientChunk, loadErr = loadfile("clients/Drunken_Crafter.lua")
        assert_true(clientChunk ~= nil, "clients/Drunken_Crafter.lua compiled cleanly: " .. tostring(loadErr))
        local clientMod = clientChunk("Drunken_Crafter")
        assert_true(type(clientMod) == "table" and type(clientMod.run) == "function", "Drunken_Crafter exports { run = fn }")

        clientMod.run({ term = fakeTerm, core = core })
        assert_eq(core.paused, true, "TUI [P] key toggled paused state before [Q] exit")
        assert_true(#writes > 0, "TUI rendered dashboard output to terminal")

        -- Verify manifests match and contain drunken_crafter
        local rootManifest = dofile("manifest.lua")
        local instManifest = dofile("installer/manifest.lua")
        assert_true(rootManifest.packages.drunken_crafter ~= nil, "manifest.lua defines drunken_crafter package")
        assert_true(instManifest.packages.drunken_crafter ~= nil, "installer/manifest.lua defines drunken_crafter package")
        assert_eq(rootManifest.packages.drunken_crafter.main, "clients/Drunken_Crafter.lua", "Manifest main path matches")

        -- Verify pocket menu lib/drunken_os_apps.lua was NOT modified to add crafter
        local appsFile = orig_fs and nil or io.open("lib/drunken_os_apps.lua", "r")
        if appsFile then
            local appsContent = appsFile:read("*a")
            appsFile:close()
            assert_true(appsContent:find("Drunken_Crafter") == nil, "lib/drunken_os_apps.lua does not reference Drunken_Crafter")
        end
    end
end)

restoreGlobals()

if not okAll then
    error(errAll, 0)
end

print(">>> All Drunken Crafter unit tests passed successfully!")
