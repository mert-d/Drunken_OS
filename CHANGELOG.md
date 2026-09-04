# Changelog

All notable changes to the **Drunken OS** ecosystem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
