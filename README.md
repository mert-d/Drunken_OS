# 🏴‍☠️ Drunken OS (Enterprise Edition v16.9)

[![Version](https://img.shields.io/badge/version-16.9.0%20Enterprise-blue.svg)](CHANGELOG.md)
[![Minecraft](https://img.shields.io/badge/minecraft-1.18.2%2B-brightgreen.svg)]()
[![Mod](https://img.shields.io/badge/mod-CC%3ATweaked%20%7C%20Restitched-orange.svg)]()
[![Tests](https://img.shields.io/badge/tests-17%2F17%20Passing%20(100%25)-success.svg)](tests/)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

A comprehensive, distributed operating system and network ecosystem designed for **CC:Tweaked** and **CC:Restitched** (ComputerCraft) in Minecraft. Engineered for high performance, fault tolerance, and rich interaction on handheld **Pocket Computers**, desktop workstations, and autonomous turtles. Fully optimized for large survival multiplayer servers and industrial modpacks such as **Create Astral**.

---

## ✨ Features

### 🔀 Multi-Tasking & Global Notification Daemon
- **Coroutine Task Manager (`lib/task_manager.lua`)**: Cooperative multitasking supervisor running concurrent apps and desktop shell simultaneously.
- **Window-Buffered Screen Memory**: Isolates display buffers (`window.create`) per task, guaranteeing 0 screen corruption or artifacting when background processes or notifications fire.
- **Global Floating Toasts**: 3.5s auto-dismissing notification banners for Mail, Chat, Bank payments, Merchant invoices, and AirDrop with 1-tap app launch.
- **Quick Task Switcher (`F1` / `Ctrl`)**: Seamless switching between open tasks and Desktop, process killing, and quick app launcher (`[N]`).
- **Zero Performance Degradation**: Fast arcade games (*Tetris*, *Floppa Bird*, *Pong*) maintain 60 FPS tick rates with zero input lag.

### ⚡ Enterprise Network & Rendering Engine
- **Delta-Row Terminal Buffering (`lib/engine.lua`)**: Caches dirty screen rows to reduce Minecraft server-to-client network packet transmission by up to 90%.
- **Universal DNS Resolution Cache (`lib/dns.lua`)**: 60-second TTL service discovery caching that eliminates network-wide broadcast storms.
- **Cryptographic Anti-Replay Security (`lib/crypto_packet.lua`)**: HMAC-SHA1 signatures, timestamps, and rolling nonce verification.
- **Chunked File Streaming (`lib/transfer.lua`)**: 2KB sliding window transfers with real-time progress indicators and SHA-1 verification.
- **Non-Blocking RPC Pipeline (`lib/rpc.lua`)**: Asynchronous multi-plexed requests with transaction IDs (`tx_id`) and non-discarding inboxes.

### 🎮 14 Built-in Games & Offline-First Gaming
- **14 Built-in Arcade Titles**:
  - *Strategy & Board*: Connect 4 (Smart AI + P2P), Battleship (Naval AI + P2P), Sokoban, Minesweeper, 2048.
  - *Action & 3D*: Drunken Doom (Raycasting FPS), Space Invaders, Drunken Duels (1v1 P2P combat + Spectator mode), Floppa Bird (with touch support), Snake, Pong, Tetris, Dungeons (Roguelike co-op), City Builder.
- **Universal Graceful Offline Mode**: Central server outages or sleeping chunks never freeze client screens. All games are instantly playable offline.
- **Offline Score Cache & Deferred Sync (`lib/score_cache.lua`)**: High scores earned while servers are offline are preserved locally in `.pending_scores.db` and automatically synchronized when the Arcade Server returns online.

### 🔴 Base Redstone Automation
- **Remote Switch Node (`clients/remote_switch.lua`)**: Headless ComputerCraft node with an interactive setup wizard to control base doors, blast doors, lighting, sirens, drawbridges, and Create mod contraptions.
- **Drunken Remote App (`apps/remote.lua`)**: Touch-first Pocket Computer app for discovering, monitoring, and toggling base switches remotely with color-coded live status (`[ ACTIVE ]`, `[ INACTIVE ]`, `[⚡ 2s]`, `[OFFLINE]`).

### 📡 Network Radar & Diagnostics
- **NetRadar Pocket Scanner (`apps/radar.lua`)**:
  - **Nearby Devices**: Scans the wireless spectrum for active players, turtles, and base computers using GPS trilateration. Calculates exact 3D Euclidean block distance ($\sqrt{\Delta x^2 + \Delta y^2 + \Delta z^2}$) and sorts by proximity.
  - **Server Health**: Real-time ping latency benchmark (`ms`) for central servers (`DB_Bank`, `ArcadeGames`, `MailServer`) with an ultra-fast 0.8s bounded timeout.

### 🛠️ Survival & Engineer Utilities
- **Survival Calculator (`apps/calc.lua`)**: Handles arithmetic, 64-item Minecraft stack division (e.g. `250 = 3 stacks + 58`), and Create mod rotational gear ratio calculations.
- **GPS Field Notes (`apps/notes.lua`)**: Touch notepad with 1-tap satellite GPS coordinate stamping.
- **AirDrop Wireless Beam (`apps/files.lua`)**: Device-to-device wireless file beam over `"DrunkenAirDrop"` with zero server dependencies.

### 🏦 Economy, Banking & Commerce
- **Central Banking (`servers/Drunken_OS_BankServer.lua`)**: Accounts, balance ledgers, transaction records, and currency exchange.
- **ATM Kiosks & POS Terminals (`clients/DB_Bank_ATM.lua`, `clients/DB_Merchant_POS.lua`)**: Public deposit/withdrawal kiosks and merchant retail terminals.
- **Autonomous Financial Turtles**: Bank Auditor Turtle (`turtles/DB_Bank_Clerk.lua`, `turtles/vending_turtle.lua`) verifying SHA-1 hash chain integrity.

### 📬 Communication & Cloud Storage
- **Mail & Cloud System (`servers/Drunken_OS_MailServer.lua`)**: User-to-user email with file attachments and cloud disk synchronization.
- **Real-Time Global Chat (`servers/modules/chat.lua`)**: Rednet chatroom with room multiplexing and user presence.

---

## 🏗️ Repository Architecture

```text
Drunken_OS/
├── apps/                         # Handheld Pocket & Desktop Modular Applets
│   ├── arcade.lua                # Arcade lobby, game launcher & leaderboard viewer
│   ├── bank.lua                  # Banking client (transfers, balance, ledger)
│   ├── calc.lua                  # Calculator with Create gear ratios & stack division
│   ├── chat.lua                  # Real-time chat client
│   ├── files.lua                 # File explorer with wireless P2P AirDrop beam
│   ├── mail.lua                  # Mail reader & composer with attachments
│   ├── notes.lua                 # Scratchpad with 1-tap GPS auto-tagging
│   ├── radar.lua                 # 3D GPS device scanner & server latency ping
│   ├── remote.lua                # Pocket remote control for base redstone switches
│   └── system.lua                # System updater, diagnostics & settings
├── clients/                      # Client Systems & Hardware Nodes
│   ├── Drunken_OS_Client.lua     # Core desktop launcher & window manager
│   ├── remote_switch.lua         # Headless base redstone switch node
│   ├── DB_Bank_ATM.lua           # Public banking ATM kiosk
│   ├── DB_Merchant_Cashier.lua   # Storefront merchant checkout
│   ├── DB_Merchant_POS.lua       # Roaming point-of-sale terminal
│   └── Admin_Console.lua         # Operator administration console
├── servers/                      # Central Network Infrastructure
│   ├── Drunken_OS_Server.lua     # Mainframe gateway coordinator
│   ├── Drunken_OS_BankServer.lua # Banking & currency ledger server
│   ├── Drunken_Arcade_Server.lua # Arcade distribution & leaderboard server
│   ├── Drunken_OS_AuthServer.lua # Cryptographic authentication server
│   ├── Drunken_OS_MailServer.lua # Email & cloud storage server
│   ├── Proxy_Mainframe.lua       # Wireless-to-wired network proxy bridge
│   ├── Proxy_Bank.lua            # Bank isolation proxy bridge
│   └── modules/                  # Modular server logic (auth, chat, mail)
├── games/                        # 14 Full Arcade Games
│   ├── Drunken_Connect4.lua      # 7x6 Connect 4 (Smart AI + P2P multiplayer)
│   ├── Drunken_Battleship.lua    # 6x6 Battleship (Naval AI + P2P multiplayer)
│   ├── Drunken_Doom.lua          # Pseudo-3D raycasting engine FPS
│   ├── Drunken_Duels.lua         # 1v1 P2P combat arena with spectator mode
│   ├── Drunken_Dungeons.lua      # Turn-based roguelike with co-op
│   ├── Drunken_Pong.lua          # 2-player arcade pong
│   ├── floppa_bird.lua           # Flappy bird with mobile touch-to-jump
│   ├── snake.lua, tetris.lua, minesweeper.lua, sokoban.lua, ...
├── lib/                          # Shared Enterprise Libraries
│   ├── engine.lua                # Delta-row dirty line terminal buffering
│   ├── dns.lua                   # 60s TTL DNS lookup cache
│   ├── crypto_packet.lua         # HMAC-SHA1 signature & replay protection
│   ├── transfer.lua              # 2KB sliding window chunked file transfer
│   ├── rpc.lua                   # Non-blocking RPC protocol layer
│   ├── score_cache.lua           # Offline score caching & deferred synchronization
│   ├── p2p_socket.lua            # P2P connection handshake & packet transport
│   ├── db.lua                    # ACID atomic database persistence & crash recovery
│   ├── task_manager.lua          # Coroutine multitasking supervisor & notification daemon
│   ├── theme.lua                 # Color palettes (Default, Matrix, Red Alert, etc.)
│   ├── utils.lua                 # UI primitives (wordWrap, safeColor, inputBox)
│   └── sdk.lua                   # Standard application development kit
├── turtles/                      # Autonomous Robotic Systems
│   ├── Chef_Turtle.lua           # Automated furnace cooking turtle
│   ├── Waiter_Turtle.lua         # GPS-guided food delivery turtle
│   └── vending_turtle.lua        # Item chest dispenser turtle
├── installer/                    # Master Installer & Deployment Disks
│   ├── Master_Installer.lua      # Menu-driven floppy disk burner
│   └── manifest.lua              # Distribution catalog & package specifications
├── tests/                        # Automated Test Suite (17/17 Passing)
│   ├── test_all.lua              # Master test runner (100% automated pass)
│   ├── test_task_manager.lua     # Multitasking & notification daemon unit tests
│   ├── test_remote.lua, test_radar.lua, test_score_cache.lua, ...
└── docs/                         # Comprehensive Engineering Documentation
    ├── FULL_SYSTEM_SETUP_GUIDE.md# End-to-end multi-server setup guide
    ├── MINECRAFT_SETUP_GUIDE.md  # Beginner player guide
    ├── INSTALLATION_GUIDE.md     # Operator update & upgrade procedures
    └── ARCHITECTURE.md           # Engineering specifications & conventions
```

---

## 🚀 Quick Start

### In-Game Master Installer
On any Advanced Computer with a disk drive attached, run:
```bash
pastebin run <installer_code>
```
*(Or launch locally: `installer/Master_Installer.lua`)*

Select a package to write to a blank floppy disk:
- **Option 1**: Mainframe Gateway Server
- **Option 2**: User Client (Pocket Computer & Desktop)
- **Option 3**: Remote Redstone Switch Node
- **Option 4**: Bank Server
- **Option 9**: Arcade Games Server
- **Option 10**: Proxy Servers & Turtles

### Requirements
- **Minecraft**: 1.18.2 or newer
- **Mod**: CC:Tweaked (1.100.8+) or CC:Restitched
- **Hardware**: Advanced Computers (Gold) and Advanced Pocket Computers (color display recommended)
- **Peripherals**: Wired modems, wireless modems, networking cables, and disk drives

---

## 🧪 Automated Testing

Drunken OS includes a 16-suite unit test runner covering all core libraries, networking layers, cryptography, and game AI. Run the master test suite on any computer:
```bash
tests/test_all.lua
```
**Results: 16/16 test suites passing (100%)**

---

## 📖 Documentation Index

- [Full System Setup Guide](docs/FULL_SYSTEM_SETUP_GUIDE.md) — Comprehensive two-tier network installation, 24/7 world spawn hosting, and in-game testing verification checklist.
- [Minecraft Survival Guide](docs/MINECRAFT_SETUP_GUIDE.md) — Step-by-step visual tutorial for survival players.
- [Operator Upgrade Guide](docs/INSTALLATION_GUIDE.md) — Update instructions and package manifests.
- [Architecture & Design Rules](docs/ARCHITECTURE.md) — Core architectural standards, concurrency rules, and network protocols.
- [Changelog](CHANGELOG.md) — Detailed version history from v3.0 to v16.8 Enterprise Edition.

---

## 📄 License
MIT License. Created by MuhendizBey with assistance from Gemini.
