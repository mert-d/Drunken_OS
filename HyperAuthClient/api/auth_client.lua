local API = require("HyperAuthClient/api/auth_api")

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
    PROTOCOL_NAME = "auth.secure.v1"
  }
end

local function requestCode(a, b)
  local cfg = get_config()
  local defaultProto = cfg.PROTOCOL_NAME or "auth.secure.v1"
  local protocol, opts
  if type(a) == "string" then protocol, opts = a, b else protocol, opts = defaultProto, a end
  assert(type(opts) == "table", "requestCode: table of options required")

  local payload = {
    type        = "request_code",
    username    = assert(opts.username, "username required"),
    request_id  = opts.request_id,
    password    = opts.password,
    computerID  = opts.computerID or os.getComputerID(),
    vendorID    = opts.vendorID or cfg.CLIENT_ID or "drunken_os_server",
    extra       = opts.extra,
    timestamp_ms= opts.timestamp_ms,
  }
  return API.auth(protocol, payload)
end

local function verifyCode(a, b)
  local cfg = get_config()
  local defaultProto = cfg.PROTOCOL_NAME or "auth.secure.v1"
  local protocol, opts
  if type(a) == "string" then protocol, opts = a, b else protocol, opts = defaultProto, a end
  assert(type(opts) == "table", "verifyCode: table of options required")
  return API.auth(protocol, {
    type         = "verify_code",
    request_id   = assert(opts.request_id, "request_id required"),
    code_entered = tostring(assert(opts.code, "code required")),
    timestamp_ms = opts.timestamp_ms,
  })
end

return { requestCode = requestCode, verifyCode = verifyCode }
