#!/usr/bin/env python3
"""Opt-in physical Air75 main-light test. Never run automatically in CI."""
import argparse
import json
from pathlib import Path
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description="Show red/cyan/purple at 15%, then restore all original Air75 configuration bytes.")
    parser.add_argument("--evidence", type=Path, help="Save sanitized results to a new JSON file.")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Requires macOS, wired ANSI Air75 V3 1.0.23.6 and Mac profile.")
    if args.evidence and args.evidence.exists():
        parser.error("Evidence file already exists; refusing to overwrite.")
    root = Path(__file__).resolve().parents[1]
    binary = root / "zig-out/bin/keyflux"

    def call(*command):
        run = subprocess.run([str(binary), *command], capture_output=True, text=True, timeout=15)
        try:
            result = json.loads(run.stdout)
        except ValueError:
            raise RuntimeError(f"{command[0]} did not return JSON") from None
        if run.returncode or result.get("ok") is False:
            raise RuntimeError(f"{command[0]} failed: {result.get('code', 'unknown')}")
        return result

    status = call("hardware-status-air75")
    if status["recovery"]["required"]:
        raise RuntimeError("An earlier Air75 capture exists. Restore it explicitly before this test.")
    initial = status["probe"]
    fingerprint = status["fingerprint"]
    if isinstance(fingerprint, list):
        fingerprint = bytes(fingerprint).decode("ascii")
    assert len(fingerprint) == 64
    record = {"platform": "macos", "transport": "usb", "firmware": initial["firmware_version"],
              "profile": initial["profile_name"], "original_state": initial["state"],
              "observations": [], "visual_verification": "requires human confirmation",
              "flash_persistence_verified": False}

    def interrupted(signum, _frame):
        raise KeyboardInterrupt(f"Received signal {signum}")

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    owned = False
    try:
        for color in ("#FF0000", "#00FFFF", "#8000FF"):
            print(f"Air75 main: {color}, 15%, 3 seconds.", flush=True)
            # Set before launching: a failed/terminated setter may already apply.
            owned = True
            result = call("hardware-solid-air75", color, "15", "--expect-device", fingerprint)
            independent = call("hardware-probe-air75")
            assert result["state"] == independent["state"], "Independent D5 snapshot mismatch"
            assert result["state"][9:] == initial["state"][9:], "Unowned fields changed"
            assert result["state"][0] == 3 and result["state"][1] == 15
            record["observations"].append({"requested": color, "result": result, "independent_state": independent["state"]})
            if color == "#00FFFF":
                duplicate = call("hardware-solid-air75", color, "15", "--expect-device", fingerprint)
                assert duplicate["changed"] is False, "Identical color was not deduplicated"
                record["duplicate_changed"] = duplicate["changed"]
            time.sleep(3)
    finally:
        # Do not let a second signal interrupt explicit recovery.
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(signum, signal.SIG_IGN)
        if owned:
            restored = call("hardware-restore-air75", "--expect-device", fingerprint)
            final = call("hardware-status-air75")
            assert final["probe"]["state"] == initial["state"], "Original 22-byte state did not restore"
            assert not final["recovery"]["required"], "Recovery journal remains"
            record["restore"] = restored
            record["final_state"] = final["probe"]["state"]
            record["journal_removed"] = True
            print("Original 22-byte state restored exactly; recovery journal removed.", flush=True)
    if args.evidence:
        with args.evidence.open("x") as output:
            json.dump(record, output, indent=2)
            output.write("\n")
        print(f"Sanitized evidence saved: {args.evidence}", flush=True)


if __name__ == "__main__":
    main()
