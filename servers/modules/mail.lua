--[[
    Drunken OS - Mail Module
    Extracted from Drunken_OS_Server.lua
]]

local MailModule = {}

-- Helper Functions (Private to module, but used by exported functions)

local function saveItem(user, item, itemType, context)
    local mailCountCache = context.mailCountCache
    local saveTableToFile = context.saveTableToFile
    
    local dir = itemType .. "/" .. user
    if not fs.exists(dir) then fs.makeDir(dir) end
    local id = os.time() .. "-" .. math.random(100, 999)
    if saveTableToFile(dir .. "/" .. id, item) then
        if itemType == "mail" then
            mailCountCache[user] = (mailCountCache[user] or 0) + 1
        end
        return true
    end
    return false
end

local function loadMail(user, context)
    local mailCountCache = context.mailCountCache
    local logActivity = context.logActivity
    
    local path = "mail/" .. user
    local mail = {}
    if fs.exists(path) and fs.isDir(path) then
        local files = fs.list(path)
        mailCountCache[user] = #files -- Refresh cache
        for _, fileName in ipairs(files) do
            local mailPath = path .. "/" .. fileName
            local handle = fs.open(mailPath, "r")
            if handle then
                local data = handle.readAll()
                handle.close()
                local success, item = pcall(textutils.unserialize, data)
                if success and item then
                    item.id = fileName
                    table.insert(mail, item)
                else
                    logActivity("Corrupted mail file: " .. mailPath, true)
                end
            end
        end
    end
    return mail
end

local function deleteItem(user, id, itemType, context)
    local mailCountCache = context.mailCountCache
    
    local path = itemType .. "/" .. user .. "/" .. id
    if fs.exists(path) then
        fs.delete(path)
        if itemType == "mail" then
            mailCountCache[user] = math.max(0, (mailCountCache[user] or 1) - 1)
        end
        return true
    end
    return false
end

-- Exported helpers for Main Server to use if needed (e.g., inside Auth module or Main loop)
function MailModule.getMailCount(user, context)
    local mailCountCache = context.mailCountCache
    if mailCountCache[user] then return mailCountCache[user] end
    local path = "mail/" .. user
    if fs.exists(path) and fs.isDir(path) then
        mailCountCache[user] = #fs.list(path)
    else
        mailCountCache[user] = 0
    end
    return mailCountCache[user]
end

-- Exported Handlers

function MailModule.handleSend(senderId, message, context)
    local users = context.users
    local lists = context.lists
    local logActivity = context.logActivity
    
    local mail = message.mail
    if mail.to == "@all" then
        for user, _ in pairs(users) do saveItem(user, mail, "mail", context) end
        logActivity(string.format("Mail from '%s' to @all", mail.from_nickname))
    elseif mail.to:sub(1, 1) == "@" then
        local list = mail.to:sub(2)
        if lists[list] then
            for _, member in ipairs(lists[list]) do saveItem(member, mail, "mail", context) end
            logActivity(string.format("Mail from '%s' to list '%s'", mail.from_nickname, list))
        end
    else
        saveItem(mail.to, mail, "mail", context)
        logActivity(string.format("Mail from '%s' to '%s'", mail.from_nickname, mail.to))
    end
    rednet.send(senderId, { status = "Sent!" }, "SimpleMail")
end

function MailModule.handleFetch(senderId, message, context)
    rednet.send(senderId, { mail = loadMail(message.user, context) }, "SimpleMail")
end

function MailModule.handleDelete(senderId, message, context)
    if deleteItem(message.user, message.id, "mail", context) then
        context.logActivity(string.format("User '%s' deleted mail '%s'", message.user, message.id))
    end
end

function MailModule.handleCreateList(senderId, message, context)
    local lists = context.lists
    local queueSave = context.queueSave
    local LISTS_DB = context.LISTS_DB
    local logActivity = context.logActivity
    
    if lists[message.name] then
        rednet.send(senderId, { success = false, status = "List exists." }, "SimpleMail")
    else
        lists[message.name] = { message.creator }
        queueSave(LISTS_DB)
        rednet.send(senderId, { success = true, status = "List created." }, "SimpleMail")
        logActivity(string.format("'%s' created list '%s'", message.creator, message.name))
    end
end

function MailModule.handleJoinList(senderId, message, context)
    local lists = context.lists
    local queueSave = context.queueSave
    local LISTS_DB = context.LISTS_DB
    local logActivity = context.logActivity

    if not lists[message.name] then
        rednet.send(senderId, { success = false, status = "List not found." }, "SimpleMail")
        return
    end
    for _, member in ipairs(lists[message.name]) do
        if member == message.user then
            rednet.send(senderId, { success = false, status = "Already a member." }, "SimpleMail")
            return
        end
    end
    table.insert(lists[message.name], message.user)
    queueSave(LISTS_DB)
    rednet.send(senderId, { success = true, status = "Joined list." }, "SimpleMail")
    logActivity(string.format("'%s' joined list '%s'", message.user, message.name))
end

function MailModule.handleGetLists(senderId, message, context)
    rednet.send(senderId, { lists = context.lists }, "SimpleMail")
end

function MailModule.handleGetUnreadCount(senderId, message, context)
    rednet.send(senderId, { type = "unread_count_response", count = MailModule.getMailCount(message.user, context) }, "SimpleMail")
end

return MailModule
