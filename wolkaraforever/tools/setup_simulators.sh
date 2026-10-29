#!/bin/bash
# Put mutable CoreSimulator device data in an APFS sparse bundle on Storage.
# usage: wolkaraforever/tools/setup_simulators.sh --apply
#
# CoreSimulatorService cannot write directly to an external USB path, even via a
# symlink or simctl --set. A native APFS disk-image mount works: the sparse
# bundle's blocks live on Storage while CoreSimulator sees an APFS mount at its
# required local path. Xcode's sealed simulator runtimes remain Apple-managed.
set -euo pipefail
cd "$(dirname "$0")/../.."

storage_image=/Volumes/Storage/Simulators.sparsebundle
mount_root="$HOME/Library/Developer/CoreSimulator"
launch_agent="$HOME/Library/LaunchAgents/com.wolkaraforever.coresimulator-storage.plist"
base_runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-0
duo_runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-1

if [ "${1:-}" != --apply ] || [ "$#" -ne 1 ]; then
    echo "usage: wolkaraforever/tools/setup_simulators.sh --apply" >&2
    exit 2
fi
for runtime in "$base_runtime" "$duo_runtime"; do
    xcrun simctl list runtimes | grep -q "$runtime" || {
        echo "setup_simulators: install the required iOS 27 runtimes in Xcode Components" >&2
        exit 1
    }
done
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

# The clean recreation is performed through simctl, not by deleting directories.
xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl delete all
killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true

if ! hdiutil info | grep -Fq "$storage_image"; then
    backup_root="$HOME/Library/Developer/CoreSimulator.pre-storage-$(date +%Y%m%d-%H%M%S)"
    mv "$mount_root" "$backup_root"
    mkdir "$mount_root"
    if [ ! -e "$storage_image" ]; then
        hdiutil create -size 150g -type SPARSEBUNDLE -fs APFS \
            -volname WolkaraSimulatorStorage "$storage_image" >/dev/null
    fi
    hdiutil attach -nobrowse -mountpoint "$mount_root" "$storage_image" >/dev/null
    mounted=1
fi

diskutil info "$mount_root" | grep -q 'Protocol:.*Disk Image' || {
    echo "setup_simulators: $mount_root is not the Storage-backed disk image" >&2
    exit 1
}

create() {
    local name=$1 type=$2 runtime=$3 udid
    udid=$(xcrun simctl list devices "$runtime" --json | python3 -c '
import json, sys
for entries in json.load(sys.stdin).get("devices", {}).values():
    for device in entries:
        if device.get("name") == sys.argv[1]:
            print(device["udid"])
            raise SystemExit
' "$name")
    if [ -z "$udid" ]; then udid=$(xcrun simctl create "$name" "$type" "$runtime"); fi
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b
    xcrun simctl shutdown "$udid"
    printf '%s %s\n' "$name" "$udid"
}

create "Wolkara iPad Pro 13 M5" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB "$base_runtime"
create "Wolkara iPhone 18 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro "$base_runtime"
create "Wolkara iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo "$duo_runtime"

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

# Keep the old clean-reset device set recoverable until the user empties Trash.
if [ -n "$backup_root" ]; then mv "$backup_root" "$HOME/.Trash/$(basename "$backup_root")"; fi
trap - ERR
echo "setup_simulators: device data is in $storage_image (mounted at $mount_root)"
