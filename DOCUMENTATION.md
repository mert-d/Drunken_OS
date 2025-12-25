# Drunken OS Documentation

Welcome to the official documentation for **Drunken OS**, a modular, Rednet-based operating system designed for ComputerCraft. This repository contains a suite of servers, clients, libraries, and games designed to work together in a secure and networked environment.

## 🏗️ Architecture Overview

Drunken OS follows a distributed architecture where a central **Mainframe** serves as the source of truth for user data, mail, and updates, while **Clients** provide the interface for users to interact with services.

### Core Components

| Component            | Path                                | Description                                                                      |
| :------------------- | :---------------------------------- | :------------------------------------------------------------------------------- |
| **Mainframe Server** | `servers/Drunken_OS_Server.lua`     | Handles authentication, mail, global chat, and app distribution.                 |
| **Bank Server**      | `servers/Drunken_OS_BankServer.lua` | Manages currencies, stock markets, and persistent transaction ledgers.           |
| **Arcade Server**    | `servers/Drunken_Arcade_Server.lua` | Specialized server for distributing and updating arcade games.                   |
| **OS Client**        | `clients/Drunken_OS_Client.lua`     | The main user interface. Manages the app lifecycle, networking, and security.    |
| **App Loader**       | `lib/app_loader.lua`                | Environment isolation for modular applets in the `apps/` directory.              |
| **Network Proxy**    | `servers/Network_Proxy.lua`         | Bridges different Rednet networks, allowing secure communication across domains. |

---

## 🔐 Security & Authentication

Drunken OS implements a multi-tier security model:

1.  **HyperAuth Integration**: The mainframe communicates with an external HyperAuth server for verifiable 2FA.
2.  **Session Management**: Secure session tokens are generated upon login, allowing users to stay logged in across reboots without re-entering passwords.
3.  **Encrypted Communication**: Sensitive data is protected using standard CC cryptographic practices (HMAC-SHA1).

### User Registration

Users must select a unique username and a display nickname. Registration is secured via the **HyperAuth API**. The system sends a verification token to the user's secondary device; once the user enters this code into the Drunken OS client, the registration is finalized.

### 🛡️ Integrity Sentinel (Auditor)

The **Bank Sentinel (Auditor Turtle)** ensures the validity of the financial system:

- Performs real-time integrity audits on the banking ledger.
- Verifies cryptographic hash chains to detect unauthorized database manipulation.
- Replays transaction history to ensure balances are mathematically consistent.

---

## 📦 Modular Applet System

Drunken OS v3.0 introduces a modular applet system. Apps are no longer hardcoded into the client but are loaded dynamically from the `apps/` directory.

### Standard Applets:

- **Bank**: Full-featured banking interface for transfers, currency exchange, and stock tracking.
- **Merchant**: Business suite with Cashier and POS modes for P2P commerce.
- **SimpleMail**: Turn-based email system with file attachments.
- **SimpleChat**: Real-time global chat room.
- **Files**: Explorer for local and network-synced files.
- **System**: Tool for checking updates, syncing apps, and managing settings.

---

## 🎮 Arcade Game Suite

The OS features a variety of games located in the `games/` directory, distributed via the **Arcade Server**.

### Featured Games:

- **Drunken Doom**: A pseudo-3D raycasting engine (v1.3) with ASCII rendering, sprites, and save states.
- **Drunken Dungeons**: A turn-based roguelike with persistent upgrades and 2-player co-op support.
- **Drunken Duels**: A 1v1 P2P combat arena for challenging friends.
- **Drunken Pong**: A classic 2-player arcade game.
- **Classic Suite**: Includes Snake, Tetris, Floppa Bird, and Space Invaders.

---

## 🛠️ Developer Guide

### Updating the System

The OS features a built-in **Master Installer** and **Updater**.

- **App Syncing**: Use the `sync apps` command in the System applet or the Client terminal to pull the latest applets from the Mainframe.
- **Game Updates**: The System applet queries the Arcade Server to check for newer versions of installed games.
- **Library Updates**: Libraries are synced automatically by the `lib/updater.lua` tool.

### Networking Protocols

When building apps for Drunken OS, use the following protocols:

- `SimpleMail_Internal`: For mainframe mail communication.
- `SimpleChat_Internal`: For global chat room traffic.
- `DB_Bank_Comm`: For bank-client transaction requests.
- `DB_Shop_Broadcast`: Used by Merchants to announce their shop status.
- `DB_Merchant_Recv`: For receiving payment proofs in Merchant Cashier.
- `Dunken_Admin`: For remote administrative commands.
- `Arcade_Discovery`: Used to locate game servers on the network.

---

## 📁 Repository Structure

```text
/
├── apps/               # Modular applet source files
├── clients/            # OS Client and Administrative tools
├── games/              # Game source files (distributed via Arcade Server)
├── installer/          # Setup and deployment scripts
├── lib/                # Core libraries (UI, Crypto, app_loader)
├── servers/            # Mainframe, Bank, Arcade, and Proxies
└── turtles/            # Specialized turtle scripts (Auditor, etc.)
```

---

_Authored by the Drunken OS Team._
