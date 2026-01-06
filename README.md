# Drunken OS

A comprehensive operating system for CC:Tweaked (ComputerCraft) in Minecraft, providing a dynamic economy, mailing systems, gaming arcade, and more — all at your fingertips on pocket computers!

## Features

### 🏦 Economy System

- **Bank Server** - Central banking with accounts, transfers, and transaction history
- **ATM Clients** - Deposit, withdraw, and transfer funds
- **Merchant POS** - Accept payments at shops with optional turtle-based vending

### 📧 Communication

- **Mail System** - Send and receive messages between players
- **Chat** - Real-time messaging with other connected users
- **Mailing Lists** - Create and manage group communications

### 🎮 Arcade Gaming

- **10 Built-in Games** - Snake, Tetris, Space Invaders, Floppa Bird, Minesweeper, Sokoban, Pong, Dungeons (Roguelike), Duels (1v1 Combat), and Doom (Raycasting FPS)
- **Leaderboards** - Global high scores synced across the server
- **Multiplayer** - P2P matchmaking for competitive games
- **Community Maps** - Share custom levels for puzzle games

### 🔐 Security

- **HyperAuth Integration** - Secure authentication with external auth servers
- **Encrypted Communications** - SHA1-HMAC signing for sensitive operations
- **Admin Console** - Remote server management for operators

## Architecture

```
Drunken_OS/
├── clients/          # User-facing client applications
├── servers/          # Backend server components
│   ├── modules/      # Modular server components (auth, mail, chat)
├── apps/             # Applets (arcade, bank, mail, etc.)
├── games/            # Arcade games
├── lib/              # Shared libraries
│   ├── db.lua        # Database persistence (atomic writes)
│   ├── theme.lua     # Centralized color themes
│   ├── utils.lua     # UI utilities (wordWrap, etc.)
│   ├── p2p_socket.lua # P2P networking for multiplayer
│   └── sdk.lua       # Developer SDK
├── installer/        # Installation scripts
└── docs/             # Documentation
```

## Installation

### Quick Install (In-Game)

```
pastebin run <installer_code>
```

Select the package type for your computer:
| Option | Package |
|--------|---------|
| 1 | Mainframe Server |
| 2 | User Client |
| 4 | Bank Server |
| 9 | Arcade Server |

### Requirements

- CC:Tweaked mod
- Wired or wireless modems for networking
- Advanced Computer or Pocket Computer (color recommended)

## Documentation

- [Installation Guide](docs/INSTALLATION_GUIDE.md) - Update and setup instructions
- [Architecture](ARCHITECTURE.md) - Design principles and patterns

## Recent Updates (v1.2)

### Architecture Refactor

- **New `lib/db.lua`** - Centralized database persistence with atomic writes and crash recovery
- **Extended `lib/theme.lua`** - Added `theme.game` namespace for consistent game colors
- **Extended `lib/utils.lua`** - Added `safeColor()` and `showLoading()` helpers
- **All games** now use shared theme library for visual consistency
- **All servers** now use shared database functions

### Compatibility

All existing databases, accounts, and save files remain fully compatible.

## Contributing

This is a personal project for a Minecraft modpack server. Feel free to fork and adapt for your own use!

## License

MIT License - See LICENSE file for details.

---

_Created by MuhendizBey with assistance from Gemini_
