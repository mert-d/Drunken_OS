--[[
    Drunken OS - App Loader
    _VERSION = 1.3
    Purpose: Dynamically loads and runs applets from the /apps directory.
]]

local loader = {}
loader._VERSION = 1.3

---
-- Dynamically loads and runs an applet from the /apps directory.
-- @param appName The name of the application (filename without .lua extension).
-- @param context The application context provided to the applet (parent, drawWindow, etc).
-- @param entryPoint Optional. The function within the applet to call. Defaults to "run".
-- @return {boolean} True if the applet ran successfully, false otherwise.
function loader.run(appName, context, entryPoint)
    entryPoint = entryPoint or "run"
    -- Try both root apps/ and programDir/apps/
    local paths = {
        fs.combine(context.programDir or "", "apps/" .. appName .. ".lua"),
        "/apps/" .. appName .. ".lua"
    }
    
    local path = nil
    for _, p in ipairs(paths) do
        if fs.exists(p) then
            path = p
            break
        end
    end

    local function notify(title, msg)
        if context and type(context.showMessage) == "function" then
            context.showMessage(title, msg)
        else
            print("[" .. tostring(title) .. "] " .. tostring(msg))
        end
    end

    if not path then
        notify("Error", "Application '" .. appName .. "' not found.")
        return false
    end

    -- Construct a robust environment
    local env = setmetatable({
        require = require,
        shell = shell,
        multishell = multishell,
    }, { __index = _G })

    local appFunc, loadErr
    if setfenv then
        appFunc, loadErr = loadfile(path)
        if appFunc then setfenv(appFunc, env) end
    else
        appFunc, loadErr = loadfile(path, "t", env)
        if not appFunc then
            appFunc, loadErr = loadfile(path, env)
        end
    end

    if not appFunc then
        notify("Load Error", tostring(loadErr))
        return false
    end

    local ok, instance = pcall(appFunc)
    if not ok then
        notify("Init Error", tostring(instance))
        return false
    end

    if type(instance) == "table" and instance[entryPoint] then
        local status, err = pcall(instance[entryPoint], context)
        if not status then
            notify("Runtime Error", tostring(err))
            return false
        end
        return true
    else
        notify("Error", "Invalid applet structure: " .. appName)
        return false
    end
end

return loader
