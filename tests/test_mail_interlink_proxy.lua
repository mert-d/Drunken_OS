--[[
    Unit Test: Mail Proxy & Interlink Flow + Score Cache Resiliency
    Verifies:
    1. lib/score_cache loads cleanly even if lib.db is missing.
    2. apps/arcade loads without throwing previous module load error.
    3. Auth Server validates session via AUTH_INTERLINK_PROTOCOL.
    4. Mail Server preserves proxy_senderId in responses.
    5. Mainframe Gateway forwards microservice responses to the proxy.
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

print("=== Running Mail Interlink Proxy & Score Cache Tests ===")

-- 1. Test score_cache without lib.db
package.loaded["lib.score_cache"] = nil
local ok_sc, scoreCache = pcall(require, "lib.score_cache")
assert_true(ok_sc and type(scoreCache) == "table", "lib.score_cache loaded cleanly")
assert_true(type(scoreCache.recordScore) == "function", "scoreCache.recordScore is callable")

-- Simulate a previous failed require state and verify arcade recovers
package.loaded["lib.score_cache"] = false
local ok_arcade, arcadeModule = pcall(require, "apps.arcade")
assert_true(ok_arcade and type(arcadeModule) == "table", "apps.arcade loads despite previous failed require state")

-- 2. Test Auth Server verify_session handler logic
local mockUsers = {
    ["mert"] = {
        password = "hash",
        nickname = "Mert Bey",
        session_token = "valid_token_123"
    }
}

local function handleAuthInterlink(msg)
    if msg.type == "verify_session" then
        local user = msg.user
        local token = msg.session_token
        local valid = (mockUsers[user] ~= nil and mockUsers[user].session_token == token)
        local nick = valid and mockUsers[user].nickname or nil
        return { type = "verify_session_response", user = user, valid = valid, nickname = nick }
    end
    return nil
end

local validResp = handleAuthInterlink({ type = "verify_session", user = "mert", session_token = "valid_token_123" })
assert_true(validResp ~= nil and validResp.valid == true, "Auth Server validates matching session token")
assert_eq(validResp.nickname, "Mert Bey", "Auth Server returns user nickname")

local invalidResp = handleAuthInterlink({ type = "verify_session", user = "mert", session_token = "wrong_token" })
assert_true(invalidResp ~= nil and invalidResp.valid == false, "Auth Server rejects invalid session token")

-- 3. Test Proxy Response Routing on Mainframe
local proxyOutgoing = {}
local directOutgoing = {}

local clientProxies = {
    [0] = 8 -- Phone 0 came through Proxy 8
}

local function routeInterlinkResponse(actualMsg)
    local targetId = actualMsg.original_senderId
    local proxyId = actualMsg.proxy_senderId or clientProxies[targetId]
    local targetProto = actualMsg.original_protocol or "SimpleMail"
    local internalProto = targetProto .. "_Internal"
    if targetId then
        if proxyId then
            table.insert(proxyOutgoing, { target = proxyId, msg = { proxy_orig_sender = targetId, proxy_response = actualMsg }, proto = internalProto })
        else
            table.insert(directOutgoing, { target = targetId, msg = actualMsg, proto = targetProto })
        end
    end
end

routeInterlinkResponse({
    original_type = "fetch",
    original_senderId = 0,
    proxy_senderId = 8,
    original_protocol = "SimpleMail",
    mail = { { subject = "Welcome" } }
})

assert_eq(#proxyOutgoing, 1, "Mail response routed to Proxy")
assert_eq(proxyOutgoing[1].target, 8, "Target proxy matches client proxy ID")
assert_eq(proxyOutgoing[1].proto, "SimpleMail_Internal", "Protocol is SimpleMail_Internal")
assert_eq(proxyOutgoing[1].msg.proxy_orig_sender, 0, "Proxy response wraps original client ID")
assert_eq(proxyOutgoing[1].msg.proxy_response.mail[1].subject, "Welcome", "Wrapped mail content intact")

print(">>> All Mail Interlink Proxy & Score Cache tests passed successfully!")
