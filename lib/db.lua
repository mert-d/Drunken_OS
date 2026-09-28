--[[
    Drunken OS - Shared Database Library (v1.1)
    Atomic file persistence with crash recovery, log compaction, and dirty tracking.
]]

local DB = {}
DB._VERSION = 1.1

local function atomicSave(path, data, serializer, logFn, desc)
    local tempPath = path .. ".tmp"
    local file, err_open = fs.open(tempPath, "w")
    if not file then
        if logFn then logFn("Could not open temp file " .. tempPath .. ": " .. tostring(err_open), true) end
        return false
    end

    local success, err_write = pcall(function()
        file.write(serializer(data))
        file.close()
    end)

    if not success then
        if logFn then logFn("Failed to write " .. (desc or "") .. " to " .. tempPath .. ": " .. tostring(err_write), true) end
        pcall(fs.delete, tempPath)
        return false
    end

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

local function loadTable(path, unserializer, logFn, desc)
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
            local success, result = pcall(unserializer, data)
            if success and type(result) == "table" then
                return result
            else
                if logFn then logFn("Corrupted " .. (desc or "") .. " data in " .. path .. ". A new file will be created.", true) end
            end
        else
            if logFn then logFn("Could not open " .. path .. " for reading: " .. tostring(err_open), true) end
        end
    end
    return {}
end

-- Saves a table using Lua serialization and atomic write (.tmp -> path)
function DB.saveTableToFile(path, data, logFn)
    return atomicSave(path, data, textutils.serialize, logFn, "data")
end

-- Saves a table using JSON serialization and atomic write
function DB.saveTableToFileJSON(path, data, logFn)
    return atomicSave(path, data, textutils.serializeJSON, logFn, "JSON")
end

-- Loads a Lua table with automatic crash recovery from .tmp
function DB.loadTableFromFile(path, logFn)
    return loadTable(path, textutils.unserialize, logFn, "Lua")
end

-- Loads a JSON file with automatic crash recovery from .tmp
function DB.loadTableFromFileJSON(path, logFn)
    return loadTable(path, textutils.unserializeJSON, logFn, "JSON")
end

-- Compacts an append-only log file if it exceeds maxBytes, keeping newest keepLines
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

    if fs.exists(path) then pcall(fs.delete, path) end
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

-- Creates a dirty tracker for lazy persistence and periodic log compaction
function DB.createDirtyTracker(dbPointers, logFn, formats)
    local dbDirty = {}
    local fmtMap = formats or {}
    local trackedLogs = {}
    local tracker = {}

    function tracker.queueSave(dbPath)
        dbDirty[dbPath] = true
    end

    function tracker.registerLog(logPath, maxBytes, keepLines)
        table.insert(trackedLogs, { path = logPath, maxBytes = maxBytes, keepLines = keepLines })
    end

    function tracker.hasPendingSaves()
        for _, isDirty in pairs(dbDirty) do
            if isDirty then return true end
        end
        return false
    end

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
        for _, l in ipairs(trackedLogs) do
            DB.compactLogFile(l.path, l.maxBytes, l.keepLines, logFn)
        end
    end

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

    function tracker.getDirtyState()
        return dbDirty
    end

    return tracker
end

return DB
