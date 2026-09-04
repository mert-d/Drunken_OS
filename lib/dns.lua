--[[
    Drunken OS - Universal DNS & Service Discovery Cache (lib/dns.lua)
    Version: 1.0
    
    Caches Rednet service discovery queries with a configurable TTL (default 60s)
    to eliminate wireless broadcast storms on high-concurrency servers.
    Provides dns.patchRednet() to automatically accelerate all existing rednet.lookup calls.
]]

local dns = {
    _VERSION = "1.0",
    DEFAULT_TTL = 60 -- 60 seconds
}

local cache = {}
local stats = { hits = 0, misses = 0 }
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

--- Looks up a computer ID hosting the specified protocol and optional hostname.
-- Returns cached ID if still valid within TTL, otherwise executes network discovery.
-- @param protocol string: The Rednet protocol name.
-- @param hostname string: (Optional) The registered service hostname.
-- @param ttl number: (Optional) Cache lifetime in seconds (defaults to 60).
-- @return number|nil: The resolved computer ID, or nil if offline.
function dns.lookup(protocol, hostname, ttl)
    if not protocol then return nil end
    local maxAge = ttl or dns.DEFAULT_TTL
    local key = makeKey(protocol, hostname)
    local now = getEpochSeconds()
    
    local entry = cache[key]
    if entry and (now - entry.timestamp) < maxAge then
        stats.hits = stats.hits + 1
        return entry.id
    end
    
    stats.misses = stats.misses + 1
    
    local lookupFn = rawLookup or (rednet and rednet.lookup)
    if not lookupFn then return nil end
    
    local id
    if hostname then
        id = lookupFn(protocol, hostname)
    else
        id = lookupFn(protocol)
    end
    
    if id then
        cache[key] = { id = id, timestamp = now }
    end
    
    return id
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
end

--- Flushes all cached DNS records completely.
function dns.flush()
    cache = {}
end

--- Returns cache performance metrics.
-- @return table: { hits = number, misses = number, entries = number }
function dns.getStats()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    return {
        hits = stats.hits,
        misses = stats.misses,
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
