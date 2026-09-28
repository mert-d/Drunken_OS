local secure = nil
local secure_candidates = {
  "/HyperAuthClient/encrypt/secure.lua",
  "HyperAuthClient/encrypt/secure.lua",
  "/encrypt/secure.lua",
  "encrypt/secure.lua",
  "/secure.lua",
  "secure.lua",
  "/servers/hyperauth/secure.lua",
  "servers/hyperauth/secure.lua"
}
for _, p in ipairs(secure_candidates) do
  if fs and fs.exists and fs.exists(p) then
    local fn, err = loadfile(p)
    if not fn then
      error("auth_api: Compile error in '" .. p .. "':\n" .. tostring(err), 0)
    end
    local ok, res = pcall(fn)
    if not ok then
      error("auth_api: Runtime error in '" .. p .. "':\n" .. tostring(res), 0)
    end
    secure = res
    break
  end
end
if not secure then
  local ok_sec, res = pcall(require, "HyperAuthClient.encrypt.secure")
  if not ok_sec then ok_sec, res = pcall(require, "HyperAuthClient/encrypt/secure") end
  if not ok_sec then ok_sec, res = pcall(require, "encrypt.secure") end
  if not ok_sec then ok_sec, res = pcall(require, "secure") end
  if ok_sec then
    secure = res
  else
    error("auth_api: failed to load secure module: " .. tostring(res), 0)
  end
end

local cached_server_id = nil

local function get_config()
  package.loaded["HyperAuthClient.config"] = nil
  package.loaded["HyperAuthClient/config"] = nil
  local ok, cfg = pcall(require, "HyperAuthClient/config")
  if not ok then ok, cfg = pcall(require, "HyperAuthClient.config") end
  if ok and type(cfg) == "table" then
    return cfg
  end
  return {
    CLIENT_ID = "drunken_os_server",
    SHARED_SECRET = "01431f1589d73d826c2a9669ab60fa8b",
    PROTOCOL_NAME = "auth.secure.v1",
    DEFAULT_TIMEOUT_SECONDS = 6
  }
end

local function open_modem()
  if peripheral and peripheral.getNames then
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == "modem" and rednet and rednet.open then
        pcall(rednet.open, name)
      end
    end
  else
    for _, s in ipairs({ "left","right","top","bottom","front","back" }) do
      if peripheral.getType(s) == "modem" and rednet and rednet.open then
        pcall(rednet.open, s)
      end
    end
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
  local cfg = get_config()
  local targetProtocol = protocol or cfg.PROTOCOL_NAME or "auth.secure.v1"
  assert(type(targetProtocol) == "string" and #targetProtocol > 0, "protocol required")

  local clientId = cfg.CLIENT_ID or "drunken_os_server"
  local sharedSecret = cfg.SHARED_SECRET or "01431f1589d73d826c2a9669ab60fa8b"
  local timeoutSec = tonumber(cfg.DEFAULT_TIMEOUT_SECONDS) or 6

  open_modem()
  secure.seed_rng()

  local payload = ensure_table(data)
  payload.timestamp_ms = payload.timestamp_ms or secure.now_ms()

  local header = { client_id = clientId, version = "v1" }
  local packet = secure.seal(sharedSecret, header, payload)
  local outer  = { client_id = clientId, packet = packet }

  local serialized = textutils.serialize(outer)
  local destServerId = cfg.KNOWN_SERVER_ID or cached_server_id

  if destServerId then
    rednet.send(destServerId, serialized, targetProtocol)
  else
    rednet.broadcast(serialized, targetProtocol)
  end

  if os.startTimer and os.pullEvent then
    local timerId = os.startTimer(timeoutSec)
    while true do
      local event, p1, p2, p3 = os.pullEvent()
      if event == "timer" and p1 == timerId then
        return nil, "timeout"
      elseif event == "rednet_message" then
        local senderId, replyMsg, replyProto = p1, p2, p3
        if not targetProtocol or replyProto == targetProtocol then
          local okOuter, outerReply = pcall(textutils.unserialize, replyMsg)
          if okOuter and type(outerReply) == "table" then
            if outerReply.error and not outerReply.packet then
              pcall(os.cancelTimer, timerId)
              return nil, outerReply.error
            elseif outerReply.packet then
              local opened, err = secure.open(sharedSecret, header, outerReply.packet)
              if opened then
                pcall(os.cancelTimer, timerId)
                cached_server_id = senderId
                return opened
              end
            end
          end
        end
      end
    end
  else
    local from, reply = rednet.receive(targetProtocol, timeoutSec)
    if not from then return nil, "timeout" end
    cached_server_id = from

    local okOuter, outerReply = pcall(textutils.unserialize, reply)
    if not okOuter or type(outerReply) ~= "table" then return nil, "decode_error" end
    if outerReply.error and not outerReply.packet then return nil, outerReply.error end

    local opened, err = secure.open(sharedSecret, header, outerReply.packet)
    if not opened then return nil, err end
    return opened
  end
end

return { auth = auth }
