-- Detect color capability once at load time
local hasColor = term.isColor and term.isColor()

---
-- Returns a color safe for the current terminal.
-- @param colorName string: Color name (e.g., "lime").
-- @param fallback number: Fallback color for non-color terminals.
-- @return number: Safe color value.
local function safeColor(colorName, fallback)
    if hasColor and colors[colorName] ~= nil then 
        return colors[colorName] 
    end
    return fallback or colors.white
end

local theme = {
    _VERSION = 1.1,
    bg = colors.black,
    text = colors.white,
    prompt = colors.cyan,
    titleBg = colors.blue,
    titleText = colors.white,
    highlightBg = colors.cyan,
    highlightText = colors.black,
    errorBg = colors.red,
    errorText = colors.white,
    windowBg = safeColor("gray", colors.gray),
    border = safeColor("gray", colors.gray),
    statusBarBg = safeColor("gray", colors.lightGray),
    statusBarText = colors.white,
    [colors.black] = colors.black,
}

-- Export safeColor for external use
theme.safeColor = safeColor

-- Game-specific colors namespace
-- Games should use these instead of hardcoding colors
theme.game = {
    -- Common game colors
    player = safeColor("cyan", colors.white),
    enemy = safeColor("red", colors.white),
    gold = safeColor("yellow", colors.white),
    hp = safeColor("red", colors.white),
    energy = safeColor("lime", colors.white),
    
    -- Snake game
    snake = safeColor("lime", colors.white),
    fruit = safeColor("red", colors.white),
    
    -- Puzzle games
    wall = safeColor("gray", colors.gray),
    floor = safeColor("lightGray", colors.white),
    box = safeColor("brown", colors.gray),
    target = safeColor("lime", colors.white),
    
    -- Combat games
    charge = safeColor("yellow", colors.white),
    damage = safeColor("red", colors.white),
    heal = safeColor("lime", colors.white),
    
    -- Tetris pieces
    piece_I = safeColor("cyan", colors.white),
    piece_O = safeColor("yellow", colors.white),
    piece_T = safeColor("purple", colors.white),
    piece_S = safeColor("lime", colors.white),
    piece_Z = safeColor("red", colors.white),
    piece_J = safeColor("blue", colors.white),
    piece_L = safeColor("orange", colors.white),
}

-- Config Path
local CONFIG_FILE = ".theme_config"

-- Presets
theme.presets = {
    ["Default (Blue)"] = {
        bg = colors.black, text = colors.white, prompt = colors.cyan,
        titleBg = colors.blue, titleText = colors.white,
        highlightBg = colors.cyan, highlightText = colors.black
    },
    ["Red Alert"] = {
        bg = colors.black, text = colors.red, prompt = colors.orange,
        titleBg = colors.red, titleText = colors.white,
        highlightBg = colors.orange, highlightText = colors.black
    },
    ["Matrix"] = {
        bg = colors.black, text = colors.lime, prompt = colors.green,
        titleBg = colors.green, titleText = colors.black,
        highlightBg = colors.lime, highlightText = colors.black
    },
    ["Midnight"] = {
        bg = colors.black, text = colors.lightGray, prompt = colors.gray,
        titleBg = colors.gray, titleText = colors.black,
        highlightBg = colors.white, highlightText = colors.black
    }
}

-- Methods
function theme.load()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if data then
            for k,v in pairs(data) do theme[k] = v end
        end
    end
end

function theme.save(presetName)
    local preset = theme.presets[presetName]
    if preset then
        -- Apply to current memory
        for k,v in pairs(preset) do theme[k] = v end
        
        -- Save to disk
        local f = fs.open(CONFIG_FILE, "w")
        f.write(textutils.serialize(preset))
        f.close()
        return true
    end
    return false
end

theme.colorToBlit = {
    [colors.white] = "0", [colors.orange] = "1", [colors.magenta] = "2", [colors.lightBlue] = "3",
    [colors.yellow] = "4", [colors.lime] = "5", [colors.pink] = "6", [colors.gray] = "7",
    [colors.lightGray] = "8", [colors.cyan] = "9", [colors.purple] = "a", [colors.blue] = "b",
    [colors.brown] = "c", [colors.green] = "d", [colors.red] = "e", [colors.black] = "f"
}

-- Auto-load on require
theme.load()

return theme
