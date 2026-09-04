--[[
    Drunken OS - Scratchpad & Notes (apps/notes.lua)
    Version: 1.0
    
    A lightweight, persistent notebook for recording mining coordinates,
    portal links, recipe reminders, and factory to-do lists.
]]

local DB = require("lib.db")
local NOTES_FILE = ".notes.db"

local app = {
    _VERSION = 1.0,
    name = "Notes",
    author = "Drunken OS Team"
}

local function loadNotes()
    return DB.loadTableFromFile(NOTES_FILE) or {}
end

local function saveNotes(notes)
    return DB.saveTableToFile(NOTES_FILE, notes)
end

function app.run(context)
    local theme = (context and context.theme) or require("lib.theme")
    local utils = (context and context.utils) or require("lib.utils")
    local w, h = term.getSize()
    local notes = loadNotes()
    local selected = 1
    
    while true do
        context.drawWindow("Notes (" .. #notes .. ")")
        
        -- Action Buttons Header
        term.setCursorPos(2, 3)
        term.setTextColor(theme.prompt or colors.yellow)
        term.write("[+ New Note]  [X Exit]")
        
        -- List of Notes
        local startY = 5
        local maxVisible = h - startY - 2
        
        if #notes == 0 then
            term.setCursorPos(2, startY)
            term.setTextColor(theme.mutedText or colors.gray)
            term.write("No notes saved yet.")
            term.setCursorPos(2, startY + 2)
            term.setTextColor(theme.text or colors.white)
            term.write("Tap [+ New Note] or press 'N'")
        else
            for i = 1, math.min(#notes, maxVisible) do
                local note = notes[i]
                term.setCursorPos(2, startY + i - 1)
                if i == selected then
                    term.setTextColor(theme.highlightText or colors.white)
                    term.setBackgroundColor(theme.highlightBg or colors.blue)
                    local title = note.title or "Untitled"
                    if #title > (w - 6) then title = title:sub(1, w - 8) .. "…" end
                    term.write(" • " .. title .. string.rep(" ", math.max(0, w - #title - 6)) .. " ")
                    term.setBackgroundColor(theme.bg or colors.black)
                else
                    term.setTextColor(theme.text or colors.white)
                    local title = note.title or "Untitled"
                    if #title > (w - 6) then title = title:sub(1, w - 8) .. "…" end
                    term.write(" • " .. title)
                end
            end
        end
        
        -- Footer hints
        term.setCursorPos(2, h - 1)
        term.setTextColor(theme.mutedText or colors.gray)
        term.write("[N] New  [Enter] View  [D] Delete")
        
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" then
            local k = p1
            if k == keys.up and #notes > 0 then
                selected = (selected == 1) and #notes or selected - 1
            elseif k == keys.down and #notes > 0 then
                selected = (selected == #notes) and 1 or selected + 1
            elseif k == keys.x or k == keys.q then
                break
            elseif k == keys.n then
                -- Create New Note
                context.drawWindow("New Note")
                term.setCursorPos(2, 4)
                term.setTextColor(theme.prompt or colors.yellow)
                term.write("Title: ")
                term.setTextColor(theme.text or colors.white)
                local title = read()
                
                if title and #title > 0 then
                    term.setCursorPos(2, 6)
                    term.setTextColor(theme.prompt or colors.yellow)
                    term.write("Content: ")
                    term.setTextColor(theme.text or colors.white)
                    local content = read()
                    
                    -- Check GPS if available
                    local coords = nil
                    if context and context.location and context.location.x then
                        coords = string.format(" [GPS: %d, %d, %d]", math.floor(context.location.x), math.floor(context.location.y or 64), math.floor(context.location.z))
                    elseif gps and gps.locate then
                        local gx, gy, gz = gps.locate(1)
                        if gx then
                            coords = string.format(" [GPS: %d, %d, %d]", math.floor(gx), math.floor(gy), math.floor(gz))
                        end
                    end
                    
                    if coords then
                        content = (content or "") .. coords
                    end
                    
                    table.insert(notes, 1, {
                        title = title,
                        body = content,
                        date = os.date and os.date("%m/%d %H:%M") or "Recent"
                    })
                    saveNotes(notes)
                    selected = 1
                end
            elseif k == keys.enter and #notes > 0 then
                -- View Selected Note
                local note = notes[selected]
                context.drawWindow(note.title or "View Note")
                term.setCursorPos(2, 3)
                term.setTextColor(theme.prompt or colors.yellow)
                term.write("Date: " .. (note.date or ""))
                
                local lines = utils.wordWrap(note.body or "", w - 4)
                local y = 5
                for _, line in ipairs(lines) do
                    if y < h - 1 then
                        term.setCursorPos(2, y)
                        term.setTextColor(theme.text or colors.white)
                        term.write(line)
                        y = y + 1
                    end
                end
                
                term.setCursorPos(2, h - 1)
                term.setTextColor(theme.mutedText or colors.gray)
                term.write("Press any key to return...")
                os.pullEvent("key")
            elseif k == keys.d and #notes > 0 then
                -- Delete Selected Note
                local delNote = table.remove(notes, selected)
                saveNotes(notes)
                if selected > #notes then selected = math.max(1, #notes) end
                context.showMessage("Deleted", "Removed: " .. (delNote.title or "Note"))
            end
        elseif event == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            if cy == 3 then
                if cx >= 2 and cx <= 13 then
                    -- Trigger New Note by clicking [+ New Note]
                    os.queueEvent("key", keys.n)
                elseif cx >= 15 and cx <= 24 then
                    break
                end
            elseif cy >= startY and cy < startY + #notes then
                local clickedIdx = cy - startY + 1
                if clickedIdx <= #notes then
                    selected = clickedIdx
                    os.queueEvent("key", keys.enter)
                end
            end
        end
    end
    
    return true
end

return app
