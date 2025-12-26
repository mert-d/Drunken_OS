# Drunken OS Architecture Decisions 🏛️

This file documents the core architectural constraints and patterns. **All Agents must enforce these rules.**

## 1. Modular Applet Architecture (v3.0+)

- **Pattern**: Apps are standalone files in `apps/`.
- **Constraint**: The "Core Client" (`Drunken_OS_Client.lua`) must **NOT** contain app-specific logic (e.g., Bank UI, Calculator logic). It only handles the Desktop, Window Manager, and Loading.
- **State Passing**: Apps must accept a `context` table containing `{ parent, theme, programDir }`.

## 2. Shared Libraries

- **Single Source of Truth**:
  - Colors/Theme -> `lib/theme.lua` (Do not hardcode `colors.black` in apps).
  - UI Helpers -> `lib/utils.lua` (Do not copy-paste `wordWrap`).
  - Manifest -> `installer/manifest.json` (Do not hardcode file lists in `install.lua`).

## 3. Networking & P2P

- **Protocol**: All multiplayer games must use `lib/p2p_socket.lua` (once created) for connections.
- **Constraint**: Games must **NOT** use `rednet.send` directly for handshake logic. This ensures compatibility with the Arcade Lobby system.

## 4. versioningStrategy

- **SemVer**: All apps and servers must report a `_VERSION` string (e.g., "1.2.0").
- **Updater**: The Updater checks this string against the Server's manifest.

## 5. Security

- **Input Sanitization**: All `read()` inputs in Servers must be type-checked before use.
- **Hardware IDs**: Users are bound to their Setup via `os.getComputerID()` checking in the Auth flow.
