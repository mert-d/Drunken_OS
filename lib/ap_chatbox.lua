--[[
    Drunken OS - Advanced Peripherals Chat Box Driver
    _VERSION = 1.0
    Purpose: Provides integration with Advanced Peripherals Chat Box ('chatBox' / 'chat_box')
    for delivering in-game 2FA verification tokens, toast popups, and notification alerts
    without requiring Minecraft OP permissions or Command Computers.
]]

local APChatBox = {}
APChatBox._VERSION = 1.0

--- Finds any attached Advanced Peripherals Chat Box peripheral.
-- Probes both modern 'chatBox' and legacy 'chat_box' peripheral type strings.
-- @return table|nil peripheral handle, string|nil peripheral name/side
function APChatBox.find()
    if not peripheral then return nil, nil end

    -- Direct probe via peripheral.find
    if peripheral.find then
        local ok1, p1 = pcall(peripheral.find, "chatBox")
        if ok1 and p1 then
            local name = peripheral.getName and peripheral.getName(p1) or "chatBox"
            return p1, name
        end
        local ok2, p2 = pcall(peripheral.find, "chat_box")
        if ok2 and p2 then
            local name = peripheral.getName and peripheral.getName(p2) or "chat_box"
            return p2, name
        end
    end

    -- Side & Network probe fallback
    local sides = peripheral.getNames and peripheral.getNames() or { "top", "bottom", "left", "right", "front", "back" }
    for _, s in ipairs(sides) do
        local ok, ptype = pcall(peripheral.getType, s)
        if ok and (ptype == "chatBox" or ptype == "chat_box") then
            local wrapOk, wrapped = pcall(peripheral.wrap, s)
            if wrapOk and wrapped then
                return wrapped, s
            end
        end
    end

    return nil, nil
end

--- Checks if an AP Chat Box is currently attached and available.
-- @return boolean true if Chat Box is available
function APChatBox.isAvailable()
    local cb = APChatBox.find()
    return cb ~= nil
end

--- Returns comprehensive status metadata about the attached Chat Box.
-- @return table status details including peripheral methods available
function APChatBox.getStatus()
    local cb, name = APChatBox.find()
    if not cb then
        return {
            available = false,
            name = nil,
            canFormatted = false,
            canToast = false,
            canPlain = false
        }
    end

    return {
        available = true,
        name = name,
        canFormatted = (type(cb.sendFormattedMessageToPlayer) == "function"),
        canToast = (type(cb.sendToastToPlayer) == "function"),
        canPlain = (type(cb.sendMessageToPlayer) == "function")
    }
end

--- Constructs the Minecraft JSON Tellraw data structure for a 2FA verification token.
-- Formatted with Drunken OS branding, clickable copy-to-clipboard, and hover tooltip.
-- @param code string|number: The 6-digit verification code.
-- @param ttlMinutes number: Expiration time in minutes.
-- @return string JSON serialized text component string.
local function buildAuthJson(code, ttlMinutes)
    local codeStr = tostring(code)
    local ttl = tonumber(ttlMinutes) or 5

    local payload = {
        "",
        { text = "=== [Drunken OS] Auth Token ===\n", bold = true, color = "aqua" },
        { text = "Security Code: ", color = "yellow", bold = false },
        {
            text = codeStr,
            bold = true,
            color = "green",
            clickEvent = { action = "copy_to_clipboard", value = codeStr },
            hoverEvent = { action = "show_text", contents = "Click to copy code" }
        },
        { text = string.format("\nExpires in %d minute(s). Do not share this code!\n", ttl), color = "gray", bold = false },
        { text = "================================", bold = true, color = "aqua" }
    }

    if textutils and textutils.serializeJSON then
        return textutils.serializeJSON(payload)
    end

    -- Fallback manual JSON serializer if textutils.serializeJSON is absent
    return string.format(
        '[{"text":"=== [Drunken OS] Auth Token ===\\n","bold":true,"color":"aqua"},' ..
        '{"text":"Security Code: ","color":"yellow"},' ..
        '{"text":"%s","bold":true,"color":"green"},' ..
        '{"text":"\\nExpires in %d minute(s). Do not share!\\n","color":"gray"},' ..
        '{"text":"================================","bold":true,"color":"aqua"}]',
        codeStr, ttl
    )
end

--- Dispatches a 2FA verification code to a player in-game via Chat Box.
-- Tries formatted JSON text component first, then plain whisper, and sends a toast popup if supported.
-- @param player string: Target player username.
-- @param code string|number: The 6-digit verification code.
-- @param ttlMinutes number: Code expiry in minutes (default 5).
-- @param prefix string: Optional custom prefix (default '[DrunkenAuth]').
-- @return boolean success, string|nil error description
function APChatBox.sendAuthCode(player, code, ttlMinutes, prefix)
    local cb = APChatBox.find()
    if not cb then
        return false, "Chat Box peripheral not attached"
    end

    local codeStr = tostring(code)
    local ttl = tonumber(ttlMinutes) or 5
    local pfx = prefix or "[DrunkenAuth]"
    local sent = false
    local lastErr = nil

    -- 1. Try formatted message to player (Minecraft JSON tellraw)
    if cb.sendFormattedMessageToPlayer then
        local rawJson = buildAuthJson(codeStr, ttl)
        local ok, res = pcall(cb.sendFormattedMessageToPlayer, rawJson, player, pfx)
        if ok and res ~= false then
            sent = true
        else
            lastErr = tostring(res)
        end
    end

    -- 2. Fallback to standard whisper (sendMessageToPlayer)
    if not sent and cb.sendMessageToPlayer then
        local plainMsg = string.format("Your verification code is: %s (Expires in %d min)", codeStr, ttl)
        local ok, res = pcall(cb.sendMessageToPlayer, plainMsg, player, pfx)
        if ok and res ~= false then
            sent = true
        else
            lastErr = tostring(res)
        end
    end

    -- 3. Optional Toast popup for enhanced visual feedback (AP 0.7+)
    if cb.sendToastToPlayer then
        pcall(cb.sendToastToPlayer, "Code: " .. codeStr .. " (Valid " .. ttl .. "m)", "Drunken OS 2FA", player, pfx)
    end

    if sent then
        return true, nil
    end
    return false, lastErr or "Failed to deliver message to player (offline or unreached)"
end

--- Sends a private plain text message to a player in-game.
-- @param message string: Message content.
-- @param player string: Target username.
-- @param prefix string: Optional prefix (default '[DrunkenOS]').
-- @return boolean success, string|nil error description
function APChatBox.sendMessage(message, player, prefix)
    local cb = APChatBox.find()
    if not cb then
        return false, "Chat Box peripheral not attached"
    end
    local pfx = prefix or "[DrunkenOS]"

    if cb.sendMessageToPlayer then
        local ok, res = pcall(cb.sendMessageToPlayer, tostring(message), player, pfx)
        if ok and res ~= false then return true, nil end
        return false, tostring(res)
    elseif cb.sendFormattedMessageToPlayer then
        local ok, res = pcall(cb.sendFormattedMessageToPlayer, tostring(message), player, pfx)
        if ok and res ~= false then return true, nil end
        return false, tostring(res)
    end

    return false, "Chat Box lacks player messaging method"
end

--- Broadcasts a message to the public server chat.
-- @param message string: Message content.
-- @param prefix string: Optional prefix (default '[DrunkenOS]').
-- @return boolean success, string|nil error description
function APChatBox.broadcast(message, prefix)
    local cb = APChatBox.find()
    if not cb then
        return false, "Chat Box peripheral not attached"
    end
    local pfx = prefix or "[DrunkenOS]"

    if cb.sendMessage then
        local ok, res = pcall(cb.sendMessage, tostring(message), pfx)
        if ok and res ~= false then return true, nil end
        return false, tostring(res)
    elseif cb.sendFormattedMessage then
        local ok, res = pcall(cb.sendFormattedMessage, tostring(message), pfx)
        if ok and res ~= false then return true, nil end
        return false, tostring(res)
    end

    return false, "Chat Box lacks broadcast method"
end

return APChatBox
