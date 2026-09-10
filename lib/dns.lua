--[[
    Drunken OS - Universal DNS & Service Discovery Cache (lib/dns.lua)
    Version: 1.1
    
    Caches Rednet service discovery queries with a configurable TTL (default 60s)
    to eliminate wireless broadcast storms on high-concurrency servers.
    Provides Stale-While-Revalidate fallback: if remote chunks are sleeping,
    unloaded, or undergoing packet loss, previously verified server IDs
    are returned seamlessly.
    Provides persistent on-disk cache (.dns_cache.db) across reboots.
    Provides dns.patchRednet() to automatically accelerate all existing rednet.lookup calls.
]]

local dns = {
    _VERSION = "1.1",
    DEFAULT_TTL = 60, -- 60 seconds
    CACHE_FILE = ".dns_cache.db"
}

local cache = {}
local stats = { hits = 0, misses = 0, stale_hits = 0 }
local rawLookup = nil
local isPatched = false

local function getEpochSeconds()
    if os.epoch then
        return os.epoch("utc") / 1000
    elseif os.clock then
        return os.clock()
    elseif os.time then
        return os.time()
    end
    return 0
end

--- Generates a unique cache key for a protocol and hostname pair
local function makeKey(protocol, hostname)
    return tostring(protocol or "") .. ":" .. tostring(hostname or "")
end

--- Loads cached DNS entries from local disk if available
function dns.loadCache()
    if fs and fs.exists and fs.exists(dns.CACHE_FILE) then
        pcall(function()
            local h = fs.open(dns.CACHE_FILE, "r")
            if h then
                local content = h.readAll()
                h.close()
                if content and #content > 0 then
                    local loaded = textutils.unserialize(content)
                    if type(loaded) == "table" then
                        cache = loaded
                    end
                end
            end
        end)
    end
end

--- Persists active DNS cache entries to local disk
function dns.saveCache()
    if fs and fs.open then
        pcall(function()
            local tmp = dns.CACHE_FILE .. ".tmp"
            local h = fs.open(tmp, "w")
            if h then
                h.write(textutils.serialize(cache))
                h.close()
                if fs.exists(dns.CACHE_FILE) then
                    fs.delete(dns.CACHE_FILE)
                end
                fs.move(tmp, dns.CACHE_FILE)
            end
        end)
    end
end

-- Initialize persistent cache on load
dns.loadCache()

--- Looks up a computer ID hosting the specified protocol and optional hostname.
-- Returns fresh cached ID if within TTL. If expired or missing, queries the network.
-- If network query fails (e.g. chunk sleeping or unloaded), falls back to stale cache if allowStale ~= false.
-- @param protocol string: The Rednet protocol name.
-- @param hostname string: (Optional) The registered service hostname.
-- @param ttl number: (Optional) Cache lifetime in seconds (defaults to 60).
-- @param allowStale boolean: (Optional) Fall back to expired cached ID if network lookup fails (default true).
-- @return number|nil: The resolved computer ID, or nil if offline.
function dns.lookup(protocol, hostname, ttl, allowStale)
    if not protocol then return nil end
    local maxAge = ttl or dns.DEFAULT_TTL
    local key = makeKey(protocol, hostname)
    local now = getEpochSeconds()
    if allowStale == nil then allowStale = true end
    
    local entry = cache[key]
    if entry and (now - entry.timestamp) < maxAge then
        stats.hits = stats.hits + 1
        return entry.id
    end
    
    stats.misses = stats.misses + 1
    
    local lookupFn = rawLookup or (rednet and rednet.lookup)
    local id
    if lookupFn then
        if hostname then
            id = lookupFn(protocol, hostname)
        else
            id = lookupFn(protocol)
        end
    end
    
    if id then
        cache[key] = { id = id, timestamp = now }
        dns.saveCache()
        return id
    end
    
    -- Stale-While-Revalidate Fallback:
    -- If network lookup returned nil (chunk unloaded, server sleeping, or radio packet drop),
    -- return last known good server ID if allowed.
    if allowStale and entry and entry.id then
        stats.stale_hits = stats.stale_hits + 1
        return entry.id
    end
    
    return nil
end

--- Purges a cached record, forcing the next lookup to query the network.
-- Call this when a message to a cached server times out or fails.
-- @param protocol string: The protocol name to invalidate.
-- @param hostname string: (Optional) The specific hostname. If omitted, all records for the protocol are purged.
function dns.invalidate(protocol, hostname)
    if not protocol then return end
    if hostname ~= nil then
        cache[makeKey(protocol, hostname)] = nil
    else
        local prefix = tostring(protocol) .. ":"
        for k in pairs(cache) do
            if k:sub(1, #prefix) == prefix then
                cache[k] = nil
            end
        end
    end
    dns.saveCache()
end

--- Flushes all cached DNS records completely from memory and disk.
function dns.flush()
    cache = {}
    if fs and fs.exists and fs.delete and fs.exists(dns.CACHE_FILE) then
        pcall(fs.delete, dns.CACHE_FILE)
    end
end

--- Returns cache performance metrics.
-- @return table: { hits = number, misses = number, stale_hits = number, entries = number }
function dns.getStats()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    return {
        hits = stats.hits,
        misses = stats.misses,
        stale_hits = stats.stale_hits,
        entries = count
    }
end

--- Automatically monkey-patches _G.rednet.lookup so all legacy scripts benefit from DNS caching.
-- Safe to call multiple times (idempotent).
function dns.patchRednet()
    if isPatched or not _G.rednet or not _G.rednet.lookup then return end
    rawLookup = _G.rednet.lookup
    _G.rednet.lookup = function(protocol, hostname)
        return dns.lookup(protocol, hostname)
    end
    isPatched = true
end

--- Restores original _G.rednet.lookup behavior.
function dns.unpatchRednet()
    if not isPatched then return end
    if _G.rednet and rawLookup then
        _G.rednet.lookup = rawLookup
    end
    rawLookup = nil
    isPatched = false
end

return dns
