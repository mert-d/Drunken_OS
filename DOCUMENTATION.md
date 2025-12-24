# Drunken OS Documentation

Welcome to the official documentation for **Drunken OS**, a modular, Rednet-based operating system designed for ComputerCraft. This repository contains a suite of servers, clients, libraries, and games designed to work together in a secure and networked environment.

## 🏗️ Architecture Overview

Drunken OS follows a distributed architecture where a central **Mainframe** serves as the source of truth for user data, mail, and updates, while **Clients** provide the interface for users to interact with services.

### Core Components

| Component            | Path                            | Description                                                                      |
| :------------------- | :------------------------------ | :------------------------------------------------------------------------------- |
| **Mainframe Server** | `servers/Drunken_OS_Server.lua` | Handles authentication, mail delivery, game high scores, and dynamic updates.    |
| **OS Client**        | `clients/Drunken_OS_Client.lua` | The main user interface. Manages the app lifecycle, networking, and security.    |
| **App Library**      | `lib/drunken_os_apps.lua`       | contains the logic for Mail, Chat, People Tracker, and the Banking Suite.        |
| **Network Proxy**    | `servers/Network_Proxy.lua`     | Bridges different Rednet networks, allowing secure communication across domains. |

---

## 🔐 Security & Authentication

Drunken OS implements a multi-tier security model:

1.  **HyperAuth Integration**: The mainframe communicates with an external HyperAuth server for verifiable 2FA.
2.  **Session Management**: Secure session tokens are generated upon login, allowing users to stay logged in across reboots without re-entering passwords.
3.  **Encrypted Communication**: Sensitive data is protected using standard CC cryptographic practices (HMAC-SHA1).

### User Registration

Users must select a unique username and a display nickname. Registration is secured via the **HyperAuth API** (running on a Command Computer). The system sends a verification token to the user's secondary device (e.g., Discord or HyperAuth client); once the user enters this code into the Drunken OS client, the registration is finalized.

### 🛡️ Integrity Sentinel (Auditor)

Security is further enhanced by the **Bank Sentinel (Auditor Turtle)**. This specialized turtle script:

- Performs real-time integrity audits on the banking ledger.
- Verifies cryptographic hash chains to detect unauthorized database manipulation.
- Replays transaction history to ensure balances are mathematically consistent.
- Triggers visual and network-wide alerts upon detecting a data breach.

---

## 📬 Communication Services

### SimpleMail

A turn-based email system allowing users to send text messages and files to any registered user.

- **Protocol**: `SimpleMail_Internal`
- **Features**: Inbox, Compose, File Attachments.

### SimpleChat

A global real-time chat room for all connected users.

- **Protocol**: `SimpleChat_Internal`

---

## 🎮 Arcade Game Suite

The OS features a variety of games located in the `games/` directory.

### Featured Games:

- **Drunken Dungeons**: A turn-based roguelike with persistent upgrades and co-op support.
- **Drunken Duels**: A 1v1 P2P combat arena for challenging friends.
- **Classic Suite**: Includes Snake, Tetris, Floppa Bird, and Space Invaders.

#### Developing Games:

To add a new game, place the `.lua` file in the `games/` directory on the server. The server will automatically detect and list it for clients.

---

## 🛠️ Developer Guide

### Updating the System

The OS features a built-in **Master Installer** and **Updater**.

- To publish an update: Use the `publish` command on the Mainframe Admin Console.
- Libraries are synced automatically by the `lib/updater.lua` tool.

### Networking Protocols

When building apps for Drunken OS, use the following protocols:

- `SimpleMail`: For mainframe communication.
- `Drunken_Admin`: For remote administrative commands.
- `Dungeon_Coop`: For P2P game synchronization.

---

## 📁 Repository Structure

```text
/
├── apps/               # (Reserved for future standalone applets)
├── clients/            # OS Client and Administrative tools
├── games/              # Game source files
├── installer/          # Setup and deployment scripts
├── lib/                # Core libraries (UI, Crypto, Apps)
├── servers/            # Mainframe, Proxies, and Dedicated servers
└── turtles/            # Specialized turtle scripts (Auditor, etc.)
```

---

_Authored by the Drunken OS Team._
