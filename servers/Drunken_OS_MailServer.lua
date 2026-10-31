--[[
    Drunken OS - Mail Server (Microservices Architecture)
    by MuhendizBey

    Handles localized storage of mail, broadcast announcements (@all), and lists.
    Communicates strictly over the internal wired interlink under ServiceGuard supervision.
]]

local programDir = (shell and shell.getRunningProgram and fs.getDir(shell.getRunningProgram())) or ""
package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. (programDir ~= "" and (fs.combine(programDir, "lib/?.lua") .. ";") or "") .. package.path

local DB = require("lib.db")
local ServiceGuard = require("lib.service_guard")

-- State
local lists = {}
local LISTS_DB = "lists.db"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"

-- Dashboard & Logger
local mailDashboard = nil
local logHistory = {}

local function logActivity(msg, isError)
    local pfx = isError and "[ERROR] " or "[INFO] "
    local logEntry = os.date("[%H:%M:%S] ") .. pfx .. tostring(msg or "")
    table.insert(logHistory, logEntry)
    if #logHistory > 100 then table.remove(logHistory, 1) end
    if mailDashboard then
        mailDashboard:log(logEntry, isError)
    else
        print(logEntry)
    end
end

-- Initialize Modems
local modems = ServiceGuard.initModems()
local wiredModem = modems.wired

-- Load Database
lists = DB.loadTableFromFile(LISTS_DB, logActivity)

-----------------------------------------------------------
-- Folder-based storage implementation
-----------------------------------------------------------

local function saveItem(user, item, itemType)
    local baseDir = (itemType == "cloud") and "cloud_data" or "mail_data"
    local dir = baseDir .. "/" .. user
    if not fs.exists(dir) then 
        pcall(fs.makeDir, dir) 
    end
    
    local id = tostring(os.epoch and os.epoch("utc") or os.time()) .. "-" .. math.random(1000, 9999)
    local path = dir .. "/" .. id .. ".txt"
    
    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serialize(item))
        f.close()
        return true
    end
    return false
end

local function loadFiles(user, itemType)
    local baseDir = (itemType == "cloud") and "cloud_data" or "mail_data"
    local path = baseDir .. "/" .. user
    local items = {}
    
    if fs.exists(path) and fs.isDir(path) then
        for _, fileName in ipairs(fs.list(path)) do
            if fileName:match("%.txt$") then
                local filePath = path .. "/" .. fileName
                local handle = fs.open(filePath, "r")
                if handle then
                    local data = handle.readAll()
                    handle.close()
                    local success, item = pcall(textutils.unserialize, data)
                    if success and item then
                        item.id = fileName:gsub("%.txt$", "")
                        table.insert(items, item)
                    else
                        logActivity("Corrupted " .. itemType .. " file: " .. filePath, true)
                    end
                end
            end
        end
    end
    return items
end

local function deleteItem(user, id, itemType)
    local baseDir = (itemType == "cloud") and "cloud_data" or "mail_data"
    local path = baseDir .. "/" .. user .. "/" .. id .. ".txt"
    if fs.exists(path) then
        fs.delete(path)
        return true
    end
    return false
end

local function getCount(user, itemType)
    local baseDir = (itemType == "cloud") and "cloud_data" or "mail_data"
    local path = baseDir .. "/" .. user
    if fs.exists(path) and fs.isDir(path) then
        local count = 0
        for _, file in ipairs(fs.list(path)) do
            if file:match("%.txt$") then count = count + 1 end
        end
        return count
    end
    return 0
end

local function countDirectories(dirName)
    if not fs.exists(dirName) or not fs.isDir(dirName) then return 0 end
    local count = 0
    for _, item in ipairs(fs.list(dirName)) do
        if fs.isDir(dirName .. "/" .. item) then
            count = count + 1
        end
    end
    return count
end

-----------------------------------------------------------
-- Handlers
-----------------------------------------------------------

local handlers = {}

function handlers.send(senderId, payload)
    local message = payload.message
    local mail = message.mail
    
    if mail.to == "@all" then
        local recipients = {}
        local recipientSet = {}

        -- 1. Scan existing mailboxes on disk
        if fs.exists("mail_data") and fs.isDir("mail_data") then
            for _, name in ipairs(fs.list("mail_data")) do
                if fs.isDir("mail_data/" .. name) and not recipientSet[name] then
                    recipientSet[name] = true
                    table.insert(recipients, name)
                end
            end
        end

        -- 2. Query Auth Server over wired interlink for registered users
        local authId = rednet.lookup and (rednet.lookup(AUTH_INTERLINK_PROTOCOL, "auth.server") or rednet.lookup(AUTH_INTERLINK_PROTOCOL))
        if authId then
            rednet.send(authId, { type = "get_user_list" }, AUTH_INTERLINK_PROTOCOL)
            local _, replyMsg = rednet.receive(AUTH_INTERLINK_PROTOCOL, 1.0)
            if replyMsg and type(replyMsg) == "table" and replyMsg.type == "user_list_response" and replyMsg.users then
                for _, u in ipairs(replyMsg.users) do
                    if not recipientSet[u] then
                        recipientSet[u] = true
                        table.insert(recipients, u)
                    end
                end
            end
        end

        local deliveredCount = 0
        for _, rec in ipairs(recipients) do
            if saveItem(rec, mail, "mail") then
                deliveredCount = deliveredCount + 1
            end
        end

        logActivity(string.format("Broadcast mail from '%s' delivered to %d user(s) (@all)", mail.from_nickname or mail.from, deliveredCount))

        rednet.send(senderId, {
            status = string.format("Broadcast sent to %d user(s)!", deliveredCount),
            success = true,
            original_type = payload.type
        }, AUTH_INTERLINK_PROTOCOL)

        pcall(rednet.broadcast, {
            type = "new_mail_notification",
            recipient = "@all",
            mail = {
                from = mail.from,
                from_nickname = mail.from_nickname,
                subject = mail.subject
            }
        }, AUTH_INTERLINK_PROTOCOL)

        if mailDashboard then mailDashboard:refreshDetails() end
        return

    elseif mail.to:sub(1, 1) == "@" then
        local list = mail.to:sub(2)
        if lists[list] then
            for _, member in ipairs(lists[list]) do 
                saveItem(member, mail, "mail") 
            end
            logActivity(string.format("Mail from '%s' to list '%s' (%d members)", mail.from_nickname or mail.from, list, #lists[list]))
        else
            logActivity("Mailing list not found: " .. list, true)
        end
    else
        saveItem(mail.to, mail, "mail")
        logActivity(string.format("Mail from '%s' to '%s'", mail.from_nickname or mail.from, mail.to))
    end
    
    -- Confirmation back to sender
    rednet.send(senderId, { status = "Sent!", success = true, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)

    -- Notify network if recipient is another user
    if mail.to ~= mail.from and mail.to ~= (payload.message and payload.message.user) then
        pcall(rednet.broadcast, {
            type = "new_mail_notification",
            recipient = mail.to,
            mail = {
                from = mail.from,
                from_nickname = mail.from_nickname,
                subject = mail.subject
            }
        }, AUTH_INTERLINK_PROTOCOL)
    end

    if mailDashboard then mailDashboard:refreshDetails() end
end

function handlers.fetch(senderId, payload)
    local message = payload.message
    rednet.send(senderId, { mail = loadFiles(message.user, "mail"), original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.delete(senderId, payload)
    local message = payload.message
    deleteItem(message.user, message.id, "mail")
    rednet.send(senderId, { success = true, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
    if mailDashboard then mailDashboard:refreshDetails() end
end

function handlers.create_list(senderId, payload)
    local message = payload.message
    if lists[message.name] then
        rednet.send(senderId, { success = false, status = "List already exists.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
    else
        lists[message.name] = { message.creator }
        DB.saveTableToFile(LISTS_DB, lists, logActivity)
        rednet.send(senderId, { success = true, status = "List created.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
        logActivity("List created: " .. message.name)
        if mailDashboard then mailDashboard:refreshDetails() end
    end
end

function handlers.join_list(senderId, payload)
    local message = payload.message
    if not lists[message.name] then
        rednet.send(senderId, { success = false, status = "List not found.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
        return
    end
    for _, m in ipairs(lists[message.name]) do
        if m == message.user then
            rednet.send(senderId, { success = false, status = "Already a member.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
            return
        end
    end
    table.insert(lists[message.name], message.user)
    DB.saveTableToFile(LISTS_DB, lists, logActivity)
    rednet.send(senderId, { success = true, status = "Joined list.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.get_lists(senderId, payload)
    rednet.send(senderId, { lists = lists, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.get_unread_count(senderId, payload)
    local message = payload.message
    local count = getCount(message.user, "mail")
    rednet.send(senderId, { type = "unread_count_response", count = count, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.cloud_save(senderId, payload)
    local message = payload.message
    saveItem(message.user, message.data, "cloud")
    rednet.send(senderId, { status = "Saved!", success = true, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
    if mailDashboard then mailDashboard:refreshDetails() end
end

function handlers.cloud_fetch(senderId, payload)
    local message = payload.message
    rednet.send(senderId, { files = loadFiles(message.user, "cloud"), original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.cloud_delete(senderId, payload)
    local message = payload.message
    deleteItem(message.user, message.id, "cloud")
    rednet.send(senderId, { success = true, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
    if mailDashboard then mailDashboard:refreshDetails() end
end

-----------------------------------------------------------
-- Main Server Loop & Supervisor
-----------------------------------------------------------

local function handleInboundPacket(senderId, payload, protocol)
    if payload and type(payload) == "table" and payload.forwarded then
        local msgType = payload.type
        if handlers[msgType] then
            local oldSend = rednet.send
            rednet.send = function(target, response, proto)
                response.original_senderId = payload.original_senderId
                response.proxy_senderId = payload.proxy_senderId
                response.original_protocol = payload.original_protocol
                oldSend(target, response, proto)
            end
            local ok, err = pcall(handlers[msgType], senderId, payload)
            rednet.send = oldSend
            
            if not ok then
                logActivity("Error handling " .. tostring(msgType) .. ": " .. tostring(err), true)
            end
        else
            logActivity("Unhandled request type: " .. tostring(msgType))
        end
    end
end

local function flushLists()
    if lists then
        pcall(DB.saveTableToFile, LISTS_DB, lists, logActivity)
    end
end

local function startMailServer()
    local function getDashboardDetails()
        local listCount = 0
        if lists then for _ in pairs(lists) do listCount = listCount + 1 end end
        local mailboxes = countDirectories("mail_data")
        local cloudAccounts = countDirectories("cloud_data")
        local wiredStatus = (wiredModem and "CONNECTED (" .. wiredModem .. ")") or "STANDALONE"

        return {
            { label = "Service", value = "Drunken OS Mail & Cloud Server", color = colors.white },
            { label = "Wired Link", value = wiredStatus, color = wiredModem and colors.lime or colors.yellow },
            { label = "Mailboxes", value = string.format("%d active user account(s)", mailboxes), color = colors.lime },
            { label = "Mailing Lists", value = string.format("%d public list(s)", listCount), color = colors.white },
            { label = "Cloud Drives", value = string.format("%d user cloud vault(s)", cloudAccounts), color = colors.lightGray },
            { label = "Protocol", value = AUTH_INTERLINK_PROTOCOL, color = colors.lightGray },
        }
    end

    mailDashboard = ServiceGuard.createDashboard({
        serverName = "MAIL SERVER",
        details = getDashboardDetails,
        status = "ONLINE",
        hintText = "[C] Clear Logs | [Q] Quit | Zero-Downtime Supervisor",
        maxLogs = 100
    })

    mailDashboard:draw()
    logActivity("Mail Server active on " .. AUTH_INTERLINK_PROTOCOL)
    logActivity("Wired interlink initialized with broadcast announcements enabled (@all)")

    while true do
        local event, p1, p2, p3 = os.pullEventRaw()
        if event == "rednet_message" then
            local senderId, payload, protocol = p1, p2, p3
            if protocol == AUTH_INTERLINK_PROTOCOL then
                ServiceGuard.protectHandler("Mail:message", handleInboundPacket, logActivity, senderId, payload, protocol)
            end
        elseif event == "peripheral" or event == "peripheral_detach" then
            ServiceGuard.handlePeripheralEvent(event, p1, nil, logActivity)
            local modems_now = ServiceGuard.initModems()
            wiredModem = modems_now.wired
            if mailDashboard then mailDashboard:refreshDetails() end
        elseif event == "key" then
            local key = p1
            if key == keys.c then
                if mailDashboard then mailDashboard:clearLogs() end
            elseif key == keys.q then
                error("Terminated", 0)
            end
        elseif event == "terminate" then
            error("Terminated", 0)
        end
    end
end

ServiceGuard.runSupervisor("Mail Server", startMailServer, flushLists, logActivity)
