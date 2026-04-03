--[[
    Drunken OS - Network Proxy (Mainframe Core)
    by MuhendizBey

    Purpose:
    Specialized proxy for core OS services. Handles Mail, Chat, Games,
    Admin, and Secure Authentication. Separated from Bank traffic to 
    prevent interference during high-load reporting.
]]

package.path = "/?.lua;/lib/?.lua;/lib/?/init.lua;" .. package.path

local ProxyBase = require("lib.proxy_base")

ProxyBase.run({
    name = "Drunken OS Mainframe Proxy",
    version = "1.6-MF",

    protocolMap = {
        ["SimpleMail"]     = "SimpleMail_Internal",
        ["SimpleChat"]     = "SimpleChat_Internal",
        ["Drunken_Admin"]  = "Drunken_Admin_Internal",
        ["auth.secure.v1"] = "auth.secure.v1_Internal",
    },

    hostMap = {
        ["mail.server"]  = "SimpleMail",
        ["chat.server"]  = "SimpleChat",
        ["admin.server"] = "Drunken_Admin",
    },

    transparentProtocols = {
        ["auth.secure.v1"]          = true,
        ["auth.secure.v1_Internal"] = true,
    }
})
