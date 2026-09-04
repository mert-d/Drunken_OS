# Drunken OS Enterprise Upgrade & Installation Guide (v16.8)

## Overview

This guide provides step-by-step instructions for installing and upgrading **Drunken OS (Enterprise Edition v16.8)**. This release incorporates the Delta-Row buffering engine, offline-first gaming with deferred score syncing, base redstone automation, network radar diagnostics, survival utilities, and 14 arcade games.

**Data Compatibility**: All existing accounts, banking ledgers, mailboxes, and save files remain 100% compatible. No database migration is required.

### System Requirements

- **Minecraft Version:** 1.18.2 or newer
- **ComputerCraft Mod:** CC:Tweaked (1.100.8+) or CC:Restitched
- **Computers:** Advanced Computers (Gold) or Advanced Pocket Computers (Color)
- **Modems:** Wired Modems + Networking Cables for backend servers; Wireless Modems for clients and remote switches.

---

## 🛠️ Master Installer Options

The Drunken OS Master Installer (`installer/Master_Installer.lua`) supports burning pre-configured packages to floppy disks:

| Option | Package Name | Target Machine | Description |
| :---: | :--- | :--- | :--- |
| **1** | **Mainframe Gateway Server** | Advanced Computer | Central coordinator, global chat, and app distribution. |
| **2** | **User Client (Pocket/Desktop)**| Pocket or Desktop PC | Full operating system with all 10 apps and 14 games. |
| **3** | **Remote Switch Node** | Advanced Computer | Headless base redstone controller node. |
| **4** | **Bank Server** | Advanced Computer | Financial ledger, currency accounts, and stock exchange. |
| **5** | **Auth Server** | Advanced Computer | Cryptographic authentication authority. |
| **6** | **Mail & Cloud Server** | Advanced Computer | Email messaging and cloud file storage. |
| **7** | **Mainframe Proxy** | Advanced Computer | Wireless-to-wired bridge for mainframe services. |
| **8** | **Bank Proxy** | Advanced Computer | Wireless-to-wired bridge for bank transactions. |
| **9** | **Arcade Games Server** | Advanced Computer | Arcade catalog distributor and global leaderboards. |
| **10** | **Bank Auditor Turtle** | Advanced Turtle | Real-time cryptographic ledger sentinel. |
| **11** | **Merchant POS Terminal** | Pocket Computer | Mobile retail checkout terminal. |
| **12** | **Bank ATM Kiosk** | Advanced Computer | Public deposit and withdrawal kiosk. |
| **13** | **Chef Turtle** | Advanced Turtle | Automated furnace cooking robot. |
| **14** | **Waiter Turtle** | Advanced Turtle | GPS-guided food delivery robot. |
| **15** | **Vending Turtle** | Advanced Turtle | Chest inventory dispensing robot. |

---

## 🔄 Updating an Existing System

### 1. Update Core Servers

Re-run the installer on each server computer or copy the updated files:

#### Core Shared Libraries (Required on ALL Machines)
Ensure the following files are present in `/lib/`:
- `lib/db.lua` (ACID atomic persistence)
- `lib/theme.lua` (Theme color palettes)
- `lib/utils.lua` (UI primitives & helpers)
- `lib/sdk.lua` (Application framework)
- `lib/p2p_socket.lua` (Peer-to-peer transport)
- `lib/engine.lua` (Delta-row terminal buffering)
- `lib/dns.lua` (Universal DNS resolution cache)
- `lib/crypto_packet.lua` (HMAC-SHA1 & anti-replay defense)
- `lib/transfer.lua` (Chunked streaming file transfer)
- `lib/rpc.lua` (Non-blocking RPC layer)
- `lib/score_cache.lua` (Offline score cache & deferred sync)

#### Server-Specific Files
- **Mainframe**: `servers/Drunken_OS_Server.lua` + `servers/modules/`
- **Bank**: `servers/Drunken_OS_BankServer.lua`
- **Arcade**: `servers/Drunken_Arcade_Server.lua` + `games/` (all 14 titles)
- **Auth**: `servers/Drunken_OS_AuthServer.lua`
- **Mail**: `servers/Drunken_OS_MailServer.lua`
- **Proxies**: `servers/Proxy_Mainframe.lua`, `servers/Proxy_Bank.lua`, `lib/proxy_base.lua`

### 2. Update Client Handhelds & Desktops

On any client computer:
1. Open the **System App** from the desktop (`apps/system.lua`).
2. Select **Check for Updates** or run `sync apps`.
3. The client will pull the latest libraries, utilities (`apps/calc.lua`, `apps/notes.lua`, `apps/remote.lua`, `apps/radar.lua`), and game titles from the Arcade Server.

---

## 🔴 Deploying Base Redstone Switches

To add remote physical control to your base:
1. Place an **Advanced Computer** directly adjacent to the redstone wire, door, blast door, or Create mod clutch/gearshift you want to actuate.
2. Attach a **Wireless Modem** to any side and **right-click it** so it glows red.
3. Install the **Remote Switch Node** package (`clients/remote_switch.lua`).
4. On first boot, complete the interactive wizard:
   - **Switch Name**: e.g., `Main Vault Door` or `Water Pump`.
   - **Redstone Side**: `top`, `bottom`, `left`, `right`, `front`, or `back`.
   - **Mode**: `toggle` (stays ON until clicked again) or `pulse` (activates momentarily).
   - **Pulse Duration**: (if pulse mode) e.g., `2` seconds.
   - **Access**: `public` (anyone can toggle) or `private` (only the owner).
5. Open **Drunken Remote** (`apps/remote.lua`) on your Pocket Computer. The new switch will appear immediately with live status badges!

---

## 🧪 Verification & Testing

Verify that all systems and libraries are intact by running the automated test suite on any computer:

```bash
tests/test_all.lua
```

Expected output:
```text
==================================================
Running Drunken OS Master Test Suite (16 Suites)...
==================================================
  [1/16] test_sha1.......................... PASS
  [2/16] test_utils......................... PASS
  [3/16] test_theme......................... PASS
  [4/16] test_db............................ PASS
  [5/16] test_sdk........................... PASS
  [6/16] test_dns........................... PASS
  [7/16] test_engine........................ PASS
  [8/16] test_crypto_packet................. PASS
  [9/16] test_rpc........................... PASS
 [10/16] test_transfer...................... PASS
 [11/16] test_score_cache................... PASS
 [12/16] test_p2p_socket.................... PASS
 [13/16] test_c4............................ PASS
 [14/16] test_battleship.................... PASS
 [15/16] test_remote........................ PASS
 [16/16] test_radar......................... PASS
==================================================
ALL 16 TEST SUITES PASSED (100%)
==================================================
```

---

## 🆘 Troubleshooting

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| **"No modem attached"** | Modem not installed or not activated | Attach modem and right-click until the red ring lights up. |
| **"Switch not discovered"** | Switch is out of wireless range or modem is off | Check switch computer, verify modem is on, and test with NetRadar (`apps/radar.lua`). |
| **"Access Denied on switch"** | Switch configured as private to another player | Log in as the switch owner or reconfigure `.remote_switch.cfg` to `access = "public"`. |
| **"Arcade Server Offline"** | Server chunk is unloaded or computer crashed | The game is still 100% playable! High scores will be saved locally and synced automatically when the server returns. |
| **Slow screen rendering** | High packet latency in multiplayer | Ensure `lib/engine.lua` is installed; delta-row buffering will optimize network transmission. |
