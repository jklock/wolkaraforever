#!/usr/bin/env python3
"""Classify one External-JIT attempt from its host and native logs."""
import argparse
from pathlib import Path


def read(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def classify(native, host):
    if not native and not host:
        return "no-evidence"
    if any(marker in native for marker in ("guest entry blocked", "native startup refused")):
        return "startup-refused"
    if any(marker in native for marker in ("something is still attached", "debugger is still attached")):
        return "debugger-attached"
    if "arena is not executable" in native:
        return "arena-unavailable"
    if "native-return success" in host:
        return "native-return-success"
    if "native-return stopped" in host:
        return "native-return-stopped"
    if "memory-warning" in host:
        return "interrupted-after-memory-warning"
    if "lifecycle-in the background" in host or "lifecycle-resigning active" in host:
        return "interrupted-after-lifecycle-transition"
    entered_main = "entering original main" in native
    metal_failure = any(marker in native for marker in ("Frame readback failed:", "Metal command buffer failed", "Metal library rejected"))
    if entered_main and metal_failure:
        return "metal-failure-after-original-main"
    if entered_main:
        return "interrupted-after-original-main"
    return "interrupted-during-startup"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native", required=True)
    parser.add_argument("--host", required=True)
    arguments = parser.parse_args()
    print(classify(read(arguments.native), read(arguments.host)))


if __name__ == "__main__":
    main()
