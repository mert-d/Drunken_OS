--[[
    Drunken OS - Shared Database Library (v1.0)
    
    Purpose:
    Provides atomic file persistence with crash recovery for all servers.
    Consolidates saveTableToFile, loadTableFromFile, and dirty tracking logic.
    
    Usage:
        local DB = require("lib.db")
        
        -- Direct save/load
        DB.saveTableToFile("users.db", usersTable)
        local users = DB.loadTableFromFile("users.db")
        
        -- Lazy persistence with dirty tracking
        local tracker = DB.createDirtyTracker(dbPointers, logFn)
        tracker.queueSave("users.db")
        -- Later, in a background loop:
        tracker.backgroundSave()
]]

local DB = {}
DB._VERSION = 1.0

---
-- Saves a Lua table to a file using an atomic write pattern to prevent corruption.
-- Uses a .tmp file and fs.move to ensure atomicity.
-- @param path string: The file path to save to.
-- @param data table: The table to save.
-- @param logFn function: Optional logging function(message, isError).
-- @return boolean: True on success, false on failure.
function DB.saveTableToFile(path, data, logFn)
    local tempPath = path .. ".tmp"
    local file, err_open = fs.open(tempPath, "w")
    if not file then
        if logFn then logFn("Could not open temporary file " .. tempPath .. ": " .. tostring(err_open), true) end
        return false
    end

    local success, err_write = pcall(function()
        file.write(textutils.serialize(data))
        file.close()
    end)

    if not success then
        if logFn then logFn("Failed to write to temporary file " .. tempPath .. ': ' .. tostring(err_write), true) end
        pcall(function() fs.delete(tempPath) end) -- Clean up the failed temp file
        return false
    end

    -- Atomic swap: delete original, move temp to original
    if fs.exists(path) then
        fs.delete(path)
    end
    fs.move(tempPath, path)
    
    return true
end

---
-- Saves a Lua table to a JSON file using an atomic write pattern.
-- @param path string: The file path to save to.
-- @param data table: The table to save.
-- @param logFn function: Optional logging function(message, isError).
-- @return boolean: True on success, false on failure.
function DB.saveTableToFileJSON(path, data, logFn)
    local tempPath = path .. ".tmp"
    local file, err_open = fs.open(tempPath, "w")
    if not file then
        if logFn then logFn("Could not open temporary file " .. tempPath .. ": " .. tostring(err_open), true) end
        return false
    end

    local success, err_write = pcall(function()
        file.write(textutils.serializeJSON(data))
        file.close()
    end)

    if not success then
        if logFn then logFn("Failed to write JSON to " .. tempPath .. ': ' .. tostring(err_write), true) end
        pcall(function() fs.delete(tempPath) end)
        return false
    end

    if fs.exists(path) then
        fs.delete(path)
    end
    fs.move(tempPath, path)
    
    return true
end

---
-- Loads a Lua table from a file, with recovery logic for interrupted saves.
-- If main file is missing but .tmp exists, recovers from the temp file.
-- @param path string: The file path to load from.
-- @param logFn function: Optional logging function(message, isError).
-- @return table: The loaded table, or an empty table on failure.
function DB.loadTableFromFile(path, logFn)
    local tempPath = path .. ".tmp"
    
    -- Recovery: If the main file is gone but the temp file exists,
    -- the last write was interrupted after delete but before move.
    if not fs.exists(path) and fs.exists(tempPath) then
        if logFn then logFn("Found incomplete save, restoring from " .. tempPath, false) end
        fs.move(tempPath, path)
    end

    if fs.exists(path) then
        local file, err_open = fs.open(path, "r")
        if file then
            local data = file.readAll()
            file.close()
            local success, result = pcall(textutils.unserialize, data)
            if success and type(result) == "table" then
                return result
            else
                if logFn then logFn("Corrupted data in " .. path .. ". A new file will be created.", true) end
            end
        else
            if logFn then logFn("Could not open " .. path .. " for reading: " .. tostring(err_open), true) end
        end
    end
    return {}
end

---
-- Loads a JSON file into a Lua table, with recovery logic.
-- @param path string: The file path to load from.
-- @param logFn function: Optional logging function(message, isError).
-- @return table: The loaded table, or an empty table on failure.
function DB.loadTableFromFileJSON(path, logFn)
    local tempPath = path .. ".tmp"
    
    if not fs.exists(path) and fs.exists(tempPath) then
        if logFn then logFn("Found incomplete save, restoring from " .. tempPath, false) end
        fs.move(tempPath, path)
    end

    if fs.exists(path) then
        local file, err_open = fs.open(path, "r")
        if file then
            local data = file.readAll()
            file.close()
            local success, result = pcall(textutils.unserializeJSON, data)
            if success and type(result) == "table" then
                return result
            else
                if logFn then logFn("Corrupted JSON in " .. path .. ". A new file will be created.", true) end
            end
        else
            if logFn then logFn("Could not open " .. path .. " for reading: " .. tostring(err_open), true) end
        end
    end
    return {}
end

---
-- Creates a dirty tracker for lazy persistence.
-- @param dbPointers table: Map of {[dbPath] = function() return dataTable end}
-- @param logFn function: Optional logging function(message, isError).
-- @return table: Tracker with queueSave(path) and backgroundSave() methods
function DB.createDirtyTracker(dbPointers, logFn)
    local dbDirty = {}
    
    local tracker = {}
    
    --- Marks a database path as needing to be saved.
    -- @param dbPath string: The database file path.
    function tracker.queueSave(dbPath)
        dbDirty[dbPath] = true
    end
    
    --- Checks if any database needs saving.
    -- @return boolean: True if at least one DB is dirty.
    function tracker.hasPendingSaves()
        for _, isDirty in pairs(dbDirty) do
            if isDirty then return true end
        end
        return false
    end
    
    --- Performs background save of all dirty databases.
    -- Should be called periodically (e.g., every 30 seconds).
    function tracker.backgroundSave()
        for path, isDirty in pairs(dbDirty) do
            if isDirty and dbPointers[path] then
                if logFn then logFn("Background saving " .. path .. "...") end
                if DB.saveTableToFile(path, dbPointers[path](), logFn) then
                    dbDirty[path] = false
                end
            end
        end
    end
    
    --- Forces immediate save of a specific database.
    -- @param dbPath string: The database file path.
    -- @return boolean: True on success.
    function tracker.forceSave(dbPath)
        if dbPointers[dbPath] then
            local success = DB.saveTableToFile(dbPath, dbPointers[dbPath](), logFn)
            if success then dbDirty[dbPath] = false end
            return success
        end
        return false
    end
    
    --- Gets the dirty state table (for debugging/inspection).
    -- @return table: The dirty flags table.
    function tracker.getDirtyState()
        return dbDirty
    end
    
    return tracker
end

return DB
