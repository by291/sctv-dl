#!/usr/bin/env python3
"""Drive real edge gestures on an explicitly selected disposable Android runtime."""

import argparse
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Disposable emulator serial")
    parser.add_argument("--pages", action="store_true", help="Verify player and history routes")
    args = parser.parse_args()
    if not args.device.startswith("emulator-"):
        parser.error("Use a disposable emulator, not a personal device")
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    adb = shutil.which("adb") or (str(Path(sdk) / "platform-tools/adb") if sdk else None)
    if not adb:
        parser.error("Put adb on PATH or set ANDROID_HOME")

    def shell(*command):
        return subprocess.check_output([adb, "-s", args.device, "shell", *command], text=True)

    sizes = re.findall(r"(\d+)x(\d+)", shell("wm", "size"))
    width, height = map(int, sizes[-1])
    if shell("settings", "get", "secure", "navigation_mode").strip() != "2":
        parser.error("Enable gesture navigation on the disposable emulator first")

    def motion(action, x):
        shell("input", "touchscreen", "motionevent", action, str(x), str(height // 2))

    process = subprocess.Popen([
        "flutter", "drive", "--driver=test_driver/integration_test.dart",
        "--target=integration_test/page_motion_test.dart" if args.pages else "--target=integration_test/predictive_back_test.dart", "-d", args.device,
        "--dart-define=PREDICTIVE_BACK_SMOKE=true",
    ], cwd=Path(__file__).resolve().parents[1], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, bufsize=0)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    pending = b""
    active = None
    completed = set()
    deadline = time.monotonic() + 600
    try:
        while time.monotonic() < deadline:
            for key, _ in selector.select(timeout=1):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    line = line.decode(errors="replace")
                    print(line, flush=True)
                    ready = re.search(r"PREDICTIVE_READY:(grid|exploration|scrolled|player|history):(left|right):(cancel|commit)", line)
                    captured = re.search(r"PREDICTIVE_CAPTURED:(grid|exploration|scrolled|player|history):(left|right):(cancel|commit)", line)
                    if ready:
                        active = ready.groups()
                        _, edge, _ = active
                        points = [1, width // 30, width // 10, width // 4, width // 2]
                        if edge == "right":
                            points = [width - x - 1 for x in points]
                        motion("DOWN", points[0])
                        for x in points[1:]:
                            motion("MOVE", x)
                            time.sleep(0.08)
                    if captured:
                        if captured.groups() != active:
                            raise RuntimeError("Gesture capture did not match the active gesture")
                        _, edge, outcome = active
                        points = [width // 10, width // 30, 2] if outcome == "cancel" else [width // 2]
                        if edge == "right":
                            points = [width - x - 1 for x in points]
                        for x in points:
                            motion("MOVE", x)
                            time.sleep(0.08)
                        motion("UP", points[-1])
                        completed.add(active)
                        active = None
            if process.poll() is not None and not selector.get_map():
                if process.returncode != 0:
                    raise RuntimeError(f"Flutter integration failed: {process.returncode}")
                expected = 8 if args.pages else 6
                if len(completed) != expected:
                    raise RuntimeError(f"Expected {expected} system gestures, observed {completed}")
                print("Verified cancellation and completion through Android system gestures.")
                return
        raise TimeoutError("Predictive-back verification exceeded ten minutes")
    finally:
        if active:
            motion("CANCEL", 1)
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        selector.close()


if __name__ == "__main__":
    main()
