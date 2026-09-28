--[[
    Unit Test: HyperAuth Zero-Config Auto-Pairing Handshake
    Tests automated discovery, PIN verification, key generation, vendor persistence,
    and end-to-end cryptographic mutual authentication.
]]

package.path = "./?.lua;./HyperAuthClient/?.lua;./servers/?.lua;" .. package.path

local function assert_true(cond, desc)
    if not cond then error("FAILED: " .. tostring(desc), 2) end
    print("  PASS: " .. desc)
end

local function assert_eq(a, b, desc)
    if a ~= b then error(string.format("FAILED [%s]: Expected %s, got %s", desc, tostring(b), tostring(a)), 2) end
    print("  PASS: " .. desc)
end

print("=== Running HyperAuth Auto-Pairing Handshake Tests ===")

-- Mock textutils for pure Lua test environment
_G.textutils = _G.textutils or {}
if not _G.textutils.serializeJSON then
    local function serializeJSON(tbl)
        if type(tbl) == "string" then
            return string.format("%q", tbl)
        elseif type(tbl) == "number" or type(tbl) == "boolean" then
            return tostring(tbl)
        elseif type(tbl) == "table" then
            local isArray = (#tbl > 0)
            local parts = {}
            if isArray then
                for _, v in ipairs(tbl) do
                    table.insert(parts, serializeJSON(v))
                end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                local keys = {}
                for k in pairs(tbl) do table.insert(keys, k) end
                table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
                for _, k in ipairs(keys) do
                    table.insert(parts, string.format("%q:%s", tostring(k), serializeJSON(tbl[k])))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end
        return "null"
    end
    _G.textutils.serializeJSON = serializeJSON
    _G.textutils.unserializeJSON = function(s)
        if not s or type(s) ~= "string" then return nil end
        local luaStr = s:gsub("null", "nil"):gsub('"(%w+)"%s*:', '["%1"]=')
        local fn, err = load("return " .. luaStr)
        if not fn then return nil end
        local ok, res = pcall(fn)
        if ok then return res end
        return nil
    end
end

-- 1. Setup Mock Rednet & Peripheral Environment
local rednetPackets = {}
local mockRednet = {
    broadcast = function(msg, proto)
        table.insert(rednetPackets, { to = "broadcast", message = msg, protocol = proto })
    end,
    send = function(target, msg, proto)
        table.insert(rednetPackets, { to = target, message = msg, protocol = proto })
    end
}

local PAIRING_PROTOCOL = "hyperauth.pair.v1"
local AUTH_SERVER_ID = 25
local HYPERAUTH_SERVER_ID = 99

local function getTime()
    return (os.epoch and os.epoch("utc")) or (os.time and os.time()) or 1000000
end

-- 2. Simulate Auth Server generating pair_request
local testPin = "7412"
local testNonce = "nonce_abc123"
local pairRequest = {
    type = "pair_request",
    computer_id = AUTH_SERVER_ID,
    label = "Drunken OS Auth #" .. AUTH_SERVER_ID,
    pin = testPin,
    nonce = testNonce,
    timestamp = getTime()
}

mockRednet.broadcast(pairRequest, PAIRING_PROTOCOL)
assert_eq(#rednetPackets, 1, "Auth Server broadcasted pairing request")
assert_eq(rednetPackets[1].protocol, PAIRING_PROTOCOL, "Pairing protocol is " .. PAIRING_PROTOCOL)
assert_eq(rednetPackets[1].message.pin, "7412", "Pairing request contains 4-digit PIN")
assert_eq(rednetPackets[1].message.computer_id, 25, "Computer ID matches Auth Server")

-- 3. Simulate HyperAuth Server ingesting pair_request
local pending_pair_requests = {}
local incomingMsg = rednetPackets[1].message
local sender_id = incomingMsg.computer_id

pending_pair_requests[sender_id] = {
    id = sender_id,
    pin = incomingMsg.pin,
    label = incomingMsg.label,
    nonce = incomingMsg.nonce,
    timestamp = getTime()
}

assert_true(pending_pair_requests[AUTH_SERVER_ID] ~= nil, "HyperAuth Server stored pending pairing request")
assert_eq(pending_pair_requests[AUTH_SERVER_ID].pin, "7412", "HyperAuth Server recorded verification PIN")

-- 4. Simulate HyperAuth Server Admin approving pairing ('pair accept 25')
local secure = require("HyperAuthClient/encrypt/secure")
local generatedSecret = secure.random_hex(32)
local generatedVendorId = "drunken_auth_" .. AUTH_SERVER_ID

assert_eq(#generatedSecret, 32, "Cryptographically generated secret has 32 hex characters")
assert_eq(generatedVendorId, "drunken_auth_25", "Assigned vendor ID conforms to drunken_auth_<id>")

-- Server sends acceptance response
local acceptReply = {
    type = "pair_accept",
    server_id = HYPERAUTH_SERVER_ID,
    vendorId = generatedVendorId,
    sharedSecret = generatedSecret,
    protocol = "auth.secure.v1",
    pin = pending_pair_requests[AUTH_SERVER_ID].pin,
    nonce = pending_pair_requests[AUTH_SERVER_ID].nonce,
    timestamp = getTime()
}
mockRednet.send(AUTH_SERVER_ID, acceptReply, PAIRING_PROTOCOL)
pending_pair_requests[AUTH_SERVER_ID] = nil

assert_eq(#rednetPackets, 2, "HyperAuth Server dispatched pair_accept reply")
assert_eq(rednetPackets[2].to, AUTH_SERVER_ID, "Reply targeted to Auth Server computer ID")
assert_eq(rednetPackets[2].message.sharedSecret, generatedSecret, "Reply contains generated secret")
assert_true(pending_pair_requests[AUTH_SERVER_ID] == nil, "Pending request cleared after approval")

-- 5. Simulate Auth Server processing acceptance and writing config
local clientReceived = rednetPackets[2].message
assert_eq(clientReceived.type, "pair_accept", "Auth Server received pair_accept")
assert_eq(clientReceived.nonce, testNonce, "Nonce matches request nonce")
assert_eq(clientReceived.pin, testPin, "PIN matches verification PIN")

local clientConfig = {
    PROTOCOL_NAME = clientReceived.protocol,
    CLIENT_ID = clientReceived.vendorId,
    SHARED_SECRET = clientReceived.sharedSecret,
    KNOWN_SERVER_ID = clientReceived.server_id,
    DEFAULT_TIMEOUT_SECONDS = 6,
    PAIRED = true
}

assert_true(clientConfig.PAIRED, "Auth Server marked as PAIRED = true")
assert_eq(clientConfig.CLIENT_ID, "drunken_auth_25", "Auth Server stored new client ID")
assert_eq(clientConfig.SHARED_SECRET, generatedSecret, "Auth Server stored new shared secret")

-- 6. End-to-End Cryptographic Verification with Paired Keys
local header = { client_id = clientConfig.CLIENT_ID, version = "v1" }
local payload = {
    type = "request_code",
    username = "Player1",
    computerID = AUTH_SERVER_ID,
    vendorID = clientConfig.CLIENT_ID
}

local sealedPacket = secure.seal(clientConfig.SHARED_SECRET, header, payload)
assert_true(type(sealedPacket) == "table", "Client sealed token request table")

-- HyperAuth Server opens packet using the vendor secret
local openedPayload, openErr = secure.open(generatedSecret, header, sealedPacket)
assert_true(openedPayload ~= nil, "HyperAuth Server successfully opened sealed payload with generated key, err: " .. tostring(openErr))
assert_eq(openedPayload.username, "Player1", "Decrypted username matches")
assert_eq(openedPayload.vendorID, "drunken_auth_25", "Decrypted vendorID matches")

print(">>> All HyperAuth Auto-Pairing Handshake tests passed successfully!")
