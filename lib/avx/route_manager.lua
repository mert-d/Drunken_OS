--[[
    AVX Module: Route Manager & Flight Management Computer (FMC) v1.0
    (Drunken OS Autonomous Navigation & Waypoint Guidance)

    Features:
    - Multi-waypoint flight plan creation, persistence (/routes/*.json), and sequencing
    - True LNAV Cross-Track Error (XTK) calculation with smooth intercept heading
    - VNAV vertical guidance: distance-proportional altitude climb/descent profiling
    - Turn anticipation (Fly-by / Fly-over) based on turn radius & ground speed
    - Waypoint terminal actions: FLYBY, FLYOVER, HOVER, ANCHOR, DOCK
    - Route loop (endless patrol) or end actions (HOVER, ANCHOR, RTB, DOCK)
]]

local M = { name = "ROUTE_MANAGER", version = 1 }

local function clamp(val, minV, maxV)
    return math.max(minV, math.min(maxV, val))
end

-- Default Points of Interest (POIs) in Skyfire's theatre of operations
M.DEFAULT_POIS = {
    { name = "DOCK_SKYFIRE", x = 1116.7, y = 184.6, z = -242.8, heading = math.rad(180), action = "DOCK", desc = "Skyfire Ana Iskele & Tersane" },
    { name = "TOWER_ILS",    x = 1000.0, y = 200.0, z = -240.0, heading = math.rad(90),  action = "FLYBY", desc = "Havalimani ILS Radar Kulesi" },
    { name = "OUTPOST_NORD", x = 1116.7, y = 210.0, z =   50.0, heading = math.rad(0),   action = "HOVER", desc = "Kuzey Gözetleme Karakolu" },
    { name = "MINING_CAMP",  x = 1500.0, y = 195.0, z = -400.0, heading = math.rad(270), action = "HOVER", desc = "Maden & Lojistik Sahasi" }
}

local RouteManager = {}
RouteManager.__index = RouteManager

function RouteManager.new(config)
    config = config or {}
    local self = setmetatable({}, RouteManager)
    self.routesDir = config.routesDir or "/routes"
    self.activeRoute = nil
    self.pois = {}
    for _, p in ipairs(M.DEFAULT_POIS) do
        table.insert(self.pois, {
            name    = p.name,
            x       = p.x,
            y       = p.y,
            z       = p.z,
            heading = p.heading,
            action  = p.action or "FLYBY",
            desc    = p.desc
        })
    end

    if fs and fs.makeDir and not fs.exists(self.routesDir) then
        pcall(fs.makeDir, self.routesDir)
    end

    return self
end

function RouteManager:createRoute(name, waypoints, loop, endAction)
    self.activeRoute = {
        name        = name or "YENI_ROTA",
        loop        = (loop == true),
        endAction   = endAction or "HOVER",
        activeIdx   = 1,
        legStartPos = nil,
        waypoints   = waypoints or {}
    }
    return self.activeRoute
end

function RouteManager:addWaypoint(wp)
    if not self.activeRoute then
        self:createRoute("VARSAYILAN_ROTA", {}, false, "HOVER")
    end
    local w = {
        name   = wp.name or string.format("WP%d", #self.activeRoute.waypoints + 1),
        x      = tonumber(wp.x) or 0,
        y      = tonumber(wp.y) or 185,
        z      = tonumber(wp.z) or 0,
        speed  = tonumber(wp.speed) or 8,
        radius = tonumber(wp.radius) or 8,
        action = wp.action or "FLYBY" -- FLYBY, FLYOVER, HOVER, ANCHOR, DOCK
    }
    table.insert(self.activeRoute.waypoints, w)
    return #self.activeRoute.waypoints
end

function RouteManager:removeWaypoint(idx)
    if not self.activeRoute or not self.activeRoute.waypoints[idx] then return false end
    table.remove(self.activeRoute.waypoints, idx)
    if self.activeRoute.activeIdx > #self.activeRoute.waypoints then
        self.activeRoute.activeIdx = math.max(1, #self.activeRoute.waypoints)
    end
    return true
end

function RouteManager:clearRoute()
    if self.activeRoute then
        self.activeRoute.waypoints = {}
        self.activeRoute.activeIdx = 1
        self.activeRoute.legStartPos = nil
    end
end

function RouteManager:setActiveIndex(idx, currentPos)
    if not self.activeRoute or #self.activeRoute.waypoints == 0 then return false end
    self.activeRoute.activeIdx = math.max(1, math.min(#self.activeRoute.waypoints, idx))
    if currentPos then
        self.activeRoute.legStartPos = {
            x = currentPos.x or 0,
            y = currentPos.y or currentPos.altitude or 185,
            z = currentPos.z or 0
        }
    else
        self.activeRoute.legStartPos = nil
    end
    return true
end

function RouteManager:getActiveWaypoint()
    if not self.activeRoute or #self.activeRoute.waypoints == 0 then return nil end
    return self.activeRoute.waypoints[self.activeRoute.activeIdx]
end

function RouteManager:getPreviousWaypoint(currentPos)
    if not self.activeRoute or #self.activeRoute.waypoints == 0 then return nil end
    local idx = self.activeRoute.activeIdx
    if idx > 1 then
        return self.activeRoute.waypoints[idx - 1]
    elseif self.activeRoute.loop and #self.activeRoute.waypoints > 1 then
        return self.activeRoute.waypoints[#self.activeRoute.waypoints]
    elseif self.activeRoute.legStartPos then
        return self.activeRoute.legStartPos
    elseif currentPos then
        return { x = currentPos.x or 0, y = currentPos.y or currentPos.altitude or 185, z = currentPos.z or 0 }
    end
    return self.activeRoute.waypoints[1]
end

-- Advances to the next waypoint; handles route end actions and looping
function RouteManager:advance(currentPos)
    if not self.activeRoute or #self.activeRoute.waypoints == 0 then return false, "NO_ROUTE" end
    local total = #self.activeRoute.waypoints
    local currWp = self.activeRoute.waypoints[self.activeRoute.activeIdx]

    -- Set leg start position to current position for the next leg's XTK calculation
    if currentPos then
        self.activeRoute.legStartPos = {
            x = currentPos.x or 0,
            y = currentPos.y or currentPos.altitude or 185,
            z = currentPos.z or 0
        }
    elseif currWp then
        self.activeRoute.legStartPos = { x = currWp.x, y = currWp.y, z = currWp.z }
    end

    if self.activeRoute.activeIdx < total then
        self.activeRoute.activeIdx = self.activeRoute.activeIdx + 1
        return true, "ADVANCED", self.activeRoute.waypoints[self.activeRoute.activeIdx]
    elseif self.activeRoute.loop then
        self.activeRoute.activeIdx = 1
        return true, "LOOPED", self.activeRoute.waypoints[1]
    else
        local endAction = self.activeRoute.endAction or "HOVER"
        return false, "COMPLETED", endAction
    end
end

-- Cross-Track Error (XTK) & Course Intercept Mathematics
-- Calculates perpendicular distance to the desired track line connecting prevWp -> tgtWp
function RouteManager:calculateGuidance(currentPos, currentVel, prevWp, tgtWp)
    if not currentPos or not tgtWp then return nil end
    local cx = currentPos.x or 0
    local cy = currentPos.y or currentPos.altitude or 185
    local cz = currentPos.z or 0

    local tx = tgtWp.x
    local ty = tgtWp.y or cy
    local tz = tgtWp.z

    -- Direct vector to target waypoint
    local toTgtX = tx - cx
    local toTgtZ = tz - cz
    local distToTgt = math.sqrt(toTgtX * toTgtX + toTgtZ * toTgtZ)
    local directHdg = math.atan2(-toTgtX, toTgtZ)

    local prevX = prevWp and prevWp.x or (cx - math.sin(directHdg) * 10)
    local prevY = prevWp and prevWp.y or cy
    local prevZ = prevWp and prevWp.z or (cz + math.cos(directHdg) * 10)

    -- Leg vector from prevWp to tgtWp
    local legX = tx - prevX
    local legZ = tz - prevZ
    local legLen = math.sqrt(legX * legX + legZ * legZ)

    local legHdg = directHdg
    local xtk = 0.0
    local along = 0.0

    if legLen > 2.0 then
        legHdg = math.atan2(-legX, legZ)
        -- Vector from prevWp to currentPos
        local px = cx - prevX
        local pz = cz - prevZ

        -- Cross-track error (positive = right of desired course, negative = left)
        -- In Minecraft X/Z: X is East (+), Z is South (+). Heading 0 is South (-cos), 90 is West (-sin).
        -- Leg unit vector: (-sin(legHdg), cos(legHdg))
        -- Perpendicular normal vector: (cos(legHdg), sin(legHdg))
        xtk = px * math.cos(legHdg) + pz * math.sin(legHdg)
        along = -px * math.sin(legHdg) + pz * math.cos(legHdg)
    end

    -- Cross-track intercept angle (Gain K_xtk: 2.5 deg per meter of XTK, capped at +/- 45 deg)
    local kXtk = 2.5
    local interceptDeg = clamp(xtk * kXtk, -45.0, 45.0)
    local commandedHdg = (legHdg - math.rad(interceptDeg)) % (2 * math.pi)

    -- VNAV vertical guidance: smooth vertical speed profile along the leg
    local deltaAlt = ty - cy
    local targetAlt = ty
    local vSpeedTarget = 0.0
    if distToTgt > 1.0 then
        local gndSpd = math.max(2.0, math.abs(currentVel and (currentVel.z or currentVel.speed) or 6.0))
        local eteSec = distToTgt / gndSpd
        vSpeedTarget = clamp(deltaAlt / math.max(1.0, eteSec), -4.0, 4.0)
    end

    -- Turn anticipation distance for FLYBY waypoints
    -- R_turn = v^2 / (g * tan(max_bank)), for mothership typical radius is 6-12m
    local wpRadius = tgtWp.radius or 8.0
    local speed = currentVel and currentVel.speed or 8.0
    local turnAnticipationDist = (tgtWp.action == "FLYBY") and (wpRadius + speed * 0.8) or wpRadius

    local isArrived = (distToTgt <= turnAnticipationDist)

    local gndSpeed = math.max(0.5, (currentVel and currentVel.speed) or 0)
    local ete = distToTgt / gndSpeed

    return {
        distToTgt     = distToTgt,
        directHdg     = directHdg,
        legHdg        = legHdg,
        commandedHdg  = commandedHdg,
        xtk           = xtk,
        along         = along,
        targetAlt     = targetAlt,
        deltaAlt      = deltaAlt,
        vSpeedTarget  = vSpeedTarget,
        ete           = ete,
        isArrived     = isArrived,
        arrivalRadius = turnAnticipationDist
    }
end

-- Disk Persistence (/routes/*.json)
function RouteManager:saveRoute(name)
    if not self.activeRoute then return false, "NO_DATA" end
    if not (fs and fs.open) then return false, "NO_FS" end
    local rName = name or self.activeRoute.name or "route"
    -- Sanitize filename
    rName = rName:gsub("[^%w_%-]", "_")
    local path = self.routesDir .. "/" .. rName .. ".json"
    local data = {
        name      = self.activeRoute.name,
        loop      = self.activeRoute.loop,
        endAction = self.activeRoute.endAction,
        waypoints = self.activeRoute.waypoints
    }
    local json = nil
    if textutils and textutils.serializeJSON then
        local ok, res = pcall(textutils.serializeJSON, data)
        if ok and res then json = res end
    end
    if not json and textutils and textutils.serialize then
        local ok, res = pcall(textutils.serialize, data)
        if ok and res then json = res end
    end
    if not json then
        -- Standalone Lua fallback serializer for unit testing
        local parts = {}
        table.insert(parts, string.format('{"name":"%s","loop":%s,"endAction":"%s","waypoints":[', data.name, tostring(data.loop), data.endAction))
        for i, w in ipairs(data.waypoints or {}) do
            table.insert(parts, string.format('{"name":"%s","x":%s,"y":%s,"z":%s,"speed":%s,"radius":%s,"action":"%s"}%s',
                w.name, tostring(w.x), tostring(w.y), tostring(w.z), tostring(w.speed), tostring(w.radius), w.action, (i < #data.waypoints and "," or "")))
        end
        table.insert(parts, "]} ")
        json = table.concat(parts)
    end

    local f = fs.open(path, "w")
    if not f then return false, "FILE_OPEN_FAIL" end
    f.write(json)
    f.close()
    return true, path
end

function RouteManager:loadRoute(name)
    if not (fs and fs.open) then return false, "NO_FS" end
    local rName = name:gsub("[^%w_%-]", "_")
    local path = self.routesDir .. "/" .. rName .. ".json"
    if not (fs.exists and fs.exists(path)) then
        path = self.routesDir .. "/" .. rName
        if not (fs.exists and fs.exists(path)) then return false, "NOT_FOUND" end
    end

    local f = fs.open(path, "r")
    if not f then return false, "FILE_OPEN_FAIL" end
    local content = f.readAll()
    f.close()

    local data = nil
    if textutils and textutils.unserializeJSON then
        local ok, res = pcall(textutils.unserializeJSON, content)
        if ok and res then data = res end
    end
    if not data and textutils and textutils.unserialize then
        local ok, res = pcall(textutils.unserialize, content)
        if ok and res then data = res end
    end
    if not data and type(content) == "string" then
        -- Simple JSON decoder fallback for standalone test environments
        local nameVal = content:match('"name"%s*:%s*"([^"]+)"')
        local loopVal = (content:match('"loop"%s*:%s*true') ~= nil)
        local endAct = content:match('"endAction"%s*:%s*"([^"]+)"')
        local wps = {}
        local wpArray = content:match('"waypoints"%s*:%s*%[(.-)%]') or content
        for wpStr in wpArray:gmatch('%{([^%}]+)%}') do
            local wName = wpStr:match('"name"%s*:%s*"([^"]+)"')
            local wx = tonumber(wpStr:match('"x"%s*:%s*([%-%d%.]+)'))
            local wy = tonumber(wpStr:match('"y"%s*:%s*([%-%d%.]+)'))
            local wz = tonumber(wpStr:match('"z"%s*:%s*([%-%d%.]+)'))
            local wspd = tonumber(wpStr:match('"speed"%s*:%s*([%-%d%.]+)'))
            local wrad = tonumber(wpStr:match('"radius"%s*:%s*([%-%d%.]+)'))
            local wact = wpStr:match('"action"%s*:%s*"([^"]+)"')
            if wName and wx and wz then
                table.insert(wps, {
                    name = wName, x = wx, y = wy or 185, z = wz, speed = wspd or 8, radius = wrad or 8, action = wact or "FLYBY"
                })
            end
        end
        if nameVal or #wps > 0 then
            data = { name = nameVal or rName, loop = loopVal, endAction = endAct or "HOVER", waypoints = wps }
        end
    end

    if type(data) ~= "table" or not data.waypoints then return false, "INVALID_FORMAT" end

    self.activeRoute = {
        name        = data.name or rName,
        loop        = (data.loop == true),
        endAction   = data.endAction or "HOVER",
        activeIdx   = 1,
        legStartPos = nil,
        waypoints   = data.waypoints or {}
    }
    return true, self.activeRoute
end

function RouteManager:listSavedRoutes()
    local list = {}
    if not (fs and fs.list and fs.exists and fs.exists(self.routesDir)) then return list end
    local files = fs.list(self.routesDir)
    for _, f in ipairs(files) do
        local base = f:match("^(.-)%.json$") or f
        table.insert(list, base)
    end
    table.sort(list)
    return list
end

-- Telemetry Hook for Avionics Core integration
function M.onTelemetry(fc, tel, dt)
    if not fc.routeManager then
        fc.routeManager = RouteManager.new()
    end
    local rm = fc.routeManager

    if not (fc.ap and fc.ap.enabled and fc.ap.mode == "LNAV") then
        tel.navRoute = nil
        return
    end

    local activeWp = rm:getActiveWaypoint()
    if not activeWp then
        -- Fall back to single waypoint legacy LNAV if route is empty
        if fc.ap.waypoint then
            local dx = fc.ap.waypoint.x - tel.pos.x
            local dz = fc.ap.waypoint.z - tel.pos.z
            local distSq = dx * dx + dz * dz
            if distSq > 25 then
                fc.ap.targetHdg = math.atan2(-dx, dz)
                if fc.ap.waypoint.y then fc.ap.targetAlt = fc.ap.waypoint.y end
            else
                fc:setMode("HOVER", tel)
            end
        end
        return
    end

    local prevWp = rm:getPreviousWaypoint(tel.pos)
    local guide = rm:calculateGuidance(tel.pos, tel.velocity or { speed = tel.speed }, prevWp, activeWp)
    if not guide then return end

    -- Apply LNAV heading & VNAV altitude guidance
    fc.ap.targetHdg = guide.commandedHdg
    fc.ap.targetAlt = guide.targetAlt
    if activeWp.speed and activeWp.speed > 0 then
        fc.ap.baseThrottle = math.min(15, math.max(2, math.floor(activeWp.speed)))
    end

    -- Export rich telemetry for Cockpit PFD, Secondary Monitors & Tactical Holo-Table
    tel.navRoute = {
        name         = rm.activeRoute.name,
        activeIdx    = rm.activeRoute.activeIdx,
        totalWps     = #rm.activeRoute.waypoints,
        wpName       = activeWp.name,
        action       = activeWp.action,
        dist         = guide.distToTgt,
        xtk          = guide.xtk,
        ete          = guide.ete,
        legHdg       = guide.legHdg,
        targetHdg    = guide.commandedHdg,
        targetAlt    = guide.targetAlt,
        loop         = rm.activeRoute.loop,
        waypoints    = rm.activeRoute.waypoints
    }

    -- Check waypoint arrival and execute sequencing or terminal action
    if guide.isArrived then
        if activeWp.action == "HOVER" then
            fc:setMode("HOVER", tel)
            rm:advance(tel.pos)
        elseif activeWp.action == "ANCHOR" then
            fc:setMode("ANCHOR", tel)
            rm:advance(tel.pos)
        elseif activeWp.action == "DOCK" then
            fc.ap.targetAlt = activeWp.y or tel.altitude
            fc.ap.baseThrottle = 0
            fc.ap.parkingBrake = true
            fc:setMode("ANCHOR", tel)
            rm:advance(tel.pos)
        else
            -- FLYBY / FLYOVER
            local advanced, status, nextWpOrEnd = rm:advance(tel.pos)
            if not advanced and status == "COMPLETED" then
                if nextWpOrEnd == "ANCHOR" then
                    fc:setMode("ANCHOR", tel)
                elseif nextWpOrEnd == "RTB" then
                    fc:engageRTB(tel)
                elseif nextWpOrEnd == "DOCK" then
                    fc.ap.baseThrottle = 0
                    fc.ap.parkingBrake = true
                    fc:setMode("ANCHOR", tel)
                else
                    fc:setMode("HOVER", tel)
                end
            end
        end
    end
end

M.RouteManager = RouteManager
return M
