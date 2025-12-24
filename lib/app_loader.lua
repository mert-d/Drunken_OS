--[[
    Drunken OS - App Loader (v1.0)
    Purpose: Dynamically loads and runs applets from the /apps directory.
]]

local loader = {}

function loader.run(appName, context, entryPoint)
    entryPoint = entryPoint or "run"
    local path = "/apps/" .. appName .. ".lua"
    
    if not fs.exists(path) then
        context.showMessage("Error", "Application '" .. appName .. "' not found.")
        return false
    end

    local success, appOrError = pcall(loadfile, path)
    if not success then
        context.showMessage("Load Error", tostring(appOrError))
        return false
    end

    local ok, instance = pcall(appOrError)
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
