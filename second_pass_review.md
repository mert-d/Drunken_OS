# Drunken OS — Second Pass Review

## 🔴 New Critical Bugs

### 1. `logTransaction` defined twice in BankServer (duplicate + field bug)
**File:** `servers/Drunken_OS_BankServer.lua` lines 117–131 and 165–193

Two separate `logTransaction` functions exist. The first (lines 117–131) writes a simple JSON line to `master.log`. The second (lines 165–193) does HMAC-chained ledger entries. Because Lua silently overwrites, only the **second** survives — but the first is still *called* by some handlers that pass different argument signatures.

Additionally, inside the surviving ledger version at line 174, `prevHash` is set **twice**:
```lua
prevHash = lastLedgerHash,
prevHash = lastLedgerHash,  -- ← plain copy-paste duplicate key
```
This wastes no CPU but signals an unfinished edit and is a lint error.

**Fix:** Remove the first `logTransaction` (lines 117–131) and remove the duplicate `prevHash` key at line 174.

---

### 2. `needsRedraw` is used but never declared in BankServer
**File:** `servers/Drunken_OS_BankServer.lua` lines 646, 715, 863, 938

```lua
needsRedraw = true -- Used in deposit, finalize_withdrawal, transfer, process_payment
```

`needsRedraw` is referenced in multiple handlers but is never declared as a `local`. This implicitly creates a *global variable* in Lua, which is a bug because:
- Other coroutines can't safely read it without a race.
- If any handler crashes before setting it, the render loop never redraws.

The server has `uiDirty = true` already declared at line 35 which does the same thing.

**Fix:** Either replace all `needsRedraw = true` with `uiDirty = true`, or declare `local needsRedraw = false` near the other state variables.

---

### 3. `bankHandlers.process_payment` is defined **twice**
**File:** `servers/Drunken_OS_BankServer.lua` lines 755–807 and lines 873–944

`process_payment` is defined twice. The second version (line 873) validates PIN and enforces `is_merchant` status; the first (line 755) does **neither** of those checks. The second wins silently.

However — `apps/bank.lua` uses the `transfer` handler for the `run()` flow, but the `pay()` flow calls `process_payment`. The first (insecure, no PIN check) definition is clearly a leftover of an earlier iteration and should be removed.

**Fix:** Delete lines 754–807 (the first, weaker `process_payment` definition).

---

### 4. Bank `transfer` handler skips PIN verification
**File:** `servers/Drunken_OS_BankServer.lua` lines 810–870

The `transfer` handler checks the PIN field is not missing (`senderAcc.pin_hash ~= pin_hash` guard) but… the message it receives from `apps/bank.lua` **does** include `pin_hash` in the payload (line 103 of `apps/bank.lua`). However the `transfer` handler at line 829 only checks:
```lua
if not senderAcc or senderAcc.balance < amount then
```
It does **not verify `pin_hash`** at all. Any client that knows another user's username can drain their account by sending a fabricated `transfer` message with any PIN.

**Fix:** Add the pin check before the balance check:
```lua
if not senderAcc or senderAcc.pin_hash ~= message.pin_hash then
    rednet.send(senderId, { success=false, reason="Auth failed." }, BANK_PROTOCOL)
    return
end
```

---

### 5. `arcade.lua` — `parseGameInfo` doesn't nil-check file handle
**File:** `apps/arcade.lua` lines 17–19

```lua
local f = fs.open(path, "r")
local content = f.readAll()  -- Crashes if f == nil
f.close()
```

Same pattern as the `theme.lua` bug that was fixed in the first pass. If the game file exists on the FS list but is unreadable (e.g. FS corruption, permissions), this crashes the entire Arcade app.

**Fix:** `if not f then return nil end` after `fs.open`.

---

### 6. `system.lua` has dead placeholder comments left in (dev artifact)
**File:** `apps/system.lua` lines 14, 16–19

```lua
-- ... (keeping existing functions until updateAll)
function system.changeNickname(context)
    -- ... (unchanged, but I need to be careful with replace_file_content range)
    -- Actually, I shouldn't replace the whole file if I can avoid it.
    -- I'll target the updateAll function specifically.
```

These are **AI agent internal reasoning comments** accidentally committed into production code. They expose implementation details and look unprofessional if a user reads the source.

**Fix:** Remove lines 14–19 comments and replace with a proper LDoc-style comment for `changeNickname`.

---

## 🟡 Medium Bugs & Security Issues

### 7. Cloud storage has no authentication
**File:** `servers/Drunken_OS_Server.lua` — `sync_file`, `download_cloud`, `delete_cloud`, `list_cloud`

All cloud handlers trust `message.user` verbatim. Any user who knows another player's username can read, overwrite, or delete their entire cloud storage. A session token check (like the one now on `is_admin_check`) would close this gap.

**Suggested fix pattern:**
```lua
local function verifySession(message)
    local u = message.user
    return u and users[u] and message.session_token
        and users[u].session_token == message.session_token
end
```
Add this check to all four cloud handlers and update the client to pass `session_token` in cloud requests.

---

### 8. `admin_action` verifies by username only (no session token)
**File:** `servers/Drunken_OS_Server.lua` line ~1508

```lua
if actualMsg.user and admins[actualMsg.user] then
```

A malicious client who knows an admin's username can execute arbitrary admin commands. The fix is to also verify `actualMsg.session_token` against `users[actualMsg.user].session_token`.

---

### 9. `arcade_payout` mints money with no authentication
**File:** `servers/Drunken_OS_BankServer.lua` lines 574–592

```lua
-- Ideally: Check senderId against a known trusted list.
```

The comment admits the problem. Any computer that knows the Bank Server's ID can award arbitrary prize money to any user. The Arcade Server's `senderId` should be stored during the `main()` handshake and verified here.

---

### 10. `city_export` has no authentication
**File:** `servers/Drunken_OS_BankServer.lua` lines 551–571

Same issue as `arcade_payout`. Any client can POST `city_export` and get free credits.

---

### 11. Mail ID collision possible under load
**File:** `servers/modules/mail.lua` line 16

```lua
local id = os.time() .. "-" .. math.random(100, 999)
```

If two mails arrive in the same in-game second (very common in busy mailboxes), the collision probability is 1-in-900. On a clash, `saveTableToFile` overwrites the earlier mail silently.

**Fix:** Use `os.epoch("utc")` (milliseconds) instead of `os.time()`.

---

### 12. Chat broadcast loop-echoes to the sender
**File:** `servers/modules/chat.lua` line 29

```lua
rednet.broadcast({ from = nickname, text = message.text }, "SimpleChat_Internal")
```

The broadcast goes to **everyone** on the network including the sender's own computer. This means the chat client will see their own message twice: once from the optimistic local append (if any) and once from the broadcast echo. Either filter by `senderId` on the client side, or use `rednet.broadcast` with exclusion.

---

### 13. `bank.pay()` reports user by hardcoded admin username
**File:** `apps/bank.lua` line 187

```lua
to = "MuhendizBey",  -- Hardcoded admin username for reports
```

Reports are mailed to a hardcoded developer username. This breaks in any deployment where "MuhendizBey" is not a registered user (the server will silently drop the mail), and exposes the admin account name in shipped code.

**Fix:** Move to a config constant or use the `@admin` list mechanism.

---

### 14. `arcade.lua` — lobby join falls through if lobby ID not found
**File:** `apps/arcade.lua` lines 228–235

```lua
if targetLobby then
    run_shell.run(...)
end
-- No else: silently does nothing if ID not found
```

If the user enters a nonexistent lobby ID, the app silently swallows the input and re-renders. Add a `showMessage` error on `else`.

---

### 15. `bank.getBankSession` — `rates` variable silently nil if login fails mid-path
**File:** `apps/bank.lua` line 47

```lua
return bankServerId, pin_hash, response.balance, response.rates
```

`bank.run()` at line 58 unpacks this as `bankServerId, pin_hash, balance, rates`. If `rates` is nil (e.g. a bank account with no configured currencies), `for name, data in pairs(rates)` at line 83 **crashes** with "attempt to iterate over nil".

**Fix:** Default `rates` to `{}`: `local rates = response.rates or {}`.

---

## 🟢 Code Quality & Minor Items

| # | File | Issue |
|---|---|---|
| 16 | `BankServer.lua` line 804 | `senderAcc.balance = senderAcc.balance` — this is a no-op "Sync?" line in the old `process_payment` that was never removed. |
| 17 | `BankServer.lua` line 52 | `dbPointers` references `ledger` before it is declared (line 138). This works at runtime because `dbPointers` is only *called* later, but is fragile and confusing. Move `local ledger = {}` to before `dbPointers`. |
| 18 | `arcade.lua` line 85 | Creates a new `P2P_Socket` (which opens a modem + does a `rednet.lookup`) for **every game navigation key press** (`fetchSideData` is called on every up/down). This is expensive. Cache the socket per game or debounce navigation. |
| 19 | `mail.lua` line 94 | `table.sort` by `timestamp` may fail if any mail has a `nil` timestamp (from corrupted/old mail files). Add a guard: `(a.timestamp or 0) > (b.timestamp or 0)`. |
| 20 | `system.lua` line 88 | Uses `theme.text` (bare module-level) instead of `context.theme.text`. Inconsistent with surrounding code. |
| 21 | `server` line ~1207 | `load(code, "manifest", "t", {})` uses an empty environment `{}` — the manifest Lua chunk can't call any standard functions. If the manifest ever uses `table`, `string`, etc., it silently returns nil. Pass `_ENV` or a safe subset. |
| 22 | `BankServer.lua` | `queueSave` is defined at line 55, then `persistenceLoop` at line 211 replaces `_G.bankQueueSave` via the tracker but the original `queueSave` local is already closured into all the bank handlers — `_G.bankQueueSave` is never called by anyone. The tracker enhancement is completely disconnected. |

---

## Priority Fix Order

```
🔴 CRITICAL (fix before next deployment)
  1. Remove duplicate logTransaction (BankServer)
  2. Declare needsRedraw properly (BankServer)
  3. Remove duplicate process_payment (BankServer)
  4. Add PIN verification to transfer handler (BankServer)
  5. Nil-check in arcade.parseGameInfo
  6. Remove AI dev comments from system.lua

🟡 MEDIUM (fix in next maintenance window)
  7. Cloud storage session verification
  8. admin_action session verification  
  9+10. Trusted sender check for arcade_payout / city_export
  11. Mail ID → os.epoch collision fix
  12. Chat self-echo (client-side filter)
  13. Hardcoded MuhendizBey admin report target
  14. Arcade lobby not-found error message
  15. bank.run rates nil guard

🟢 MINOR (housekeeping)
  16-22. See table above
```
