# 🏴‍☠️ Drunken OS: The Ultimate Minecraft Setup Guide 🚀

Hello, fellow Minecrafter! Welcome to the step-by-step setup guide for **Drunken OS**. 

Drunken OS is a super cool in-game operating system for the **ComputerCraft (CC: Tweaked / CC: Restitched)** mod. It adds a complete bank system, email messaging, global chat, shops, and a full arcade with 10 awesome games to your Minecraft world!

Setting up servers can sound scary, but don't worry! If you can copy and paste commands, you can set this up in less than 10 minutes. Let's get started! 🌊

---

## 🎒 Part 1: What You Need (Shopping List)

Before you begin, gather these blocks and items from ComputerCraft and vanilla Minecraft:

1. **Advanced Computers (Gold)**: You will need one for each server (Mainframe, Bank, Arcade, and Mail) and any desktop terminal you want.
2. **Pocket Computer (Advanced)**: This is your in-game mobile phone! You will run the client on this to walk around your base and access your bank or read emails.
3. **Disk Drives**: Used to write programs onto floppy disks.
4. **Floppy Disks**: Get a stack of these! They will hold the installers.
5. **Wired Modems & Networking Cables**: To connect all your backend servers together.
6. **Wireless Modems**: Essential for your pocket computers and turtles to communicate over the air.
7. **Advanced Turtles**: If you want to use the automated **Chef**, **Waiter**, or **Bank Clerk** robots!

---

## 🔌 Part 2: Understanding ComputerCraft Networks

Computers in Minecraft talk to each other using **Rednet** (a network protocol).
* **Wired Network (Cables)**: Best for servers. It connects computers directly so nobody can intercept your bank data.
* **Wireless Network (Wireless Modems)**: Best for Pocket Computers and Turtles so they can connect from anywhere nearby.

> [!IMPORTANT]
> **Newbie Rule #1:** A modem attached to a computer does nothing until you **Right-Click it**! Right-clicking turns it on (it will glow red). If you forget this, the computers won't be able to talk to each other!

---

## 🛠️ Step 1: Set Up the "Master Installer" (The Disk Maker)

First, we will build a dedicated "Installer Station" where we can write setup files onto floppy disks.

1. Place down one **Advanced Computer**.
2. Place a **Disk Drive** directly next to it (touching any side).
3. Right-click the computer to open its screen.
4. Run the following command (type it exactly or copy and paste it into Minecraft):
   ```
   pastebin run <installer_code>
   ```
   *(Note: replace `<installer_code>` with the pastebin code provided by your server admin or modpack).*
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
3. The computer will download the program from GitHub and write it to the disk.
4. Once it says "Success", the disk drive will eject the floppy.
5. **Take the disk out and rename it** in an anvil (e.g. name it "Mainframe Disk" or "Bank Disk") so you don't mix them up!
6. Repeat this process for all 5 servers.

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

1. Hold an **Advanced Pocket Computer** in your hand, right-click to turn it on, and equip it with a **Wireless Modem** (put it in your crafting grid with a wireless modem).
2. Start the pocket computer.
3. Place a **Disk Drive** next to a computer linked to your installer station, insert a floppy, select `Drunken OS Client` from the installer menu, and write it to the disk.
4. Insert that disk into a drive next to your pocket computer, boot it, and let it install!
5. Once installed, start the client. It will automatically scan the wireless airwaves, find the Mainframe Server, and show the login screen.
6. Select **Register** to create your username and password, then log in!

---

## 🤖 Step 6: Restaurant Automation & Turtles (Optional)

Drunken OS includes a complete restaurant system where **Chef** and **Waiter** turtles automatically prepare and deliver food.

### 1. Setup the Restaurant Server
Create an installation disk for the `Restaurant Queue Manager` package, and install it on a server computer connected to your wired network.

### 2. Setup the Turtles
1. Place down an **Advanced Turtle** (with a wireless modem).
2. Run the installer disk for `Drunken Bites Chef Turtle` or `Drunken Bites Waiter Turtle` on the turtle.
3. Once installed, edit the config file on the turtle:
   * Run: `edit chef.conf` (or `edit waiter.conf`)
   * Change `server_id` to the **Computer ID** of your Restaurant Server computer.
   * Save the file (Press **Ctrl**, then **Enter**, then **Exit**).
4. Reboot the turtle. It will pair with the Restaurant Server and wait for commands!

---

## ❓ Troubleshooting (If something goes wrong)

* **Error: "No modem attached"**
  * You forgot to attach a modem, or you did not **Right-Click** the modem to turn it on! Modems must glow red to work.
* **Error: "Mainframe not found"**
  * Make sure your Mainframe computer is running and has a **Wireless Modem** attached and turned on. Make sure your Pocket Computer also has a wireless modem!
* **Error: "Bank Server offline"**
  * Check your wired network cables. Make sure all server computers are linked via cables and their wired modems are turned on.
* **"How do I scroll in lists?"**
  * Use the **UP** and **DOWN** arrow keys on your keyboard, and press **ENTER** to select. Press **Q** or **TAB** to go back.

---

Have fun running your Minecraft town with **Drunken OS**! 🌾🍻
