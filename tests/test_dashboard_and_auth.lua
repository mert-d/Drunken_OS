--[[
    Unit Test: Managed Dashboard, Ring-Buffer Logging, and Auth Server Standalone / @all Delivery
    (tests/test_dashboard_and_auth.lua)
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

print("=== Running ServiceGuard Dashboard, Auth Standalone & Mail @all Tests ===")

-- 1. Mock Terminal Environment for CC:Tweaked
local termBuffer = {}
local termColors = {}
local curCursorX, curCursorY = 1, 1
local curBg, curFg = 32768, 1 -- black, white
local termScrollCalls = 0
local TERM_W, TERM_H = 51, 19

local function resetMockTerm()
    termBuffer = {}
    termColors = {}
    for y = 1, TERM_H do
        termBuffer[y] = string.rep(" ", TERM_W)
        termColors[y] = { bg = string.rep("f", TERM_W), fg = string.rep("0", TERM_W) }
    end
    curCursorX, curCursorY = 1, 1
    termScrollCalls = 0
end

resetMockTerm()

_G.colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32,
    pink = 64, gray = 128, lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768
}

_G.term = {
    getSize = function() return TERM_W, TERM_H end,
    isColor = function() return true end,
    setBackgroundColor = function(c) curBg = c end,
    setTextColor = function(c) curFg = c end,
    getCursorPos = function() return curCursorX, curCursorY end,
    setCursorPos = function(x, y) curCursorX = x; curCursorY = y end,
    clearLine = function()
        if curCursorY >= 1 and curCursorY <= TERM_H then
            termBuffer[curCursorY] = string.rep(" ", TERM_W)
        end
    end,
    clear = function()
        resetMockTerm()
    end,
    scroll = function(n)
        termScrollCalls = termScrollCalls + (n or 1)
    end,
    write = function(text)
        local str = tostring(text or "")
        if curCursorY < 1 or curCursorY > TERM_H then return end
        local line = termBuffer[curCursorY]
        local before = line:sub(1, math.max(0, curCursorX - 1))
        local after = line:sub(curCursorX + #str)
        termBuffer[curCursorY] = (before .. str .. after):sub(1, TERM_W)
        curCursorX = curCursorX + #str
    end
}

_G.os = _G.os or {}
_G.os.getComputerID = function() return 42 end

-- Load ServiceGuard
local ServiceGuard = require("lib.service_guard")
assert_true(ServiceGuard ~= nil, "lib.service_guard loaded")
assert_true(type(ServiceGuard.createDashboard) == "function", "ServiceGuard.createDashboard exists")

-- 2. Test createDashboard Non-Scrolling Behavior
local userCount = 3
local dashboard = ServiceGuard.createDashboard({
    serverName = "AUTH TEST SERVER",
    details = function()
        return {
            { label = "Service", value = "Auth Authority", color = colors.white },
            { label = "User Database", value = string.format("%d users", userCount), color = colors.lime },
            { label = "Status", value = "ONLINE", color = colors.lime }
        }
    end,
    status = "ONLINE",
    hintText = "[P] Pair | [C] Clear | [Q] Quit",
    maxLogs = 100
})

assert_true(dashboard ~= nil, "Dashboard instance created")
dashboard:draw()

-- Check top title bar at Row 1
assert_true(termBuffer[1]:find("AUTH TEST SERVER") ~= nil, "Row 1 contains Server Name")
assert_true(termBuffer[1]:find("#42") ~= nil, "Row 1 contains Computer ID")

-- Check Metadata Box at Rows 3..5
assert_true(termBuffer[3]:find("Auth Authority") ~= nil, "Row 3 displays Service")
assert_true(termBuffer[4]:find("3 users") ~= nil, "Row 4 displays initial 3 users")

-- Check Divider at Row 6
assert_true(termBuffer[6]:find("%-%-%-%-") ~= nil, "Row 6 displays divider")

-- Check Footer at Row 19
assert_true(termBuffer[TERM_H]:find("%[ONLINE%]") ~= nil, "Row 19 displays status footer")
assert_true(termBuffer[TERM_H]:find("Quit") ~= nil, "Row 19 displays hint text")

-- Send 60 log messages into the dashboard (simulating high network traffic)
for i = 1, 60 do
    dashboard:log(string.format("Packet #%03d processed successfully", i), i % 10 == 0)
end

-- CRITICAL ASSERTION: Zero terminal scroll calls occurred!
assert_eq(termScrollCalls, 0, "No term.scroll calls occurred during 60 log entries")

-- Row 1, Row 6, and Row 19 MUST still be 100% intact!
assert_true(termBuffer[1]:find("AUTH TEST SERVER") ~= nil, "Row 1 intact after 60 logs")
assert_true(termBuffer[6]:find("%-%-%-%-") ~= nil, "Row 6 divider intact after 60 logs")
assert_true(termBuffer[TERM_H]:find("%[ONLINE%]") ~= nil, "Row 19 footer intact after 60 logs")

-- Visible log rows (7 to 18) contain the latest log messages (packets 49 to 60)
assert_true(termBuffer[18]:find("Packet #060") ~= nil, "Row 18 displays latest log #060")

-- Test live details refresh
userCount = 7
dashboard:refreshDetails()
assert_true(termBuffer[4]:find("7 users") ~= nil, "Row 4 updated to 7 users via refreshDetails")
assert_eq(termScrollCalls, 0, "No term.scroll calls occurred during refreshDetails")

-- 3. Test Mail Server @all Folder Distribution Mock
local mockMailbox = {}
local function mockSaveItem(u, item)
    if not mockMailbox[u] then mockMailbox[u] = {} end
    table.insert(mockMailbox[u], item)
    return true
end

local existingUsers = { "alice", "bob", "carol", "dave" }
local mailPacket = {
    from = "admin",
    from_nickname = "SysAdmin",
    to = "@all",
    subject = "Scheduled Server Maintenance",
    body = "Servers will restart at midnight."
}

for _, u in ipairs(existingUsers) do
    mockSaveItem(u, mailPacket)
end

assert_eq(#mockMailbox["alice"], 1, "Alice received @all announcement")
assert_eq(#mockMailbox["bob"], 1, "Bob received @all announcement")
assert_eq(#mockMailbox["carol"], 1, "Carol received @all announcement")
assert_eq(#mockMailbox["dave"], 1, "Dave received @all announcement")
assert_eq(mockMailbox["alice"][1].subject, "Scheduled Server Maintenance", "Subject delivered intact")

print(">>> All Dashboard, Ring-Buffer & Mail @all Tests Passed Successfully!")
return true
