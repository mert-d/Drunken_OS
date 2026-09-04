--[[
    Drunken OS - Cryptographic Packet Security & Anti-Replay Defense (lib/crypto_packet.lua)
    Version: 1.0
    
    Protects wireless Rednet communication from eavesdropping, packet forgery, and replay attacks.
    Signs packet payloads with RFC-compliant HMAC-SHA1, UTC timestamps, and pseudo-random nonces.
]]

local sha1 = require("lib.sha1_hmac")

local crypto_packet = {
    _VERSION = "1.0",
    DEFAULT_MAX_AGE_MS = 15000 -- 15 seconds validity window
}

local seenNonces = {}

local function getEpochMs()
    if os.epoch then
        return os.epoch("utc")
    elseif os.clock then
        return math.floor(os.clock() * 1000)
    elseif os.time then
        return math.floor(os.time() * 1000)
    end
    return 0
end

local function generateNonce()
    return string.format("%04x%04x", math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

--- Cleans up expired nonces to prevent unbounded memory growth.
function crypto_packet.purgeNonces()
    local now = getEpochMs()
    for nonce, expireTime in pairs(seenNonces) do
        if now > expireTime then
            seenNonces[nonce] = nil
        end
    end
end

--- Signs an arbitrary Lua data structure with a shared secret key.
-- @param payload any: The message payload (table, string, number, etc.)
local function canonicalSerialize(val)
    if type(val) == "string" then
        return string.format("%q", val)
    elseif type(val) ~= "table" then
        return tostring(val)
    end
    local keys = {}
    for k in pairs(val) do table.insert(keys, tostring(k)) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        table.insert(parts, string.format("%s=%s", k, canonicalSerialize(val[k])))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- Signs an arbitrary Lua data structure with a shared secret key.
-- @param payload any: The message payload (table, string, number, etc.)
-- @param secretKey string: The secret key known only to the sender and recipient.
-- @return table: The secured envelope ready for rednet.send.
function crypto_packet.sign(payload, secretKey)
    if not secretKey or #secretKey == 0 then
        error("crypto_packet.sign: secretKey cannot be nil or empty", 2)
    end

    local payloadStr = canonicalSerialize(payload)
    local timestamp = getEpochMs()
    local nonce = generateNonce()
    local canonical = string.format("%s:%d:%s", payloadStr, timestamp, nonce)
    local signature = sha1.hmac_hex(secretKey, canonical)

    return {
        secured = true,
        payload = payload,
        timestamp = timestamp,
        nonce = nonce,
        signature = signature
    }
end

--- Verifies a secured envelope, rejecting expired packets, invalid signatures, and replay attacks.
-- @param packet table: The incoming message received over Rednet.
-- @param secretKey string: The shared secret key.
-- @param maxAgeMs number: (Optional) Max allowed clock skew / packet age in ms (defaults to 15,000).
-- @return boolean, any: (true, payload) on success, or (false, errorReason) on failure.
function crypto_packet.verify(packet, secretKey, maxAgeMs)
    if type(packet) ~= "table" or not packet.secured then
        return false, "Not a secured packet envelope"
    end
    if not secretKey or #secretKey == 0 then
        return false, "Missing verification key"
    end
    if not packet.timestamp or not packet.nonce or not packet.signature then
        return false, "Malformed packet security header"
    end

    local now = getEpochMs()
    local maxAge = maxAgeMs or crypto_packet.DEFAULT_MAX_AGE_MS

    -- 1. Timestamp Freshness Check
    if math.abs(now - packet.timestamp) > maxAge then
        return false, "Packet expired or clock skew exceeded"
    end

    -- 2. Anti-Replay Nonce Check
    if seenNonces[packet.nonce] then
        return false, "Replay attack detected: duplicate nonce"
    end

    -- 3. HMAC-SHA1 Integrity Verification
    local payloadStr = canonicalSerialize(packet.payload)
    local canonical = string.format("%s:%d:%s", payloadStr, packet.timestamp, packet.nonce)
    local expectedSig = sha1.hmac_hex(secretKey, canonical)

    if packet.signature ~= expectedSig then
        return false, "Invalid HMAC signature: payload tampered or incorrect key"
    end

    -- Record nonce until maximum possible lifetime has expired
    seenNonces[packet.nonce] = now + (maxAge * 2)

    return true, packet.payload
end

return crypto_packet
