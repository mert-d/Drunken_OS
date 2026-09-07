--[[
    Unit Test: Task Manager & Notification Daemon (lib/task_manager.lua)
    Verifies coroutine multitasking, event transparency, toast overlays, and task switching.
]]

package.path = "./?.lua;" .. package.path

local redrawnWindows = {}
local canceledTimers = {}
local activeTimers = {}
local nextTimer = 100

_G.colors = _G.colors or {
    white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16,
    lime = 32, pink = 64, gray = 128, lightGray = 256, cyan = 512,
    purple = 1024, blue = 2048, brown = 4096, green = 8192,
    red = 16384, black = 32768
}

local mockTerm = {
    getSize = function() return 26, 20 end,
    clear = function() end,
    setCursorPos = function(x, y) end,
    getCursorPos = function() return 1, 1 end,
    setTextColor = function(c) end,
    setBackgroundColor = function(c) end,
    write = function(s) end,
    current = function() return mockTerm end,
    redirect = function(t) return t end
}
_G.term = mockTerm

_G.window = {
    create = function(parent, x, y, w, h, visible)
        local winObj = {
            _x = x, _y = y, _w = w, _h = h, _visible = visible,
            _redrawCount = 0
        }
        winObj.getSize = function() return w, h end
        winObj.setVisible = function(v) winObj._visible = v end
        winObj.redraw = function()
            winObj._redrawCount = winObj._redrawCount + 1
            table.insert(redrawnWindows, winObj)
        end
        winObj.restoreCursor = function() end
        winObj.clear = function() end
        winObj.setCursorPos = function() end
        winObj.setTextColor = function() end
        winObj.setBackgroundColor = function() end
        winObj.write = function() end
        return winObj
    end
}

_G.os = _G.os or {}
_G.os.startTimer = function(dur)
    nextTimer = nextTimer + 1
    activeTimers[nextTimer] = dur
    return nextTimer
end
_G.os.cancelTimer = function(id)
    table.insert(canceledTimers, id)
    activeTimers[id] = nil
end

local TaskManager = require("lib.task_manager")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Task Manager & Notification Daemon Tests ===")

-- 1. Initialization
TaskManager.init({ username = "MertD" })
assert_eq(type(TaskManager.getTasks()), "table", "Tasks list initialized")
assert_eq(#TaskManager.getTasks(), 0, "Tasks list starts empty")

-- 2. Create Task & Coroutine Execution
local task1Events = {}
local task1 = TaskManager.createTask("GameLoop", function(ctx)
    while true do
        local ev, p1, p2 = coroutine.yield("timer")
        table.insert(task1Events, { ev = ev, p1 = p1, p2 = p2 })
        if ev == "exit" or p1 == "exit" or ev == "terminate" then break end
    end
end, {}, false)

assert_eq(#TaskManager.getTasks(), 1, "Task 1 registered")
assert_eq(TaskManager.getActiveTask().name, "GameLoop", "Active task is GameLoop")
assert_eq(task1.alive, true, "Task 1 is alive")

-- 3. Event Pass-Through (Zero Delay)
-- Step a timer event into the supervisor
TaskManager.step("timer", 101)
assert_eq(#task1Events, 1, "Timer delivered to active task")
assert_eq(task1Events[1].ev, "timer", "Event name preserved")
assert_eq(task1Events[1].p1, 101, "Timer parameter preserved")

-- Step a non-matching event (filtered out by task1 yielding "timer")
TaskManager.step("mouse_click", 1, 5, 5)
assert_eq(#task1Events, 1, "Non-matching mouse event filtered by coroutine filter")

-- Step another timer
TaskManager.step("timer", 102)
assert_eq(#task1Events, 2, "Second timer delivered immediately")

-- 4. Create Second Task & Task Switching
local task2Keys = {}
local task2 = TaskManager.createTask("Notes", function(ctx)
    while true do
        local ev, key = coroutine.yield("key")
        table.insert(task2Keys, key)
        if key == 999 then break end
    end
end, {}, false)

assert_eq(#TaskManager.getTasks(), 2, "2 tasks active concurrently")
assert_eq(TaskManager.getActiveIndex(), 2, "Focus automatically shifted to new task")
assert_eq(TaskManager.getActiveTask().name, "Notes", "Active task is now Notes")

-- Send key event to Task 2
TaskManager.step("key", 42)
assert_eq(#task2Keys, 1, "Key delivered to Task 2")
assert_eq(task2Keys[1], 42, "Key code 42 received")
assert_eq(#task1Events, 2, "Task 1 received 0 keys while in background")

-- Switch back to Task 1
TaskManager.switchTask(1)
assert_eq(TaskManager.getActiveTask().name, "GameLoop", "Switched back to Task 1")

-- 5. Toast Notification Subsystem
redrawnWindows = {}
TaskManager.notify("💬 Chat", "Steve: Are you online?", colors.blue, 3.5, "chat")

-- Verify notification dismiss timer
local toastTimerId = nextTimer
assert_eq(activeTimers[toastTimerId], 3.5, "Toast timer set for 3.5s")

-- Step timer event to dismiss toast
TaskManager.step("timer", toastTimerId)
assert_eq(#canceledTimers, 1, "Toast timer cleaned up")
assert_eq(#redrawnWindows > 0, true, "Active task window redrawn to restore screen buffer")

-- 6. Background Network Packets
-- Simulate background mail arriving while playing game in Task 1
canceledTimers = {}
TaskManager.step("rednet_message", 5, { type = "new_mail", from = "Alice", subject = "Create Cogwheels" }, "SimpleMail")
local mailTimer = nextTimer
assert_eq(activeTimers[mailTimer], 4.0, "Mail notification toast triggered with 4.0s timer")

-- Simulate background bank payment arriving
TaskManager.step("rednet_message", 1, { type = "payment_proof", from = "Bob", amount = 250 }, "DB_Bank")
local bankTimer = nextTimer
assert_eq(activeTimers[bankTimer], 4.0, "Bank payment notification toast triggered")

-- 7. Task Exit & Clean Reaping
-- Switch to Task 2 and exit it
TaskManager.switchTask(2)
TaskManager.step("key", 999) -- triggers break in Task 2
assert_eq(#TaskManager.getTasks(), 1, "Task 2 exited and was reaped cleanly")
assert_eq(TaskManager.getActiveTask().name, "GameLoop", "Active task automatically reverted to Task 1")

-- Exit Task 1
TaskManager.step("timer", "exit")
assert_eq(#TaskManager.getTasks(), 0, "Task 1 exited and all tasks reaped")

print(">>> All Task Manager & Notification Daemon tests passed successfully!")
