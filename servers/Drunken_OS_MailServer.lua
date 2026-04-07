--[[
    Drunken OS - Mail Server (Microservices Architecture)
    Handles localized storage of mail and lists.
    Communicates strictly over the internal wired interlink.
]]

package.path = "/?.lua;" .. package.path

local DB = require("lib.db")

-- State
local lists = {}
local LISTS_DB = "lists.db"
local AUTH_INTERLINK_PROTOCOL = "Drunken_Auth_Interlink"

-- Modem Setup
local wiredModem = nil

local function logActivity(msg, isError)
    local pfx = isError and "[ERROR] " or "[INFO] "
    print(os.date("[%H:%M:%S] ") .. pfx .. msg)
end

for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        if not peripheral.call(name, "isWireless") then
            wiredModem = name
            rednet.open(name)
        end
    end
end

if not wiredModem then
    error("Mail Server requires a wired modem to function.")
end

-- Load Database
lists = DB.loadTableFromFile(LISTS_DB, logActivity)

logActivity("Mail Server starting up on Wired Interlink...")

-----------------------------------------------------------
-- Folder-based storage implementation
-----------------------------------------------------------

local function saveItem(user, item, itemType)
    local baseDir = (itemType == "cloud") and "cloud_data" or "mail_data"
    local dir = baseDir .. "/" .. user
    if not fs.exists(dir) then 
        fs.makeDir(dir) 
    end
    
    local id = tostring(os.epoch("utc")) .. "-" .. math.random(1000, 9999)
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
                        item.id = fileName:gsub("%.txt$", "") -- Strip extension for id
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

-----------------------------------------------------------
-- Handlers
-----------------------------------------------------------

local handlers = {}

function handlers.send(senderId, payload)
    local message = payload.message
    local mail = message.mail
    
    if mail.to == "@all" then
        -- We don't have local 'users' table since it's on Auth, so we need to rely on Mail Server forwarding to users.
        -- But wait, Mail server doesn't own `users`. Thus, `to: @all` requires asking AuthServer for users?
        -- Alternatively, AuthServer owns users. MailServer can send a `get_users` query?
        -- For now, ask AuthServer via interlink for all users or just skip @all handling for simple standalone.
        -- Let's query AuthServer for users if `@all` is used.
        rednet.send(senderId, { success = false, status = "@all not fully supported without Auth integration.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
        return
    elseif mail.to:sub(1, 1) == "@" then
        local list = mail.to:sub(2)
        if lists[list] then
            for _, member in ipairs(lists[list]) do 
                saveItem(member, mail, "mail") 
            end
            logActivity(string.format("Mail from '%s' to list '%s'", mail.from_nickname, list))
        end
    else
        saveItem(mail.to, mail, "mail")
        logActivity(string.format("Mail from '%s' to '%s'", mail.from_nickname, mail.to))
    end
    
    rednet.send(senderId, { status = "Sent!", success = true, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.fetch(senderId, payload)
    local message = payload.message
    rednet.send(senderId, { mail = loadFiles(message.user, "mail"), original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.delete(senderId, payload)
    local message = payload.message
    if deleteItem(message.user, message.id, "mail") then
        logActivity("Deleted mail " .. message.id .. " for " .. message.user)
    end
    rednet.send(senderId, { success = true, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.create_list(senderId, payload)
    local message = payload.message
    if lists[message.name] then
        rednet.send(senderId, { success = false, status = "List exists.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
    else
        lists[message.name] = { message.creator }
        DB.saveTableToFile(LISTS_DB, lists, logActivity)
        rednet.send(senderId, { success = true, status = "List created.", original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
        logActivity("List created: " .. message.name)
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
end

function handlers.cloud_fetch(senderId, payload)
    local message = payload.message
    rednet.send(senderId, { files = loadFiles(message.user, "cloud"), original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

function handlers.cloud_delete(senderId, payload)
    local message = payload.message
    deleteItem(message.user, message.id, "cloud")
    rednet.send(senderId, { success = true, original_type = payload.type }, AUTH_INTERLINK_PROTOCOL)
end

-----------------------------------------------------------
-- Main Loop
-----------------------------------------------------------

while true do
    local senderId, payload, protocol = rednet.receive(AUTH_INTERLINK_PROTOCOL)
    
    if payload and type(payload) == "table" and payload.forwarded then
        local msgType = payload.type
        if handlers[msgType] then
            -- We wrap the rednet send to automatically append original_senderId
            local oldSend = rednet.send
            rednet.send = function(target, response, proto)
                response.original_senderId = payload.original_senderId
                response.original_protocol = payload.original_protocol
                oldSend(target, response, proto)
            end
            local ok, err = pcall(handlers[msgType], senderId, payload)
            rednet.send = oldSend
            
            if not ok then
                logActivity("Error handling " .. msgType .. ": " .. tostring(err), true)
            end
        else
            logActivity("Unhandled request type: " .. tostring(msgType))
        end
    end
end
