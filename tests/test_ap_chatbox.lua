--[[
    Drunken OS - Advanced Peripherals Chat Box Unit & Integration Tests
    Validates AP Chat Box detection, JSON tellraw formatting, toast notifications,
    and Auth Server hybrid fallback authentication flow.
]]

local function assert_true(cond, msg)
    if not cond then error("ASSERTION FAILED: " .. (msg or "expected true"), 2) end
    print("  PASS: " .. msg)
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("ASSERTION FAILED: %s (expected %s, got %s)", msg or "values equal", tostring(b), tostring(a)), 2)
    end
    print("  PASS: " .. msg)
end

print("=== Running Advanced Peripherals Chat Box 2FA Tests ===")

-- 1. Load module
local APChatBox = require("lib.ap_chatbox")
assert_true(type(APChatBox) == "table", "lib.ap_chatbox loads cleanly as a table")
assert_true(type(APChatBox.sendAuthCode) == "function", "sendAuthCode function exported")
assert_true(type(APChatBox.find) == "function", "find function exported")

-- 2. Mock environment setup
local mockPeripherals = {}
local mockGlobalPeripheral = {
    find = function(ptype)
        for _, p in pairs(mockPeripherals) do
            if p.type == ptype then return p.obj end
        end
        return nil
    end,
    getNames = function()
        local list = {}
        for name in pairs(mockPeripherals) do table.insert(list, name) end
        return list
    end,
    getType = function(name)
        return mockPeripherals[name] and mockPeripherals[name].type or nil
    end,
    wrap = function(name)
        return mockPeripherals[name] and mockPeripherals[name].obj or nil
    end,
    getName = function(obj)
        for name, p in pairs(mockPeripherals) do
            if p.obj == obj then return name end
        end
        return "chatBox"
    end
}

local origPeripheral = rawget(_G, "peripheral")
rawset(_G, "peripheral", mockGlobalPeripheral)

-- Test: No peripheral attached
assert_eq(APChatBox.isAvailable(), false, "isAvailable returns false when no peripheral attached")
local noDevStatus = APChatBox.getStatus()
assert_eq(noDevStatus.available, false, "getStatus reports available = false when absent")

-- 3. Test: Mock modern 'chatBox' peripheral
local dispatchedMessages = {}
local dispatchedFormatted = {}
local dispatchedToasts = {}

local modernChatBox = {
    sendMessageToPlayer = function(msg, player, prefix)
        table.insert(dispatchedMessages, { msg = msg, player = player, prefix = prefix })
        return true
    end,
    sendFormattedMessageToPlayer = function(json, player, prefix)
        table.insert(dispatchedFormatted, { json = json, player = player, prefix = prefix })
        return true
    end,
    sendToastToPlayer = function(msg, title, player, prefix)
        table.insert(dispatchedToasts, { msg = msg, title = title, player = player, prefix = prefix })
        return true
    end,
    sendMessage = function(msg, prefix)
        table.insert(dispatchedMessages, { msg = msg, player = "*", prefix = prefix })
        return true
    end
}

mockPeripherals["chatBox_0"] = { type = "chatBox", obj = modernChatBox }

assert_true(APChatBox.isAvailable(), "isAvailable returns true when chatBox is attached")
local cbObj, cbName = APChatBox.find()
assert_true(cbObj ~= nil, "find() returns peripheral handle")
assert_eq(cbName, "chatBox_0", "find() returns correct peripheral name")

local status = APChatBox.getStatus()
assert_true(status.available, "Status available is true")
assert_true(status.canFormatted, "Status detects sendFormattedMessageToPlayer")
assert_true(status.canToast, "Status detects sendToastToPlayer")
assert_true(status.canPlain, "Status detects sendMessageToPlayer")

-- 4. Test: 2FA Token Dispatch
local ok_send, err_send = APChatBox.sendAuthCode("Steve", "123456", 5, "[DrunkenAuth]")
assert_true(ok_send, "sendAuthCode succeeds for player 'Steve'")
assert_eq(#dispatchedFormatted, 1, "Formatted JSON message dispatched")
assert_eq(dispatchedFormatted[1].player, "Steve", "Target player matches Steve")
assert_true(dispatchedFormatted[1].json:find("123456") ~= nil, "JSON payload contains 2FA code")
assert_true(dispatchedFormatted[1].json:find("Drunken OS") ~= nil, "JSON payload contains Drunken OS branding")
assert_eq(#dispatchedToasts, 1, "Toast notification dispatched for enhanced UX")
assert_eq(dispatchedToasts[1].player, "Steve", "Toast target matches Steve")

-- 5. Test: Fallback to plain text when formatted message is unsupported
mockPeripherals["chatBox_0"].obj.sendFormattedMessageToPlayer = nil
dispatchedMessages = {}
local ok_plain, err_plain = APChatBox.sendAuthCode("Alex", "654321", 10)
assert_true(ok_plain, "sendAuthCode succeeds via plain text fallback")
assert_eq(#dispatchedMessages, 1, "Plain message dispatched")
assert_eq(dispatchedMessages[1].player, "Alex", "Plain message target matches Alex")
assert_true(dispatchedMessages[1].msg:find("654321") ~= nil, "Plain message contains 2FA code")

-- 6. Test: Legacy 'chat_box' peripheral type resolution
mockPeripherals["chatBox_0"] = nil
mockPeripherals["chat_box_legacy"] = { type = "chat_box", obj = modernChatBox }
assert_true(APChatBox.isAvailable(), "isAvailable successfully resolves legacy 'chat_box' peripheral")
local legacyObj, legacyName = APChatBox.find()
assert_true(legacyObj ~= nil, "find() returns legacy peripheral handle")
assert_eq(legacyName, "chat_box_legacy", "find() returns legacy peripheral name")

-- 7. Test: General messaging & broadcast
local ok_msg = APChatBox.sendMessage("Hello survival!", "Steve")
assert_true(ok_msg, "sendMessage sends private chat message")
local ok_bcast = APChatBox.broadcast("Server maintenance in 5m")
assert_true(ok_bcast, "broadcast sends public chat announcement")

-- Clean up mock environment
rawset(_G, "peripheral", origPeripheral)

print(">>> All Advanced Peripherals Chat Box tests passed successfully!")
