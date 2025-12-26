# Drunken OS Agent Swarm 🐝

This document defines the roles and responsibilities for different AI Agents working on this repository. Use this to assign tasks and avoid conflicts (e.g., two agents trying to edit `Drunken_OS_Server.lua` at the same time).

## 👑 Orchestrator (Main)

- **Scope**: Project Management, Roadmap (`ROADMAP.md`), Task Tracking (`task.md`), Repo Health, Documentation.
- **Responsibilities**:
  - Initialize new projects.
  - Review high-level architecture.
  - Create workflows.
- **Do Not Assign**: specific deep-dive coding tasks if another specialist is available.

## 🧹 Refactoring Agent

- **Scope**: `lib/`, Code Quality, Shared Logic.
- **Responsibilities**:
  - Extracting duplicated code into shared libraries.
  - Renaming variables/functions for clarity.
  - Adding comments/JSDoc.
- **Files**: `lib/*`, cleaning up `client/` and `server/` imports.

## 📡 Networking Agent

- **Scope**: P2P Protocols, Rednet Handshakes, Sockets.
- **Responsibilities**:
  - Simplifying multiplayer connections.
  - Debug network timeouts.
  - Standardizing message formats.
- **Files**: `games/*` (Network logic), `lib/p2p_socket.lua` (Future).

## 🖥️ Server Agent

- **Scope**: Mainframe, Database, Authentication.
- **Responsibilities**:
  - Modularizing `Drunken_OS_Server.lua`.
  - Managing User Data and Auth.
- **Files**: `servers/Drunken_OS_Server.lua`, `servers/modules/*`.

## 🎮 Game/App Developer Agent

- **Scope**: Specific Features.
- **Responsibilities**:
  - Building a specific new game or app.
  - Fixing bugs in a specific game.
- **Files**: `apps/new_app.lua`, `games/new_game.lua`.

---

## Conflict Avoidance Rules

1.  **Server VS Refactor**: If Refactor Agent is extracting `lib/utils.lua`, Server Agent should wait before editing `Server.lua` to avoid merge conflicts on imports.
2.  **Network VS Game**: Network Agent should define the API first; Game Agent implements it.
