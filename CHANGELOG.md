# Changelog

All notable changes to the **Drunken OS** ecosystem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [17.1.0] - 2026-09-09 - Hardware Sound Engine, In-Game Doctor & Pocket UX Edition

### 🔊 Phase 10: CC:Tweaked Speaker Engine, In-Game Doctor, Log Compaction & Pocket UX

#### Added
- **Speaker Audio Engine (`lib/sound.lua`)**:
  - Comprehensive retro 8-bit sound effects engine for CC:Tweaked Speaker peripherals with automatic silent fallback when no speaker is attached or when muted.
  - **Contextual Notification Chimes (`Sound.playToast(category)`)**: Custom acoustic signatures for incoming Mail (`chime`), Chat (`bell`), Bank transfers (`pling`), and Airdrops (`flute`).
  - **Financial Audio Feedback (`Sound.playCoin()`)**: Dual-tone ascending coin pickup sound triggered on ATM withdrawals, merchant payments, and banking transfers.
  - **Radar Proximity Pitch Scaling (`Sound.playRadarPing(distance)`)**: Frequency-modulated sonar ping where pitch dynamically scales from 6 semitones (distant >80m) up to 22 semitones (immediate <=10m).
  - **Tactile UI & Arcade FX**: Tactile UI click (`Sound.playClick()`), harmonic success chords (`Sound.playSuccess()`), warning error buzz (`Sound.playError()`), and arcade chiptune beeps (`Sound.playGameBeep()`).
- **In-Game System Doctor Diagnostics (`apps/doctor.lua`)**:
  - Interactive diagnostic suite and programmatic health audit API (`doctor.diagnose()` & `doctor.autoRepair()`).
  - **Hardware & Display Audit**: Automatically identifies screen resolution and terminal profile (Pocket Computer 26x20 vs Advanced Computer 51x19) and color depth (16-color palette vs monochrome).
  - **Peripheral Audit**: Scans for dual wired/wireless modems, speakers, external monitors, and disk drives.
  - **World Spawn Latency Benchmarks**: Tests round-trip latency and availability to Mainframe, Chat, Bank, Arcade, and Auth servers.
  - **Storage & Integrity Audit**: Computes free disk space, validates filesystem read/write privileges, and detects orphaned `.tmp` files.
  - **1-Click Auto-Repair**: Auto-reconnects closed modems, flushes universal DNS cache, and purges orphaned `.tmp` files with single keypress (`[F]`) or touch tap.
- **Append-Only Log Compaction (`DB.compactLogFile` in `lib/db.lua`)**:
  - Atomic log compaction with safety margin thresholds (`maxBytes` and `keepLines`) using `.tmp` buffers and `fs.move`.
  - Registered in database tracker (`tracker.registerLog()`) and integrated into background state flushes to prevent world save file bloat.
- **Stale-While-Revalidate DNS Caching (`lib/dns.lua`)**:
  - Eliminates Rednet lookup failures when target servers reside in unloaded or sleeping Minecraft chunks by returning previously verified cached IDs (`allowStale = true`).
  - Persistent on-disk cache (`.dns_cache.db`) preserving server topology across computer reboots.
- **Pocket Computer (26x20) UI & Touch Tuning (`lib/sdk.lua`)**:
  - Responsive modal dialogs in `sdk.UI.showMessage`: automatic text wrapping, width clamping to terminal boundaries, and finger-friendly `[ OK (Tap) ]` action buttons.
  - Clamped item width and touch hitboxes in `sdk.UI.drawMenu` preventing line-wrap visual artifacts on small screens.
- **Automated Unit Tests**:
  - `tests/test_sound.lua`: Comprehensive unit test suite (Suite #19) for note playback, mute controls, category chimes, coin sound, radar pitch scaling, and silent fallback.
  - `tests/test_doctor.lua`: Comprehensive unit test suite (Suite #20) for hardware diagnosis, peripheral scanning, latency pings, storage checks, and auto-repair.

#### Changed
- **Audio Integration Across Apps & Clients**:
  - Integrated `Sound.playToast(targetApp)` into `lib/task_manager.lua` notification daemon.
  - Added `Sound.playCoin()` to `apps/bank.lua` and `clients/DB_Bank_ATM.lua` on successful payments and cash withdrawals.
  - Added `Sound.playRadarPing(distance)` to `apps/radar.lua` ping receiver.
  - Added `Sound.playClick()` to `lib/sdk.lua` dialog dismiss and menu selections.
- **Master Test Runner (`tests/test_all.lua`)**:
  - Expanded from 18 to 20 test suites with 100% pass rate.
- **Package Manifests**:
  - Added `lib/sound.lua` to `shared` and `apps/doctor.lua` to `all_apps`, `store`, and `client.files` in `manifest.lua` and `installer/manifest.lua` (100% byte-for-byte synchronization).

---

## [17.0.0] - 2026-09-08 - Self-Healing Infrastructure & Peripheral Hot-Plug Edition

### 🛡️ Phase 9: Self-Healing Server Watchdogs & Peripheral Hot-Plug

#### Added
- **Service Guard & Watchdog Supervisor (`lib/service_guard.lua`)**:
  - Comprehensive service supervisor library providing automatic crash detection, emergency state preservation, and zero-downtime auto-restart.
  - **Zero-Downtime Server Supervisor (`ServiceGuard.runSupervisor`)**:
    - Catches unexpected runtime crashes, unhandled errors, and nil references without terminating server processes.
    - Automatically triggers emergency state flushes (`dbTracker.backgroundSave()`) before restart to guarantee 0 data loss.
    - Appends timestamped stack traces and exception reports to persistent log files (`logs/<service>_crash.log`).
    - Respects operator termination (`Ctrl+T` / `keys.escape` / `"Terminated"`) for clean shutdown.
  - **Dynamic Peripheral Hot-Plug Subsystem (`ServiceGuard.initModems`, `ServiceGuard.handlePeripheralEvent`)**:
    - Actively detects native ComputerCraft `peripheral` and `peripheral_detach` events.
    - Automatically opens wired and wireless modems on rednet upon connection/re-connection.
    - Re-binds external monitors dynamically (`monitor.setTextScale(0.5)`).
    - Automatically re-hosts all network protocols without requiring server reboots.
  - **Protected Packet Dispatcher (`ServiceGuard.protectHandler`)**:
    - Enforces protected `pcall` execution wrappers around packet handlers, immunizing servers and proxies against malformed packets, nil fields, and corrupted payloads.
- **Automated Test Suite (`tests/test_service_guard.lua`)**:
  - Comprehensive unit tests verifying modem auto-discovery, wired/wireless filtering, peripheral hot-plug callbacks, monitor re-binding, detachment logging, protected handler execution, crash logging, and zero-downtime supervisor auto-restart.
  - Registered in master test runner (`tests/test_all.lua`) as Suite #18 with 100% pass rate.

#### Changed
- **Network Proxies (`lib/proxy_base.lua`)**:
  - Wired and wireless modem detection modernized with `ServiceGuard.initModems()`.
  - Dispatcher loop updated to handle `peripheral` and `peripheral_detach` events for auto-reconnection.
  - `forward` and `relay` packet dispatching wrapped with `ServiceGuard.protectHandler`.
  - Entire proxy dispatcher supervised under `ServiceGuard.runSupervisor`.
- **Mainframe Core Gateway (`servers/Drunken_OS_Server.lua`)**:
  - Wired modem initialization upgraded via `ServiceGuard.initModems("wired")`.
  - Added dynamic protocol re-hosting and monitor re-binding on peripheral hot-plug events.
  - Wrapped `mailHandlers` execution in safe `pcall` with guaranteed `rednet.send` restoration.
  - Main event loop supervised under `ServiceGuard.runSupervisor` with `flushMainframeState` callback.
- **Bank Server (`servers/Drunken_OS_BankServer.lua`)**:
  - Modems auto-configured with `ServiceGuard.initModems()`.
  - Added hot-plug event handling and re-hosting for `"DB_Bank_Internal"` and `"DB_Bank"`.
  - Protected `bankHandlers` dispatch and audit protocol handlers (`stock_report`, `get_transaction_log`).
  - Event loop supervised under `ServiceGuard.runSupervisor` with `flushBankState` callback.
- **Arcade Games Server (`servers/Drunken_Arcade_Server.lua`)**:
  - Modems initialized via `ServiceGuard.initModems()`.
  - Network listener converted to event-driven loop supporting `peripheral` hot-plug and 1-second refresh timer.
  - Game message handlers protected via `ServiceGuard.protectHandler`.
  - Server loops supervised under `ServiceGuard.runSupervisor` with `flushArcadeState` callback.
- **Authentication Server (`servers/Drunken_OS_AuthServer.lua`)**:
  - Modems auto-initialized via `ServiceGuard.initModems()`.
  - Network listener upgraded with peripheral hot-plug handling and `ServiceGuard.protectHandler`.
  - Server execution supervised under `ServiceGuard.runSupervisor` with `flushAuthState` callback.
- **Package Manifests**:
  - Synchronized `lib/service_guard.lua` across `shared` packages and all server/proxy packages in both `manifest.lua` and `installer/manifest.lua`.

---

## [16.9.0] - 2026-09-07 - Multi-Tasking Edition

### ⚡ Phase 8: Multi-Tasking & Global Notification Daemon

#### Added
- **Coroutine Multi-Tasking Supervisor (`lib/task_manager.lua`)**:
  - Full cooperative multitasking supervisor supporting multiple concurrent processes.
  - Window-buffered screen memory (`window.create`) per task: isolates rendering buffers so background processes and toasts cause 0 screen corruption on foreground games or apps.
  - Zero performance degradation: event pass-through directly honors coroutine filters with 0ms delay, preserving 60 FPS tick rates on fast arcade games.
- **Global Floating Notification Toast Daemon**:
  - Non-intrusive 2-line floating banner rendered across the top of the terminal with 3.5s auto-dismiss timer.
  - Multi-protocol alerts: `✉ New Mail` (Light Blue), `💬 Chat` (Blue), `💰 Bank Payment` (Green), `💳 Invoice Request` (Orange with speaker chime), and `📡 AirDrop` (Cyan/Lime).
  - **Tap to Open**: Clicking or tapping on the toast banner automatically opens or switches focus to the relevant application (`mail`, `chat`, `bank`, `merchant`, `files`).
  - Buffered screen restoration: restores the underlying active task's window buffer cleanly upon dismissal with zero character artifacts.
- **Quick Task Switcher (`F1` / `Ctrl`)**:
  - Hotkey accessible from any game or tool to switch active foreground focus between open tasks and the Desktop.
  - **Process Killing (`[X]` / `[Del]`)**: Closes any running task cleanly while protecting the system desktop.
  - **App Launcher (`[N]`)**: Built-in quick app picker to launch any installed app or game without losing state in running programs.
- **Centralized Network Packet Dispatcher**:
  - Centralizes `rednet_message` processing in `TaskManager.step()` to prevent background listener threads from intercepting or stealing packets meant for active child apps.
  - Transparently forwards all network packets to the active foreground task.
- **Automated Test Suite (`tests/test_task_manager.lua`)**:
  - Added full test suite verifying task creation, coroutine execution, high-frequency timers, event filtering, toast overlays, timer dismissals, and process reaping.
  - Upgraded `tests/test_all.lua` to 17 automated test suites with 100% pass rate.

#### Changed
- **Drunken OS Mobile Client (`clients/Drunken_OS_Client.lua`)**:
  - Initialized `TaskManager` supervisor running the Desktop as protected Task #1.
  - Updated app launcher (`executeChoice`) to spawn apps as managed tasks with clean coroutine suspension.
  - Replaced CPU-burning 0.5s poll loops in `backgroundListener` with a lightweight 15-second periodic synchronization timer for high scores and unread mail counts.
  - Added `{ name = "task_manager" }` to `REQUIRED_LIBS` and exposed `context.taskManager` and `context.notify`.
- **Manifest Synchronization**:
  - Added `lib/task_manager.lua` to `shared` packages in both `manifest.lua` and `installer/manifest.lua`.

---

## [16.8.0] - 2026-09-04 - Enterprise Edition

### 🚀 Phase 7: Base Redstone Automation & Network Diagnostics

#### Added
- **Base Redstone Switch Node (`clients/remote_switch.lua`)**:
  - Headless / stand-alone ComputerCraft node for controlling machines, doors, blast doors, drawbridges, and Create mod contraptions.
  - Interactive 4-step setup wizard on first boot (`Switch Name`, `Redstone Side [top/bottom/left/right/front/back]`, `Operating Mode [toggle/pulse]`, `Pulse Duration [seconds]`, `Access [public/private]`).
  - Configuration saved locally to `.remote_switch.cfg`.
  - Protocol handler for `"DrunkenRemote"` supporting `PING`, `GET_STATE`, `SET_STATE`, and `PULSE` commands.
  - Live ASCII visual monitor displaying switch status (`[ ACTIVE ]`, `[ INACTIVE ]`, `[ PULSING ]`), toggle count, and last remote operator.
  - Added dedicated package `packages.remote_switch` to `installer/manifest.lua` and root `manifest.lua`.
- **Drunken Remote Pocket App (`apps/remote.lua`)**:
  - Touch-first 26×20 Pocket Computer application for remote base control.
  - Auto-discovery of all online `remote_switch` nodes on `"DrunkenRemote"`.
  - Color-coded status badges (`[ ACTIVE ]` green, `[ INACTIVE ]` gray, `[⚡ 2s]` orange pulse, `[OFFLINE]` red).
  - Dual control scheme: 1-tap touch toggling or quick numeric key shortcuts (`1`-`9`).
  - Ownership security: shows `[LOCKED]` on private switches registered to another player.
- **NetRadar Pocket Scanner (`apps/radar.lua`)**:
  - Handheld wireless network diagnostic tool for Pocket Computers.
  - **Nearby Devices Tab**: Scans the airwaves for active player pocket computers, turtles, and base computers using GPS trilateration. Calculates exact 3D Euclidean block distance ($\sqrt{\Delta x^2 + \Delta y^2 + \Delta z^2}$) and sorts live by proximity.
  - **Server Health Tab**: Diagnostic ping tool that measures round-trip network latency in milliseconds (`ms`) for central servers (`DB_Bank`, `ArcadeGames`, `MailServer`), with a fast 0.8s bounded timeout.
- **Automated Test Suites**:
  - Added `tests/test_remote.lua` (discovery, toggling, pulse duration, and owner permissions).
  - Added `tests/test_radar.lua` (distance math, proximity sorting, server ping latency, and offline handling).
  - Upgraded `tests/test_all.lua` to run 16 automated test suites with 100% pass rate.

#### Changed
- **Client Desktop & App Store**:
  - Added `remote` and `radar` to `REQUIRED_APPS` and default shortcuts in `clients/Drunken_OS_Client.lua`.
  - Bundled `apps/remote.lua`, `apps/radar.lua`, `apps/calc.lua`, `apps/notes.lua`, and `clients/remote_switch.lua` in `packages.client` in both `manifest.lua` and `installer/manifest.lua`.
  - Added aliases `remote`, `remoteApp`, `radar`, and `netRadar` to `lib/drunken_os_apps.lua`.
  - Added background listener for `"DrunkenRadar"` ping requests in `clients/Drunken_OS_Client.lua`.

---

## [16.5.0] - 2026-09-03 - Offline Gaming & P2P Era

### 🎮 Phase 6: P2P Wireless Gaming & Universal Offline Resilience

#### Added
- **Offline-First Score Cache (`lib/score_cache.lua`)**:
  - Local database (`.game_scores.db`) caching personal bests and timestamps for all 14 arcade games.
  - Deferred sync queue (`.pending_scores.db`): high scores achieved while central server chunks are offline or unloaded are safely preserved and automatically pushed to the Arcade Server upon reconnecting.
- **Drunken Connect 4 (`games/Drunken_Connect4.lua`)**:
  - 7×6 interactive grid game with full touch and numeric input.
  - Single Player mode featuring an intelligent heuristic AI (checks winning moves, blocks opponents, values center columns).
  - Wireless 2-Player P2P multiplayer using `lib/p2p_socket.lua` on protocol `"C4_P2P"`.
- **Drunken Battleship (`games/Drunken_Battleship.lua`)**:
  - 6×6 naval combat grid with Carrier (4), Cruiser (3), Destroyer (2), and Submarine (1).
  - Strategic auto-deploy algorithm with boundary and collision detection.
  - Single Player mode vs Naval AI with hunt/target parity search.
  - Wireless 2-Player P2P multiplayer using `lib/p2p_socket.lua` on protocol `"Battleship_P2P"`.
- **AirDrop File Beam (`apps/files.lua`)**:
  - Direct device-to-device wireless file transfer over protocol `"DrunkenAirDrop"`.
  - Allows players to beam files between pocket computers anywhere in the world with zero server chunk dependency.
- **Automated Tests**:
  - Added `tests/test_score_cache.lua`, `tests/test_p2p_socket.lua`, `tests/test_c4.lua`, and `tests/test_battleship.lua`.

#### Changed
- **Universal Graceful Offline Mode**:
  - Bounded 1.2s–1.5s network timeouts across `apps/bank.lua`, `apps/mail.lua`, and `apps/arcade.lua`.
  - Central server outages or sleeping chunks no longer freeze clients or cause black screens.
  - All 14 arcade games can be launched and played offline without active server connections.

---

## [16.0.0] - 2026-09-02 - Mobile Touch & Survival Utilities

### 📱 Phase 5: Mobile Touch & Survival Utilities

#### Added
- **Survival Calculator (`apps/calc.lua`)**:
  - Standard arithmetic expressions with safe evaluation.
  - Minecraft stack division helper (converts raw item counts into stacks + remainder, e.g. `250 = 3 stacks (64) + 58`).
  - Create Mod rotational speed ratio calculator (computes gear ratios and RPM between driving and driven cogwheels).
- **GPS Field Notes (`apps/notes.lua`)**:
  - Touch-friendly scratchpad for saving base notes, waypoint coordinates, and todo lists.
  - One-tap "Tag GPS" button that auto-fetches exact coordinates from wireless satellites.
- **Touch-to-Jump**:
  - Added full mouse/touch click event handlers in `games/floppa_bird.lua` for mobile pocket play.
- **Dynamic Status Notch**:
  - Top header on pocket computers displays real-time Minecraft clock (`HH:MM`), wireless connection status, unread mail indicator, and battery/ID status.

---

## [15.0.0] - 2026-09-01 - High-Concurrency & Enterprise Core

### ⚡ Phase 4: High-Concurrency & Network Optimization

#### Added
- **Delta-Row Terminal Buffering (`lib/engine.lua`)**:
  - Differential screen renderer caching dirty lines. Only sends modified characters to ComputerCraft, reducing Minecraft server-to-client network packet overhead by up to 90%.
- **Universal DNS Cache (`lib/dns.lua`)**:
  - Client-side name resolution caching with 60-second TTL.
  - Patches `rednet.lookup` to prevent network-wide broadcast storms when multiple users launch apps simultaneously.
- **Cryptographic Anti-Replay Defense (`lib/crypto_packet.lua`)**:
  - HMAC-SHA1 signature verification, unix timestamps, and rolling nonce protection against packet replay attacks.
- **Chunked Streaming File Transfers (`lib/transfer.lua`)**:
  - 2KB sliding window chunked transfer engine with SHA-1 integrity verification, sequence numbering, and live progress bars.
- **Non-Blocking RPC Layer (`lib/rpc.lua`)**:
  - Asynchronous remote procedure calls with transaction IDs (`tx_id`), bounded timeouts, and dedicated inboxes that preserve unrelated packets.

---

## [4.0.0] - 2026-08-20 - Multiplayer & Arcade Expansion

### 🕹️ Phase 2: Multiplayer & Leaderboards

#### Added
- **P2P Socket Library (`lib/p2p_socket.lua`)**:
  - Reliable peer-to-peer transport with connection handshake, heartbeat pings, and disconnect detection.
- **Arcade Server High Score Persistence (`servers/Drunken_Arcade_Server.lua`)**:
  - Centralized global leaderboards and game distribution.
- **Spectator Mode & Lobby**:
  - Live game observation and matchmaking in `Drunken Duels`.

---

## [3.0.0] - 2026-08-10 - Modular Applet System

### 🏗️ Phase 1: Stabilization & Modularity

#### Added
- **Modular App Loader (`lib/app_loader.lua`)**:
  - Decoupled apps from `clients/Drunken_OS_Client.lua` into isolated `.lua` files in `apps/`.
- **Shared Libraries**:
  - `lib/theme.lua`: Centralized color themes (`Default`, `Matrix`, `Red Alert`, `Midnight`, `Game`).
  - `lib/utils.lua`: Shared UI helpers (`wordWrap`, `safeColor`, `showLoading`, `inputBox`).
  - `lib/db.lua`: ACID-compliant atomic database writes with crash protection.
  - `lib/sdk.lua`: Standardized application development kit.
- **Server Modularization**:
  - Split `servers/Drunken_OS_Server.lua` into `servers/modules/auth.lua` and `servers/modules/chat.lua`.
