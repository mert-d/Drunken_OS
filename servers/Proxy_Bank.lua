--[[
    Drunken OS - Network Proxy (Banking Core)
    by MuhendizBey

    Purpose:
    Specialized proxy for Banking services. Handles DB_Bank and 
    associated reports. Separated from Mainframe traffic to 
    prevent high-volume reports from blocking OS communications.
]]

local ProxyBase = require("lib.proxy_base")

ProxyBase.run({
    name = "Drunken OS Bank Proxy",
    version = "1.5-BANK",

    protocolMap = {
        ["DB_Bank"] = "DB_Bank_Internal",
    },

    hostMap = {
        ["bank.server"] = "DB_Bank",
    },

    transparentProtocols = {}
})
