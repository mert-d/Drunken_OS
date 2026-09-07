# 📖 Drunken OS Enterprise Documentation (v16.8)

Welcome to the technical documentation for **Drunken OS (Enterprise Edition)**, an advanced, modular, Rednet-based operating system designed for **CC:Tweaked** and **CC:Restitched** in Minecraft. This document covers the distributed architecture, enterprise networking layers, security models, application suites, and protocol specifications.

---

## 🏛️ System Architecture Overview

Drunken OS employs an enterprise **two-tier network architecture** designed to isolate critical backend servers (Auth, Mail, Bank ledgers) from public wireless packet interception, using transparent proxy bridges:

```
                  ┌──────────────────────────────────────────────┐
                  │          TIER 1: PUBLIC WIRELESS AIR         │
                  │   Pocket Computers, Switches, Remote Terminals│
                  └───────┬──────────────────────────────┬───────┘
                          │                              │
                          ▼                              ▼
                 ┌──────────────────┐           ┌──────────────────┐
                 │  Proxy Mainframe │           │    Proxy Bank    │
                 │   (Wireless +    │           │   (Wireless +    │
                 │      Wired)      │           │      Wired)      │
                 └────────┬─────────┘           └────────┬─────────┘
                          │                              │
══════════════════════════╪══════════════════════════════╪═════════════════════════
                          │   TIER 2: INTERNAL WIRED     │
                          │   INTERLINK (CABLES)         │
     ┌────────────────────┼──────────────────────────────┴───────────────┐
     │                    │                                              │
     ▼                    ▼                         ▼                    ▼
┌───────────┐      ┌───────────────┐         ┌───────────────┐    ┌─────────────┐
│   Auth    │◄────►│   Mainframe   │◄───────►│     Mail      │    │    Bank     │
│  Server   │      │ (Coordination)│         │ (Files/Cloud) │    │   Server    │
└───────────┘      └───────────────┘         └───────────────┘    └──────┬──────┘
                                                                         │
                                                                  ┌──────▼──────┐
                                                                  │ Bank Auditor│
                                                                  │   Turtle    │
                                                                  └─────────────┘
```

### Core Components

| Component | Path | Description |
| :--- | :--- | :--- |
| **Mainframe Gateway** | `servers/Drunken_OS_Server.lua` | Service discovery coordinator, global chat, and app distribution gateway. |
| **Auth Server** | `servers/Drunken_OS_AuthServer.lua` | Cryptographic credential authority using SHA-1 salts and secure tokens. |
| **Mail & Cloud Server**| `servers/Drunken_OS_MailServer.lua` | Stores user-to-user messages, attachments, and cloud files. |
| **Bank Server** | `servers/Drunken_OS_BankServer.lua` | Double-entry accounting ledger, balances, transfers, and stock exchange. |
| **Arcade Server** | `servers/Drunken_Arcade_Server.lua` | Game distribution hub and global high score leaderboard repository. |
| **Mainframe Proxy** | `servers/Proxy_Mainframe.lua` | Bridges wireless client airwaves to backend wired network cables. |
| **Bank Proxy** | `servers/Proxy_Bank.lua` | Bridges public wireless bank inquiries to the isolated vault network. |
| **OS Client** | `clients/Drunken_OS_Client.lua` | Handheld / Desktop launcher, window manager, and dynamic mobile status notch. |
| **Remote Switch Node**| `clients/remote_switch.lua` | Headless ComputerCraft node controlling base redstone contraptions. |
| **Auditor Turtle** | `turtles/DB_Bank_Clerk.lua` | Robotic sentinel verifying SHA-1 ledger hash chains in real time. |

---

## ⚡ Enterprise Core Libraries

Drunken OS includes a suite of high-performance libraries in the `lib/` directory:

### 1. `lib/engine.lua` — Delta-Row Terminal Buffering
- Caches dirty characters on a per-row basis.
- Only transmits changed characters to the terminal driver (`term.setCursorPos` + `term.blit`), slashing Minecraft server-to-client network packet overhead by up to **90%**.
- Prevents visible screen flicker during high-speed game rendering.

### 2. `lib/dns.lua` — Universal DNS Cache
- Intercepts `rednet.lookup` calls and caches service-to-ID mappings with a 60-second Time-To-Live (TTL).
- Eliminates broadcast storms when dozens of clients ping the network at the same time.

### 3. `lib/crypto_packet.lua` — Anti-Replay Cryptographic Packets
- Wraps sensitive payloads with HMAC-SHA1 signatures, millisecond timestamps, and rolling random nonces.
- Automatically rejects stale or replayed packets.

### 4. `lib/transfer.lua` — Chunked File Streaming
- Implements 2KB sliding window transfers for transferring documents, games, or apps over Rednet.
- Features chunk sequence numbering, dynamic ASCII progress bars, and SHA-1 checksum verification.

### 5. `lib/rpc.lua` — Non-Blocking RPC Layer
- Enables multi-plexed requests and responses using unique transaction IDs (`tx_id`).
- Incoming messages for other services are stored safely in an inbox rather than discarded during polling.

### 6. `lib/score_cache.lua` — Offline Score Caching & Deferred Sync
- Local persistent store (`.game_scores.db`) tracking personal bests for all 14 arcade games.
- Pending high score queue (`.pending_scores.db`) that automatically syncs scores to the Arcade Server when it comes back online.

### 7. `lib/p2p_socket.lua` — Peer-to-Peer Socket Transport
- Symmetric connection handshake, continuous heartbeat pinging, and timeout disconnection detection for multiplayer games.

### 8. `lib/db.lua` — ACID Atomic Database Persistence
- Crash-safe database writes using atomic `.tmp` swap files. Guarantees that sudden server restarts never corrupt bank accounts or mailboxes.

### 9. `lib/task_manager.lua` — Multi-Tasking & Notification Daemon
- Cooperative coroutine supervisor managing multiple active processes and the desktop shell concurrently.
- Window-buffered screen memory (`window.create`) per task: isolates rendering buffers so background processes and toasts cause 0 screen corruption on running games or apps.
- Centralized network packet dispatcher: catches `rednet_message` events for Mail, Chat, Bank transfers, Merchant invoices, and Radar pings, displays non-intrusive floating toast banners with tap-to-open, and forwards packets transparently to the active foreground app.
- Task switcher interface (`F1` / `Ctrl`) with process killing (`[X]`) and quick app launcher (`[N]`).

---

## 📱 Modular Applet Suite

Applications in Drunken OS are isolated modules located in `apps/`. Each app receives a standard `context` table containing `{ parent, theme, programDir }`:

### Core System Applets
- **`apps/arcade.lua`**: Browse installed games, view global & local high scores, launch titles, and sync updates from the Arcade Server.
- **`apps/bank.lua`**: Check balance, transfer funds to players, view transaction history, and check stock prices. Features bounded 1.2s timeout for graceful offline operation.
- **`apps/mail.lua`**: Send and receive messages, view inbox/outbox, attach documents, and manage contacts.
- **`apps/chat.lua`**: Real-time global IRC-style chatroom.
- **`apps/files.lua`**: Local file explorer with built-in **AirDrop** wireless beam to transfer files directly to nearby pocket computers without server dependencies.
- **`apps/system.lua`**: App store / package updater, theme selector (`Default`, `Matrix`, `Red Alert`, `Midnight`), and network diagnostics.

### Survival & Engineer Utilities
- **`apps/calc.lua`**:
  - Full arithmetic expression evaluator.
  - Minecraft 64-item stack division (e.g. `250 = 3 stacks (64) + 58 items`).
  - Create Mod rotational gear ratio calculator (computes gear ratios and output RPM).
- **`apps/notes.lua`**: Handheld notepad with 1-tap satellite GPS coordinate tagging.

### Base Automation & Diagnostics
- **`apps/remote.lua`**: Handheld Pocket Computer remote control for base redstone switches. Auto-discovers online `remote_switch` nodes on `"DrunkenRemote"`, displays live color-coded status badges, and supports 1-tap touch and numeric key toggling.
- **`apps/radar.lua`**:
  - *Nearby Devices Tab*: Scans the airwaves for active pocket computers, turtles, and base computers using GPS trilateration. Calculates 3D Euclidean block distance ($\sqrt{\Delta x^2 + \Delta y^2 + \Delta z^2}$) and sorts live by proximity.
  - *Server Health Tab*: Tests round-trip latency in milliseconds (`ms`) for `DB_Bank`, `ArcadeGames`, and `MailServer` with a 0.8s bounded timeout.

---

## 🎮 Arcade Game Suite (14 Titles)

The OS features 14 complete arcade games located in `games/`, distributed via the **Arcade Server** and fully playable offline:

| Game | File | Description | Controls |
| :--- | :--- | :--- | :--- |
| **Drunken Connect 4** | `games/Drunken_Connect4.lua` | 7×6 strategy grid vs Smart Heuristic AI or 2-Player Wireless P2P. | Touch column or keys 1–7 |
| **Drunken Battleship**| `games/Drunken_Battleship.lua`| 6×6 naval tactics grid vs Naval AI or 2-Player Wireless P2P. | Touch cell or arrows + Enter |
| **Drunken Doom** | `games/Drunken_Doom.lua` | Pseudo-3D raycasting engine (v1.3) with ASCII textures and sprites. | W/A/S/D + Space |
| **Drunken Duels** | `games/Drunken_Duels.lua` | Real-time 1v1 P2P combat arena with spectator broadcast mode. | Arrows + Space |
| **Drunken Dungeons** | `games/Drunken_Dungeons.lua` | Turn-based roguelike RPG with procedural dungeons and co-op. | Arrow keys |
| **Floppa Bird** | `games/floppa_bird.lua` | Flappy bird clone with gravity physics, obstacles, and touch-to-jump. | Touch or Space |
| **Drunken Pong** | `games/Drunken_Pong.lua` | Classic paddle arcade game for 1 or 2 players. | W/S or Arrow keys |
| **Snake** | `games/snake.lua` | Classic arcade snake with speed ramp and fruit spawning. | Arrow keys |
| **Tetris** | `games/tetris.lua` | Block stacking with line clearing and ghost piece preview. | Arrow keys + Space |
| **Space Invaders** | `games/space_invaders.lua` | Retro alien shooter with moving shields and UFOs. | Arrows + Space |
| **Minesweeper** | `games/minesweeper.lua` | Grid logic game with flagging and flood fill revealing. | Touch or Arrows |
| **Sokoban** | `games/sokoban.lua` | Box pushing puzzle with undo history and level loader. | Arrow keys + U |
| **City Builder** | `games/city_builder.lua` | Grid management simulation managing population and power. | Touch / Mouse |
| **2048** | `games/2048.lua` | Number sliding puzzle with score persistence. | Arrow keys |

---

## 📡 Networking Protocols Specification

When building applications or peripheral devices for Drunken OS, use the following official protocols:

| Protocol String | Layer / Purpose | Packet Payload Format |
| :--- | :--- | :--- |
| `"DrunkenRemote"` | Base Redstone Automation | `{ type = "PING" / "GET_STATE" / "SET_STATE" / "PULSE", target_id = N, state = bool, duration = N, sender_user = "name" }` |
| `"DrunkenRadar"` | Network Scanner & Diagnostics | `{ type = "PING" / "PONG", role = "client" / "server" / "turtle", label = "name", timestamp = os.epoch("utc") }` |
| `"C4_P2P"` | Connect 4 Multiplayer | Handled via `lib/p2p_socket.lua` for matchmaking and turn moves. |
| `"Battleship_P2P"` | Battleship Multiplayer | Handled via `lib/p2p_socket.lua` for fleet placement and firing coordinates. |
| `"DrunkenAirDrop"` | P2P File Beam | `{ type = "OFFER" / "ACCEPT" / "CHUNK" / "DONE", filename = "str", data = "str", sender_user = "name" }` |
| `"SimpleMail_Internal"` | Mainframe Email | `{ type = "SEND" / "FETCH" / "DELETE", token = "str", message = table }` |
| `"SimpleChat_Internal"` | Global Chatroom | `{ type = "MSG" / "JOIN" / "LEAVE", username = "str", text = "str" }` |
| `"DB_Bank_Comm"` | Bank Transactions | `{ action = "balance" / "transfer" / "history", account = "str", ... }` |
| `"auth.secure.v1"` | User Authentication | `{ action = "login" / "register", username = "str", hash = "str" }` |
| `"Arcade_Discovery"` | Game Server Lookup | `{ type = "DISCOVER" / "CATALOG", version = "str" }` |

---

## 🧪 Verification & Automated Testing

The Drunken OS test suite can be run directly on any ComputerCraft machine or simulated runner:

```bash
tests/test_all.lua
```

The test runner executes 16 automated test suites:
1. `tests/test_sha1.lua` — HMAC-SHA1 cryptographic verification.
2. `tests/test_utils.lua` — String wrapping, safe coloring, and UI utilities.
3. `tests/test_theme.lua` — Theme palette switching and game colors.
4. `tests/test_db.lua` — Database persistence and atomic swap recovery.
5. `tests/test_sdk.lua` — App loader environment isolation and context injection.
6. `tests/test_dns.lua` — DNS resolution caching and TTL expiration.
7. `tests/test_engine.lua` — Delta-row differential terminal buffering.
8. `tests/test_crypto_packet.lua` — Anti-replay cryptographic validation and nonces.
9. `tests/test_rpc.lua` — Asynchronous RPC multi-plexing and timeout handling.
10. `tests/test_transfer.lua` — Chunked file streaming and SHA-1 verification.
11. `tests/test_score_cache.lua` — Offline score caching and deferred sync queue.
12. `tests/test_p2p_socket.lua` — Peer-to-peer connection lifecycle and disconnect detection.
13. `tests/test_c4.lua` — Connect 4 AI move evaluation and win-condition validation.
14. `tests/test_battleship.lua` — Battleship auto-deployer and hunt/target search AI.
15. `tests/test_remote.lua` — Redstone switch discovery, toggling, and access control.
16. `tests/test_radar.lua` — 3D GPS distance math, proximity sorting, and latency ping.

**Current Test Status: 16/16 Test Suites Passing (100%)**

---

_Authored by the Drunken OS Engineering Team._
