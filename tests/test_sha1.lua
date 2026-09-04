--[[
    Unit Test: SHA-1 & HMAC-SHA1
    Verifies cryptographic hashing against RFC 3174 & RFC 2202 test vectors.
]]

package.path = "./?.lua;" .. package.path
local sha1 = require("lib.sha1_hmac")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running SHA-1 & HMAC-SHA1 Tests ===")

-- RFC 3174 Test Vectors
assert_eq(sha1.hex(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709", "Empty string")
assert_eq(sha1.hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d", "String 'abc'")
assert_eq(sha1.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"), "84983e441c3bd26ebaae4aa1f95129e5e54670f1", "Long multi-block string")
assert_eq(sha1.hex("The quick brown fox jumps over the lazy dog"), "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12", "Quick brown fox")

-- RFC 2202 HMAC-SHA1 Test Vectors
assert_eq(sha1.hmac_hex("key", "The quick brown fox jumps over the lazy dog"), "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9", "HMAC fox with key")
assert_eq(sha1.hmac_hex(string.rep("\x0b", 20), "Hi There"), "b617318655057264e28bc0b6fb378c8ef146be00", "RFC 2202 Test 1")

print(">>> All SHA-1 & HMAC tests passed successfully!\n")
return true
