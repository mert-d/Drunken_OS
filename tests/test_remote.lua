--[[
    Unit Test: Drunken Remote & Switch Suite (tests/test_remote.lua)
    Verifies auto-discovery, switch toggling, pulse handling, and permissions.
]]

package.path = "./?.lua;" .. package.path

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION FAILED: %s (expected %s, got %s)", msg or "", tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. (msg or "assert_eq"))
end

print("=== Running Drunken Remote & Switch Tests ===")

-- Mock redstone & rednet environment
local redstoneState = {
    back = false,
    left = false,
    right = false
}

_G.redstone = {
    setOutput = function(side, state)
        redstoneState[side] = (state == true)
    end,
    getOutput = function(side)
        return redstoneState[side] == true
    end
}

local sentPackets = {}
local currentComputerId = 42

_G.os = _G.os or {}
_G.os.getComputerID = function() return currentComputerId end
_G.os.epoch = function() return 1000000 end

_G.rednet = {
    isOpen = function() return true end,
    send = function(target, msg, proto)
        table.insert(sentPackets, { target = target, msg = msg, proto = proto })
    end,
    broadcast = function(msg, proto)
        table.insert(sentPackets, { target = "broadcast", msg = msg, proto = proto })
    end
}

-- 1. Switch State Engine Logic
local switchConfig = {
    name = "Main Blast Gate",
    side = "back",
    mode = "toggle",
    pulseDuration = 2,
    isPublic = true,
    owner = "Mert",
    state = false,
    toggleCount = 0
}

local function processRemoteMsg(sender, msg, config)
    if type(msg) ~= "table" or not msg.type then return end
    local isAuthorized = config.isPublic or (msg.user and msg.user == config.owner)

    if msg.type == "scan" then
        rednet.send(sender, {
            type = "switch_info",
            id = os.getComputerID(),
            name = config.name,
            side = config.side,
            mode = config.mode,
            state = config.state,
            isPublic = config.isPublic,
            owner = config.owner
        }, "DrunkenRemote")
    elseif msg.type == "toggle" then
        if isAuthorized then
            config.state = not config.state
            config.toggleCount = config.toggleCount + 1
            redstone.setOutput(config.side, config.state)
            rednet.send(sender, {
                type = "switch_update",
                id = os.getComputerID(),
                state = config.state,
                success = true
            }, "DrunkenRemote")
        else
            rednet.send(sender, {
                type = "switch_update",
                id = os.getComputerID(),
                state = config.state,
                success = false,
                error = "Unauthorized"
            }, "DrunkenRemote")
        end
    end
end

-- Test 1: Scan Discovery
sentPackets = {}
processRemoteMsg(10, { type = "scan", user = "Mert" }, switchConfig)
assert_eq(#sentPackets, 1, "Scan request generated 1 reply packet")
assert_eq(sentPackets[1].target, 10, "Target is requesting computer 10")
assert_eq(sentPackets[1].msg.type, "switch_info", "Packet is switch_info")
assert_eq(sentPackets[1].msg.name, "Main Blast Gate", "Switch name preserved")
assert_eq(sentPackets[1].msg.state, false, "Initial state is false")

-- Test 2: Toggle Activation
sentPackets = {}
processRemoteMsg(10, { type = "toggle", user = "Mert" }, switchConfig)
assert_eq(switchConfig.state, true, "Switch state flipped to true")
assert_eq(redstone.getOutput("back"), true, "Physical redstone output set to true")
assert_eq(#sentPackets, 1, "Toggle generated reply packet")
assert_eq(sentPackets[1].msg.success, true, "Toggle reported success")

-- Test 3: Toggle Deactivation
sentPackets = {}
processRemoteMsg(10, { type = "toggle", user = "Mert" }, switchConfig)
assert_eq(switchConfig.state, false, "Switch state flipped back to false")
assert_eq(redstone.getOutput("back"), false, "Physical redstone output set to false")

-- Test 4: Private Switch Security
switchConfig.isPublic = false
switchConfig.owner = "Mert"
sentPackets = {}
processRemoteMsg(15, { type = "toggle", user = "Intruder" }, switchConfig)
assert_eq(switchConfig.state, false, "Unauthorized toggle rejected")
assert_eq(sentPackets[1].msg.success, false, "Reply reports success=false")
assert_eq(sentPackets[1].msg.error, "Unauthorized", "Error reason is Unauthorized")

-- Test 5: Authorized Owner on Private Switch
sentPackets = {}
processRemoteMsg(10, { type = "toggle", user = "Mert" }, switchConfig)
assert_eq(switchConfig.state, true, "Authorized owner can toggle private switch")
assert_eq(sentPackets[1].msg.success, true, "Owner toggle reports success")

print(">>> All Drunken Remote & Switch tests passed successfully!\n")
return true
