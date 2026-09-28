--[[
    Unit Test: Installer Disk Creation & Boot Simulation (tests/test_installer.lua)
    
    Verifies:
    1. Manifest integrity & file existence for all packages.
    2. Server Gateway disk footprint fits strictly within CC:Tweaked floppy limit (125,000 bytes).
    3. Mock disk creation with standard 125,000 byte capacity.
    4. Clean computer boot from disk, automated installation, file copying, startup configuration.
    5. Root startup execution resolving /.program_path to Drunken_OS_Server.lua.
]]

package.path = "./?.lua;" .. package.path

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

local function assert_true(cond, desc)
    if not cond then
        error("FAILED [" .. desc .. "]: condition was false", 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Drunken OS Installer & Boot Simulation Tests ===")

-- 1. Load manifest and verify files
local manifest = require("manifest")
assert_true(type(manifest) == "table", "Manifest loaded successfully")
assert_true(type(manifest.packages) == "table", "Packages table present")

local serverPkg = manifest.packages.server
assert_true(serverPkg ~= nil, "Server package defined in manifest")
assert_eq(serverPkg.type, "server", "Server package type is server")
assert_eq(serverPkg.main, "servers/Drunken_OS_Server.lua", "Server main program path")

-- 2. Verify all server package files exist on local disk and calculate total size
local totalPkgBytes = 0
for _, relPath in ipairs(serverPkg.files) do
    local f = io.open(relPath, "rb")
    assert_true(f ~= nil, "Package file exists: " .. relPath)
    local content = f:read("*a")
    f:close()
    totalPkgBytes = totalPkgBytes + #content
end
print(string.format("  INFO: Server package raw file size: %d bytes (%.2f KB)", totalPkgBytes, totalPkgBytes / 1024))

-- Verify installer templates exist
local f_tmpl = io.open("installer/install_template.lua", "rb")
assert_true(f_tmpl ~= nil, "install_template.lua exists")
local installTemplateCode = f_tmpl:read("*a")
f_tmpl:close()

local f_srv_tmpl = io.open("installer/server_startup_template.lua", "rb")
assert_true(f_srv_tmpl ~= nil, "server_startup_template.lua exists")
local srvStartupCode = f_srv_tmpl:read("*a")
f_srv_tmpl:close()

local dummyConfig = {
    name = serverPkg.name,
    type = serverPkg.type,
    main_program = serverPkg.main,
    files = serverPkg.files,
    needs_setup = false
}
-- Use textutils or fallback serializer
local configStr = "{\n"
for k, v in pairs(dummyConfig) do
    if type(v) == "table" then
        configStr = configStr .. "  " .. k .. " = {\n"
        for _, item in ipairs(v) do
            configStr = configStr .. "    \"" .. item .. "\",\n"
        end
        configStr = configStr .. "  },\n"
    elseif type(v) == "string" then
        configStr = configStr .. "  " .. k .. " = \"" .. v .. "\",\n"
    elseif type(v) == "boolean" then
        configStr = configStr .. "  " .. k .. " = " .. tostring(v) .. ",\n"
    end
end
configStr = configStr .. "}\n"

local totalDiskBytes = totalPkgBytes + #installTemplateCode + #srvStartupCode + #configStr
print(string.format("  INFO: Total Server Gateway disk footprint: %d bytes (%.2f KB)", totalDiskBytes, totalDiskBytes / 1024))
local FLOPPY_LIMIT = 125000
assert_true(totalDiskBytes <= FLOPPY_LIMIT, "Server Gateway disk footprint <= 125,000 bytes limit")
local margin = FLOPPY_LIMIT - totalDiskBytes
print(string.format("  INFO: Safety margin remaining on floppy: %d bytes (%.2f KB)", margin, margin / 1024))
assert_true(margin >= 4096, "Safety margin is at least 4 KB (>4096 bytes)")

-- 3. Simulate Master Installer writing to a 125,000 byte mock floppy drive
local diskStorage = {}
local diskUsedBytes = 0

local function mockWriteDisk(relPath, content)
    local needed = #content - (diskStorage[relPath] and #diskStorage[relPath] or 0)
    if diskUsedBytes + needed > FLOPPY_LIMIT then
        return false, "Disk full (exceeded 125,000 bytes)"
    end
    diskStorage[relPath] = content
    diskUsedBytes = diskUsedBytes + needed
    return true
end

-- Write installer files in verified order (critical boot files first)
assert_true(mockWriteDisk("startup.lua", installTemplateCode), "Write disk/startup.lua")
assert_true(mockWriteDisk("startup", 'shell.run("startup.lua")\n'), "Write disk/startup (legacy forwarder)")
assert_true(mockWriteDisk("server_startup.lua", srvStartupCode), "Write disk/server_startup.lua")
assert_true(mockWriteDisk("server_startup", 'shell.run("server_startup.lua")\n'), "Write disk/server_startup (legacy forwarder)")
assert_true(mockWriteDisk("install_config.lua", configStr), "Write disk/install_config.lua")

for _, relPath in ipairs(serverPkg.files) do
    local f = io.open(relPath, "rb")
    local content = f:read("*a")
    f:close()
    assert_true(mockWriteDisk(relPath, content), "Write disk/" .. relPath)
end

assert_true(diskStorage["startup.lua"] ~= nil and #diskStorage["startup.lua"] > 0, "disk/startup.lua is valid & non-empty")
assert_true(diskStorage["startup"] ~= nil and #diskStorage["startup"] > 0, "disk/startup forwarder is valid & non-empty")
assert_true(diskStorage["server_startup.lua"] ~= nil and #diskStorage["server_startup.lua"] > 0, "disk/server_startup.lua is valid & non-empty")
assert_true(diskStorage["server_startup"] ~= nil and #diskStorage["server_startup"] > 0, "disk/server_startup forwarder is valid & non-empty")
assert_true(diskStorage["install_config.lua"] ~= nil and #diskStorage["install_config.lua"] > 0, "disk/install_config.lua is valid & non-empty")

-- 4. Clean Boot & Installation Simulation on Target Advanced Computer
-- Setup mock environment for target machine
local targetRootStorage = {}
local diskEjected = false
local rebootCalled = false

local mockFs = {
    exists = function(path)
        path = path:gsub("^/", "")
        if path:sub(1, 5) == "disk/" then
            local rel = path:sub(6)
            return diskStorage[rel] ~= nil
        elseif path == "disk" then
            return true
        end
        return targetRootStorage[path] ~= nil
    end,
    getDir = function(path)
        local dir = path:match("^(.*)/[^/]+$")
        return dir or ""
    end,
    getName = function(path)
        return path:match("[^/]+$") or path
    end,
    combine = function(base, rel)
        if base == "" or base == "." then return rel end
        base = base:gsub("/+$", "")
        rel = rel:gsub("^/+", "")
        return base .. "/" .. rel
    end,
    makeDir = function(path)
        -- directories are virtual
    end,
    delete = function(path)
        path = path:gsub("^/", "")
        targetRootStorage[path] = nil
    end,
    copy = function(from, to)
        from = from:gsub("^/", "")
        to = to:gsub("^/", "")
        local content = nil
        if from:sub(1, 5) == "disk/" then
            content = diskStorage[from:sub(6)]
        else
            content = targetRootStorage[from]
        end
        if not content then error("No such file: " .. from) end
        targetRootStorage[to] = content
    end,
    open = function(path, mode)
        path = path:gsub("^/", "")
        if mode == "r" then
            local content = nil
            if path:sub(1, 5) == "disk/" then
                content = diskStorage[path:sub(6)]
            else
                content = targetRootStorage[path]
            end
            if not content then return nil end
            local pos = 1
            return {
                readAll = function() return content end,
                readLine = function()
                    if pos > #content then return nil end
                    local nl = content:find("\n", pos, true)
                    local line
                    if nl then
                        line = content:sub(pos, nl - 1)
                        pos = nl + 1
                    else
                        line = content:sub(pos)
                        pos = #content + 1
                    end
                    return line
                end,
                close = function() end
            }
        elseif mode == "w" then
            return {
                write = function(str)
                    targetRootStorage[path] = (targetRootStorage[path] or "") .. tostring(str)
                end,
                close = function() end
            }
        end
        return nil
    end
}

local mockColors = {
    black = 32768, white = 1, cyan = 512, yellow = 16, green = 8192,
    red = 16384, lightGray = 256, orange = 2
}

local mockTerm = {
    isColor = function() return true end,
    setBackgroundColor = function() end,
    setTextColor = function() end,
    clear = function() end,
    setCursorPos = function() end
}

local mockPeripheral = {
    getNames = function() return { "top" } end,
    getType = function(name) return "drive" end,
    find = function(ptype)
        if ptype == "drive" then
            return {
                isDiskPresent = function() return not diskEjected end,
                ejectDisk = function() diskEjected = true end,
                getMountPath = function() return "disk" end
            }
        end
        return nil
    end
}

local mockDisk = {
    getMountPath = function(side) return "disk" end
}

local mockShell = {
    getRunningProgram = function() return "disk/startup.lua" end,
    run = function(cmd) end
}

local mockOs = {
    pullEvent = function(ev) return ev end,
    reboot = function() rebootCalled = true end,
    sleep = function(t) end,
    epoch = function() return 1000000 end
}

local function serializeLuaVal(val)
    if type(val) == "string" then
        return string.format("%q", val)
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    elseif type(val) == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local kStr = type(k) == "number" and ("[" .. k .. "]") or ("[\"" .. tostring(k) .. "\"]")
            table.insert(parts, kStr .. " = " .. serializeLuaVal(v))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    end
    return "nil"
end

local mockTextutils = {
    unserialize = function(str)
        local fn = load("return " .. str)
        if fn then return fn() end
        return nil
    end,
    serialize = function(t)
        if textutils and textutils.serialize then return textutils.serialize(t) end
        return serializeLuaVal(t)
    end
}

-- Execute disk/startup.lua in target machine environment
local env = {
    fs = mockFs,
    term = mockTerm,
    colors = mockColors,
    peripheral = mockPeripheral,
    disk = mockDisk,
    shell = mockShell,
    os = mockOs,
    textutils = mockTextutils,
    sleep = function(t) end,
    print = function(...) end,
    io = { write = function(...) end },
    pcall = pcall,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    string = string,
    table = table,
    ipairs = ipairs,
    pairs = pairs
}

local installChunk, compileErr = load(diskStorage["startup.lua"], "disk/startup.lua", "t", env)
assert_true(installChunk ~= nil, "disk/startup.lua compiled without syntax errors: " .. tostring(compileErr))

local ok_run, runErr = pcall(installChunk)
assert_true(ok_run, "disk/startup.lua executed without runtime errors: " .. tostring(runErr))
assert_true(rebootCalled, "Installer requested system reboot (os.reboot called)")
assert_true(diskEjected, "Installer requested floppy disk ejection (drive.ejectDisk called)")

-- 5. Verify Target Hard Drive Root State Post-Installation
assert_true(targetRootStorage["startup.lua"] ~= nil, "/startup.lua installed on target hard drive")
assert_true(targetRootStorage["startup"] ~= nil, "/startup (legacy forwarder) installed on target hard drive")
assert_true(targetRootStorage[".program_path"] == "servers/Drunken_OS_Server.lua", "/.program_path points to servers/Drunken_OS_Server.lua")
assert_true(targetRootStorage["servers/Drunken_OS_Server.lua"] ~= nil, "Main server program copied to hard drive")
assert_true(targetRootStorage["lib/db.lua"] ~= nil, "lib/db.lua copied to hard drive")
assert_true(targetRootStorage["lib/service_guard.lua"] ~= nil, "lib/service_guard.lua copied to hard drive")
assert_true(targetRootStorage["manifest.lua"] ~= nil, "manifest.lua copied to hard drive")

-- 6. Target Machine Second Boot (Hard Drive Boot)
local launchedProgram = nil
local hdShell = {
    run = function(path) launchedProgram = path end
}
local hdEnv = {
    fs = mockFs,
    shell = hdShell,
    print = function(...) end,
    printError = function(...) end,
    read = function() end,
    pcall = pcall,
    tostring = tostring
}

local rootStartupChunk, rootCompileErr = load(targetRootStorage["startup.lua"], "/startup.lua", "t", hdEnv)
assert_true(rootStartupChunk ~= nil, "/startup.lua compiled cleanly: " .. tostring(rootCompileErr))

local ok_boot, bootErr = pcall(rootStartupChunk)
assert_true(ok_boot, "/startup.lua executed cleanly: " .. tostring(bootErr))
assert_eq(launchedProgram, "servers/Drunken_OS_Server.lua", "Startup booted into Server Gateway program")

-- 7. HyperAuth Server Package Verification & Installation Simulation
local haPkg = manifest.packages.hyperauth_server
assert_true(haPkg ~= nil, "HyperAuth server package defined in manifest")
assert_eq(haPkg.type, "server", "HyperAuth package type is server")
assert_eq(haPkg.main, "servers/HyperAuth_Server.lua", "HyperAuth main program path")

local haPkgBytes = 0
for _, relPath in ipairs(haPkg.files) do
    local f = io.open(relPath, "rb")
    assert_true(f ~= nil, "HyperAuth package file exists: " .. relPath)
    local content = f:read("*a")
    f:close()
    haPkgBytes = haPkgBytes + #content
end
print(string.format("  INFO: HyperAuth server raw file size: %d bytes (%.2f KB)", haPkgBytes, haPkgBytes / 1024))
local haTotalDisk = haPkgBytes + #installTemplateCode + #srvStartupCode + 1024
assert_true(haTotalDisk <= FLOPPY_LIMIT, "HyperAuth package fits comfortably within 125,000 bytes limit")
print(string.format("  INFO: HyperAuth floppy margin remaining: %d bytes (%.2f KB)", FLOPPY_LIMIT - haTotalDisk, (FLOPPY_LIMIT - haTotalDisk) / 1024))

-- Verify vendor registry consistency
local vf = io.open("vendors.jsonl", "r")
assert_true(vf ~= nil, "vendors.jsonl exists in root")
local vContent = vf:read("*a")
vf:close()
assert_true(vContent:find("drunken_os_server") ~= nil, "Configured vendor drunken_os_server is registered in vendors.jsonl")
assert_true(vContent:find("01431f1589d73d826c2a9669ab60fa8b") ~= nil, "Configured secret registered in vendors.jsonl")
assert_true(vContent:find("DrunkenOS_AuthNode") ~= nil, "Default vendor DrunkenOS_AuthNode is registered in vendors.jsonl")
assert_true(vContent:find("drunken_secret_2026") ~= nil, "Default shared secret configured in vendors.jsonl")

-- Verify HyperAuthClient config matches
package.loaded["HyperAuthClient.config"] = nil
package.loaded["HyperAuthClient/config"] = nil
local haConfig = require("HyperAuthClient.config")
assert_eq(haConfig.CLIENT_ID, "drunken_os_server", "HyperAuthClient configured with matching CLIENT_ID")
assert_eq(haConfig.SHARED_SECRET, "01431f1589d73d826c2a9669ab60fa8b", "HyperAuthClient configured with matching SHARED_SECRET")
assert_eq(haConfig.PROTOCOL_NAME, "auth.secure.v1", "HyperAuthClient configured with auth.secure.v1 protocol")

-- Simulate Command Computer installation for HyperAuth Server
local haTargetRoot = {}
local haMockFs = {
    exists = function(path)
        path = path:gsub("^/", "")
        if path:sub(1, 5) == "disk/" then
            local rel = path:sub(6)
            for _, f in ipairs(haPkg.files) do if f == rel then return true end end
            if rel == "startup.lua" or rel == "server_startup.lua" or rel == "install_config.lua" then return true end
            return false
        elseif path == "disk" then
            return true
        end
        return haTargetRoot[path] ~= nil
    end,
    getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
    getName = function(path) return path:match("[^/]+$") or path end,
    combine = function(b, r) return (b == "" or b == ".") and r or (b:gsub("/+$","") .. "/" .. r:gsub("^/+","")) end,
    makeDir = function() end,
    delete = function(p) haTargetRoot[p:gsub("^/","")] = nil end,
    copy = function(from, to)
        from, to = from:gsub("^/",""), to:gsub("^/","")
        if from:sub(1, 5) == "disk/" then
            local rel = from:sub(6)
            local f = io.open(rel, "rb")
            if f then haTargetRoot[to] = f:read("*a"); f:close() end
        else
            haTargetRoot[to] = haTargetRoot[from]
        end
    end,
    open = function(p, m)
        p = p:gsub("^/","")
        if m == "r" then
            local c = nil
            if p:sub(1, 5) == "disk/" then
                local rel = p:sub(6)
                if rel == "install_config.lua" then
                    c = "{\n  name = \"" .. haPkg.name .. "\",\n  type = \"server\",\n  main_program = \"" .. haPkg.main .. "\",\n  files = {\n"
                    for _, file in ipairs(haPkg.files) do c = c .. "    \"" .. file .. "\",\n" end
                    c = c .. "  }\n}\n"
                elseif rel == "server_startup.lua" then
                    c = srvStartupCode
                else
                    local f = io.open(rel, "rb")
                    if f then c = f:read("*a"); f:close() end
                end
            else
                c = haTargetRoot[p]
            end
            if not c then return nil end
            local pos = 1
            return {
                readAll = function() return c end,
                readLine = function()
                    if pos > #c then return nil end
                    local nl = c:find("\n", pos, true)
                    local line = nl and c:sub(pos, nl - 1) or c:sub(pos)
                    pos = nl and (nl + 1) or (#c + 1)
                    return line
                end,
                close = function() end
            }
        elseif m == "w" then
            return {
                write = function(s) haTargetRoot[p] = (haTargetRoot[p] or "") .. tostring(s) end,
                close = function() end
            }
        end
        return nil
    end
}

local haEnv = {
    fs = haMockFs,
    term = mockTerm,
    colors = mockColors,
    peripheral = mockPeripheral,
    disk = mockDisk,
    shell = mockShell,
    os = mockOs,
    textutils = mockTextutils,
    sleep = function() end,
    print = function() end,
    io = { write = function() end },
    pcall = pcall,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    string = string,
    table = table,
    ipairs = ipairs,
    pairs = pairs
}

local haInstallChunk = load(installTemplateCode, "disk/startup.lua", "t", haEnv)
local ok_ha_inst = pcall(haInstallChunk)
assert_true(ok_ha_inst, "HyperAuth installation executed cleanly from disk")
assert_true(haTargetRoot["startup.lua"] ~= nil, "HyperAuth server_startup written to /startup.lua")
assert_true(haTargetRoot["startup"] ~= nil, "HyperAuth /startup legacy forwarder written to Command PC")
assert_true(haTargetRoot[".program_path"] == "servers/HyperAuth_Server.lua", "HyperAuth /.program_path set correctly")
assert_true(haTargetRoot["servers/HyperAuth_Server.lua"] ~= nil, "HyperAuth_Server.lua installed on Command PC")
assert_true(haTargetRoot["servers/hyperauth/secure.lua"] ~= nil, "hyperauth/secure.lua installed on Command PC")
assert_true(haTargetRoot["vendors.jsonl"] ~= nil, "vendors.jsonl installed on Command PC")

-- Simulate Command Computer boot
local haLaunched = nil
local haHdEnv = {
    fs = haMockFs,
    shell = { run = function(cmd) haLaunched = cmd end },
    print = function() end,
    printError = function() end,
    read = function() end,
    pcall = pcall,
    tostring = tostring
}
local haBootChunk = load(haTargetRoot["startup.lua"], "/startup.lua", "t", haHdEnv)
local ok_ha_boot = pcall(haBootChunk)
assert_true(ok_ha_boot, "Command Computer booted HyperAuth startup.lua")
assert_eq(haLaunched, "servers/HyperAuth_Server.lua", "Command PC launched HyperAuth_Server.lua")

-- 8. Verify Authentication Authority Server (auth_server) Package & Boot
local authPkg = manifest.packages.auth_server
assert_true(authPkg ~= nil, "Auth server package defined in manifest")
assert_eq(authPkg.type, "server", "Auth server package type is server")
assert_eq(authPkg.main, "servers/Drunken_OS_AuthServer.lua", "Auth server main program path")

local authPkgBytes = 0
for _, relPath in ipairs(authPkg.files) do
    local f = io.open(relPath, "rb")
    assert_true(f ~= nil, "Auth package file exists: " .. relPath)
    local content = f:read("*a")
    f:close()
    authPkgBytes = authPkgBytes + #content
end
print(string.format("  INFO: Auth server raw file size: %d bytes (%.2f KB)", authPkgBytes, authPkgBytes / 1024))
assert_true(authPkgBytes <= 125000, "Auth server package fits comfortably within 125,000 bytes limit")

-- Simulate Auth Server disk installation
local authMockDisk = {}
local authTargetRoot = {}

authMockDisk["startup.lua"] = installTemplateCode
authMockDisk["startup"] = 'shell.run("startup.lua")\n'
authMockDisk["server_startup.lua"] = srvStartupCode
authMockDisk["server_startup"] = 'shell.run("server_startup.lua")\n'
local authConfigData = {
    name = authPkg.name,
    type = authPkg.type,
    main_program = authPkg.main,
    files = authPkg.files
}
authMockDisk["install_config.lua"] = mockTextutils.serialize(authConfigData)
for _, fpath in ipairs(authPkg.files) do
    local f = io.open(fpath, "rb")
    authMockDisk[fpath] = f:read("*a")
    f:close()
end

local authMockFs = {
    combine = function(a, b)
        if a == "" or a == "/" then return b end
        if b == "" then return a end
        return a:gsub("/+$", "") .. "/" .. b:gsub("^/+", "")
    end,
    getDir = function(p)
        local d = p:match("^(.-)/[^/]+$")
        return d or ""
    end,
    getName = function(p) return p:match("[^/]+$") or p end,
    exists = function(p)
        local np = p:gsub("^/+", "")
        if np:sub(1, 5) == "disk/" then
            local rel = np:sub(6)
            return authMockDisk[rel] ~= nil
        end
        return authTargetRoot[np] ~= nil
    end,
    open = function(p, mode)
        local np = p:gsub("^/+", "")
        if mode == "r" then
            local data = nil
            if np:sub(1, 5) == "disk/" then
                data = authMockDisk[np:sub(6)]
            else
                data = authTargetRoot[np]
            end
            if not data then return nil end
            return {
                readAll = function() return data end,
                close = function() end
            }
        elseif mode == "w" then
            return {
                write = function(content)
                    authTargetRoot[np] = content
                end,
                close = function() end
            }
        end
    end,
    copy = function(src, dest)
        local nsrc = src:gsub("^/+", "")
        local ndest = dest:gsub("^/+", "")
        local data = nil
        if nsrc:sub(1, 5) == "disk/" then
            data = authMockDisk[nsrc:sub(6)]
        else
            data = authTargetRoot[nsrc]
        end
        if data then
            authTargetRoot[ndest] = data
            return true
        end
        return false, "file not found"
    end,
    delete = function(p)
        local np = p:gsub("^/+", "")
        authTargetRoot[np] = nil
    end,
    makeDir = function() end,
    getSize = function(p)
        local np = p:gsub("^/+", "")
        local d = authTargetRoot[np] or (np:sub(1, 5) == "disk/" and authMockDisk[np:sub(6)])
        return d and #d or 0
    end
}

local authEnv = {
    fs = authMockFs,
    term = mockTerm,
    colors = mockColors,
    peripheral = mockPeripheral,
    disk = mockDisk,
    shell = mockShell,
    os = mockOs,
    textutils = mockTextutils,
    sleep = function() end,
    print = function() end,
    io = { write = function() end },
    pcall = pcall,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    string = string,
    table = table,
    ipairs = ipairs,
    pairs = pairs
}

local authInstallChunk = load(installTemplateCode, "disk/startup.lua", "t", authEnv)
local ok_auth_inst = pcall(authInstallChunk)
assert_true(ok_auth_inst, "Auth Server installation executed cleanly from disk")
assert_true(authTargetRoot["startup.lua"] ~= nil, "Auth Server startup written to /startup.lua")
assert_true(authTargetRoot["startup"] ~= nil, "Auth Server /startup legacy forwarder written")
assert_true(authTargetRoot[".program_path"] == "servers/Drunken_OS_AuthServer.lua", "Auth Server /.program_path set correctly")
assert_true(authTargetRoot["servers/Drunken_OS_AuthServer.lua"] ~= nil, "Auth Server main program installed")
assert_true(authTargetRoot["HyperAuthClient/api/auth_client.lua"] ~= nil, "HyperAuthClient auth_client.lua installed")
assert_true(authTargetRoot["HyperAuthClient/encrypt/secure.lua"] ~= nil, "HyperAuthClient secure.lua installed")
assert_true(authTargetRoot["HyperAuthClient/encrypt/sha1.lua"] ~= nil, "HyperAuthClient sha1.lua installed")

-- Simulate Auth Server computer boot
local authLaunched = nil
local authHdEnv = {
    fs = authMockFs,
    shell = { run = function(cmd) authLaunched = cmd end },
    print = function() end,
    printError = function() end,
    read = function() end,
    pcall = pcall,
    tostring = tostring
}
local authBootChunk = load(authTargetRoot["startup.lua"], "/startup.lua", "t", authHdEnv)
local ok_auth_boot = pcall(authBootChunk)
assert_true(ok_auth_boot, "Advanced Computer booted Auth Server startup.lua")
assert_eq(authLaunched, "servers/Drunken_OS_AuthServer.lua", "Advanced Computer launched Drunken_OS_AuthServer.lua")

print(">>> All Installer & Boot Simulation tests passed successfully!")
