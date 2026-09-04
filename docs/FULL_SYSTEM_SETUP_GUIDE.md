# 🏴‍☠️ Drunken OS: Full System Installation & Setup Guide 🚀

This is the definitive, step-by-step setup and deployment guide for the complete **Drunken OS (Enterprise Edition v16.8)** ecosystem in Minecraft using the **ComputerCraft** mod (**CC: Tweaked** or **CC: Restitched**).

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

> [!TIP]
> **Single-Computer / Base Setup**: If you are playing single-player or in a small base and do not require strict wired network isolation, you can attach both wired and wireless modems directly to the Mainframe, Bank, and Arcade servers without running separate proxy computers.

---

## 🎒 Hardware Bill of Materials

Gather the following items from ComputerCraft and Minecraft:

### Core Server Infrastructure (5 Servers + 2 Proxies)
1. **7× Advanced Computers (Gold)**:
   - 1× Mainframe Server (`servers/Drunken_OS_Server.lua`)
   - 1× Auth Server (`servers/Drunken_OS_AuthServer.lua`)
   - 1× Mail & Cloud Server (`servers/Drunken_OS_MailServer.lua`)
   - 1× Bank Server (`servers/Drunken_OS_BankServer.lua`)
   - 1× Arcade Server (`servers/Drunken_Arcade_Server.lua`)
   - 1× Mainframe Proxy (`servers/Proxy_Mainframe.lua`)
   - 1× Bank Proxy (`servers/Proxy_Bank.lua`)
2. **7× Wired Modems** + **1× Stack Networking Cables** (for backend interlink).
3. **3× Wireless Modems (Ender or Normal)**:
   - 1× on Mainframe Proxy
   - 1× on Bank Proxy
   - 1× on Arcade Server (or Mainframe directly in single-tier setups)
4. **1× Advanced Turtle** (for Bank Auditor Sentinel).

### Client & Field Hardware
- **Advanced Pocket Computers** (Equipped with Wireless Modem in crafting grid).
- **Advanced Computers** (for Base Redstone Switch nodes, ATM kiosks, and Desktop terminals).
- **Wireless Modems** (for each base switch and terminal).

### Installation Station
- **1× Advanced Computer** + **1× Disk Drive** + **Stack of Floppy Disks**.

---

## 🛠️ Step 1: Create the Installation Media

Set up an installer station to write software packages to floppy disks:

1. Place an **Advanced Computer** with a **Disk Drive** touching it.
2. Turn on the computer and launch the Master Installer:
   ```bash
   pastebin run <installer_code>
   ```
   *(Or if offline/local, type: `installer/Master_Installer.lua`)*
3. Insert a blank floppy disk into the drive.
4. Select the desired package from the menu and press **Enter** to burn:
   - `Drunken OS Auth Server`
   - `Drunken OS Mail Server`
   - `Drunken OS Server Gateway` (Mainframe)
   - `Drunken OS Bank Server`
   - `Drunken Arcade Server`
   - `Mainframe Proxy`
   - `Bank Proxy`
   - `Auditor Turtle`
   - `Remote Switch Node`
   - `Drunken OS Client`
5. Eject and label each disk in an anvil (e.g., "Auth Disk", "Bank Disk", "Client Disk", "Switch Disk").

---

## 🔌 Step 2: Wire the Backend Interlink

1. Place the 5 core servers (`Auth`, `Mail`, `Mainframe`, `Bank`, `Arcade`) in your server room.
2. Attach a **Wired Modem** to the back of each computer.
3. Attach **Wired Modems** to the back of your two Proxy computers (`Proxy Mainframe`, `Proxy Bank`).
4. Connect all wired modems together using **Networking Cables**.
5. **CRITICAL STEP**: **Right-click every single wired modem** so that the red ring lights up. An unlit modem is offline!

---

## 🖥️ Step 3: Install & Start the Core Servers

Install and boot the servers in this recommended order:

### 1. Auth Server
1. Insert the **Auth Disk** into a disk drive next to the Auth computer.
2. Boot the computer; it will install the package and reboot into `servers/Drunken_OS_AuthServer.lua`.
3. Displays: `Drunken Auth Server Active on auth.secure.v1 / Drunken_Auth_Interlink`.

### 2. Mail & Cloud Server
1. Insert the **Mail Disk** into the Mail computer and boot.
2. It initializes folder databases (`mail_data/`, `cloud_data/`).
3. Displays: `Listening on Drunken_Auth_Interlink`.

### 3. Mainframe Server
1. Insert the **Mainframe Disk** into the Mainframe computer and boot.
2. Automatically loads `servers/modules/chat.lua`, `servers/modules/auth.lua`, and `lib/db.lua`.
3. Displays: `Mainframe Server Gateway Online`.

### 4. Bank Server
1. Insert the **Bank Disk** into the Bank computer and boot.
2. Sets up currency ledger, transaction history, and stock exchange.
3. Displays: `Drunken Beard Bank Server Online on DB_Bank / DB_Bank_Internal`.

### 5. Arcade Server
1. Insert the **Arcade Disk** into the Arcade computer and boot.
2. Attach a **Wireless Modem** to the top (or wire through a proxy) and right-click it on.
3. Automatically scans and registers all 14 games in `games/` (`Connect 4`, `Battleship`, `Doom`, `Duels`, `Floppa Bird`, `Snake`, `Tetris`, etc.).
4. Type `s` or `sync` in the console to index all games.

---

## 🌉 Step 4: Configure the Proxy Layer

The proxies route client wireless packets to the secured internal wired cables:

1. **Proxy Mainframe**:
   - Has a **Wired Modem** (connected to the server cable network).
   - Has a **Wireless Modem** (facing outwards to the players).
   - Boots `servers/Proxy_Mainframe.lua`.
   - Routes `SimpleMail`, `SimpleChat`, and `auth.secure.v1` seamlessly between wireless clients and wired servers.
2. **Proxy Bank**:
   - Has a **Wired Modem** (connected to server cables).
   - Has a **Wireless Modem** (facing outwards).
   - Boots `servers/Proxy_Bank.lua`.
   - Routes `DB_Bank` to `DB_Bank_Internal`.

---

## 🛡️ Step 5: Launch the Bank Auditor Sentinel

1. Place an **Advanced Turtle** in your bank vault or server room.
2. Attach a **Wired Modem** connected to the server network cable.
3. Insert the **Auditor Disk** and boot the turtle.
4. The auditor will monitor the bank ledger in real time, calculating SHA-1 hash chains to guarantee mathematical integrity.

---

## 🔴 Step 6: Deploy Base Redstone Switches

Automate blast doors, water pumps, lighting, drawbridges, and Create mod machinery:

1. Place an **Advanced Computer** adjacent to your target redstone wire or machine.
2. Attach a **Wireless Modem** to any side and **right-click it** (red ring glows).
3. Insert the **Switch Disk** and boot the computer.
4. Complete the 4-step wizard on first boot:
   - **Switch Name**: e.g. `Main Blast Door` or `Iron Factory Power`.
   - **Redstone Side**: Side touching the redstone (`top`, `bottom`, `left`, `right`, `front`, `back`).
   - **Mode**: `toggle` (stays on/off) or `pulse` (momentary activation).
   - **Pulse Duration**: (if pulse) e.g., `2` seconds.
   - **Access**: `public` (anyone in base can toggle) or `private` (locked to your user).
5. The switch will start listening on `"DrunkenRemote"` with a live ASCII status monitor.

---

## 📱 Step 7: Client Setup & First User Login

Now that the backend and base switches are operational, set up player clients:

1. Craft an **Advanced Pocket Computer** and combine it with a **Wireless Modem** in a crafting table.
2. Install the `Drunken OS Client` package from your floppy disk.
3. Turn on the pocket computer:
   - It will discover the Mainframe on wireless rednet.
   - Choose **Register** to create a user account.
   - Choose your username, password, and nickname.
   - Once registered, select **Login**.
4. You are now inside **Drunken OS Desktop**:
   - 📬 **Mail**: Send messages and attachments.
   - 💬 **Chat**: Global chat room.
   - 🏦 **Bank**: View accounts, transfer funds, check stocks.
   - 🎮 **Arcade**: Browse high scores and play all 14 games!
   - 📁 **Files**: Manage local files with **AirDrop** wireless P2P file beam.
   - 🧮 **Calc**: Arithmetic, 64-item stack division, Create mod gear ratio math.
   - 📝 **Notes**: Scratchpad with 1-tap satellite GPS coordinate tagging.
   - 🔴 **Remote**: Toggle base doors and contraptions from anywhere in range.
   - 📡 **Radar**: Scan nearby devices by 3D distance and ping server latency.
   - ⚙️ **Settings**: Switch themes (`Default`, `Matrix`, `Red Alert`, `Midnight`).

---

## ⚡ Pro-Tip: 24/7 Server Hosting with World Spawn Chunks

In survival Minecraft (including modpacks like **Create Astral**), computers and turtles freeze when the chunk they reside in is unloaded by the game engine.

### How to Keep Your Mainframe Online 24/7 (Zero Mods Needed)
In Minecraft, the chunks located around **World Spawn** (where compasses point by default) are **permanently kept in server memory 24/7 by the game engine**, even when no players are nearby.

1. **Find World Spawn**:
   - Hold a standard Minecraft compass or check your F3 screen around initial world spawn coordinates (often around `X: 0, Z: 0` or the spawn point).
2. **Build Server Room at World Spawn**:
   - Place your **Mainframe Gateway, Bank Server, Mail Server, and Arcade Server** inside this World Spawn chunk area.
   - **Result**: Your servers will never sleep or unload! All 20+ players across the entire server can access Bank, Mail, and Arcade services from anywhere in the world at all times without needing chunk-loader blocks or mods.

---

## 📋 Comprehensive In-Game Verification Checklist

Follow this checklist to test every component of the Drunken OS ecosystem in your Minecraft world:

### Phase A: Core Infrastructure & Networking
- [ ] **Modem Audit**: Verify every wired and wireless modem has been right-clicked and glows red.
- [ ] **Wired Cable Continuity**: Verify networking cables cleanly bridge all 5 servers and proxies.
- [ ] **Automated Test Suite**: Run `tests/test_all.lua` on any computer. Confirm **16/16 test suites pass (100%)**.

### Phase B: Auth, Mail & Banking
- [ ] **User Registration**: Register a new user (`UserA`) on a Pocket Computer. Verify successful login.
- [ ] **Session Persistence**: Reboot the Pocket Computer. Verify it logs in automatically using the saved session token without prompting for a password.
- [ ] **Mail Test**: Compose a mail message from `UserA` to `UserB` with a small text file attached. Log in as `UserB` and verify receipt.
- [ ] **Bank Deposit & Transfer**:
  - Check account balance in `apps/bank.lua`.
  - Transfer $100 from `UserA` to `UserB`. Verify both ledger balances update immediately.
  - Check Bank Auditor Turtle console; verify hash chain validation reported `INTEGRITY OK`.

### Phase C: Arcade & Universal Offline Mode
- [ ] **Game Catalog Sync**: Open `apps/arcade.lua`. Verify all 14 titles are listed.
- [ ] **Single Player Gaming**: Launch `Connect 4` or `Battleship`. Verify smooth rendering and smart AI responses.
- [ ] **Offline Gaming**: Move away from base until servers are out of wireless range (or temporarily turn off the Arcade Server). Launch `apps/arcade.lua`. Verify it warns `[OFFLINE]` but launches games immediately without freezing.
- [ ] **Deferred Score Sync**: Play a game offline and achieve a new high score. Reconnect to the server wireless range. Verify the score is synchronized to the Arcade leaderboard.

### Phase D: Peer-to-Peer (P2P) Wireless Multiplayer
- [ ] **P2P Connect 4**: On two Pocket Computers, launch `Connect 4`, select **Multiplayer P2P**, have Player 1 Host and Player 2 Join. Play 3 turns and verify real-time wireless board syncing.
- [ ] **P2P Battleship**: On two Pocket Computers, launch `Battleship`, select **Multiplayer P2P**, place ships, and fire shots. Verify radar and hit indicators sync between players.
- [ ] **AirDrop File Beam**: In `apps/files.lua`, select a document, choose **AirDrop**, and beam it to a nearby player's computer. Verify successful receipt without server involvement.

### Phase E: Base Redstone Automation (`remote_switch` + `apps/remote.lua`)
- [ ] **Switch Deployment**: Place an Advanced Computer next to an iron door or redstone lamp. Run `clients/remote_switch.lua`. Configure as `Main Door`, side `back`, mode `toggle`.
- [ ] **Pocket Remote Discovery**: Open `apps/remote.lua` on a Pocket Computer. Confirm `Main Door` appears in the list with `[ INACTIVE ]`.
- [ ] **Remote Toggle**: Tap the door switch in `apps/remote.lua`. Verify the switch status flips to `[ ACTIVE ]` in green and the Minecraft iron door opens physically. Tap again to close.
- [ ] **Pulse Mode Test**: Set up a second switch in `pulse` mode with a `2` second duration. Trigger it from the remote; verify the redstone pulses on for 2 seconds and automatically turns off.
- [ ] **Private Switch Security**: Configure a switch as `access = "private"` under `UserA`. Attempt to toggle from `UserB`'s pocket computer. Verify toggle is rejected with `Access Denied`.

### Phase F: Network Radar Diagnostics (`apps/radar.lua`)
- [ ] **Nearby Devices Scan**: Open `apps/radar.lua` on a Pocket Computer. Switch to the **Nearby Devices** tab. Confirm nearby player pocket computers and base computers are detected with accurate 3D block distances.
- [ ] **Proximity Sorting**: Walk away from a base computer. Refresh the scan; verify the distance increases and sorting reflects proximity.
- [ ] **Server Latency Ping**: Switch to the **Server Health** tab. Confirm round-trip latency pings (`ms`) return for `DB_Bank`, `ArcadeGames`, and `MailServer`.

### Phase G: Survival Utilities (`apps/calc.lua` & `apps/notes.lua`)
- [ ] **Stack Division**: In `apps/calc.lua`, test stack division: enter `300` -> verify output displays `4 stacks (64) + 44 items`.
- [ ] **Create Mod Ratio**: In `apps/calc.lua`, calculate gear ratio: enter driving `32` RPM with small cog (16) into large cog (32) -> verify calculated output `16` RPM.
- [ ] **GPS Notes**: In `apps/notes.lua`, create a note titled `Diamond Mine`, tap **Tag GPS** button. Verify satellite coordinates are fetched and inserted into the note.

---

## 🆘 Troubleshooting & Support

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| **"No modem attached"** | Modem not installed or not activated | Ensure modem is attached and **right-clicked** until it glows red. |
| **"Mainframe not found"** | Mainframe or Proxy is offline or out of wireless range | Check if Proxy Mainframe is running with an active wireless modem. |
| **"Bank offline"** | Wired cable disconnected or Proxy Bank not running | Verify wired modems on cables are lit red and Proxy Bank is running. |
| **"Invalid Credentials"** | User not registered in Auth Server | Ensure Auth Server is running and register a new user first. |
| **"Switch Offline" in Remote** | Switch computer is unloaded or modem unlit | Ensure switch chunk is loaded and wireless modem is glowing red. |
| **Corrupted Database** | Sudden Minecraft server crash | `lib/db.lua` automatically restores from `.tmp` swap files on next boot. |

---

_Authored by the Drunken OS Engineering Team._
