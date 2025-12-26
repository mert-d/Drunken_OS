-- Test script for Arcade Leaderboards verification
-- This script simulates a client interacting with the Arcade Server

local function test()
    print("Arcade Leaderboard Verification Script")
    
    local modem = peripheral.find("modem")
    if not modem then
        print("Error: Modem not found. Please attach a modem to run this test.")
        return
    end
    rednet.open(peripheral.getName(modem))

    local serverId = rednet.lookup("ArcadeGames", "arcade.server")
    if not serverId then
        print("Error: Arcade Server not found on rednet. Ensure Drunken_Arcade_Server.lua is running.")
        return
    end
    print("Connected to Arcade Server (ID: " .. serverId .. ")")

    -- 1. Submit a test score
    local testUser = "TestUser_" .. math.random(1000, 9999)
    local testScore = math.random(500, 5000)
    print("Submitting score for " .. testUser .. ": " .. testScore)
    rednet.send(serverId, {
        type = "submit_score",
        game = "Snake",
        user = testUser,
        score = testScore,
        timestamp = os.epoch("utc")
    }, "ArcadeGames")

    -- 2. Wait for background processing (though submission is async on server)
    sleep(1)

    -- 3. Request the board
    print("Requesting leaderboard for Snake...")
    rednet.send(serverId, {
        type = "get_board",
        game = "Snake"
    }, "ArcadeGames")

    local id, msg = rednet.receive("ArcadeGames", 5)
    if not id then
        print("Error: No response from server for get_board.")
        return
    end

    if msg.type == "leaderboard_response" then
        print("\n--- Snake Leaderboard ---")
        for i, entry in ipairs(msg.board) do
            print(string.format("%d. %s: %d", i, entry.user, entry.score))
        end
        print("-------------------------\n")
        
        -- Verify if our test user is there
        local found = false
        for _, entry in ipairs(msg.board) do
            if entry.user == testUser and entry.score == testScore then
                found = true
                break
            end
        end
        
        if found then
            print("SUCCESS: Test score found in leaderboard!")
        else
            print("FAILURE: Test score not found in top 10 (might be due to higher existing scores).")
        end
    else
        print("Error: Unexpected response type: " .. tostring(msg.type))
    end
end

test()
