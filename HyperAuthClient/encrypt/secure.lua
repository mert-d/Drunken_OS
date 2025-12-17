local sha1 = require("HyperAuthClient/encrypt/sha1")
local bit = bit32
local bor, bxor, rshift, band = bit.bor, bit.bxor, bit.rshift, bit.band

local NONCE_HEX_LENGTH    = 16
local TIMESTAMP_TOLERANCE = 2 * 60 * 1000

local function now_ms() return os.epoch("utc") end
local function seed_rng()
  math.randomseed( tonumber(string.sub(tostring({}),8),16) + now_ms() )
end

local function random_hex(n)
  local h="0123456789abcdef"; local t={}
  for i=1,n do local k=math.random(#h); t[i]=h:sub(k,k) end
  return table.concat(t)
end

local function keystream(key, nonce_raw, byte_len)
  local out = {}
  local counter = 0
  while #table.concat(out) < byte_len do
    local ctr = string.char(
      band(rshift(counter,24),255),
      band(rshift(counter,16),255),
      band(rshift(counter,8),255),
      band(counter,255)
    )
    local block = sha1.sha1_raw(key .. nonce_raw .. ctr)
    out[#out+1] = block
    counter = (counter + 1) % 2^32
  end
  local s = table.concat(out)
  return s:sub(1, byte_len)
end

local function xor_bytes(a,b)
  local t={}
  for i=1,#a do t[i]=string.char(bxor(a:byte(i), b:byte(i))) end
  return table.concat(t)
end

local function to_json(tbl) return textutils.serializeJSON(tbl) end
local function from_json(s) local ok,t=pcall(textutils.unserializeJSON,s); if ok then return t end end

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
  if type(packet)~="table" or not packet.nonce or not packet.ciphertext_hex or not packet.mac_hex then
    return nil, "bad_packet"
  end
  local header_json = to_json(header_table)
  local mac_input   = table.concat({"v1", header_json, packet.nonce, packet.ciphertext_hex}, "|")
  local expected    = sha1.hmac_sha1(shared_key, mac_input)

  local diff=0; local a,b=expected, tostring(packet.mac_hex)
  local n=math.max(#a,#b)
  for i=1,n do
    diff = bor(diff, bxor(a:byte(i) or 0, b:byte(i) or 0))
  end
  if not (diff==0 and #a==#b) then return nil, "mac_mismatch" end

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
