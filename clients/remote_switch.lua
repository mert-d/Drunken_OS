--[[
    Drunken Remote Switch (v1.0)
    Part of Drunken OS Base Automation Suite

    Purpose:
    Runs on any computer or wireless turtle placed adjacent to redstone components
    (clutches, gearshifts, redstone links, blast doors, pumps, sirens).
    Responds to wireless commands from the Drunken Remote pocket app.
]]

local configFile = ".switch_config.db"
local PROTOCOL = "DrunkenRemote"

-- Helper to safely load / save config table
local function loadConfig()
    if fs.exists(configFile) then
        local f = fs.open(configFile, "r")
        if f then
            local data = f.readAll()
            f.close()
            if textutils and textutils.unserialize then
                local t = textutils.unserialize(data)
                if type(t) == "table" then return t end
            end
        end
    end
    return nil
end

local function saveConfig(cfg)
    local f = fs.open(configFile, "w")
    if f then
        f.write(textutils.serialize(cfg))
        f.close()
        return true
    end
    return false
end

-- Check modem
local modem = peripheral.find("modem")
if not modem then
    term.clear()
    term.setCursorPos(1, 1)
    print("Error: Drunken Remote Switch requires a Wireless Modem.")
    print("Attach a wireless modem and run again.")
    return
end

if not rednet.isOpen() then
    rednet.open(peripheral.getName(modem))
end

-- First-time Setup Wizard
local config = loadConfig()
if not config then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.clear()
    term.setCursorPos(1, 2)
    print("=== DRUNKEN REMOTE SWITCH SETUP ===")
    term.setTextColor(colors.white)
    print("Configure this redstone switch for Drunken Remote.\n")

    -- 1. Switch Name
    write("Switch Name (e.g. Main Gate, Factory): ")
    term.setTextColor(colors.cyan)
    local name = read()
    if not name or name == "" then name = "Switch-" .. os.getComputerID() end
    term.setTextColor(colors.white)

    -- 2. Redstone Output Side
    print("\nSelect Redstone Output Side:")
    local sides = { "back", "left", "right", "top", "bottom", "front" }
    for i, s in ipairs(sides) do
        print(string.format(" [%d] %s", i, s:upper()))
    end
    write("Choose side [1-6] (Default 1): ")
    local sideChoice = tonumber(read()) or 1
    local side = sides[sideChoice] or "back"

    -- 3. Switch Mode
    print("\nSelect Switch Mode:")
    print(" [1] TOGGLE (Standard On/Off)")
    print(" [2] PULSE  (Momentary button press, e.g. 2s pulse)")
    write("Choose mode [1-2] (Default 1): ")
    local modeChoice = tonumber(read()) or 1
    local mode = (modeChoice == 2) and "pulse" or "toggle"
    local pulseDuration = 2
    if mode == "pulse" then
        write("Pulse duration in seconds (Default 2): ")
        pulseDuration = tonumber(read()) or 2
    end

    -- 4. Access Control
    print("\nAccess Level:")
    print(" [1] PUBLIC (Anyone in range can toggle)")
    print(" [2] PRIVATE (Owner only)")
    write("Choose access [1-2] (Default 1): ")
    local accChoice = tonumber(read()) or 1
    local isPublic = (accChoice ~= 2)
    local owner = nil
    if not isPublic then
        write("Enter owner username: ")
        owner = read()
    end

    config = {
        name = name,
        side = side,
        mode = mode,
        pulseDuration = pulseDuration,
        isPublic = isPublic,
        owner = owner or "Public",
        state = false,
        toggleCount = 0,
        lastOperator = "None"
    }
    saveConfig(config)
end

-- Ensure redstone state matches config on launch
redstone.setOutput(config.side, config.state)

local function drawStatus()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Title Bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" DRUNKEN REMOTE SWITCH v1.0 ")

    -- Details
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.yellow)
    term.write("Switch: ")
    term.setTextColor(colors.white)
    term.write(config.name)

    term.setCursorPos(2, 4)
    term.setTextColor(colors.gray)
    term.write("ID: " .. os.getComputerID() .. " | Side: " .. (config.side or "right"):upper() .. " | Mode: " .. (config.mode or "toggle"):upper())

    -- State Indicator
    term.setCursorPos(2, 6)
    term.write("Output State: ")
    if config.state then
        term.setBackgroundColor(colors.green)
        term.setTextColor(colors.white)
        term.write(" [  ACTIVE / ON  ] ")
    else
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.write(" [ INACTIVE / OFF ] ")
    end
    term.setBackgroundColor(colors.black)

    -- Stats
    term.setCursorPos(2, 8)
    term.setTextColor(colors.gray)
    term.write("Access: " .. (config.isPublic and "Public" or ("Owner (" .. tostring(config.owner) .. ")")))
    term.setCursorPos(2, 9)
    term.write("Toggles: " .. tostring(config.toggleCount) .. " | Last: " .. tostring(config.lastOperator))

    -- Footer hint
    term.setCursorPos(2, h)
    term.setTextColor(colors.lightGray or colors.gray)
    term.write("Listening on Rednet... [Q] to quit")
end

local pulseTimer = nil

local function setSwitchState(newState, operator)
    config.state = newState
    config.toggleCount = config.toggleCount + 1
    config.lastOperator = operator or "Unknown"
    redstone.setOutput(config.side, config.state)
    saveConfig(config)
    drawStatus()
end

drawStatus()

local running = true
while running do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "key" and p1 == keys.q then
        running = false
    elseif event == "timer" and p1 == pulseTimer then
        -- End of pulse
        pulseTimer = nil
        setSwitchState(false, "Auto-Reset")
    elseif event == "rednet_message" and p3 == PROTOCOL then
        local sender = p1
        local msg = p2

        if type(msg) == "table" and msg.type then
            local isAuthorized = config.isPublic or (msg.user and msg.user == config.owner)

            if msg.type == "scan" then
                -- Announce switch state to scanning remotes
                rednet.send(sender, {
                    type = "switch_info",
                    id = os.getComputerID(),
                    name = config.name,
                    side = config.side,
                    mode = config.mode,
                    pulseDuration = config.pulseDuration,
                    state = config.state,
                    isPublic = config.isPublic,
                    owner = config.owner
                }, PROTOCOL)

            elseif msg.type == "toggle" then
                if isAuthorized then
                    if (config.mode or "toggle") == "pulse" then
                        setSwitchState(true, msg.user)
                        pulseTimer = os.startTimer(config.pulseDuration or 2)
                    else
                        setSwitchState(not config.state, msg.user)
                    end
                    rednet.send(sender, {
                        type = "switch_update",
                        id = os.getComputerID(),
                        state = config.state,
                        success = true
                    }, PROTOCOL)
                else
                    rednet.send(sender, {
                        type = "switch_update",
                        id = os.getComputerID(),
                        state = config.state,
                        success = false,
                        error = "Unauthorized"
                    }, PROTOCOL)
                end

            elseif msg.type == "set_state" then
                if isAuthorized then
                    setSwitchState(msg.state == true, msg.user)
                    rednet.send(sender, {
                        type = "switch_update",
                        id = os.getComputerID(),
                        state = config.state,
                        success = true
                    }, PROTOCOL)
                else
                    rednet.send(sender, {
                        type = "switch_update",
                        id = os.getComputerID(),
                        state = config.state,
                        success = false,
                        error = "Unauthorized"
                    }, PROTOCOL)
                end
            end
        end
    end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Drunken Remote Switch closed.")
