# 🏴‍☠️ Drunken OS: The Ultimate Minecraft Setup Guide 🚀

Hello, fellow Minecrafter! Welcome to the step-by-step setup guide for **Drunken OS (Enterprise Edition v16.8)**. 

Drunken OS is a complete operating system and network suite for the **ComputerCraft (CC: Tweaked / CC: Restitched)** mod. It adds a central bank, email messaging, global chat, merchant shops, base redstone automation, survival tools, and a full arcade with **14 awesome games** to your Minecraft world!

Setting up servers can sound scary, but don't worry! If you can copy and paste commands, you can set this up in less than 10 minutes. Let's get started! 🌊

---

## 🎒 Part 1: What You Need (Shopping List)

Before you begin, gather these blocks and items from ComputerCraft and vanilla Minecraft:

1. **Advanced Computers (Gold)**: You will need one for each server (Mainframe, Bank, Arcade, and Mail), any base redstone switches, and any desktop terminals you want.
2. **Pocket Computer (Advanced)**: This is your in-game mobile phone! You will run the client on this to walk around your base, access your bank, toggle base doors, or play games.
3. **Disk Drives**: Used to write programs onto floppy disks.
4. **Floppy Disks**: Get a stack of these! They will hold the installers.
5. **Wired Modems & Networking Cables**: To connect all your backend servers together.
6. **Wireless Modems**: Essential for your pocket computers, remote switches, and turtles to communicate over the air.
7. **Advanced Turtles**: If you want to use the automated **Chef**, **Waiter**, or **Bank Sentinel** robots!

---

## 🔌 Part 2: Understanding ComputerCraft Networks

Computers in Minecraft talk to each other using **Rednet** (a network protocol).
* **Wired Network (Cables)**: Best for servers. It connects computers directly so nobody can intercept your bank data.
* **Wireless Network (Wireless Modems)**: Best for Pocket Computers, Remote Switches, and Turtles so they can connect from anywhere nearby.

> [!IMPORTANT]
> **Newbie Rule #1:** A modem attached to a computer does nothing until you **Right-Click it**! Right-clicking turns it on (it will glow red). If you forget this, the computers won't be able to talk to each other!

---

## 🛠️ Step 1: Set Up the "Master Installer" (The Disk Maker)

First, we will build a dedicated "Installer Station" where we can write setup files onto floppy disks.

1. Place down one **Advanced Computer**.
2. Place a **Disk Drive** directly next to it (touching any side).
3. Right-click the computer to open its screen.
4. Run the following command (type it exactly or copy and paste it into Minecraft):
   ```bash
   pastebin run <installer_code>
   ```
   *(Note: replace `<installer_code>` with your installer code or run `installer/Master_Installer.lua`).*
5. The screen will display the **Drunken Master Installer** menu!

---

## 💾 Step 2: Make Your Installation Disks

Now we will write installers for all the servers onto floppy disks.

1. Put a blank **Floppy Disk** into the **Disk Drive**.
2. On your Installer Station computer, use the **UP/DOWN Arrow Keys** to highlight one of these programs, and press **ENTER**:
   * `Drunken OS Server Gateway` (The Mainframe)
   * `Drunken OS Bank Server` (The Bank)
   * `Drunken Arcade Server` (The Arcade/Games Server)
   * `Drunken OS Mail Server` (The Mail/Cloud Storage Server)
   * `Drunken OS Auth Server` (The Secure Login Server)
   * `Remote Switch Node` (Base Redstone Switch)
   * `Drunken OS Client` (Pocket / Desktop Client)
3. The computer will write the package to the disk.
4. Once it says "Success", the disk drive will eject the floppy.
5. **Take the disk out and rename it** in an anvil (e.g. name it "Mainframe Disk" or "Switch Disk") so you don't mix them up!
6. Repeat this process for each disk.

---

## 🖥️ Step 3: Install the Servers

Now we will set up the actual server machines. 

### 1. Set Up the Mainframe Server (The Brain)
1. Place down an **Advanced Computer**.
2. Place a **Disk Drive** next to it.
3. Attach a **Wired Modem** to the back of the computer and a **Wireless Modem** to the top.
4. Right-click both modems to turn them on (they must glow red!).
5. Insert your **Mainframe Disk** into the disk drive.
6. Turn on the computer. It will boot from the disk and automatically copy all the mainframe files onto its local storage.
7. Once finished, eject the disk. The computer will reboot and start the **Mainframe Server Gateway**!

### 2. Set Up the Other Servers (Bank, Mail, Arcade, Auth)
Repeat the exact same steps for your other server computers:
1. Place down a computer.
2. Attach a **Wired Modem** and right-click to turn it on.
3. Put the corresponding floppy disk into an attached disk drive, boot the computer, wait for installation to finish, and eject the disk.

---

## 🕸️ Step 4: Wire Them Up!

Your servers need to be connected to the same local network using **Networking Cables** so they can exchange information securely.

1. Connect a **Networking Cable** to the **Wired Modem** on the back of each server.
2. Link all the cables together.
3. Make sure all modems are turned on (red ring).
4. Now, the Mail Server can securely verify user logins with the Auth Server, and the Bank Server can verify account data!

---

## 📱 Step 5: Install Your Client (Pocket Computer)

Now that the network is running, you can set up your portable pocket phone!

1. Hold an **Advanced Pocket Computer** in your hand and craft it with a **Wireless Modem** in your crafting grid.
2. Place a **Disk Drive** next to your installer station, insert a floppy, select `Drunken OS Client`, and write it to the disk.
3. Insert that disk into a drive touching a desktop computer, or run the installer directly.
4. Once installed, start the client. It will automatically scan the wireless airwaves, find the Mainframe Server, and show the login screen.
5. Select **Register** to create your username and password, then log in!

---

## 🔴 Step 6: Control Base Doors & Machines with Drunken Remote

You can control iron doors, blast doors, drawbridges, and Create mod machines right from your Pocket Computer:

1. Place an **Advanced Computer** next to the redstone wire or door you want to control.
2. Attach a **Wireless Modem** and **right-click it** (red ring glows).
3. Insert your **Switch Disk** and turn on the computer.
4. Follow the setup prompts:
   - Name your switch (e.g. `Main Blast Door`).
   - Pick the side touching your redstone (`front`, `back`, `left`, `right`, `top`, or `bottom`).
   - Choose `toggle` (stays on/off) or `pulse` (activates for 2 seconds).
   - Set access to `public` (anyone can toggle) or `private` (only you).
5. Open the **Remote App** (`apps/remote.lua`) on your Pocket Computer. Your switch will show up automatically! Tap it or press its number to open the door wirelessly!

---

## 🧮 Step 7: Survival Utilities & Diagnostics

Your Pocket Computer comes equipped with handy survival tools:
* **Calculator (`apps/calc.lua`)**: Type arithmetic expressions, calculate 64-item Minecraft stack divisions (e.g. `250 = 3 stacks + 58`), and compute Create mod gear ratios.
* **Notes (`apps/notes.lua`)**: Keep todo lists and waypoints. Tap the **Tag GPS** button to automatically stamp your current satellite coordinates!
* **NetRadar (`apps/radar.lua`)**: See who is nearby! Scans for active players and base computers, shows exact 3D block distances, and pings server latency.
* **Files AirDrop (`apps/files.lua`)**: Beam files directly to a friend's pocket computer over wireless rednet with zero server lag!

---

## 🤖 Step 8: Restaurant Automation & Turtles (Optional)

Drunken OS includes an automated restaurant system where **Chef** and **Waiter** turtles automatically prepare and deliver food.

### 1. Setup the Restaurant Server
Create an installation disk for the `Restaurant Queue Manager` package, and install it on a server computer connected to your wired network.

### 2. Setup the Turtles
1. Place down an **Advanced Turtle** (with a wireless modem).
2. Run the installer disk for `Drunken Bites Chef Turtle` or `Drunken Bites Waiter Turtle` on the turtle.
3. Once installed, edit the config file on the turtle:
   * Run: `edit chef.conf` (or `edit waiter.conf`)
   * Change `server_id` to the **Computer ID** of your Restaurant Server computer.
   * Save the file (Press **Ctrl**, then **Enter**, then **Exit**).
4. Reboot the turtle. It will pair with the Restaurant Server and wait for cooking orders!

---

## ❓ Troubleshooting (If something goes wrong)

* **Error: "No modem attached"**
  * You forgot to attach a modem, or you did not **Right-Click** the modem to turn it on! Modems must glow red to work.
* **Error: "Mainframe not found"**
  * Make sure your Mainframe computer is running and has a **Wireless Modem** attached and turned on. Make sure your Pocket Computer also has a wireless modem!
* **Error: "Bank Server offline"**
  * Check your wired network cables. Make sure all server computers are linked via cables and their wired modems are turned on.
* **"How do I scroll in lists?"**
  * Use the **UP** and **DOWN** arrow keys on your keyboard, and press **ENTER** to select. On Pocket Computers, you can also just tap the screen with your mouse! Press **Q** to go back.

---

Have fun running your Minecraft world with **Drunken OS**! 🌾🍻
