--[[
    Drunken OS - Automated Master Test Runner
    Executes all core library and component unit tests.
]]

package.path = "./?.lua;" .. package.path

local tests = {
    { name = "SHA-1 & HMAC Cryptography", file = "tests/test_sha1.lua" },
    { name = "Utils & String Algorithms", file = "tests/test_utils.lua" },
    { name = "Theme & Palette Subsystem", file = "tests/test_theme.lua" },
    { name = "Database & Atomic Persistence", file = "tests/test_db.lua" },
    { name = "SDK UI Menus & Selection",  file = "tests/test_sdk_menu_local.lua" },
    { name = "Engine Delta-Row Buffering", file = "tests/test_engine_delta.lua" },
    { name = "DNS & Discovery Cache",    file = "tests/test_dns.lua" },
    { name = "Crypto Packet Anti-Replay", file = "tests/test_crypto_packet.lua" },
    { name = "Chunked File Streaming",    file = "tests/test_transfer.lua" },
    { name = "Non-Blocking Net RPC Layer", file = "tests/test_rpc.lua" },
    { name = "Calc & Create Mod Ratios",   file = "tests/test_calc.lua" },
    { name = "Score Cache & Offline Sync", file = "tests/test_score_cache.lua" },
    { name = "Connect 4 Physics & AI",     file = "tests/test_connect4.lua" },
    { name = "Battleship Naval AI & Radar", file = "tests/test_battleship.lua" },
    { name = "Drunken Remote & Switches",  file = "tests/test_remote.lua" },
    { name = "NetRadar Proximity & Ping",  file = "tests/test_radar.lua" },
    { name = "Task Manager & Daemon",      file = "tests/test_task_manager.lua" },
    { name = "Service Guard & Watchdog",   file = "tests/test_service_guard.lua" },
    { name = "Speaker Audio Engine",       file = "tests/test_sound.lua" },
    { name = "System Doctor Diagnostics",  file = "tests/test_doctor.lua" },
    { name = "Installer Disk & Boot Sim",   file = "tests/test_installer.lua" },
    { name = "HyperAuth Auto-Pairing Handshake", file = "tests/test_hyperauth_pairing.lua" },
    { name = "Mail Proxy & Interlink Flow", file = "tests/test_mail_interlink_proxy.lua" },
}

print("========================================================")
print("       Drunken OS Test Suite Runner")
print("========================================================")

local passed = 0
local failed = 0

for _, t in ipairs(tests) do
    io.write(string.format("[TEST] %-32s ... ", t.name))
    local fn, err = loadfile(t.file)
    if not fn then
        print("FAILED (Compile: " .. tostring(err) .. ")")
        failed = failed + 1
    else
        local ok, res = pcall(fn)
        if ok then
            print("OK")
            passed = passed + 1
        else
            print("FAILED (" .. tostring(res) .. ")")
            failed = failed + 1
        end
    end
end

print("========================================================")
print(string.format("Total: %d | Passed: %d | Failed: %d", #tests, passed, failed))
print("========================================================")

if failed > 0 then
    error(string.format("%d test suite(s) failed.", failed), 0)
end

return true
