--[[
    Drunken OS - Task Manager & Notification Daemon (v1.0)
    by MuhendizBey

    Features:
    - Ultra-low overhead coroutine multitasking
    - Window-buffered screen memory (window.create): 0 screen corruption on toast dismissal
    - Floating toast notifications (Mail, Chat, Bank, AirDrop, Radar)
    - Zero tick delay or input lag for fast games & apps
    - Fast task switcher via F1/Ctrl or mouse tap [≡]
]]

local TaskManager = {}
TaskManager._VERSION = 1.0

local safeKeys = setmetatable({}, {
    __index = function(_, k)
        return (keys and keys[k]) or -9999
    end
})

local tasks = {}
local activeIndex = 1
local nextTaskId = 1
local rootTerm = (term and term.current and term.current()) or term
local screenW, screenH = 51, 19
if rootTerm and rootTerm.getSize then
    screenW, screenH = rootTerm.getSize()
end

local toast = {
    active = false,
    title = "",
    message = "",
    color = (colors and colors.blue) or 2048,
    timerId = nil,
    targetApp = nil,
    win = nil,
}

local contextRef = nil
local myUsername = nil

--==============================================================================
-- Initialization
--==============================================================================

function TaskManager.init(ctx)
    contextRef = ctx
    myUsername = (ctx and ctx.parent and ctx.parent.username) or (ctx and ctx.username) or ""
    rootTerm = (term and term.current and term.current()) or term
    if rootTerm and rootTerm.getSize then
        screenW, screenH = rootTerm.getSize()
    end

    -- Create floating toast overlay window (hidden by default)
    if window and window.create then
        toast.win = window.create(rootTerm, 1, 1, screenW, 2, false)
    end
end

function TaskManager.setUsername(user)
    myUsername = user
end

--==============================================================================
-- Notification Toast Subsystem
--==============================================================================

--- Displays a non-intrusive floating toast overlay.
-- @param title string: Bold header (e.g. "💬 Chat", "💰 Bank")
-- @param message string: Preview text
-- @param color number: Background color constant
-- @param duration number: Display duration in seconds (defaults to 3.5)
-- @param targetApp string|nil: App name to switch to if tapped
function TaskManager.notify(title, message, color, duration, targetApp)
    toast.active = true
    toast.title = title or "Notification"
    toast.message = message or ""
    toast.color = color or colors.blue
    toast.targetApp = targetApp

    if toast.timerId then
        pcall(os.cancelTimer, toast.timerId)
    end
    toast.timerId = os.startTimer(duration or 3.5)

    if toast.win then
        toast.win.setVisible(true)
        toast.win.setBackgroundColor(toast.color)
        toast.win.setTextColor(colors.white)
        toast.win.clear()

        -- Top row: Header + tap hint
        toast.win.setCursorPos(2, 1)
        toast.win.write(toast.title)
        if toast.targetApp then
            local hint = "[Tap to Open]"
            if screenW - #hint > #toast.title + 4 then
                toast.win.setCursorPos(screenW - #hint, 1)
                toast.win.setTextColor(colors.yellow)
                toast.win.write(hint)
                toast.win.setTextColor(colors.white)
            end
        end

        -- Bottom row: Message preview
        toast.win.setCursorPos(2, 2)
        local maxLen = screenW - 3
        local msgText = toast.message
        if #msgText > maxLen then
            msgText = msgText:sub(1, maxLen - 2) .. ".."
        end
        toast.win.write(msgText)
    end
end

local function dismissToast()
    if not toast.active then return end
    toast.active = false
    if toast.timerId then
        pcall(os.cancelTimer, toast.timerId)
        toast.timerId = nil
    end

    if toast.win then
        toast.win.setVisible(false)
    end

    -- Instantly restore the covered lines from active task's window buffer
    local activeTask = tasks[activeIndex]
    if activeTask and activeTask.win and activeTask.win.redraw then
        activeTask.win.redraw()
        if activeTask.win.restoreCursor then
            activeTask.win.restoreCursor()
        end
    end
end

function TaskManager.dismissToast()
    dismissToast()
end

--==============================================================================
-- Task Management (Coroutines & Windows)
--==============================================================================

--- Creates and registers a new multitasking process.
-- @param name string: Display title (e.g. "Connect 4", "Pocket Bank")
-- @param taskFunc function: The function executed in the coroutine
-- @param context table: OS context provided to the function
-- @param isSystem boolean: If true, cannot be closed via task manager
-- @return table: Created task object
function TaskManager.createTask(name, taskFunc, context, isSystem)
    screenW, screenH = rootTerm.getSize()

    local taskWin = nil
    if window and window.create then
        taskWin = window.create(rootTerm, 1, 1, screenW, screenH, false)
    else
        taskWin = rootTerm
    end

    local task = {
        id = nextTaskId,
        name = name,
        func = taskFunc,
        context = context,
        win = taskWin,
        filter = nil,
        isSystem = isSystem or false,
        alive = true
    }
    nextTaskId = nextTaskId + 1

    -- Wrap task execution inside coroutine
    task.co = coroutine.create(function()
        if taskWin ~= rootTerm and term.redirect then
            pcall(term.redirect, taskWin)
        end

        local ok, err = pcall(taskFunc, context)
        if not ok and err and err ~= "Terminated" then
            if context and type(context.showMessage) == "function" then
                context.showMessage("Application Error", tostring(err))
            else
                print("[Task Error: " .. name .. "] " .. tostring(err))
            end
        end
    end)

    table.insert(tasks, task)

    -- Switch focus to new task
    TaskManager.switchTask(#tasks)

    -- Initial resume to run up to first yield
    local ok, filter = coroutine.resume(task.co)
    task.filter = filter
    if not ok then
        if context and type(context.showMessage) == "function" then
            context.showMessage("Application Error", tostring(filter))
        else
            print("[Task Init Error: " .. name .. "] " .. tostring(filter))
        end
        task.alive = false
    elseif coroutine.status(task.co) == "dead" then
        task.alive = false
    end

    return task
end

--- Switches active foreground focus to a given task index.
-- @param index number: Index in tasks table
function TaskManager.switchTask(index)
    if index < 1 or index > #tasks then return end

    -- Hide current active task window
    local oldTask = tasks[activeIndex]
    if oldTask and oldTask.win and oldTask.win ~= rootTerm and oldTask.win.setVisible then
        oldTask.win.setVisible(false)
    end

    activeIndex = index
    local newTask = tasks[activeIndex]

    if newTask and newTask.win and newTask.win ~= rootTerm then
        if newTask.win.setVisible then
            newTask.win.setVisible(true)
        end
        if newTask.win.redraw then
            newTask.win.redraw()
        end
        if newTask.win.restoreCursor then
            newTask.win.restoreCursor()
        end
        if term.redirect then
            pcall(term.redirect, newTask.win)
        end
    else
        if term.redirect then
            pcall(term.redirect, rootTerm)
        end
    end

    -- If a toast is currently active, ensure it stays on top
    if toast.active and toast.win and toast.win.redraw then
        toast.win.redraw()
    end

    if os.queueEvent then
        pcall(os.queueEvent, "task_resume")
    end
end

--- Closes a task and reaps its resources.
-- @param index number: Index in tasks table
function TaskManager.closeTask(index)
    local task = tasks[index]
    if not task or task.isSystem then return end

    task.alive = false
    if task.win and task.win ~= rootTerm and task.win.setVisible then
        task.win.setVisible(false)
    end

    table.remove(tasks, index)

    if activeIndex > #tasks then
        activeIndex = #tasks
    end
    TaskManager.switchTask(activeIndex)
end

function TaskManager.getTasks()
    return tasks
end

function TaskManager.getActiveIndex()
    return activeIndex
end

function TaskManager.getActiveTask()
    return tasks[activeIndex]
end

--==============================================================================
-- Quick Task Switcher UI
--==============================================================================

local function showAppLauncher()
    if not (fs and fs.exists and fs.exists("apps") and fs.isDir and fs.isDir("apps")) then return false end
    local appList = {}
    for _, f in ipairs(fs.list("apps")) do
        if not fs.isDir("apps/" .. f) and f:match("%.lua$") and not f:find("turtle") then
            local appName = f:gsub("%.lua$", "")
            local label = appName:gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper() .. rest:lower():gsub("_", " ")
            end)
            table.insert(appList, { name = appName, label = label })
        end
    end
    table.sort(appList, function(a, b) return a.label < b.label end)
    if #appList == 0 then return false end

    local w, h = rootTerm.getSize()
    local boxW = math.min(30, w - 2)
    local boxH = math.min(#appList + 4, h - 2)
    local startX = math.floor((w - boxW) / 2) + 1
    local startY = math.floor((h - boxH) / 2) + 1

    local lWin = nil
    if window and window.create then
        lWin = window.create(rootTerm, startX, startY, boxW, boxH, true)
    else
        lWin = rootTerm
    end

    local sel = 1
    local scroll = 0
    local maxVisible = boxH - 3

    while true do
        lWin.setBackgroundColor(colors.black)
        lWin.setTextColor(colors.white)
        lWin.clear()

        lWin.setCursorPos(2, 1)
        lWin.setTextColor(colors.yellow)
        lWin.write("Launch Application")

        if sel < 1 then sel = 1 end
        if sel > #appList then sel = #appList end
        if sel <= scroll then scroll = sel - 1 end
        if sel > scroll + maxVisible then scroll = sel - maxVisible end
        if scroll < 0 then scroll = 0 end

        for i = 1, maxVisible do
            local idx = scroll + i
            local item = appList[idx]
            if item then
                lWin.setCursorPos(2, 1 + i)
                if idx == sel then
                    lWin.setBackgroundColor(colors.blue)
                    lWin.setTextColor(colors.white)
                    local txt = " " .. item.label
                    lWin.write(txt .. string.rep(" ", boxW - #txt - 2))
                    lWin.setBackgroundColor(colors.black)
                else
                    lWin.setTextColor(colors.lightGray)
                    lWin.write(" " .. item.label)
                end
            end
        end

        lWin.setCursorPos(2, boxH)
        lWin.setTextColor(colors.gray)
        lWin.write("[Enter] Run | [Q] Cancel")

        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            if p1 == safeKeys.up then
                sel = (sel == 1) and #appList or sel - 1
            elseif p1 == safeKeys.down then
                sel = (sel == #appList) and 1 or sel + 1
            elseif p1 == safeKeys.enter then
                local chosen = appList[sel]
                if lWin ~= rootTerm then lWin.setVisible(false) end
                if chosen and contextRef and contextRef.appLoader and contextRef.appLoader.run then
                    local newTask = TaskManager.createTask(chosen.label, function(ctx)
                        contextRef.appLoader.run(chosen.name, ctx)
                    end, contextRef)
                    newTask.appName = chosen.name
                end
                return true
            elseif p1 == safeKeys.q then
                break
            end
        elseif ev == "mouse_click" then
            local clickY = p3 - startY + 1
            local clickedIdx = scroll + clickY - 1
            if clickedIdx >= 1 and clickedIdx <= #appList then
                sel = clickedIdx
                local chosen = appList[sel]
                if lWin ~= rootTerm then lWin.setVisible(false) end
                if chosen and contextRef and contextRef.appLoader and contextRef.appLoader.run then
                    local newTask = TaskManager.createTask(chosen.label, function(ctx)
                        contextRef.appLoader.run(chosen.name, ctx)
                    end, contextRef)
                    newTask.appName = chosen.name
                end
                return true
            elseif clickY == boxH then
                break
            end
        end
    end

    if lWin ~= rootTerm then lWin.setVisible(false) end
    return false
end

local function showTaskSwitcher()
    local w, h = rootTerm.getSize()
    local boxW = math.min(32, w - 2)
    local boxH = math.min(#tasks + 5, h - 2)
    local startX = math.floor((w - boxW) / 2) + 1
    local startY = math.floor((h - boxH) / 2) + 1

    local switcherWin = nil
    if window and window.create then
        switcherWin = window.create(rootTerm, startX, startY, boxW, boxH, true)
    else
        switcherWin = rootTerm
    end

    local sel = activeIndex
    while true do
        switcherWin.setBackgroundColor(colors.gray)
        switcherWin.setTextColor(colors.white)
        switcherWin.clear()

        -- Title bar
        switcherWin.setCursorPos(2, 1)
        switcherWin.setTextColor(colors.yellow)
        switcherWin.write("Drunken Task Switcher")

        -- Task List
        for i, t in ipairs(tasks) do
            local y = 2 + i
            switcherWin.setCursorPos(2, y)
            if i == sel then
                switcherWin.setBackgroundColor(colors.cyan)
                switcherWin.setTextColor(colors.black)
                local label = string.format(" > %d. %s", i, t.name:sub(1, boxW - 8))
                switcherWin.write(label .. string.rep(" ", boxW - #label - 2))
                switcherWin.setBackgroundColor(colors.gray)
            else
                switcherWin.setTextColor(colors.white)
                switcherWin.write(string.format("   %d. %s", i, t.name:sub(1, boxW - 8)))
            end
        end

        -- Footer
        switcherWin.setCursorPos(2, boxH)
        switcherWin.setTextColor(colors.lightGray)
        switcherWin.write("[Enter] Go | [N] New | [X] Kill")

        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "key" then
            if p1 == safeKeys.up then
                sel = (sel == 1) and #tasks or sel - 1
            elseif p1 == safeKeys.down then
                sel = (sel == #tasks) and 1 or sel + 1
            elseif p1 == safeKeys.enter then
                if switcherWin ~= rootTerm then switcherWin.setVisible(false) end
                TaskManager.switchTask(sel)
                return
            elseif p1 == safeKeys.n then
                if switcherWin ~= rootTerm then switcherWin.setVisible(false) end
                if showAppLauncher() then return end
                if switcherWin ~= rootTerm then switcherWin.setVisible(true) end
            elseif p1 == safeKeys.x or p1 == safeKeys.delete then
                if not tasks[sel].isSystem then
                    TaskManager.closeTask(sel)
                    if #tasks == 0 or sel > #tasks then sel = math.max(1, #tasks) end
                end
            elseif p1 == safeKeys.q or p1 == safeKeys.f1 or p1 == safeKeys.leftCtrl or p1 == safeKeys.rightCtrl then
                break
            end
        elseif ev == "mouse_click" then
            local clickY = p3 - startY + 1
            local clickedIdx = clickY - 2
            if clickedIdx >= 1 and clickedIdx <= #tasks then
                sel = clickedIdx
                if switcherWin ~= rootTerm then switcherWin.setVisible(false) end
                TaskManager.switchTask(sel)
                return
            elseif clickY == boxH then
                break
            end
        end
    end

    if switcherWin ~= rootTerm then
        switcherWin.setVisible(false)
    end
    -- Restore active task window
    local activeTask = tasks[activeIndex]
    if activeTask and activeTask.win and activeTask.win.redraw then
        activeTask.win.redraw()
        if activeTask.win.restoreCursor then activeTask.win.restoreCursor() end
    end
end

--==============================================================================
-- Main Event Supervisor & Dispatcher
--==============================================================================

--- Single event pump step. Dispatches system alerts and delivers events to active task.
-- @param event string: Event name
-- @param p1, p2, p3, p4, p5: Event parameters
-- @return boolean: True if tasks remain alive, false if all tasks exited.
function TaskManager.step(event, p1, p2, p3, p4, p5)
    if #tasks == 0 then return false end

    -- 1. Check Toast Timer Dismissal
    if event == "timer" and toast.active and p1 == toast.timerId then
        dismissToast()
        return true
    end

    -- 2. Check Global Task Switcher Hotkey (F1 or Ctrl)
    if event == "key" and (p1 == safeKeys.f1 or p1 == safeKeys.leftCtrl or p1 == safeKeys.rightCtrl) then
        showTaskSwitcher()
        return true
    end

    -- 3. Check Mouse Click on Active Toast Banner (Tap to open app)
    if event == "mouse_click" and toast.active then
        local btn, clickX, clickY = p1, p2, p3
        if clickY <= 2 then
            local target = toast.targetApp
            dismissToast()
            if target and contextRef then
                -- Launch or switch to target app
                for i, t in ipairs(tasks) do
                    if t.name:lower():find(target:lower()) then
                        TaskManager.switchTask(i)
                        return true
                    end
                end
                -- App not running: launch via appLoader
                if contextRef.appLoader and contextRef.appLoader.run then
                    TaskManager.createTask(target:sub(1,1):upper() .. target:sub(2), function(ctx)
                        contextRef.appLoader.run(target, ctx)
                    end, contextRef)
                end
            end
            return true
        end
    end

    -- 4. Background Network Packet Inspection (Mail, Chat, Bank, AirDrop, Merchant, Radar)
    if event == "rednet_message" then
        local senderId, msg, proto = p1, p2, p3
        if type(msg) == "table" then
            if proto == "SimpleMail" then
                if msg.type == "new_mail" or (msg.mail and msg.mail.from) then
                    local sender = (msg.mail and (msg.mail.from_nickname or msg.mail.from)) or msg.from or "Someone"
                    local subj = (msg.mail and msg.mail.subject) or msg.subject or "New Message"
                    TaskManager.notify("✉ New Mail", sender .. ": " .. subj, colors.lightBlue, 4.0, "mail")
                elseif msg.count then
                    if contextRef and contextRef.parent then
                        contextRef.parent.unreadCount = msg.count
                    end
                end
            elseif proto == "SimpleChat" then
                if msg.type == "message" and msg.from and msg.from ~= myUsername then
                    local sender = msg.from_nickname or msg.from
                    local text = msg.message or msg.text or ""
                    TaskManager.notify("💬 Chat", sender .. ": " .. text, colors.blue, 3.5, "chat")
                end
            elseif proto == "DB_Merchant_Req" then
                if msg.type == "payment_request" and (not msg.target or msg.target == myUsername) then
                    if contextRef and contextRef.parent then
                        if not contextRef.parent.pendingInvoices then contextRef.parent.pendingInvoices = {} end
                        table.insert(contextRef.parent.pendingInvoices, msg)
                    end
                    local speaker = peripheral and peripheral.find and peripheral.find("speaker")
                    if speaker and speaker.playNote then pcall(speaker.playNote, "pling", 1, 2) end
                    TaskManager.notify("💳 Invoice", string.format("Payment requested: $%d", msg.amount or 0), colors.orange, 5.0, "merchant")
                end
            elseif proto == "DB_Shop_Broadcast" and msg.menu then
                if contextRef and contextRef.parent then
                    contextRef.parent.nearbyShop = msg
                end
            elseif proto == "DrunkenRadar" and msg.type == "radar_ping" then
                local myGps = contextRef and contextRef.parent and contextRef.parent.location
                if not myGps and gps and gps.locate then
                    local gx, gy, gz = gps.locate(0.2)
                    if gx and gy and gz then myGps = { x = math.floor(gx), y = math.floor(gy), z = math.floor(gz) } end
                end
                if rednet and rednet.send then
                    rednet.send(senderId, {
                        type = "radar_pong",
                        id = (os.getComputerID and os.getComputerID()) or 0,
                        user = (myUsername ~= "" and myUsername) or "Pocket User",
                        device = "Pocket",
                        label = (os.getComputerLabel and os.getComputerLabel()) or ("Pocket #" .. ((os.getComputerID and os.getComputerID()) or 0)),
                        gps = myGps
                    }, "DrunkenRadar")
                end
            elseif proto == "DB_Merchant_Recv" or proto == "DB_Bank" then
                if msg.type == "payment_proof" or msg.type == "transfer_notification" then
                    local sender = msg.from or "Someone"
                    local amt = msg.amount or 0
                    TaskManager.notify("💰 Bank Payment", string.format("Received $%d from %s", amt, sender), colors.green, 4.0, "bank")
                end
            elseif proto == "DrunkenAirDrop" then
                if msg.type == "airdrop_ping" and msg.user and msg.user ~= myUsername then
                    TaskManager.notify("📡 AirDrop", "Device nearby: " .. msg.user, colors.cyan, 3.0, "files")
                elseif msg.type == "xfer_init" then
                    TaskManager.notify("📡 AirDrop", "Receiving file: " .. (msg.filename or "file"), colors.lime, 4.0, "files")
                end
            end
        end
    end

    -- 5. Dispatch Event to Active Task (Zero Overhead Pass-Through)
    local activeTask = tasks[activeIndex]
    if activeTask and activeTask.alive then
        if not activeTask.filter or activeTask.filter == event or event == "terminate" then
            if activeTask.win and term.redirect then
                pcall(term.redirect, activeTask.win)
            end
            local ok, filter = coroutine.resume(activeTask.co, event, p1, p2, p3, p4, p5)
            activeTask.filter = filter

            if not ok then
                -- Coroutine threw unhandled error
                if contextRef and type(contextRef.showMessage) == "function" then
                    contextRef.showMessage("Crash: " .. activeTask.name, tostring(filter))
                end
                activeTask.alive = false
            elseif coroutine.status(activeTask.co) == "dead" then
                -- Task completed normally
                activeTask.alive = false
            end
        end
    end

    -- Clean up dead tasks
    local i = 1
    while i <= #tasks do
        if not tasks[i].alive then
            local isCurrent = (i == activeIndex)
            if tasks[i].win and tasks[i].win ~= rootTerm and tasks[i].win.setVisible then
                tasks[i].win.setVisible(false)
            end
            table.remove(tasks, i)
            if isCurrent then
                if activeIndex > #tasks then activeIndex = #tasks end
                if #tasks > 0 then
                    TaskManager.switchTask(activeIndex)
                end
            elseif i < activeIndex then
                activeIndex = activeIndex - 1
            end
        else
            i = i + 1
        end
    end

    return #tasks > 0
end

--- Runs the supervisor loop until all tasks exit.
function TaskManager.run()
    while #tasks > 0 do
        local evData = { os.pullEventRaw() }
        local keepRunning = TaskManager.step(table.unpack(evData))
        if not keepRunning then break end
    end
end

return TaskManager
