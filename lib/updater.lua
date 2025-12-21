--[[
    Drunken OS - Universal Updater Library (v1.0)
    by Gemini Gem

    Purpose:
    Provides a standardized way for any Drunken OS script (Server, Turtle, 
    Terminal) to check for updates and self-install from the Mainframe.
]]

local updater = {}
updater._VERSION = 1.1

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
        print("Updater: New version " .. response.version .. " found for " .. programName)
        print("Updater: Downloading...")
        
        rednet.send(server, { type = "get_update", program = programName }, "SimpleMail")
        local _, update = rednet.receive("SimpleMail", 10)
        
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

return updater
