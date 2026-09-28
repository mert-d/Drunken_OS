--[[
    HyperAuth - Cryptographic Security & Envelope Module
    Implements symmetric keystream cipher, HMAC-SHA1 verification, and timestamp anti-replay.
]]

local sha1 = nil
local sha1_candidates = {
  "/servers/hyperauth/sha1.lua",
  "servers/hyperauth/sha1.lua",
  "/hyperauth/sha1.lua",
  "hyperauth/sha1.lua",
  "/sha1.lua",
  "sha1.lua",
  "/lib/sha1_hmac.lua",
  "lib/sha1_hmac.lua"
}
for _, p in ipairs(sha1_candidates) do
  if fs and fs.exists and fs.exists(p) then
    local fn, err = loadfile(p)
    if not fn then
      error("secure: Compile error in '" .. p .. "':\n" .. tostring(err), 0)
    end
    if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
    local ok, res = pcall(fn)
    if not ok then
      error("secure: Runtime error in '" .. p .. "':\n" .. tostring(res), 0)
    end
    sha1 = res
    break
  end
end
if not sha1 then
  local ok_sha1, res = pcall(require, "servers.hyperauth.sha1")
  if not ok_sha1 then ok_sha1, res = pcall(require, "hyperauth.sha1") end
  if not ok_sha1 then ok_sha1, res = pcall(require, "sha1") end
  if not ok_sha1 then ok_sha1, res = pcall(require, "lib.sha1_hmac") end
  if ok_sha1 then
    sha1 = res
  else
    error("secure: cannot find or load sha1 module: " .. tostring(res), 0)
  end
end

local bit = bit32 or _G.bit32 or _G.bit
if not bit then
  local ok, mod = pcall(require, "bit")
  if ok and mod then bit = mod end
end

local bor, bxor, rshift, band
if bit then
  bor, bxor, rshift, band = bit.bor, bit.bxor, bit.rshift, bit.band
else
  local load_fn = loadstring or load
  local ok_native, native_funcs = pcall(load_fn, [[
    return {
      bor  = function(a, b) return (a | b) & 0xFFFFFFFF end,
      bxor = function(a, b) return (a ~ b) & 0xFFFFFFFF end,
      rshift = function(a, b) return (a >> b) & 0xFFFFFFFF end,
      band = function(a, b) return (a & b) & 0xFFFFFFFF end
    }
  ]])
  if ok_native and native_funcs then
    local nf = native_funcs()
    bor, bxor, rshift, band = nf.bor, nf.bxor, nf.rshift, nf.band
  else
    error("secure: No bit32 library or native bitwise operators found.", 0)
  end
end

local NONCE_HEX_LENGTH    = 16
local TIMESTAMP_TOLERANCE = 2 * 60 * 1000

local function now_ms() return os.epoch and os.epoch("utc") or (os.time() * 1000) end
local function seed_rng()
  local hex = tostring({}):match("(%x+)$") or "0"
  local val = tonumber(hex, 16) or 0
  local ms = (now_ms() % 2147483647)
  math.randomseed((val + ms) % 2147483647)
end

local function random_hex(n)
  local h = "0123456789abcdef"
  local t = {}
  for i = 1, n do
    local k = math.random(#h)
    t[i] = h:sub(k, k)
  end
  return table.concat(t)
end

local function keystream(key, nonce_raw, byte_len)
  local out = {}
  local counter = 0
  while #table.concat(out) < byte_len do
    local ctr = string.char(
      band(rshift(counter, 24), 255),
      band(rshift(counter, 16), 255),
      band(rshift(counter, 8), 255),
      band(counter, 255)
    )
    local block = sha1.sha1_raw(key .. nonce_raw .. ctr)
    out[#out + 1] = block
    counter = (counter + 1) % (2 ^ 32)
  end
  local s = table.concat(out)
  return s:sub(1, byte_len)
end

local function xor_bytes(a, b)
  local t = {}
  for i = 1, #a do
    t[i] = string.char(bxor(a:byte(i), b:byte(i)))
  end
  return table.concat(t)
end

local function to_json(tbl) return textutils.serializeJSON(tbl) end
local function from_json(s)
  local ok, t = pcall(textutils.unserializeJSON, s)
  if ok then return t end
end

local M = {}

function M.seal(shared_key, header_table, payload_table)
  local header_json  = to_json(header_table)
  local payload_json = to_json(payload_table)

  local nonce_hex  = random_hex(NONCE_HEX_LENGTH)
  local nonce_raw  = sha1.from_hex(nonce_hex)
  local stream     = keystream(shared_key, nonce_raw, #payload_json)
  local cipher_raw = xor_bytes(payload_json, stream)
  local cipher_hex = sha1.to_hex(cipher_raw)

  local mac_input  = table.concat({"v1", header_json, nonce_hex, cipher_hex}, "|")
  local mac_hex    = sha1.hmac_sha1(shared_key, mac_input)

  return { nonce = nonce_hex, ciphertext_hex = cipher_hex, mac_hex = mac_hex }
end

function M.open(shared_key, header_table, packet)
  if type(packet) ~= "table" or not packet.nonce or not packet.ciphertext_hex or not packet.mac_hex then
    return nil, "bad_packet"
  end
  local header_json = to_json(header_table)
  local mac_input   = table.concat({"v1", header_json, packet.nonce, packet.ciphertext_hex}, "|")
  local expected    = sha1.hmac_sha1(shared_key, mac_input)

  local diff = 0
  local a, b = expected, tostring(packet.mac_hex)
  local n = math.max(#a, #b)
  for i = 1, n do
    diff = bor(diff, bxor(a:byte(i) or 0, b:byte(i) or 0))
  end
  if not (diff == 0 and #a == #b) then return nil, "mac_mismatch" end

  local nonce_raw   = sha1.from_hex(packet.nonce)
  local cipher_raw  = sha1.from_hex(packet.ciphertext_hex)
  local stream      = keystream(shared_key, nonce_raw, #cipher_raw)
  local plain_json  = xor_bytes(cipher_raw, stream)

  local payload = from_json(plain_json)
  if not payload then return nil, "json_error" end

  if payload.timestamp_ms and math.abs(now_ms() - tonumber(payload.timestamp_ms)) > TIMESTAMP_TOLERANCE then
    return nil, "stale_timestamp"
  end

  return payload
end

M.now_ms = now_ms
M.seed_rng = seed_rng
M.random_hex = random_hex
M.NONCE_HEX_LENGTH = NONCE_HEX_LENGTH

return M
