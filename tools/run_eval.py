#!/usr/bin/env python3
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bridge

def run_eval(lua_code: str, timeout: float = 3.0) -> str:
    # 1. Remove any old eval_out.txt
    subprocess.run(["adb", "shell", f"run-as com.termux rm -f {bridge.PHONE_CC_DIR}/eval_out.txt"], check=False, stdout=subprocess.DEVNULL)
    
    # 2. Write and push new command
    payload = "EVAL:\n" + lua_code.strip() + "\n"
    tmp_path = "/tmp/eval_cmd.txt"
    with open(tmp_path, "w") as f:
        f.write(payload)
    
    subprocess.run(["adb", "push", tmp_path, "/data/local/tmp/fcc_cmd.txt"], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["adb", "shell", f"run-as com.termux cp /data/local/tmp/fcc_cmd.txt {bridge.PHONE_CC_DIR}/fcc_cmd.txt"], check=True, stdout=subprocess.DEVNULL)
    
    # 3. Poll for eval_out.txt
    start = time.time()
    while time.time() - start < timeout:
        res = subprocess.run(["adb", "exec-out", f"run-as com.termux cat {bridge.PHONE_CC_DIR}/eval_out.txt"], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout and "No such file" not in res.stdout:
            return res.stdout.strip()
        time.sleep(0.1)
    
    return "[TIMEOUT waiting for eval_out.txt]"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        code = " ".join(sys.argv[1:])
    else:
        code = sys.stdin.read()
    print(run_eval(code))
