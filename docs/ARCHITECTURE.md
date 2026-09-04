# Drunken OS Architecture Decisions 🏛️

This document codifies the core architectural constraints, design patterns, and engineering standards for **Drunken OS**. **All contributors, developers, and agents must enforce these rules.**

---

## 1. Modular Applet Architecture (v3.0+)

- **Pattern**: Apps are standalone executable files in `apps/`.
- **Constraint**: The "Core Client" (`clients/Drunken_OS_Client.lua`) must **NOT** contain app-specific business logic (e.g. Banking transactions, calculator math, redstone pulse logic). The client handles only the Desktop UI, Window Manager, and lifecycle loading.
- **State Passing**: All apps must accept a `context` table containing:
  ```lua
  {
      parent = parentWindow,   -- CC window or term redirect target
      theme = currentTheme,    -- Active theme palette from lib/theme.lua
      programDir = "/apps",    -- Root applet directory
      user = currentUser       -- Authenticated username (if logged in)
  }
  ```

---

## 2. Shared Libraries & Single Source of Truth

- **Themes**: All colors must reference `lib/theme.lua`. Never hardcode `colors.black`, `colors.blue`, etc., directly inside application render loops.
- **UI Utilities**: Standard UI routines (word wrapping, safe text coloring, loading spinners, input dialogs) must be imported from `lib/utils.lua`.
- **Database Persistence**: All file-based databases must use `lib/db.lua` for ACID atomic writes (`.tmp` swap pattern) to prevent corruption during Minecraft crashes or chunk unloads.
- **Distribution Manifests**: System manifests (`manifest.lua` and `installer/manifest.lua`) must remain strictly synchronized.

---

## 3. Networking & Peer-to-Peer (P2P)

- **Standard Transport**: All multiplayer games must use `lib/p2p_socket.lua` for matchmaking, connection handshakes, heartbeat pings, and disconnect detection.
- **Direct Rednet Restriction**: Games must **NOT** call `rednet.send` directly for connection handshakes. Standardize on the P2P socket layer to guarantee compatibility with arcade lobbies.

---

## 4. High-Concurrency & Enterprise Performance

- **Differential Screen Buffering**: High-frame-rate rendering (such as games or rapid UI transitions) must leverage `lib/engine.lua`'s delta-row buffering. Only rows with altered characters or colors should be sent to the terminal driver to conserve Minecraft network packet bandwidth.
- **DNS Caching**: Applications resolving service hostnames must route queries through `lib/dns.lua` (or use the patched `rednet.lookup`), caching results with a 60-second TTL to eliminate broadcast storms.
- **Non-Blocking RPC**: Remote procedure calls must use `lib/rpc.lua` with unique transaction IDs (`tx_id`) and bounded timeouts. Incoming messages for other protocols must be preserved in the queue rather than discarded.
- **Anti-Replay Defense**: Sensitive commands (such as financial transactions and remote base actuation) must encapsulate payloads in `lib/crypto_packet.lua` with HMAC-SHA1 signatures, timestamps, and nonces.

---

## 5. Offline-First Resilience & Bounded Timeouts

- **Zero Blocking Freezes**: Network calls to central servers must enforce bounded timeouts between **0.8s and 1.5s**. Never allow an unreachable server chunk to freeze a player's screen or crash an applet.
- **Universal Graceful Degradation**: Core apps (Games, Calculator, Notes, Files, Remote) must remain fully functional when central servers are offline or asleep.
- **Deferred High Score Sync**: Game high scores earned offline must be saved locally via `lib/score_cache.lua` in `.game_scores.db` and queued in `.pending_scores.db`. When the Arcade Server is detected online, pending scores must be synchronized automatically.

---

## 6. Handheld Pocket Computer Constraints

- **Single Upgrade Slot Rule**: Advanced Pocket Computers have only **one** internal upgrade slot, which is reserved for the **Wireless Modem**.
  - **CRITICAL**: Never add dependencies on `speaker` peripherals or audio calls (`speaker.playNote`, `speaker.playSound`) to Pocket Computer applications or client desktop components.
- **Form Factor Budget**: Pocket Computer screens are strictly **26 columns by 20 rows**. UI layouts must fit within these dimensions without overflow or clipping.
- **Dual Input Modality**: All pocket interfaces must support both mouse touch clicks (`mouse_click`) and keyboard shortcuts (numeric keys `1`–`9` and arrow keys) for compatibility with all ComputerCraft client variants.

---

## 7. Base Redstone Protocol & Access Control

- **Standard Protocol**: Base redstone nodes and pocket remotes communicate over protocol `"DrunkenRemote"`.
- **Access Verification**:
  - Switches configured as `access = "private"` must verify that `sender_user == switch.owner` before executing state changes or pulses.
  - Switches configured as `access = "public"` may be actuated by any authenticated user on the network.

---

## 8. Routing Layer Abstraction

- **Pattern**: Proxy servers are lightweight wrappers.
- **Constraint**: Instead of implementing bespoke bridging loops, proxy servers must declare `PROTOCOL_MAP` and `HOST_MAP` configurations and invoke the centralized `ProxyBase.run()` dispatcher in `lib/proxy_base.lua`.

---

## 9. Event Loop & Concurrency

- **Pattern**: Non-blocking asynchronous event handling.
- **Constraint**: Server and background listener loops must utilize `parallel.waitForAny()` and `os.pullEventRaw()` to guarantee TPS safety and prevent blocking the Minecraft main thread during heavy packet loads.

---

_Enforced by the Drunken OS Architecture Committee._
