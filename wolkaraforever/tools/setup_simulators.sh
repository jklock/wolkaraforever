#!/bin/bash
# Make sure the two matrix simulators exist.
# usage: wolkaraforever/tools/setup_simulators.sh --apply
#
# The test matrix is three devices and no others (see
# development/architecture/DEVICE_CONTRACT.md):
#
#   1. iPhone Duo                    - simulator, ensured here
#   2. iPad Pro 13-inch (M5)         - simulator, ensured here
#   3. iPad Pro 12.9-inch (5th gen)  - the physical iPad, no simulator involved
#
# So this script creates, at most, those two simulators. It deletes nothing and
# shuts nothing down: a simulator already carrying a matrix name is reused as it
# is, and every other simulator on this Mac is left alone.
#
# It does not relocate CoreSimulator's data root. It used to, onto an APFS disk
# image on the external Storage volume, to keep device data off the boot disk -
# and that made every simulator unbootable: a device whose data lives on a disk
# image never finishes its first boot. SpringBoard gets a PID,
# `com.apple.springboard.services` never registers, the screen stays on the Apple
# logo and the writes stop. The identical device on the boot volume reaches the
# home screen in seconds (measured, 2026-11-06, both matrix simulators). Device
# data is under a gigabyte; the runtime images beside it are tens of gigabytes and
# live on the boot volume either way.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/simulators.sh

data_root="$HOME/Library/Developer/CoreSimulator"

if [ "${1:-}" != --apply ] || [ "$#" -ne 1 ]; then
    echo "usage: wolkaraforever/tools/setup_simulators.sh --apply" >&2
    exit 2
fi
if mount | grep -Fq " on $data_root "; then
    cat >&2 <<EOF
setup_simulators: $data_root is a mounted volume, not a directory.

A simulator cannot boot from there. Move the device data back to the boot disk:

  xcrun simctl shutdown all
  launchctl bootout gui/\$(id -u)/com.wolkaraforever.coresimulator-storage
  diskutil unmount force $data_root
  mkdir -p $data_root
  cp -a <backup>/Devices $data_root/Devices

See development/guides/BUILDING.md, "Simulator devices".
EOF
    exit 1
fi

# The UDID of a device whose name starts with this one, or nothing.
device_udid() {
    xcrun simctl list devices -j | python3 -c '
import json, sys
prefix = sys.argv[1].lower()
for group in json.load(sys.stdin)["devices"].values():
    for device in group:
        if device["name"].lower().startswith(prefix):
            print(device["udid"])
            raise SystemExit
print("")' "$1"
}

# The newest installed iOS runtime that can host this form factor.
newest_runtime() {
    xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
runtimes = [
    r for r in json.load(sys.stdin)["runtimes"]
    if r.get("platform") == "iOS" and r.get("isAvailable", True)
]
phones = [r for r in runtimes if "iPhone" in r["identifier"]]
if want == "iphone":
    runtimes = phones or runtimes
else:
    runtimes = [r for r in runtimes if "iPhone" not in r["identifier"]] or runtimes
if not runtimes:
    raise SystemExit
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(runtimes[-1]["identifier"])' "$1"
}

# Ensure one matrix simulator. A device that already exists is reported and left
# exactly as it is; a device this run creates is boot-checked once, so a broken
# runtime is found here instead of in the middle of a suite, and then shut down.
ensure_device() {
    local key=$1 type=$2 name=$3 udid runtime
    udid=$(device_udid "$name")
    if [ -n "$udid" ]; then
        echo "setup_simulators: $name already exists ($udid); left as it is"
        printf '%s %s\n' "$name" "$udid"
        return
    fi
    runtime=$(newest_runtime "$key")
    [ -n "$runtime" ] || {
        echo "setup_simulators: install an iOS simulator runtime for $name in Xcode Components" >&2
        exit 1
    }
    udid=$(xcrun simctl create "$name" "$type" "$runtime")
    echo "setup_simulators: created $name on $runtime ($udid)"
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    printf '%s %s\n' "$name" "$udid"
}

ensure_device ipad com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-16GB "$WOLKARA_MATRIX_IPAD"
ensure_device iphone com.apple.CoreSimulator.SimDeviceType.iPhone-Duo "$WOLKARA_MATRIX_IPHONE"

cat <<EOF

The test matrix is these three devices and no others:
  1. $WOLKARA_MATRIX_IPHONE  (simulator)
  2. $WOLKARA_MATRIX_IPAD  (simulator)
  3. $WOLKARA_MATRIX_PHYSICAL  (hardware, through device_matrix.sh)
EOF
