local API = nil
local api_candidates = {
  "/HyperAuthClient/api/auth_api.lua",
  "HyperAuthClient/api/auth_api.lua",
  "/api/auth_api.lua",
  "api/auth_api.lua",
  "/auth_api.lua",
  "auth_api.lua"
}
for _, p in ipairs(api_candidates) do
  if fs and fs.exists and fs.exists(p) then
    local fn, err = loadfile(p)
    if not fn then
      error("auth_client: Compile error in '" .. p .. "':\n" .. tostring(err), 0)
    end
    if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
    local ok, res = pcall(fn)
    if not ok then
      error("auth_client: Runtime error in '" .. p .. "':\n" .. tostring(res), 0)
    end
    API = res
    break
  end
end
if not API then
  local ok_api, res = pcall(require, "HyperAuthClient.api.auth_api")
  if not ok_api then ok_api, res = pcall(require, "HyperAuthClient/api/auth_api") end
  if not ok_api then ok_api, res = pcall(require, "api.auth_api") end
  if not ok_api then ok_api, res = pcall(require, "auth_api") end
  if ok_api then
    API = res
  else
    error("auth_client: failed to load auth_api: " .. tostring(res), 0)
  end
end

local function get_config()
  local candidates = {
    "/HyperAuthClient/config.lua",
    "HyperAuthClient/config.lua",
    "/config.lua",
    "config.lua"
  }
  for _, p in ipairs(candidates) do
    if fs and fs.exists and fs.exists(p) then
      local fn, err = loadfile(p)
      if fn then
        if setfenv and getfenv then pcall(setfenv, fn, getfenv()) end
        local ok, cfg = pcall(fn)
        if ok and type(cfg) == "table" then
          return cfg
        end
      end
    end
  end

  if package and package.loaded then
    package.loaded["HyperAuthClient.config"] = nil
    package.loaded["HyperAuthClient/config"] = nil
  end
  if require then
    local ok, cfg = pcall(require, "HyperAuthClient/config")
    if not ok then ok, cfg = pcall(require, "HyperAuthClient.config") end
    if ok and type(cfg) == "table" then
      return cfg
    end
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
