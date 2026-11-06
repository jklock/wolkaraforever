#!/bin/bash
# Put mutable CoreSimulator device data in an APFS sparse bundle on Storage, and
# make sure the two matrix simulators exist.
# usage: wolkaraforever/tools/setup_simulators.sh --apply
#
# CoreSimulatorService cannot write directly to an external USB path, even via a
# symlink or simctl --set. A native APFS disk-image mount works: the sparse
# bundle's blocks live on Storage while CoreSimulator sees an APFS mount at its
# required local path. Xcode's sealed simulator runtimes remain Apple-managed.
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
# is, and every other simulator on this Mac is left alone. `simctl create` is the
# only simulator creation in this repository, and it is called from here for
# these two names only.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/simulators.sh

storage_image=/Volumes/Storage/Simulators.sparsebundle
mount_root="$HOME/Library/Developer/CoreSimulator"
launch_agent="$HOME/Library/LaunchAgents/com.wolkaraforever.coresimulator-storage.plist"

if [ "${1:-}" != --apply ] || [ "$#" -ne 1 ]; then
    echo "usage: wolkaraforever/tools/setup_simulators.sh --apply" >&2
    exit 2
fi
[ -d /Volumes/Storage ] && [ -w /Volumes/Storage ] || {
    echo "setup_simulators: /Volumes/Storage is not writable" >&2
    exit 1
}
[ ! -L "$mount_root" ] || {
    echo "setup_simulators: refusing symlinked $mount_root; restore a real directory first" >&2
    exit 1
}

mounted=0
backup_root=
rollback() {
    local exit_status=$?
    trap - ERR
    if [ "$mounted" = 1 ]; then hdiutil detach "$mount_root" >/dev/null 2>&1 || true; fi
    if [ -n "$backup_root" ] && [ -d "$backup_root" ]; then
        rmdir "$mount_root" >/dev/null 2>&1 || true
        mv "$backup_root" "$mount_root"
    fi
    exit "$exit_status"
}
trap rollback ERR

# `hdiutil info | grep -q` reads as a mount test and is not one under pipefail:
# grep -q exits at the first match, hdiutil then dies of SIGPIPE, and the
# pipeline reports failure for an image that is attached - which sent the old
# script down the unattach branch to move a live mount point aside. Match in the
# shell instead, where there is no pipe to break.
amount=$(hdiutil info 2>/dev/null || true)
case "$amount" in
    *"$storage_image"*) ;;
    *)
        backup_root="$HOME/Library/Developer/CoreSimulator.pre-storage-$(date +%Y%m%d-%H%M%S)"
        mv "$mount_root" "$backup_root"
        mkdir "$mount_root"
        if [ ! -e "$storage_image" ]; then
            hdiutil create -size 150g -type SPARSEBUNDLE -fs APFS \
                -volname WolkaraSimulatorStorage "$storage_image" >/dev/null
        fi
        hdiutil attach -nobrowse -mountpoint "$mount_root" "$storage_image" >/dev/null
        mounted=1
        ;;
esac

case "$(diskutil info "$mount_root" 2>/dev/null || true)" in
    *Protocol:*"Disk Image"*) ;;
    *)
        echo "setup_simulators: $mount_root is not the Storage-backed disk image" >&2
        exit 1
        ;;
esac

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

mkdir -p "$(dirname "$launch_agent")"
cat > "$launch_agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.wolkaraforever.coresimulator-storage</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/hdiutil</string><string>attach</string><string>-nobrowse</string>
    <string>-mountpoint</string><string>$mount_root</string><string>$storage_image</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST

# Keep the old device set recoverable until the user empties Trash.
if [ -n "$backup_root" ]; then mv "$backup_root" "$HOME/.Trash/$(basename "$backup_root")"; fi
trap - ERR
cat <<EOF
setup_simulators: device data is in $storage_image (mounted at $mount_root)

The test matrix is these three devices and no others:
  1. $WOLKARA_MATRIX_IPHONE  (simulator)
  2. $WOLKARA_MATRIX_IPAD  (simulator)
  3. $WOLKARA_MATRIX_PHYSICAL  (hardware, through device_matrix.sh)
EOF
