--[[
    Drunken OS - NetPkg (GitHub Package Fetcher) v1.0

    Downloads package files straight from the project's GitHub repo (HTTPS raw)
    onto the computer's hard drive, so packages are not limited by floppy size.
    Updates are all-or-nothing: every file is downloaded and syntax-checked
    before anything is written, so a failed/partial download never bricks a PC.
]]
local M = {}
M.BASE = "https://raw.githubusercontent.com/mert-d/Drunken_OS/main/"
M.MANIFEST = "installer/manifest.lua"

-- Fetch one repo-relative file. Returns content or nil, err.
function M.get(rel, base)
    if not (http and http.get) then return nil, "HTTP kapali" end
    local ts = tostring((os.epoch and os.epoch("utc")) or os.time())
    local ok, r = pcall(http.get, (base or M.BASE) .. rel .. "?v=" .. ts)
    if not ok or not r then return nil, "baglanti yok" end
    local code = r.getResponseCode and r.getResponseCode() or 200
    local c = r.readAll()
    pcall(r.close)
    if code ~= 200 or not c or #c == 0 then return nil, "HTTP " .. tostring(code) end
    return c
end

-- Write via temp file + move so a crash mid-write keeps the old file.
function M.write(path, c)
    local d = fs.getDir(path)
    if d and d ~= "" and not fs.exists(d) then fs.makeDir(d) end
    local tmp = path .. ".tmp"
    local f = fs.open(tmp, "w")
    if not f then return false end
    f.write(c)
    f.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

function M.manifest(base)
    local c, e = M.get(M.MANIFEST, base)
    if not c then return nil, e end
    local fn = load(c, "manifest", "t", {})
    local ok, m = pcall(fn or error, "parse")
    if not ok or type(m) ~= "table" then return nil, "manifest bozuk" end
    return m
end

-- Ordered file list of a package: disk files + GitHub-only remote_files.
function M.fileList(pkg)
    local list, seen = {}, {}
    for _, key in ipairs({ "files", "remote_files" }) do
        for _, f in ipairs(pkg[key] or {}) do
            if not seen[f] then seen[f] = true; list[#list + 1] = f end
        end
    end
    return list
end

-- Install/update every file of a package. opts: base, progress(i, n, rel)
function M.update(pkgId, opts)
    opts = opts or {}
    local m, e = M.manifest(opts.base)
    if not m then return false, e end
    local pkg = m.packages and m.packages[pkgId]
    if not pkg then return false, "paket yok: " .. tostring(pkgId) end
    local list, got = M.fileList(pkg), {}
    for i, rel in ipairs(list) do
        if opts.progress then opts.progress(i, #list, rel) end
        local c, err = M.get(rel, opts.base)
        if not c then return false, rel .. ": " .. tostring(err) end
        if rel:match("%.lua$") and not load(c, rel) then return false, rel .. ": syntax" end
        got[i] = c
    end
    for i, rel in ipairs(list) do
        if not M.write("/" .. rel, got[i]) then return false, rel .. ": yazilamadi" end
    end
    return true, #list
end

return M
