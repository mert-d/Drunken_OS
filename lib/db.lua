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
    local ok_move, err_move = pcall(fs.move, tempPath, path)
    if not ok_move then
        if logFn then logFn("Failed to move " .. tempPath .. " to " .. path .. ": " .. tostring(err_move), true) end
        return false
    end
    
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
    local ok_move, err_move = pcall(fs.move, tempPath, path)
    if not ok_move then
        if logFn then logFn("Failed to move JSON " .. tempPath .. " to " .. path .. ": " .. tostring(err_move), true) end
        return false
    end
    
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
        pcall(fs.move, tempPath, path)
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
        pcall(fs.move, tempPath, path)
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
-- Compacts an append-only log file if it exceeds a size threshold.
-- Reads the file, preserves the newest keepLines, and performs an atomic rewrite.
-- @param path string: Path to the log file.
-- @param maxBytes number|nil: Size threshold in bytes (default: 50 * 1024 = 50KB).
-- @param keepLines number|nil: Number of recent lines to keep (default: 200).
-- @param logFn function|nil: Optional logging function(msg, isErr).
-- @return boolean: True if compacted, false if not needed or failed.
function DB.compactLogFile(path, maxBytes, keepLines, logFn)
    if not fs or not fs.exists or not fs.exists(path) then return false end
    local threshold = maxBytes or (50 * 1024)
    local linesToKeep = keepLines or 200

    local size = (fs.getSize and fs.getSize(path)) or 0
    if size <= threshold then return false end

    local file = fs.open(path, "r")
    if not file then return false end

    local allLines = {}
    local line = file.readLine()
    while line do
        table.insert(allLines, line)
        line = file.readLine()
    end
    file.close()

    if #allLines <= linesToKeep then return false end

    local tempPath = path .. ".tmp"
    local tempFile, err = fs.open(tempPath, "w")
    if not tempFile then
        if logFn then logFn("Failed to open temp file for log compaction: " .. tostring(err), true) end
        return false
    end

    local startIdx = #allLines - linesToKeep + 1
    for i = startIdx, #allLines do
        tempFile.writeLine(allLines[i])
    end
    tempFile.close()

    -- Atomic swap
    if fs.exists(path) then
        pcall(fs.delete, path)
    end
    local ok_move, err_move = pcall(fs.move, tempPath, path)
    if ok_move then
        if logFn then
            logFn(string.format("Compacted %s: reduced from %d lines to %d lines.", path, #allLines, linesToKeep), false)
        end
        return true
    else
        if logFn then logFn("Failed to finalize log compaction: " .. tostring(err_move), true) end
        return false
    end
end

---
-- Creates a dirty tracker for lazy persistence.
-- @param dbPointers table: Map of {[dbPath] = function() return dataTable end}
-- @param logFn function: Optional logging function(message, isError).
-- @param formats table|nil: Optional map of {[dbPath] = "json"|"lua"}
-- @return table: Tracker with queueSave(path) and backgroundSave() methods
function DB.createDirtyTracker(dbPointers, logFn, formats)
    local dbDirty = {}
    local fmtMap = formats or {}
    local trackedLogs = {}
    
    local tracker = {}
    
    --- Marks a database path as needing to be saved.
    -- @param dbPath string: The database file path.
    function tracker.queueSave(dbPath)
        dbDirty[dbPath] = true
    end
    
    --- Registers an append-only log file to be auto-compacted during background save.
    -- @param logPath string: File path to the log file.
    -- @param maxBytes number|nil: Size threshold in bytes (default: 50KB).
    -- @param keepLines number|nil: Number of recent lines to keep (default: 200).
    function tracker.registerLog(logPath, maxBytes, keepLines)
        table.insert(trackedLogs, { path = logPath, maxBytes = maxBytes, keepLines = keepLines })
    end

    --- Checks if any database needs saving.
    -- @return boolean: True if at least one DB is dirty.
    function tracker.hasPendingSaves()
        for _, isDirty in pairs(dbDirty) do
            if isDirty then return true end
        end
        return false
    end
    
    --- Performs background save of all dirty databases and compacts registered logs.
    -- Should be called periodically (e.g., every 30 seconds).
    function tracker.backgroundSave()
        for path, isDirty in pairs(dbDirty) do
            if isDirty and dbPointers[path] then
                if logFn then logFn("Background saving " .. path .. "...") end
                local isJson = (fmtMap[path] == "json" or path:match("%.json$"))
                local saveFunc = isJson and DB.saveTableToFileJSON or DB.saveTableToFile
                if saveFunc(path, dbPointers[path](), logFn) then
                    dbDirty[path] = false
                end
            end
        end

        -- Periodic log compaction
        for _, l in ipairs(trackedLogs) do
            DB.compactLogFile(l.path, l.maxBytes, l.keepLines, logFn)
        end
    end
    
    --- Forces immediate save of a specific database.
    -- @param dbPath string: The database file path.
    -- @return boolean: True on success.
    function tracker.forceSave(dbPath)
        if dbPointers[dbPath] then
            local isJson = (fmtMap[dbPath] == "json" or dbPath:match("%.json$"))
            local saveFunc = isJson and DB.saveTableToFileJSON or DB.saveTableToFile
            local success = saveFunc(dbPath, dbPointers[dbPath](), logFn)
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
