# Drunken OS - Architecture Update Installation Guide

## Overview

This update consolidates shared utilities and standardizes theme usage across the entire codebase. **No data migration is required** - all existing databases and accounts remain compatible.

---

## For Existing Server Operators

### Quick Update (Recommended)

If you already have servers running, simply re-run the installer on each server computer to get the new files:

```
pastebin run <installer_code>
```

Select the same package type you originally installed:

- **Mainframe Server** → Option 1
- **Bank Server** → Option 4
- **Arcade Server** → Option 9

The installer will download the new `lib/db.lua` and updated libraries automatically.

---

### Manual Update

If you prefer manual updates, download these new/modified files:

#### Required for ALL Servers:

| File            | Status             |
| --------------- | ------------------ |
| `lib/db.lua`    | **NEW** - Required |
| `lib/theme.lua` | Modified           |
| `lib/utils.lua` | Modified           |

#### Server-Specific Files:

| Server    | File                                |
| --------- | ----------------------------------- |
| Mainframe | `servers/Drunken_OS_Server.lua`     |
| Bank      | `servers/Drunken_OS_BankServer.lua` |
| Arcade    | `servers/Drunken_Arcade_Server.lua` |

---

## For Client Users

Clients will auto-update when connecting to an updated mainframe. No action required.

Games are synced from the Arcade Server - once you update your Arcade Server and run a `sync`, all clients will receive the updated games automatically.

---

## What Changed

### New Shared Library: `lib/db.lua`

- Provides atomic database writes (prevents corruption on server crash)
- Centralized persistence with dirty tracking
- Used by all three servers

### Extended Libraries

- **`lib/theme.lua`** - Now includes `theme.game` namespace with standardized game colors
- **`lib/utils.lua`** - Added `safeColor()` and `showLoading()` helpers

### Updated Components

- All 3 servers now use `lib/db.lua` for persistence
- All 10 games now use `lib/theme.lua` for consistent colors
- `Admin_Console.lua` uses shared `wordWrap` function

---

## Compatibility Notes

| Item                         | Compatible? |
| ---------------------------- | ----------- |
| Existing user accounts       | ✅ Yes      |
| Existing mail/messages       | ✅ Yes      |
| Bank balances & transactions | ✅ Yes      |
| Leaderboard scores           | ✅ Yes      |
| Game save files              | ✅ Yes      |

**All existing data is preserved.** The serialization format is unchanged.

---

## Troubleshooting

### Server won't start after update

Ensure you downloaded `lib/db.lua` - this is a **new required file** for all servers.

### Games show wrong colors

Re-sync games from the Arcade Server. The old local copies may be cached.

### "attempt to index nil" errors

This usually means a library file is missing. Verify these files exist:

- `/lib/db.lua`
- `/lib/theme.lua`
- `/lib/utils.lua`

---

## Version Info

| Component     | New Version |
| ------------- | ----------- |
| Manifest      | 1.2         |
| lib/db.lua    | 1.0 (NEW)   |
| lib/theme.lua | 1.1         |
| lib/utils.lua | 1.1         |
