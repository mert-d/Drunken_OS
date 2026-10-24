-- clients/ILS_Beacon_Tower.lua
-- Drunken OS - Runway ILS (Instrument Landing System) & RTB Beacon Transmitter

local CONFIG_PATH = "ils_beacon.conf"

local defaultConfig = {
    baseName     = "DRUNKEN-BASE-ALPHA",
    runwayId     = "RWY-36",
    thrX         = 0,     -- Pist esigi (Threshold) X koordinati
    thrY         = 68,    -- Pist esigi Y (Irtifa) koordinati
    thrZ         = 0,     -- Pist esigi Z koordinati
    rwyHeadingDeg= 0,     -- Pistin baktigi pusula acisi (0=Guzey/+Z veya Create:Avionics referansi)
    glideSlopeDeg= 8.0,   -- Suzulus acisi (derece)
    approachDist = 80,    -- FAF baslangic yaklasma mesafesi (blok)
    mastX        = 25,    -- Zeplin demirleme kulesi (Mooring Mast) X
    mastY        = 85,    -- Zeplin demirleme irtifasi Y
    mastZ        = 0      -- Zeplin demirleme kulesi Z
}

local function loadOrInitConfig()
    if fs and fs.exists and fs.exists(CONFIG_PATH) then
        local f = fs.open(CONFIG_PATH, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then return data end
    end
    if fs and fs.open then
        local f = fs.open(CONFIG_PATH, "w")
        f.write(textutils.serialize(defaultConfig))
        f.close()
    end
    return defaultConfig
end

local cfg = loadOrInitConfig()
local modem = peripheral and peripheral.find and peripheral.find("modem", function(_, m) return m.isWireless and m.isWireless() end)
if modem and rednet then
    pcall(rednet.open, peripheral.getName(modem))
end

print("=== DRUNKEN OS ILS & RTB BEACON TOWER ===")
print("Us Adi  : " .. tostring(cfg.baseName) .. " (" .. tostring(cfg.runwayId) .. ")")
print(string.format("Esik Pos: (%d, %d, %d) | Pruva: %d deg", cfg.thrX or 0, cfg.thrY or 68, cfg.thrZ or 0, cfg.rwyHeadingDeg or 0))

local running = true
while running do
    local packet = {
        type          = "AVIONICS_ILS_BEACON",
        baseName      = cfg.baseName,
        runwayId      = cfg.runwayId,
        threshold     = { x = cfg.thrX, y = cfg.thrY, z = cfg.thrZ },
        rwyHeadingRad = math.rad(cfg.rwyHeadingDeg or 0),
        glideSlopeRad = math.rad(cfg.glideSlopeDeg or 8.0),
        approachDist  = cfg.approachDist or 80,
        zeppelinMast  = { x = cfg.mastX, y = cfg.mastY, z = cfg.mastZ },
        timestamp     = os.epoch and os.epoch("utc") or os.time()
    }
    if rednet and rednet.isOpen and rednet.isOpen() then
        pcall(rednet.broadcast, packet, "DRUNKEN_ILS")
    end
    sleep(1.0)
end
