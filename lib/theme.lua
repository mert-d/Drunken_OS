-- Standard ComputerCraft color bitmasks (1, 2, 4, ... 32768)
local C = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768
}

local function col(name)
    if colors and type(colors) == "table" and colors[name] ~= nil then
        return colors[name]
    end
    return C[name] or 1
end

-- Detect color capability once at load time safely
local hasColor = (term and term.isColor and term.isColor()) or false

---
-- Returns a color safe for the current terminal.
-- @param colorName string: Color name (e.g., "lime").
-- @param fallback number: Fallback color for non-color terminals.
-- @return number: Safe color value.
local function safeColor(colorName, fallback)
    if hasColor and colors and colors[colorName] ~= nil then 
        return colors[colorName] 
    end
    return fallback or col("white")
end

local theme = {
    _VERSION = 1.2,
    bg = col("black"),
    text = col("white"),
    mutedText = safeColor("gray", col("lightGray")),
    prompt = col("cyan"),
    titleBg = col("blue"),
    titleText = col("white"),
    highlightBg = col("cyan"),
    highlightText = col("black"),
    errorBg = col("red"),
    errorText = col("white"),
    windowBg = safeColor("gray", col("gray")),
    border = safeColor("gray", col("gray")),
    statusBarBg = safeColor("gray", col("lightGray")),
    statusBarText = col("white"),
    [32768] = 32768,
}

-- Export safeColor for external use
theme.safeColor = safeColor

-- Game-specific colors namespace
-- Games should use these instead of hardcoding colors
theme.game = {
    -- Common game colors
    player = safeColor("cyan", col("white")),
    enemy = safeColor("red", col("white")),
    gold = safeColor("yellow", col("white")),
    hp = safeColor("red", col("white")),
    energy = safeColor("lime", col("white")),
    
    -- Snake game
    snake = safeColor("lime", col("white")),
    fruit = safeColor("red", col("white")),
    
    -- Puzzle games
    wall = safeColor("gray", col("gray")),
    floor = safeColor("lightGray", col("white")),
    box = safeColor("brown", col("gray")),
    target = safeColor("lime", col("white")),
    
    -- Combat games
    charge = safeColor("yellow", col("white")),
    damage = safeColor("red", col("white")),
    heal = safeColor("lime", col("white")),
    
    -- Tetris pieces
    piece_I = safeColor("cyan", col("white")),
    piece_O = safeColor("yellow", col("white")),
    piece_T = safeColor("purple", col("white")),
    piece_S = safeColor("lime", col("white")),
    piece_Z = safeColor("red", col("white")),
    piece_J = safeColor("blue", col("white")),
    piece_L = safeColor("orange", col("white")),
}

-- Config Path
local CONFIG_FILE = ".theme_config"

-- Preset Palettes
theme.presets = {
    ["Default"] = {
        bg = col("black"), text = col("white"), prompt = col("cyan"),
        titleBg = col("blue"), titleText = col("white"),
        highlightBg = col("cyan"), highlightText = col("black")
    },
    ["Red Alert"] = {
        bg = col("black"), text = col("red"), prompt = col("orange"),
        titleBg = col("red"), titleText = col("white"),
        highlightBg = col("orange"), highlightText = col("black")
    },
    ["Matrix"] = {
        bg = col("black"), text = col("lime"), prompt = col("green"),
        titleBg = col("green"), titleText = col("black"),
        highlightBg = col("lime"), highlightText = col("black")
    },
    ["Midnight"] = {
        bg = col("black"), text = col("lightGray"), prompt = col("gray"),
        titleBg = col("gray"), titleText = col("black"),
        highlightBg = col("white"), highlightText = col("black")
    }
}

-- Keys that are safe to load from a config file (colors only)
local SAFE_THEME_KEYS = {
    bg=true, text=true, mutedText=true, prompt=true,
    titleBg=true, titleText=true, highlightBg=true, highlightText=true,
    errorBg=true, errorText=true, windowBg=true, border=true,
    statusBarBg=true, statusBarText=true,
}

-- Methods
---
-- Loads user-saved theme overrides from the local configuration file.
function theme.load()
    if fs and fs.exists and fs.exists(CONFIG_FILE) and textutils and textutils.unserialize then
        local f = fs.open(CONFIG_FILE, "r")
        if not f then return end -- Guard: file exists but couldn't be opened
        local content = f.readAll()
        f.close()
        local data = textutils.unserialize(content)
        if data then
            for k,v in pairs(data) do
                if SAFE_THEME_KEYS[k] then theme[k] = v end
            end
        end
    end
end

---
-- Saves a specific theme preset to the configuration file, and applies it to memory.
-- @param presetName string: The name of the preset to apply.
-- @return boolean: True if the preset was successfully saved and applied, false otherwise.
function theme.save(presetName)
    local preset = theme.presets[presetName]
    if preset then
        -- Apply to current memory
        for k,v in pairs(preset) do theme[k] = v end
        
        -- Save to disk
        if fs and fs.open and textutils and textutils.serialize then
            local f = fs.open(CONFIG_FILE, "w")
            if f then
                f.write(textutils.serialize(preset))
                f.close()
            end
        end
        return true
    end
    return false
end

-- Safely build colorToBlit map using standard CC bitmasks (1, 2, 4, ... 32768)
theme.colorToBlit = {
    [1] = "0", [2] = "1", [4] = "2", [8] = "3",
    [16] = "4", [32] = "5", [64] = "6", [128] = "7",
    [256] = "8", [512] = "9", [1024] = "a", [2048] = "b",
    [4096] = "c", [8192] = "d", [16384] = "e", [32768] = "f"
}

if colors and type(colors) == "table" then
    for name, code in pairs({
        white = "0", orange = "1", magenta = "2", lightBlue = "3",
        yellow = "4", lime = "5", pink = "6", gray = "7",
        lightGray = "8", cyan = "9", purple = "a", blue = "b",
        brown = "c", green = "d", red = "e", black = "f"
    }) do
        if colors[name] ~= nil then
            theme.colorToBlit[colors[name]] = code
        end
    end
end

---
-- Returns the blit hex character for a given color.
-- @param c number: Color value.
-- @return string: Blit hex character (0-f).
function theme.toBlit(c)
    if colors and colors.toBlit then
        local ok, blitChar = pcall(colors.toBlit, c)
        if ok and blitChar then return blitChar end
    end
    return theme.colorToBlit[c] or "0"
end

-- Auto-load on require
theme.load()

return theme
