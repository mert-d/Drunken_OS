  local args = { ... }
if #args < 4 then
  print("Usage: ghsub <user> <repo> <branch> <remote_prefix> [strip_prefix]")
  return
end

local user, repo, branch, remote_prefix, strip_prefix =
  args[1], args[2], args[3], args[4], args[5] or args[4]

local function urlencode(s) return s:gsub("[^%w%-_%.~]", function(c)
  return string.format("%%%02X", string.byte(c))
end) end

local function http_get(url, headers)
  local h = { ["User-Agent"]="HyperAuth-CC", ["Accept"]="application/vnd.github+json" }
  if headers then for k,v in pairs(headers) do h[k]=v end end
  local r = http.get(url, h)
  if not r then error("HTTP GET failed: "..url) end
  local b = r.readAll(); r.close(); return b
end

local function ensure_dirs(path)
  local parts = {}
  for p in path:gmatch("[^/]+") do parts[#parts+1]=p end
  table.remove(parts)
  local cur=""
  for i=1,#parts do
    cur = cur.."/"..parts[i]
    if not fs.exists(cur) then fs.makeDir(cur) end
  end
end

local api = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1")
  :format(urlencode(user), urlencode(repo), urlencode(branch))
local body = http_get(api)
local ok, tree = pcall(textutils.unserializeJSON, body)
if not ok or type(tree)~="table" or type(tree.tree)~="table" then
  error("Bad GitHub API response.")
end

local n=0
for _, node in ipairs(tree.tree) do
  if node.type=="blob" and type(node.path)=="string" then
    if node.path:sub(1, #remote_prefix) == remote_prefix then
      local base = strip_prefix
      if node.path:sub(1, #base) ~= base then base = remote_prefix end
      local rel = node.path:sub(#base + 1)
      local local_path = "/" .. rel
      local raw = ("https://raw.githubusercontent.com/%s/%s/%s/%s")
        :format(urlencode(user), urlencode(repo), urlencode(branch), urlencode(node.path))
      local content = http_get(raw, {["Accept"]="*/*"})
      ensure_dirs(local_path)
      local f = fs.open(local_path, "w"); f.write(content); f.close()
      print("Wrote: "..local_path); n=n+1
    end
  end
end

print(("Done. %d file(s) installed."):format(n))
if n==0 then print("Nothing matched. Check branch/paths.") end
