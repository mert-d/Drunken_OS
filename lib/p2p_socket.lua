--[[
    P2P Socket Library (v1.0)
    Part of Drunken OS Shared Libraries

    Purpose:
    Standardizes networking for multiplayer games, handling:
    - Rednet initialization
    - Arcade Server Lobby Management (Host/List)
    - Peer-to-Peer Handshakes & Version Checking
    - Game Loop Communication
]]

local P2P_Socket = {}
P2P_Socket.__index = P2P_Socket

--- Creates a new P2P Socket instance
-- @param gameName string: The internal name of the game (e.g. "DrunkenDuels")
-- @param version number: The game version for compatibility checks
-- @param protocol string: The rednet protocol for this game (e.g. "DrunkenDuels_Game")
-- @return table: The new socket instance
function P2P_Socket.new(gameName, version, protocol)
    local self = setmetatable({}, P2P_Socket)
    self.gameName = gameName
    self.version = version
    self.protocol = protocol
    self.lobbyProtocol = protocol .. "_Lobby" -- Convention: GameProtocol + "_Lobby"
    self.peerId = nil
    self.spectatorIds = {}
    self.isHost = false
    self.arcadeId = nil
    
    -- Initialize Network on creation
    self:initNetwork()
    
    return self
end

--- Ensures Modem is present and Rednet is open
function P2P_Socket:initNetwork()
    local modem = peripheral.find("modem")
    if not modem then
        error(self.gameName .. " requires a Modem to play!", 0)
    end
    if not rednet.isOpen() then
        rednet.open(peripheral.getName(modem))
    end
    self.arcadeId = rednet.lookup("ArcadeGames_Internal", "arcade.server.internal")
end

--- Searches for the Arcade Server
-- @return boolean: true if found, false otherwise
function P2P_Socket:checkArcade()
    self.arcadeId = rednet.lookup("ArcadeGames_Internal", "arcade.server.internal")
    return self.arcadeId ~= nil
end

--- Lists available lobbies for this game from the Arcade
-- @return table|nil: A list of lobbies { {id=1, user="Name"}, ... } or nil if failed
function P2P_Socket:findLobbies()
    if not self:checkArcade() then return nil, "Arcade Offline" end
    
    rednet.send(self.arcadeId, {type="list_lobbies"}, "ArcadeGames")
    local _, reply = rednet.receive("ArcadeGames", 3)
    
    if not reply or not reply.lobbies then return nil, "No response" end
    
    local options = {}
    for id, lob in pairs(reply.lobbies) do
        if lob.game == self.gameName then
            table.insert(options, {id=id, user=lob.user})
        end
    end
    
    return options
end

--- Registers this machine as a Host on the Arcade
-- @param username string: The host's username
function P2P_Socket:hostGame(username)
    if not self:checkArcade() then return false, "Arcade Offline" end
    
    self.isHost = true
    rednet.send(self.arcadeId, {type="host_game", user=username, game=self.gameName}, "ArcadeGames")
    return true
end

--- Cancels hosting (removes from Arcade)
function P2P_Socket:stopHosting()
    if self.arcadeId then
        rednet.send(self.arcadeId, {type="close_lobby"}, "ArcadeGames")
    end
end

--- Waits for a player to join (Host side handshake)
-- @param timeout number: How long to wait in seconds (optional)
-- @return table|nil: The join message if successful (contains user, class, etc.), or nil
function P2P_Socket:waitForJoin(timeout)
    local id, msg = rednet.receive(self.lobbyProtocol, timeout)
    if id and msg and msg.type == "match_join" then
        self.peerId = id
        -- Accept the match
        rednet.send(id, {
            type="match_accept", 
            version=self.version
        }, self.lobbyProtocol)
        
        -- Close lobby listing
        self:stopHosting()
        
        return msg -- Return the join payload (often contains username, class, etc.)
    end
    return nil
end

--- Connects to a specific Host ID (Client side handshake)
-- @param hostId number: The ID of the host to connect to
-- @param payload table: Additional data to send (username, class, etc.)
-- @return table|false: The accept message if successful, false/error otherwise
function P2P_Socket:connect(hostId, payload)
    self.peerId = hostId
    self.isHost = false
    
    local joinMsg = payload or {}
    joinMsg.type = "match_join"
    joinMsg.version = self.version
    
    rednet.send(hostId, joinMsg, self.lobbyProtocol)
    
    local id, msg = rednet.receive(self.lobbyProtocol, 5)
    if id == hostId and msg and msg.type == "match_accept" then
        if msg.version ~= self.version then
            return false, "Version Mismatch! Host: v" .. (msg.version or "??")
        end
        return msg -- Success, return accept payload
    end
    
    return false, "Connection Timed Out"
end

--- Waits for a spectator to join
-- @param timeout number: How long to wait in seconds (optional)
-- @return table|nil: The spectate message if successful, or nil
function P2P_Socket:acceptSpectator(timeout)
    local id, msg = rednet.receive(self.lobbyProtocol, timeout)
    if id and msg and msg.type == "spectate_join" then
        table.insert(self.spectatorIds, id)
        -- Accept the spectator
        rednet.send(id, {
            type="spectate_accept", 
            version=self.version
        }, self.lobbyProtocol)
        
        return msg
    end
    return nil
end

--- Connects as a spectator (Client side)
-- @param hostId number: The ID of the host to spectate
-- @return table|false: The accept message if successful, false/error otherwise
function P2P_Socket:spectate(hostId)
    self.peerId = hostId -- For spectators, the host is the "peer" they listen to
    self.isHost = false
    
    local joinMsg = {
        type = "spectate_join",
        version = self.version
    }
    
    rednet.send(hostId, joinMsg, self.lobbyProtocol)
    
    local id, msg = rednet.receive(self.lobbyProtocol, 5)
    if id == hostId and msg and msg.type == "spectate_accept" then
        if msg.version ~= self.version then
            return false, "Version Mismatch! Host: v" .. (msg.version or "??")
        end
        return msg
    end
    
    return false, "Connection Timed Out"
end

--- Sends data to the connected peer
-- @param data table: The data to send
function P2P_Socket:send(data)
    if self.isHost then
        -- Send to primary peer (Player 2)
        if self.peerId then
            rednet.send(self.peerId, data, self.protocol)
        end
        -- Also send to all spectators
        for _, id in ipairs(self.spectatorIds) do
            rednet.send(id, data, self.protocol)
        end
    else
        -- Clients/Spectators send only to host
        if self.peerId then
            rednet.send(self.peerId, data, self.protocol)
        end
    end
end

--- Receives data from the connected peer
-- @param timeout number: Timeout in seconds
-- @return table|nil: The received data or nil
function P2P_Socket:receive(timeout)
    local id, msg = rednet.receive(self.protocol, timeout)
    if id == self.peerId then
        return msg
    end
    return nil
end

return P2P_Socket
