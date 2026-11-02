#!/usr/bin/env python3
"""
Drunken OS <-> Poco Minecraft Server Bridge (AGY Autonomous Bridge)
Enables the Drunken OS Antigravity Agent to:
  1. Instantly deploy avionics/flight code to Computer 15 on Android Poco F7.
  2. Perform autonomous flight tests with real-time safety tripwires and telemetry logging.
  3. Freeze, unfreeze, rescue (dock reset), and monitor live physics.
"""

import argparse
import math
import os
import re
import socket
import struct
import subprocess
import sys
import time

RCON_HOST = "127.0.0.1"
RCON_PORT = 25575
RCON_PASS = "b51c1aa39c5a53a6af4f2705"

SHIP_UUID = "2941f7ec-b533-4c93-8faa-04a6cc69a8db"
DOCK_POS = (1116.7, 184.64, -242.8)
DOCK_ROT = (180.0, 0.0)  # Yaw=180 (North), Pitch=0

PHONE_CC_DIR = "/data/data/com.termux/files/home/poco-mc-server/servers/32d8ad19/world/computercraft/computer/15"
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))


def rcon_command(cmd: str, timeout: float = 5.0) -> str:
    """Send an RCON command to the Minecraft server."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((RCON_HOST, RCON_PORT))
        
        # Auth
        req_id = 1
        pkt = struct.pack("<iii", len(RCON_PASS) + 10, req_id, 3) + RCON_PASS.encode("utf-8") + b"\x00\x00"
        s.sendall(pkt)
        s.recv(4096)
        
        # Command
        req_id = 2
        pkt = struct.pack("<iii", len(cmd) + 10, req_id, 2) + cmd.encode("utf-8") + b"\x00\x00"
        s.sendall(pkt)
        
        out = b""
        while True:
            try:
                part = s.recv(4096)
                if not part:
                    break
                out += part
                length = struct.unpack("<i", out[:4])[0]
                if len(out) >= length + 4:
                    break
            except socket.timeout:
                break
        s.close()
        return out[12:-2].decode("utf-8", errors="replace") if len(out) > 12 else ""
    except Exception as e:
        return f"[RCON ERROR] {e}"


def get_ship_telemetry():
    """Query Shtreimel info and parse ship telemetry."""
    raw = rcon_command(f"shtreimel info {SHIP_UUID}")
    data = {
        "raw": raw,
        "valid": False,
        "pos": (0.0, 0.0, 0.0),
        "vel": (0.0, 0.0, 0.0),
        "euler": (0.0, 0.0, 0.0),  # yaw, pitch, roll
        "frozen": True,
        "mass": 0.0,
    }
    if not raw or "Sub-level" not in raw:
        return data

    pos_m = re.search(r"pos=\(([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)\)", raw)
    orient_m = re.search(r"orient=\(x=([-\d.]+),\s*y=([-\d.]+),\s*z=([-\d.]+),\s*w=([-\d.]+)\)", raw)
    frozen_m = re.search(r"frozen=(\w+)", raw)
    mass_m = re.search(r"mass=([-\d.]+)", raw)
    vel_m = re.search(r"lin=([-\d.]+)\s*m/s", raw)

    if pos_m:
        data["pos"] = tuple(map(float, pos_m.groups()))
        data["valid"] = True
    if mass_m:
        data["mass"] = float(mass_m.group(1))
    if frozen_m:
        data["frozen"] = (frozen_m.group(1).lower() == "true")
    if vel_m:
        data["lin_vel"] = float(vel_m.group(1))

    if orient_m:
        qx, qy, qz, qw = map(float, orient_m.groups())
        sinr_cosp = 2 * (qw * qx + qy * qz)
        cosr_cosp = 1 - 2 * (qx * qx + qy * qy)
        roll = math.degrees(math.atan2(sinr_cosp, cosr_cosp))

        sinp = 2 * (qw * qy - qz * qx)
        pitch = math.degrees(math.asin(max(-1.0, min(1.0, sinp))))

        siny_cosp = 2 * (qw * qz + qx * qy)
        cosy_cosp = 1 - 2 * (qy * qy + qz * qz)
        yaw = math.degrees(math.atan2(siny_cosp, cosy_cosp))
        data["euler"] = (yaw, pitch, roll)

    return data


def cmd_status(args):
    """Print comprehensive server, ship, and player status."""
    print("==========================================================")
    print("  🛰️  DRUNKEN OS <-> POCO MINECRAFT SERVER STATUS")
    print("==========================================================")
    
    # 1. Players
    players = rcon_command("list")
    print(f"[Players] {players.strip()}")

    # 2. Ship Telemetry
    tel = get_ship_telemetry()
    if tel["valid"]:
        x, y, z = tel["pos"]
        yaw, pitch, roll = tel["euler"]
        status_tag = "❄️ FROZEN" if tel["frozen"] else "🚀 AIRBORNE / ACTIVE"
        print(f"[Ship Status]  Skyfire ({SHIP_UUID}) -> {status_tag}")
        print(f"[Position]     X: {x:.2f}, Y: {y:.2f}, Z: {z:.2f}")
        print(f"[Attitude]     Yaw: {yaw:.2f}°, Pitch: {pitch:.2f}°, Roll: {roll:.2f}°")
        print(f"[Physics]      Mass: {tel['mass']:.1f} kg, Speed: {tel.get('lin_vel', 0.0):.2f} m/s")
    else:
        print("[Ship Status]  Could not retrieve ship telemetry from Shtreimel!")

    # 3. ComputerCraft Status
    cc_status = rcon_command("computercraft dump 15")
    if "is not" not in cc_status.lower():
        print(f"[Avionics CC]  Computer #15 is ACTIVE")
    else:
        print(f"[Avionics CC]  Computer #15 status: {cc_status.strip()}")
    print("==========================================================")


def cmd_freeze(args):
    """Freeze nearest ship immediately."""
    res = rcon_command(f"shtreimel freeze {SHIP_UUID}")
    print(f"❄️ Freeze Result: {res.strip()}")


def cmd_unfreeze(args):
    """Unfreeze Skyfire."""
    res = rcon_command(f"shtreimel unfreeze {SHIP_UUID}")
    print(f"🔥 Unfreeze Result: {res.strip()}")


def cmd_rescue(args):
    """Safely reset ship to dock and players to deck."""
    print("⚓ Rescuing ship to dock...")
    # Step 1: Unfreeze
    rcon_command(f"shtreimel unfreeze {SHIP_UUID}")
    time.sleep(0.2)
    # Step 2: Sable teleport
    dx, dy, dz = DOCK_POS
    yaw, pitch = DOCK_ROT
    tp_res = rcon_command(f"sable teleport {SHIP_UUID} {dx} {dy} {dz} {yaw} {pitch}")
    time.sleep(0.5)
    # Step 3: Freeze
    rcon_command(f"shtreimel freeze {SHIP_UUID}")
    # Step 4: Teleport players
    rcon_command(f"tp @a[distance=..500] {dx} {dy + 10.0} {dz}")
    print(f"⚓ Rescue complete! Teleport output: {tp_res.strip()}")


def cmd_push(args):
    """Package avionics, apps, and lib directories and push to Android Computer 15."""
    print("📦 Packaging Drunken OS avionics files...")
    tar_path = "/tmp/drunken_avionics_sync.tar.gz"
    
    # Files/folders to sync
    sync_targets = []
    for item in ["apps", "lib", "clients", "blackbox.lua"]:
        if os.path.exists(os.path.join(PROJECT_DIR, item)):
            sync_targets.append(item)
            
    if not sync_targets:
        print("❌ Error: No sync targets found in Drunken_OS directory!")
        return

    tar_cmd = ["tar", "-czf", tar_path, "-C", PROJECT_DIR] + sync_targets
    subprocess.run(tar_cmd, check=True)

    print("📲 Pushing to Android device (ADB)...")
    push_cmd = ["adb", "push", tar_path, "/data/local/tmp/drunken_avionics_sync.tar.gz"]
    subprocess.run(push_cmd, check=True, stdout=subprocess.DEVNULL)

    print("📂 Extracting into Computer #15 and #8...")
    extract_sh = f"run-as com.termux tar -xzf /data/local/tmp/drunken_avionics_sync.tar.gz -C {PHONE_CC_DIR}/"
    subprocess.run(["adb", "shell", extract_sh], check=True)
    cockpit_dir = PHONE_CC_DIR.replace("/15", "/8")
    subprocess.run(["adb", "shell", f"run-as com.termux tar -xzf /data/local/tmp/drunken_avionics_sync.tar.gz -C {cockpit_dir}/"], check=False)

    if not args.no_reboot:
        print("🔄 Rebooting ComputerCraft #15 Avionics Core Daemon...")
        rcon_command("computercraft shutdown 15")
        rcon_command("computercraft shutdown 8")
        time.sleep(0.5)
        rcon_command("computercraft turn-on 15")
        rcon_command("computercraft turn-on 8")
        print("✅ Computer #15 & #8 rebooted with latest code!")
    else:
        print("✅ Files deployed (reboot skipped).")


def cmd_logs(args):
    """Fetch recent lines of flight_log.csv or flight_log.txt."""
    lines = args.lines
    log_file = "flight_log.csv" if not args.txt else "flight_log.txt"
    cmd = f"run-as com.termux tail -n {lines} {PHONE_CC_DIR}/{log_file}"
    res = subprocess.run(["adb", "exec-out", cmd], capture_output=True, text=True)
    if res.stdout:
        print(f"=== Computer #15 {log_file} (Last {lines} lines) ===")
        print(res.stdout)
    else:
        print(f"⚠️ Could not read {log_file} (or file is empty).")


def cmd_rcon(args):
    """Execute raw RCON command."""
    cmd = " ".join(args.command)
    res = rcon_command(cmd)
    print(res.strip())


def cmd_test(args):
    """
    Autonomous Flight Test Runner:
      1. Verifies dock position.
      2. Unfreezes ship.
      3. Samples telemetry at 5 Hz for duration.
      4. Emergency tripwire: if Y < 120 or |Pitch| > 50, aborts and rescues immediately.
      5. Freezes ship at test end.
      6. Outputs flight telemetry analysis.
    """
    duration = args.seconds
    print("==========================================================")
    print(f"  🛫 STARTING AUTONOMOUS FLIGHT TRIAL ({duration}s Test)")
    print("==========================================================")
    
    init_tel = get_ship_telemetry()
    if not init_tel["valid"]:
        print("❌ Cannot start test: unable to contact ship physics!")
        return

    init_y = init_tel["pos"][1]
    print(f"Initial State: Y = {init_y:.2f} m, Pitch = {init_tel['euler'][1]:.2f}°")

    print(f"🚁 Engaging Computer #15 HOVER Autopilot Mode...")
    subprocess.run(["adb", "shell", f"run-as com.termux sh -c 'echo HOVER > {PHONE_CC_DIR}/fcc_cmd.txt'"], check=False)
    time.sleep(0.5)

    print(f"🔥 Unfreezing Skyfire... Monitoring for {duration} seconds...")
    rcon_command(f"shtreimel unfreeze {SHIP_UUID}")

    start_time = time.time()
    telemetry_samples = []
    aborted = False
    abort_reason = ""

    try:
        while time.time() - start_time < duration:
            t_rel = time.time() - start_time
            tel = get_ship_telemetry()
            if tel["valid"]:
                x, y, z = tel["pos"]
                yaw, pitch, roll = tel["euler"]
                v_lin = tel.get("lin_vel", 0.0)
                telemetry_samples.append((t_rel, y, pitch, roll, v_lin))
                
                # Real-time console update
                sys.stdout.write(f"\r  [T+{t_rel:4.1f}s] Alt: {y:6.2f}m | Pitch: {pitch:+5.1f}° | Roll: {roll:+5.1f}° | Speed: {v_lin:4.2f}m/s")
                sys.stdout.flush()

                # Safety Tripwires
                if y < 120.0:
                    aborted = True
                    abort_reason = f"Critical plunge below safety floor (Y={y:.2f} < 120m)"
                    break
                if abs(pitch) > 55.0:
                    aborted = True
                    abort_reason = f"Extreme pitch runaway (Pitch={pitch:.1f}° > 55°)"
                    break

            time.sleep(0.2)
    except KeyboardInterrupt:
        aborted = True
        abort_reason = "Manual user abort (Ctrl+C)"

    print()
    # Freeze immediately!
    print("❄️ Freezing ship...")
    rcon_command(f"shtreimel freeze {SHIP_UUID}")
    subprocess.run(["adb", "shell", f"run-as com.termux sh -c 'echo DISARM > {PHONE_CC_DIR}/fcc_cmd.txt'"], check=False)

    if aborted:
        print(f"\n🚨 TEST ABORTED BY TRIPWIRE: {abort_reason}")
        print("⚓ Auto-rescuing to dock...")
        cmd_rescue(None)
    else:
        print("\n✅ Test completed normally.")

    # Calculate statistics
    if telemetry_samples:
        times, alts, pitches, rolls, speeds = zip(*telemetry_samples)
        delta_y = alts[-1] - init_y
        avg_pitch = sum(pitches) / len(pitches)
        max_pitch = max(abs(p) for p in pitches)
        avg_roll = sum(rolls) / len(rolls)
        max_roll = max(abs(r) for r in rolls)

        print("----------------------------------------------------------")
        print("  📊 FLIGHT TEST SUMMARY RESULTS")
        print("----------------------------------------------------------")
        print(f"  Duration:         {times[-1]:.1f} s ({len(telemetry_samples)} samples)")
        print(f"  Altitude Drift:   {delta_y:+.2f} m (Start: {init_y:.2f}m -> End: {alts[-1]:.2f}m)")
        print(f"  Pitch Stability:  Avg: {avg_pitch:+.2f}°, Max Abs: {max_pitch:.2f}°")
        print(f"  Roll Stability:   Avg: {avg_roll:+.2f}°, Max Abs: {max_roll:.2f}°")
        
        status_eval = "STABLE HOVER 🎯" if max_pitch < 5.0 and abs(delta_y) < 2.0 else "UNSTABLE ⚠️"
        print(f"  Overall Rating:   {status_eval}")
        print("----------------------------------------------------------")

        # Save to flight_trials.md
        trial_log_path = os.path.join(PROJECT_DIR, "flight_trials.md")
        with open(trial_log_path, "a") as f:
            f.write(f"\n### Flight Trial ({time.strftime('%Y-%m-%d %H:%M:%S')})\n")
            f.write(f"- **Result:** {status_eval}\n")
            f.write(f"- **Duration:** {times[-1]:.1f}s | **Altitude Drift:** {delta_y:+.2f}m\n")
            f.write(f"- **Pitch:** Avg {avg_pitch:+.2f}°, Max {max_pitch:.2f}°\n")
            f.write(f"- **Roll:** Avg {avg_roll:+.2f}°, Max {max_roll:.2f}°\n")
            if aborted:
                f.write(f"- **Abort Reason:** {abort_reason}\n")
        print(f"Saved trial results to {trial_log_path}")


def main():
    parser = argparse.ArgumentParser(description="Drunken OS <-> Poco Minecraft Server Bridge")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # status
    p_status = subparsers.add_parser("status", help="Show live server, ship, and player status")
    p_status.set_defaults(func=cmd_status)

    # push
    p_push = subparsers.add_parser("push", help="Sync avionics files to Computer 15 and reboot")
    p_push.add_argument("--no-reboot", action="store_true", help="Don't reboot ComputerCraft")
    p_push.set_defaults(func=cmd_push)

    # test
    p_test = subparsers.add_parser("test", help="Run autonomous flight trial with live telemetry")
    p_test.add_argument("--seconds", type=float, default=15.0, help="Test duration in seconds (default: 15)")
    p_test.set_defaults(func=cmd_test)

    # rescue
    p_rescue = subparsers.add_parser("rescue", help="Reset ship to dock coordinates and freeze")
    p_rescue.set_defaults(func=cmd_rescue)

    # freeze / unfreeze
    p_freeze = subparsers.add_parser("freeze", help="Freeze nearest ship")
    p_freeze.set_defaults(func=cmd_freeze)
    p_unfreeze = subparsers.add_parser("unfreeze", help="Unfreeze Skyfire")
    p_unfreeze.set_defaults(func=cmd_unfreeze)

    # logs
    p_logs = subparsers.add_parser("logs", help="View recent ComputerCraft flight logs")
    p_logs.add_argument("-n", "--lines", type=int, default=30, help="Number of lines (default: 30)")
    p_logs.add_argument("--txt", action="store_true", help="Read flight_log.txt instead of csv")
    p_logs.set_defaults(func=cmd_logs)

    # rcon
    p_rcon = subparsers.add_parser("rcon", help="Execute raw Minecraft RCON command")
    p_rcon.add_argument("command", nargs="+", help="RCON command to execute")
    p_rcon.set_defaults(func=cmd_rcon)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
