--[[
    Unit Test: Cryptographic Packet Signing & Anti-Replay Defense (lib/crypto_packet.lua)
    Verifies HMAC authentication, tampering rejection, replay defense, and expiry.
]]

package.path = "./?.lua;" .. package.path

if not _G.textutils then
    _G.textutils = {
        serialize = function(t)
            if type(t) == "table" then
                local parts = {}
                for k, v in pairs(t) do
                    table.insert(parts, tostring(k) .. "=" .. tostring(v))
                end
                table.sort(parts)
                return "{" .. table.concat(parts, ",") .. "}"
            end
            return tostring(t)
        end
    }
end

local crypto = require("lib.crypto_packet")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Cryptographic Packet Security Tests ===")

local secretKey = "SuperSecretBankKey999"
local payload = { from = "Mert", to = "Player2", amount = 500 }

-- 1. Sign Packet
local packet = crypto.sign(payload, secretKey)
assert_eq(packet.secured, true, "Envelope secured flag")
assert_eq(type(packet.signature), "string", "Envelope signature is string")
assert_eq(#packet.signature, 40, "HMAC-SHA1 hex length is 40 chars")
assert_eq(type(packet.nonce), "string", "Nonce generated")

-- 2. Valid Verification
local ok, verifiedPayload = crypto.verify(packet, secretKey)
assert_eq(ok, true, "Valid packet verifies successfully")
assert_eq(verifiedPayload.from, "Mert", "Payload from field preserved")
assert_eq(verifiedPayload.amount, 500, "Payload amount field preserved")

-- 3. Replay Attack Defense (Same packet submitted second time)
local okReplay, replayErr = crypto.verify(packet, secretKey)
assert_eq(okReplay, false, "Duplicate nonce rejected")
assert_eq(replayErr:find("Replay attack") ~= nil, true, "Replay attack error message returned")

-- 4. Incorrect Key Verification
local packet2 = crypto.sign(payload, secretKey)
local okWrongKey, keyErr = crypto.verify(packet2, "WrongSecretKey123")
assert_eq(okWrongKey, false, "Wrong key verification rejected")
assert_eq(keyErr:find("Invalid HMAC") ~= nil, true, "Invalid HMAC error reported")

-- 5. Tampered Payload Attack
local packet3 = crypto.sign({ from = "Mert", to = "Attacker", amount = 10 }, secretKey)
packet3.payload.amount = 999999 -- Attacker modifies amount in flight!
local okTamper, tamperErr = crypto.verify(packet3, secretKey)
assert_eq(okTamper, false, "Tampered payload rejected")
assert_eq(tamperErr:find("Invalid HMAC") ~= nil, true, "Tamper detected by HMAC mismatch")

-- 6. Expired Timestamp
local packet4 = crypto.sign(payload, secretKey)
packet4.timestamp = packet4.timestamp - 30000 -- 30 seconds in the past
local okExpired, expErr = crypto.verify(packet4, secretKey, 15000)
assert_eq(okExpired, false, "Expired timestamp rejected")
assert_eq(expErr:find("expired") ~= nil, true, "Expiry error reported")

print(">>> All Cryptographic Packet tests passed successfully!\n")
return true
