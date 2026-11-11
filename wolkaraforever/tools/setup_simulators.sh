#!/bin/bash
# Make sure the two matrix simulators exist, and refuse the storage layout that
# is known not to work.
# usage: wolkaraforever/tools/setup_simulators.sh --apply
#
# Device data stays where CoreSimulator puts it: a real directory at
# ~/Library/Developer/CoreSimulator on the boot volume. An APFS sparse bundle
# mounted there was tried and is withdrawn - it is not a supported layout, and
# it does not merely fail: every device booted from it hangs for ever at the
# Apple logo. SpringBoard gets a PID, com.apple.springboard.services never
# registers, `simctl io screenshot` returns a static frame and writes stop dead,
# while the same runtime on the same device on the boot volume reaches its home
# screen in seconds. `simctl bootstatus -b` then hangs too, so the fault reads
# as "a slow boot" rather than as the layout. Proven on 2026-11-06 by booting a
# throwaway device in a device set on the boot disk and comparing the two.
# See development/guides/BUILDING.md.
#
# The test matrix is three devices and no others (see
# development/architecture/DEVICE_CONTRACT.md). The two simulators are the
# requirement; the physical iPad is nice to have and no simulator is involved:
#
#   1. iPhone Duo                    - simulator, required, ensured here
#   2. iPad Pro 13-inch (M5)         - simulator, required, ensured here
#   3. iPad Pro 12.9-inch (5th gen)  - the physical iPad, nice to have
#
# So this script creates, at most, those two simulators. It deletes nothing and
# shuts nothing down: a simulator already carrying a matrix name is reused as it
# is, and every other simulator on this Mac is left alone. `simctl create` is the
# only simulator creation in this repository, and it is called from here for
# these two names only.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/simulators.sh

mount_root="$HOME/Library/Developer/CoreSimulator"
legacy_image=/Volumes/Storage/Simulators.sparsebundle
legacy_agent="$HOME/Library/LaunchAgents/com.wolkaraforever.coresimulator-storage.plist"

if [ "${1:-}" != --apply ] || [ "$#" -ne 1 ]; then
    echo "usage: wolkaraforever/tools/setup_simulators.sh --apply" >&2
    exit 2
fi

# A machine still carrying the withdrawn layout would have this script report
# success while every suite it enables hangs, so it stops and says how to get
# out instead. Nothing is moved or detached here: a live mount point and the
# user's device data are theirs to change, and the commands below are exact.
legacy=
case "$(diskutil info "$mount_root" 2>/dev/null || true)" in
    *Protocol:*"Disk Image"*) legacy="a disk image is mounted at $mount_root";;
esac
if [ -z "$legacy" ] && [ -e "$legacy_agent" ]; then
    legacy="$legacy_agent still attaches one at login"
fi
if [ -n "$legacy" ]; then
    cat >&2 <<EOF
setup_simulators: this Mac still uses the withdrawn storage layout: $legacy.

That layout is why a simulator boot hangs at the Apple logo for ever, and this
script will not add to it. To go back to the supported one:

  launchctl bootout gui/\$(id -u)/com.wolkaraforever.coresimulator-storage 2>/dev/null || true
  mv "$legacy_agent" "$legacy_agent.disabled"
  hdiutil detach "$mount_root"          # only if the image is attached
  # the device data on the image is the same shape CoreSimulator expects:
  # copy it back into a real directory at \$HOME/Library/Developer/CoreSimulator

Then run this script again. The image at $legacy_image is left alone:
deleting it is your call, and nothing here needs it.
EOF
    exit 1
fi

[ ! -L "$mount_root" ] || {
    echo "setup_simulators: refusing symlinked $mount_root; restore a real directory first" >&2
    exit 1
}
mkdir -p "$mount_root"

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
setup_simulators: device data stays at $mount_root on the boot volume

The test matrix is these three devices and no others. The two simulators are the
requirement; the physical iPad is nice to have:
  1. $WOLKARA_MATRIX_IPHONE  (simulator, required)
  2. $WOLKARA_MATRIX_IPAD  (simulator, required)
  3. $WOLKARA_MATRIX_PHYSICAL  (hardware, nice to have, through device_matrix.sh)
EOF
