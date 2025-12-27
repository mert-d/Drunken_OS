--[[
    Drunken OS - Package Manifest (v1.1)
    
    This file defines the files required for each component of the OS.
    The Installer and Updater use this to know what to download.
]]

return {
    version = 1.1,

    -- Files common to almost all client-side installations
    shared = {
        "lib/sha1_hmac.lua",
        "lib/drunken_os_apps.lua",
        "lib/updater.lua",
        "lib/app_loader.lua",
        "lib/theme.lua",
        "lib/utils.lua",
        "lib/p2p_socket.lua",
        "lib/sdk.lua",
        "manifest.lua"
    },

    packages = {
        -- Mainframe Server
        server = {
            name = "Drunken OS Server",
            type = "server",
            main = "servers/Drunken_OS_Server.lua",
            files = {
                "servers/Drunken_OS_Server.lua",
                "servers/modules/chat.lua",
                "servers/modules/auth.lua",
                "servers/modules/mail.lua",
                "lib/sha1_hmac.lua",
                "clients/Admin_Console.lua",
                -- HyperAuthClient Dependencies
                "HyperAuthClient/config.lua",
                "HyperAuthClient/api/auth_api.lua",
                "HyperAuthClient/api/auth_client.lua",
                "HyperAuthClient/encrypt/secure.lua",
                "HyperAuthClient/encrypt/sha1.lua"
            },
            include_shared = false 
        },

        -- Standard User Client (Pocket Computer / Terminal)
        client = {
            name = "Drunken OS Client",
            type = "client",
            main = "clients/Drunken_OS_Client.lua",
            files = {
                "clients/Drunken_OS_Client.lua",
                "apps/arcade.lua",
                "apps/bank.lua",
                "apps/chat.lua",
                "apps/files.lua",
                "apps/mail.lua",
                "apps/merchant.lua",
                "apps/system.lua",
                "apps/developer.lua"
            },
            include_shared = true
        },

        -- Bank Server
        bank_server = {
            name = "Drunken OS Bank Server",
            type = "server",
            main = "servers/Drunken_OS_BankServer.lua",
            files = {
                "servers/Drunken_OS_BankServer.lua",
                "lib/sha1_hmac.lua"
            },
            include_shared = false,
            needs_setup = true,
            setup_type = "bank_server"
        },

        -- ATM Client
        atm = {
            name = "DB Bank ATM",
            type = "client",
            main = "clients/DB_Bank_ATM.lua",
            files = {
                "clients/DB_Bank_ATM.lua",
                "apps/bank.lua"
            },
            include_shared = true,
            needs_setup = true,
            setup_type = "atm"
        },

        -- Bank Clerk Terminal
        clerk = {
            name = "DB Bank Clerk Terminal",
            type = "client",
            main = "clients/DB_Bank_Clerk_Terminal.lua",
            files = {
                "clients/DB_Bank_Clerk_Terminal.lua",
                "apps/bank.lua"
            },
            include_shared = true
        },

        -- Auditor Turtle
        auditor = {
            name = "Auditor Turtle",
            type = "turtle",
            main = "turtles/Auditor.lua",
            files = {
                "turtles/Auditor.lua",
                "lib/sha1_hmac.lua",
                "lib/updater.lua"
            },
            include_shared = false,
            needs_setup = true,
            setup_type = "auditor"
        },
        
        -- Merchant POS
        merchant_pos = {
            name = "Merchant POS",
            type = "client",
            main = "clients/DB_Merchant_POS.lua",
            files = {
                "clients/DB_Merchant_POS.lua",
                "apps/merchant.lua",
                "apps/bank.lua"
            },
            include_shared = true
        },

        -- Merchant Cashier
        merchant_cashier = {
            name = "Merchant Cashier PC",
            type = "client",
            main = "clients/DB_Merchant_Cashier.lua",
            files = {
                "clients/DB_Merchant_Cashier.lua",
                "apps/merchant.lua",
                "apps/bank.lua"
            },
            include_shared = true
        },
        
        -- Specialized Networking
        proxy_mainframe = {
            name = "Mainframe Proxy",
            type = "server",
            main = "servers/Proxy_Mainframe.lua",
            files = { "servers/Proxy_Mainframe.lua", "lib/sha1_hmac.lua" },
            include_shared = false
        },
        proxy_bank = {
            name = "Bank Proxy",
            type = "server",
            main = "servers/Proxy_Bank.lua",
            files = { "servers/Proxy_Bank.lua", "lib/sha1_hmac.lua" },
            include_shared = false
        },
        arcade_server = {
             name = "Drunken Arcade Server",
             type = "server",
             main = "servers/Drunken_Arcade_Server.lua",
             files = {
                "servers/Drunken_Arcade_Server.lua",
                "lib/sha1_hmac.lua"
             },
             include_shared = false
        }
    },

    -- Listing all apps and games for easy reference or future dynamic inclusion
    all_apps = {
        "apps/arcade.lua",
        "apps/bank.lua",
        "apps/chat.lua",
        "apps/files.lua",
        "apps/mail.lua",
        "apps/merchant.lua",
        "apps/system.lua",
        "apps/developer.lua"
    },

    all_games = {
        "games/Drunken_Doom.lua",
        "games/Drunken_Duels.lua",
        "games/Drunken_Dungeons.lua",
        "games/Drunken_Pong.lua",
        "games/Drunken_Sokoban.lua",
        "games/Drunken_Sweeper.lua",
        "games/floppa_bird.lua",
        "games/invaders.lua",
        "games/snake.lua",
        "games/tetris.lua"
    }
}
