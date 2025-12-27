# DrunkenOS SDK Developer Guide (v1.0)

Welcome to the DrunkenOS SDK! This toolkit allows you to build powerful, native-feeling applications for the Drunken OS ecosystem without worrying about low-level details.

## Getting Started

To use the SDK in your application, simply require it at the top of your file:

```lua
local SDK = require("lib.sdk")
```

_Note: The SDK is automatically available on all Drunken OS clients v16.1+._

---

## 1. UI Module (`SDK.UI`)

Handle window drawing, popups, and user interaction.

### `SDK.UI.drawWindow(title)`

Clears the screen and draws the standard OS window frame with a title.

- **title** (string): The title to display at the top.

**Example:**

```lua
SDK.UI.drawWindow("My Cool App")
```

### `SDK.UI.showMessage(title, message)`

Displays a blocking modal popup. Use this for alerts or simple info.

- **title** (string): Header text.
- **message** (string): Body text.

**Example:**

```lua
SDK.UI.showMessage("Success", "File saved successfully!")
```

---

## 2. Network Module (`SDK.Net`)

Simplified networking for multiplayer games and client-server communication.

### `SDK.Net.createGameSocket(gameId)`

Creates a standardized P2P socket for multiplayer games.

- **gameId** (string): A unique identifier for your game (e.g., "BattleShips").
- **Returns**: A `P2P_Socket` instance.

**Example:**

```lua
local socket = SDK.Net.createGameSocket("SuperPong")

-- Switch to Host Mode
if socket:hostGame("Player1") then
    print("Hosting...")
    local msg = socket:waitForJoin(30) -- Wait 30s
    if msg then print("Player joined: " .. msg.user) end
end
```

### `SDK.Net.connect()`

Ensures the modem is open and ready.

- **Returns**: `true` if connected/ready.

---

## 3. System Module (`SDK.System`)

Access user session and system utilities.

### `SDK.System.getUsername()`

Returns the username of the currently logged-in user.

- **Returns**: `string` (e.g., "Mert") or "Guest".

**Example:**

```lua
local user = SDK.System.getUsername()
print("Hello, " .. user .. "!")
```
