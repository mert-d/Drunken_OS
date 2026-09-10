# Drunken OS Roadmap 🗺️

This document outlines the strategic direction and milestones for **Drunken OS**. Contributors and developers should refer to this roadmap when planning new capabilities.

---

## 🟢 Phase 1: Stabilization & Modularity
_Goal: Move away from monolithic files and establish a modular app and shared library architecture._

- [x] **Modular App Loader**: Moved core apps to `apps/` with isolated environments and standard context passing.
- [x] **Server Refactoring**: Modularized `Drunken_OS_Server.lua` with dedicated handlers in `servers/modules/` (e.g. `auth.lua`, `chat.lua`).
- [x] **Standardized Shared Libraries**: Extracted common UI patterns and persistence into `lib/theme.lua`, `lib/utils.lua`, and `lib/db.lua`.

---

## 🟡 Phase 2: The Multiplayer Era
_Goal: Standardize peer-to-peer gaming and centralized arcade leaderboards._

- [x] **P2P API Standardization**: Created `lib/p2p_socket.lua` for standardized handshakes, heartbeat pings, and disconnect handling.
- [x] **Arcade Leaderboards**: Global high score persistence and game catalog distribution in `servers/Drunken_Arcade_Server.lua`.
- [x] **Spectator Mode**: Enabled real-time match spectating in `Drunken Duels`.
- [x] **Unified Arcade Lobby**: Rebuilt `apps/arcade.lua` to browse games, view high scores, and sync updates.

---

## 🔴 Phase 3: Developer Ecosystem & Automated Testing
_Goal: Provide robust verification tools and developer SDKs._

- [x] **Developer SDK (`lib/sdk.lua`)**: Standardized application framework with event loops and window abstraction.
- [x] **Automated Test Suite**: Built `tests/test_all.lua` providing end-to-end automated testing for core libraries.

---

## 🟣 Phase 4: High-Concurrency & Enterprise Performance (Create Astral Tier)
_Goal: Scale the OS for 20+ concurrent players without network lag, broadcast storms, or packet replay vulnerabilities._

- [x] **Delta-Row Terminal Buffering (`lib/engine.lua`)**: Differential screen row caching, reducing Minecraft server-to-client network packet overhead by up to 90%.
- [x] **Universal DNS Cache (`lib/dns.lua`)**: Service discovery caching with 60-second TTL, preventing network broadcast storms.
- [x] **Cryptographic Anti-Replay Defense (`lib/crypto_packet.lua`)**: HMAC-SHA1 signature verification, unix timestamps, and rolling nonce protection against replay attacks.
- [x] **Chunked Streaming File Transfers (`lib/transfer.lua`)**: 2KB sliding window transfers with real-time ASCII progress bars and SHA-1 verification.
- [x] **Non-Blocking RPC Layer (`lib/rpc.lua`)**: Multi-plexed requests using transaction IDs (`tx_id`) and non-discarding inboxes.

---

## 🔵 Phase 5: Mobile Touch, UI Polish & Survival Utilities
_Goal: Modernize the handheld Pocket Computer experience with touch controls and Create Astral survival utilities._

- [x] **Universal Touch & Mouse Interaction**: Added `mouse_click` and `mouse_scroll` across `lib/sdk.lua` and desktop launcher with 100% keyboard fallback.
- [x] **Dynamic Mobile Status Notch**: Top bar displays real-time Minecraft clock (`HH:MM`), wireless status `[NET]`, and unread mail badge `(2)`.
- [x] **In-Game Survival Utilities**: Built `apps/calc.lua` (arithmetic, 64-item stack division, and Create Mod rotational gear ratios) and `apps/notes.lua` (scratchpad with satellite GPS coordinate tagging).
- [x] **Touch Controls in Games**: Added tap-to-jump in `games/floppa_bird.lua`.

---

## 🟠 Phase 6: P2P Wireless Gaming & Universal Offline Resilience
_Goal: Ensure games and tools remain 100% playable even when central server chunks are asleep or unloaded._

- [x] **Offline-First Score Cache (`lib/score_cache.lua`)**: Local database (`.game_scores.db`) caching personal bests, with a deferred sync queue (`.pending_scores.db`) that auto-syncs high scores when the Arcade Server comes back online.
- [x] **Graceful Offline Mode**: Bounded 1.2s–1.5s network timeouts across `apps/bank.lua`, `apps/mail.lua`, and `apps/arcade.lua`, preventing black-screen freezes.
- [x] **Wireless Turn-Based Connect 4 (`games/Drunken_Connect4.lua`)**: 7×6 touch-first grid with Single Player vs Smart Heuristic AI and Wireless 2-Player P2P multiplayer on `"C4_P2P"`.
- [x] **Wireless Turn-Based Battleship (`games/Drunken_Battleship.lua`)**: 6×6 naval tactical grid with auto-deploy algorithm, Single Player vs Naval AI, and Wireless 2-Player P2P multiplayer on `"Battleship_P2P"`.
- [x] **Wireless P2P "AirDrop" File Sharing (`apps/files.lua`)**: Direct device-to-device file streaming beam over `"DrunkenAirDrop"` with zero server chunk dependency.
- [x] **World Spawn 24/7 Hosting Guide**: Added Minecraft spawn chunk hosting tutorial to `docs/FULL_SYSTEM_SETUP_GUIDE.md`.

---

## 🟤 Phase 7: Base Redstone Automation & Network Diagnostics (Completed in v16.8)
_Goal: Extend Drunken OS beyond computers to control Minecraft physical bases, doors, and wireless network health._

- [x] **Base Redstone Switch Node (`clients/remote_switch.lua`)**: Headless ComputerCraft node with interactive 4-step wizard, redstone toggle/pulse modes, pulse durations, live ASCII monitor, and `"DrunkenRemote"` protocol.
- [x] **Drunken Remote Pocket App (`apps/remote.lua`)**: Handheld Pocket Computer remote control with auto-discovery, color-coded live status badges (`[ ACTIVE ]`, `[ INACTIVE ]`, `[⚡ 2s]`, `[OFFLINE]`), and 1-tap touch and numeric key toggling.
- [x] **NetRadar Pocket Scanner (`apps/radar.lua`)**: Wireless diagnostic tool with 3D Euclidean distance GPS scanner and server latency ping benchmark with 0.8s bounded timeout.
- [x] **App Store & Manifest Bundling**: Integrated `remote_switch`, `remote`, `radar`, `calc`, and `notes` into packages in `manifest.lua` and `installer/manifest.lua`.
- [x] **Automated Test Coverage (16 Suites)**: Created `tests/test_remote.lua` and `tests/test_radar.lua`, achieving 16/16 test suites passing (100%).

---

## ⚡ Phase 8: Multi-Tasking & Global Notification Daemon (Completed in v16.9)
_Goal: Introduce true cooperative multitasking, window-buffered screen memory, and global floating notification alerts with zero game lag._

- [x] **Coroutine Supervisor & Task Manager (`lib/task_manager.lua`)**: Window-buffered multitasking supervisor (`window.create`) running multiple apps concurrently with 0 screen corruption and 0 tick lag.
- [x] **Global Floating Notification Toast Daemon**: Non-intrusive 3.5s auto-dismissing toast alerts for Mail, Chat, Bank payments, Merchant invoices, and AirDrop with tap-to-open.
- [x] **Centralized Network Packet Inspection**: Intercepts packets inside `TaskManager.step()`, preventing background listeners from stealing rednet messages while forwarding transparently to child apps.
- [x] **Quick Task Switcher (`F1` / `Ctrl`)**: Hotkey-driven process switcher with task termination (`[X]`) and quick app launcher (`[N]`).
- [x] **Automated Test Coverage (17 Suites)**: Created `tests/test_task_manager.lua`, achieving 17/17 test suites passing (100%).

---

## 🛡️ Phase 9: Self-Healing Infrastructure & Peripheral Hot-Plug (Completed in v17.0)
_Goal: Eliminate server crashes and connection drops with zero-downtime watchdogs and automatic peripheral cable hot-plugging._

- [x] **Service Guard Watchdog Supervisor (`lib/service_guard.lua`)**: Intercepts unhandled crashes, executes emergency database flushes (`dbTracker.backgroundSave()`), logs timestamped stack traces, and auto-restarts server loops with 0 downtime.
- [x] **Peripheral Hot-Plug & Cable Auto-Reconnection**: Dynamic event handling for native `peripheral` and `peripheral_detach` events to auto-reopen modems, re-bind external monitors, and re-host protocols.
- [x] **Protected Packet Handlers (`ServiceGuard.protectHandler`)**: Enforces `pcall` envelopes around all packet handlers across servers and proxies, preventing malformed payload crashes.
- [x] **Automated Test Coverage (18 Suites)**: Created `tests/test_service_guard.lua`, achieving 18/18 test suites passing (100%).

---

## 🔊 Phase 10: Hardware Sound Engine, In-Game Doctor & Pocket UX (Completed in v17.1)
_Goal: Add retro 8-bit note block sound effects, interactive in-game diagnostic tools, append-only log compaction, stale DNS fallback, and pocket mobile touch scaling._

- [x] **CC:Tweaked Speaker Sound Engine (`lib/sound.lua`)**: Procedural note-block audio engine with silent fallback; contextual notification chimes (Mail, Chat, Bank, AirDrop), rising coin pickup sounds for ATM/POS, radar proximity pitch scaling (6 to 22 semitones), tactile clicks, and arcade SFX.
- [x] **In-Game "System Doctor" Diagnostic Suite (`apps/doctor.lua`)**: Interactive diagnostic tool and health check API auditing terminal dimensions (Pocket 26x20 vs Desktop 51x19), color palette, modems, speakers, monitors, disk drives, Rednet state, 5-server latency benchmarks, free storage, and 1-click auto-repair (`[F]`).
- [x] **Append-Only Log Compaction (`DB.compactLogFile` in `lib/db.lua`)**: Safely compacts transaction and event logs when exceeding byte thresholds while preserving the latest $N$ lines via atomic `.tmp` swap, preventing world save bloat.
- [x] **Stale-While-Revalidate DNS (`lib/dns.lua`)**: Solves Rednet lookup failures when remote servers reside in sleeping or unloaded Minecraft chunks by falling back to verified cached server IDs (`allowStale = true`). Includes persistent on-disk cache (`.dns_cache.db`).
- [x] **Pocket Computer (26x20) Responsive UI (`lib/sdk.lua`)**: Dynamic dialog text wrapping, screen-bounded message boxes, and finger-friendly `[ OK (Tap) ]` action buttons preventing text clipping on mobile displays.
- [x] **Automated Test Coverage (20 Suites)**: Created `tests/test_sound.lua` and `tests/test_doctor.lua`, achieving 20/20 test suites passing (100%).

---

## 💡 Future Wishlist & Next Frontiers

- [ ] **Astral Telemetry Satellite**: Specialized turtle or computer reading Create Astral space rocket data or train station departures.
- [ ] **Advanced Peripheral Integration**: Native printing support with ComputerCraft printers and multi-block external monitor displays.
- [ ] **Decentralized Arcade Mirror Proxies**: Autonomous proxy relays that mirror high score catalogs across faraway mining dimensions.
