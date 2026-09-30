--[[
    Drunken OS - Offline-First Score Cache & Deferred Sync (lib/score_cache.lua)
    Version: 1.0
    
    Guarantees game achievements and high scores are never lost when playing
    offline or in unloaded chunks. High scores are cached locally and automatically
    synced to the Arcade Server leaderboard once the server is back online.
]]

local DB
local ok_db, loadedDB = pcall(require, "lib.db")
if ok_db and type(loadedDB) == "table" and type(loadedDB.loadTableFromFile) == "function" then
    DB = loadedDB
else
    -- Built-in lightweight fallback so score_cache never fails if lib.db is missing or damaged
    DB = {
        loadTableFromFile = function(path)
            if not fs.exists(path) then return {} end
            local f = fs.open(path, "r")
            if not f then return {} end
            local data = f.readAll()
            f.close()
            local ok, res = pcall(textutils.unserialize, data)
            return (ok and type(res) == "table") and res or {}
        end,
        saveTableToFile = function(path, tbl)
            local f = fs.open(path, "w")
            if not f then return false end
            f.write(textutils.serialize(tbl))
            f.close()
            return true
        end
    }
end

local SCORES_FILE = ".game_scores.db"
local PENDING_FILE = ".pending_scores.db"

local score_cache = {
    _VERSION = 1.0
}

local function getEpoch()
    if os.epoch then return math.floor(os.epoch("utc") / 1000) end
    if os.time then return os.time() end
    return 0
end

--- Retrieves all locally recorded game scores.
function score_cache.loadScores()
    return DB.loadTableFromFile(SCORES_FILE) or {}
end

--- Retrieves the personal best score for a game.
-- @param gameName string: Name of the game.
-- @return number: Highest recorded score or 0.
function score_cache.getPersonalBest(gameName)
    local data = score_cache.loadScores()
    if data[gameName] and data[gameName].personalBest then
        return data[gameName].personalBest
    end
    return 0
end

--- Retrieves the local history / leaderboard for a game.
-- @param gameName string: Name of the game.
-- @return table: Array of { score = number, user = string, timestamp = number }
function score_cache.getLocalLeaderboard(gameName)
    local data = score_cache.loadScores()
    if data[gameName] and data[gameName].history then
        return data[gameName].history
    end
    return {}
end

--- Records a game score locally, then submits to server or queues for deferred sync.
-- @param gameName string: Game title.
-- @param score number: Final score.
-- @param username string: Player's username.
-- @return boolean, string: Success flag and status ("submitted" or "queued").
function score_cache.recordScore(gameName, score, username)
    username = username or "Player"
    score = tonumber(score) or 0
    
    -- 1. Update Local Scores DB
    local allScores = score_cache.loadScores()
    if not allScores[gameName] then
        allScores[gameName] = { personalBest = 0, history = {} }
    end
    
    if score > (allScores[gameName].personalBest or 0) then
        allScores[gameName].personalBest = score
    end
    
    table.insert(allScores[gameName].history, 1, {
        user = username,
        score = score,
        timestamp = getEpoch()
    })
    
    -- Keep top 10 local entries
    table.sort(allScores[gameName].history, function(a, b) return a.score > b.score end)
    while #allScores[gameName].history > 10 do
        table.remove(allScores[gameName].history)
    end
    
    DB.saveTableToFile(SCORES_FILE, allScores)
    
    -- 2. Attempt Immediate Submission if Server is Reachable
    local arcadeId = nil
    if _G.rednet and rednet.isOpen and rednet.isOpen() then
        pcall(function()
            arcadeId = rednet.lookup("ArcadeGames", "arcade.server")
        end)
    end
    
    if arcadeId then
        rednet.send(arcadeId, {
            type = "submit_score",
            game = gameName,
            user = username,
            score = score
        }, "ArcadeGames")
        return true, "submitted"
    else
        -- 3. Queue for Deferred Sync
        local pending = DB.loadTableFromFile(PENDING_FILE) or {}
        table.insert(pending, {
            game = gameName,
            user = username,
            score = score,
            timestamp = getEpoch()
        })
        DB.saveTableToFile(PENDING_FILE, pending)
        return true, "queued"
    end
end

--- Returns the number of scores waiting to be synchronized.
function score_cache.getPendingCount()
    local pending = DB.loadTableFromFile(PENDING_FILE) or {}
    return #pending
end

--- Synchronizes all queued scores to the central Arcade server if online.
-- @return number, number: Synced count, Remaining pending count.
function score_cache.syncPending()
    local pending = DB.loadTableFromFile(PENDING_FILE) or {}
    if #pending == 0 then return 0, 0 end
    
    local arcadeId = nil
    if _G.rednet and rednet.isOpen and rednet.isOpen() then
        pcall(function()
            arcadeId = rednet.lookup("ArcadeGames", "arcade.server")
        end)
    end
    
    if not arcadeId then
        return 0, #pending -- Server still offline or unloaded
    end
    
    local synced = 0
    for _, item in ipairs(pending) do
        rednet.send(arcadeId, {
            type = "submit_score",
            game = item.game,
            user = item.user,
            score = item.score
        }, "ArcadeGames")
        synced = synced + 1
    end
    
    -- Clear pending queue after successful broadcast
    DB.saveTableToFile(PENDING_FILE, {})
    return synced, 0
end

return score_cache
