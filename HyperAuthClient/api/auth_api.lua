local secure = require("HyperAuthClient/encrypt/secure")
local config = require("HyperAuthClient/config")


local CLIENT_ID = assert(config.CLIENT_ID, "CLIENT_ID missing in /HyperAuthClient/config.lua")
local SHARED_SECRET = assert(config.SHARED_SECRET, "SHARED_SECRET missing in /HyperAuthClient/config.lua")
local KNOWN_SERVER_ID = config.KNOWN_SERVER_ID
local DEFAULT_TIMEOUT = tonumber(config.DEFAULT_TIMEOUT_SECONDS) or 6

local function open_modem()
  for _, s in ipairs({ "left","right","top","bottom","front","back" }) do
    if peripheral.getType(s) == "modem" then rednet.open(s) end
  end
end

local function ensure_table(x)
  if type(x) == "table" then return x end
  if type(x) == "string" then
    local ok, t = pcall(textutils.unserializeJSON, x)
    if ok and type(t) == "table" then return t end
  end
  error("auth(data): expected table or JSON")
end

local function auth(protocol, data)
  assert(type(protocol)=="string" and #protocol>0, "protocol required")
  open_modem(); secure.seed_rng()

  local payload = ensure_table(data)
  payload.timestamp_ms = payload.timestamp_ms or secure.now_ms()

  local header = { client_id = CLIENT_ID, version = "v1" }
  local packet = secure.seal(SHARED_SECRET, header, payload)
  local outer  = { client_id = CLIENT_ID, packet = packet }

  local serialized = textutils.serialize(outer)
  if KNOWN_SERVER_ID then rednet.send(KNOWN_SERVER_ID, serialized, protocol)
  else rednet.broadcast(serialized, protocol) end

  local from, reply = rednet.receive(protocol, DEFAULT_TIMEOUT)
  if not from then return nil, "timeout" end
  KNOWN_SERVER_ID = KNOWN_SERVER_ID or from

  local okOuter, outerReply = pcall(textutils.unserialize, reply)
  if not okOuter or type(outerReply)~="table" then return nil, "decode_error" end
  if outerReply.error and not outerReply.packet then return nil, outerReply.error end

  local opened, err = secure.open(SHARED_SECRET, header, outerReply.packet)
  if not opened then return nil, err end
  return opened
end

return { auth = auth }
