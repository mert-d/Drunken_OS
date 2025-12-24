--[[
    Drunken OS - App Loader (v1.2)
    Purpose: Dynamically loads and runs applets from the /apps directory.
]]

local loader = {}

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

    local appFunc, loadErr = loadfile(path)
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
