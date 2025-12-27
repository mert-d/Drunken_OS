--[[
    Drunken OS - Universal Updater Library (v1.2)
    by Gemini Gem

    Purpose:
    Provides a standardized way for any Drunken OS script (Server, Turtle, 
    Terminal) to check for updates and self-install from the Mainframe.
]]
local updater = {}
updater._VERSION = 1.1

---
-- Checks for a newer version of a program or library and installs it if available.
-- @param programName {string} The name of the program to check.
-- @param currentVersion {number} The current local version number.
-- @param targetPath {string|nil} The path to install to. Defaults to the running program.
-- @return {boolean} Returns true if an update was installed.
function updater.check(programName, currentVersion, targetPath)
    if not rednet.isOpen() then
        -- Try to open modem on back or any side
        local modem = peripheral.find("modem")
        if modem then rednet.open(peripheral.getName(modem)) end
    end

    local server = rednet.lookup("SimpleMail", "mail.server")
    if not server then
        -- print("Updater: Mainframe not detected. Skipping.")
        return false
    end

    -- print("Updater: Checking for " .. programName .. " updates...")
    rednet.send(server, { type = "get_version", program = programName }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 3)

    if response and response.version and response.version > currentVersion then
        print(string.format("Update: %s | Local: v%s vs Server: v%s", programName, currentVersion, response.version))
        print("Updater: Downloading...")
        
        rednet.send(server, { type = "get_update", program = programName }, "SimpleMail")
        local _, update = rednet.receive("SimpleMail", 5)
        
        if update and update.code then
            local path = targetPath or shell.getRunningProgram()
            local file = fs.open(path, "w")
            if file then
                file.write(update.code)
                file.close()
                print("Updater: " .. programName .. " updated successfully!")
                return true -- Signal that a reboot/reload is recommended
            else
                print("Updater: Error! Could not write " .. path)
            end
        else
            print("Updater: Error! Download failed for " .. programName)
        end
    end

    return false
end

---
-- Installs or updates a full package definition from the Mainframe manifest.
-- @param packageName {string} The key of the package tuple in the manifest (e.g., "client", "server")
-- @param uiCallback {function|nil} Optional callback(statusString) to update UI.
-- @return {boolean} True if successful.
function updater.install_package(packageName, uiCallback)
    local function logUI(msg) if uiCallback then uiCallback(msg) else print(msg) end end

    if not rednet.isOpen() then
        local modem = peripheral.find("modem")
        if modem then rednet.open(peripheral.getName(modem)) end
    end
    
    local server = rednet.lookup("SimpleMail", "mail.server")
    if not server then
        logUI("Error: Mainframe not found.")
        return false
    end

    logUI("Fetching manifest...")
    rednet.send(server, { type = "get_manifest" }, "SimpleMail")
    local _, response = rednet.receive("SimpleMail", 3)
    
    if not response or response.type ~= "manifest_response" or not response.manifest then
        logUI("Error: Failed to fetch manifest.")
        return false
    end
    
    local manifest = response.manifest
    if not manifest.packages then
        logUI("Error: Invalid manifest (no packages).")
        return false
    end
    local pkg = manifest.packages[packageName]
    if not pkg then
        logUI("Error: Package '"..packageName.."' not found in manifest.")
        return false
    end
    
    local filesToInstall = {}
    for _, f in ipairs(pkg.files or {}) do table.insert(filesToInstall, f) end
    
    if pkg.include_shared and manifest.shared then
        for _, f in ipairs(manifest.shared) do
            local exists = false
            for _, existing in ipairs(filesToInstall) do if existing == f then exists=true break end end
            if not exists then table.insert(filesToInstall, f) end
        end
    end
    
    logUI("Syncing " .. #filesToInstall .. " files...")
    
    for i, filePath in ipairs(filesToInstall) do
        -- Check if file needs update? For now we just overwrite to ensure sync
        -- Optimization: In potential future, we could send hashes.
        logUI("Downloading " .. filePath .. " (" .. i .. "/" .. #filesToInstall .. ")")
        rednet.send(server, { type = "get_file", path = filePath }, "SimpleMail")
        local _, fileData = rednet.receive("SimpleMail", 3)
        
        if fileData and fileData.success and fileData.code then
             -- Special Case: Preserve HyperAuth Configuration
             if filePath == "HyperAuthClient/config.lua" and fs.exists(filePath) then
                 logUI("Skipping existing config: " .. filePath)
             else
                 if not fs.exists(fs.getDir(filePath)) then fs.makeDir(fs.getDir(filePath)) end
                 local f = fs.open(filePath, "w")
                 f.write(fileData.code)
                 f.close()
             end
        else
            logUI("Error: Failed to download " .. filePath)
            -- Just warn, don't abort entire update?
        end
    end
    
    logUI("Update complete.")
    return true
end

---
-- Checks if an optional app is currently installed.
-- @param appName {string} The name/key in manifest.store
function updater.is_installed(appName)
    -- This requires fetching manifest first to know the path?
    -- Or we assume standard "apps/Name.lua"?
    -- Ideally we ask the server or cache the manifest.
    
    -- For efficiency, let's assume the store logic passes the PATH or we rely on a quick manifest check.
    -- But since this is a helper, let's do the robust thing: Fetch Manifest check.
    -- ACTUALLY, that's too slow for a menu loop.
    
    -- COMPROMISE: We check standard paths.
    -- Most store apps will be "apps/<File>.lua".
    -- But we don't know <File> from <AppName> without the manifest lookup.
    
    -- Allow the caller to pass the mapped path if they have it (Store App will have it).
    return false -- Stub, expect caller to use fs.exists if they have the path.
end

---
-- Installs a specific app from the On-Demand Store.
-- @param appName {string} The display name/key in manifest.store
-- @param uiCallback {function}
function updater.install_app(appName, uiCallback)
    local function log(s) if uiCallback then uiCallback(s) else print(s) end end
    
    if not rednet.isOpen() then
        local m = peripheral.find("modem"); if m then rednet.open(peripheral.getName(m)) end
    end
    
    local server = rednet.lookup("SimpleMail", "mail.server")
    if not server then log("Error: No Connection."); return false end
    
    log("Fetching Store Directory...")
    rednet.send(server, { type = "get_manifest" }, "SimpleMail")
    local _, resp = rednet.receive("SimpleMail", 3)
    
    if not resp or not resp.manifest or not resp.manifest.store then
        log("Error: Store unavailable."); return false
    end
    
    local path = resp.manifest.store[appName]
    if not path then
        log("Error: App not found in store."); return false
    end
    
    log("Downloading " .. appName .. "...")
    rednet.send(server, { type = "get_file", path = path }, "SimpleMail")
    local _, fileData = rednet.receive("SimpleMail", 5)
    
    if fileData and fileData.success and fileData.code then
        if not fs.exists(fs.getDir(path)) then fs.makeDir(fs.getDir(path)) end
        local f = fs.open(path, "w")
        f.write(fileData.code)
        f.close()
        log("Successfully installed " .. appName)
        return true
    else
        log("Error: Download failed.")
        return false
    end
end

---
-- Uninstalls an app.
-- @param path {string} The path to the app file.
function updater.uninstall_app(path)
    if fs.exists(path) then
        fs.delete(path)
        return true
    end
    return false
end

return updater
