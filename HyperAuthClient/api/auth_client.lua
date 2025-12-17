local API = require("HyperAuthClient/api/auth_api")
local config = require("HyperAuthClient/config")

local DEFAULT_PROTOCOL = config.PROTOCOL_NAME or "auth.secure.v1"

local function requestCode(a, b)
  local protocol, opts
  if type(a) == "string" then protocol, opts = a, b else protocol, opts = DEFAULT_PROTOCOL, a end
  assert(type(opts) == "table", "requestCode: table of options required")

  local payload = {
    type        = "request_code",
    username    = assert(opts.username, "username required"),
    request_id  = opts.request_id,
    password    = opts.password,
    computerID  = opts.computerID or os.getComputerID(),
    vendorID    = opts.vendorID,
    extra       = opts.extra,
    timestamp_ms= opts.timestamp_ms,
  }
  return API.auth(protocol, payload)
end

local function verifyCode(a, b)
  local protocol, opts
  if type(a) == "string" then protocol, opts = a, b else protocol, opts = DEFAULT_PROTOCOL, a end
  assert(type(opts) == "table", "verifyCode: table of options required")
  return API.auth(protocol, {
    type         = "verify_code",
    request_id   = assert(opts.request_id, "request_id required"),
    code_entered = tostring(assert(opts.code, "code required")),
    timestamp_ms = opts.timestamp_ms,
  })
end

return { requestCode = requestCode, verifyCode = verifyCode }
