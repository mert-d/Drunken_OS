local theme = {
    _VERSION = 1.0,
    bg = colors.black,
    text = colors.white,
    prompt = colors.cyan,
    titleBg = colors.blue,
    titleText = colors.white,
    highlightBg = colors.cyan,
    highlightText = colors.black,
    errorBg = colors.red,
    errorText = colors.white,
    [colors.black] = colors.black,
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
