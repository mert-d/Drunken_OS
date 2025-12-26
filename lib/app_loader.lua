--[[
    Drunken OS - App Loader (v1.2)
    Purpose: Dynamically loads and runs applets from the /apps directory.
]]

local loader = {}

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

    if not path then
        context.showMessage("Error", "Application '" .. appName .. "' not found.")
        return false
    end

    -- Pass _G to ensure require and other globals are available
    local appFunc, loadErr = loadfile(path, _G)
    if not appFunc then
        context.showMessage("Load Error", tostring(loadErr))
        return false
    end

    local ok, instance = pcall(appFunc)
    if not ok then
        context.showMessage("Init Error", tostring(instance))
        return false
    end

    if type(instance) == "table" and instance[entryPoint] then
        local status, err = pcall(instance[entryPoint], context)
        if not status then
            context.showMessage("Runtime Error", tostring(err))
            return false
        end
        return true
    else
        context.showMessage("Error", "Invalid applet structure: " .. appName)
        return false
    end
end

return loader
