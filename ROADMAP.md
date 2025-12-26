# Drunken OS Roadmap 🗺️

This document outlines the strategic direction for Drunken OS. Agents and contributors should refer to this when planning new features.

## 🟢 Phase 1: Stabilization & Modularity (Current)

_Goal: Move away from monolithic files and ensure the new modular app system is robust._

- [x] **Modular App Loader**: Move core apps to `apps/` (Done in v3.0).
- [x] **Server Refactoring**: Break down `Drunken_OS_Server.lua` (1400+ lines) into modular modules (e.g., `servers/modules/auth.lua`, `servers/modules/chat.lua`).
- [x] **Standardized UI Lib**: Extract common UI patterns from `Drunken_OS_Client.lua` and `drunken_os_apps.lua` into `lib/theme.lua` and `lib/utils.lua`.

## 🟡 Phase 2: The Multiplayer Era

_Goal: Enhance the P2P and Arcade experience._

- [x] **P2P API Standardization**: Create a unified API for games to connect peer-to-peer without rewriting handshake logic every time (Completed in v3.1 using `lib/p2p_socket.lua`).
- [ ] **Arcade Leaderboards**: Persist high scores on the Arcade Server.
- [ ] **Spectator Mode**: Allow users to watch P2P matches (e.g., in Drunken Duels).

## 🔴 Phase 3: Developer Ecosystem

_Goal: Make it easy to create content for Drunken OS._

- [ ] **SDK / DevKit**: A template repository or script to generate a new Drunken OS App.
- [ ] **Test Suite**: A simple `tests/` directory with scripts to verify core library functions (`sha1`, `wordWrap`, etc.).
- [ ] **Package Manager**: A "store" that can download 3rd party apps (beyond the official Arcade).

## 💡 Wishlist / Ideas

- **Voice Chat**: Integration with a voice chat mod (if applicable) or simple TTS/beep codes.
- **Hardware Integration**: Support for advanced peripherals (Printers, monitors, speakers).
