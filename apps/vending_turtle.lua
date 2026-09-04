--[[
    Drunken OS - Vending Turtle Info Applet
    Note: The active daemon worker is located at turtles/vending_turtle.lua
]]

local app = {
    _VERSION = 1.1,
    name = "Vending Turtle",
    author = "MuhendizBey"
}

function app.run(context)
    if context and context.drawWindow then
        context.drawWindow("Vending Turtle")
        local w, h = term.getSize()
        term.setCursorPos(2, 4)
        term.setTextColor(context.theme and context.theme.text or colors.white)
        term.write("This application is a turtle worker daemon.")
        term.setCursorPos(2, 6)
        term.write("To run on a wireless turtle:")
        term.setCursorPos(2, 7)
        term.setTextColor(context.theme and context.theme.prompt or colors.yellow)
        term.write("  turtles/vending_turtle")
        term.setCursorPos(2, 9)
        term.setTextColor(colors.lightGray)
        term.write("Press any key to return...")
        os.pullEvent("key")
    else
        print("Vending Turtle daemon is located at turtles/vending_turtle.lua")
    end
    return true
end

return app
