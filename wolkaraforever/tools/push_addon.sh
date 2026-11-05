#!/bin/bash
# Copy the Interface mobile add-on (addons/WolkaraRoue) into the game's Interface/AddOns on the
# device, as the add-on's own commit says to install it.
#
# usage: wolkaraforever/tools/push_addon.sh [--dry-run]
#
# The game reads its add-ons when its interface loads, so this refuses while a game session is
# live; like every tool that writes the game's files, it also refuses while an update is
# writing. Every file is read back from the device and compared before success is reported.
# It only adds and replaces: a file removed from the add-on stays on the device. The add-on's
# settings are not touched - they live in the game's WTF folder, not beside the add-on.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
. wolkaraforever/tools/env.sh
device=${DEVICE:-}
bundle=${TOLKARA_BUNDLE_ID:-local.tolkara.app}
[ -n "$device" ] || { echo "push_addon: set DEVICE in local.env (see local.env.example)" >&2; exit 2; }
dry=0
case "${1:-}" in
    '') ;;
    --dry-run) dry=1 ;;
    *) echo "usage: wolkaraforever/tools/push_addon.sh [--dry-run]" >&2; exit 2 ;;
esac

state=$(bash wolkaraforever/tools/pilot.sh state 2>&1) || { echo "$state" >&2; exit 1; }
if echo "$state" | grep -q "a game session is live"; then
    echo "push_addon: a game session is live; quit the game first (the Quit tile of the Interface mobile menu saves)" >&2
    exit 1
fi
echo "$state" | grep -qE "update writing: 0 file" ||
    { echo "push_addon: an update may be writing; try again when it has stopped" >&2; exit 1; }

addon=addons/WolkaraRoue
destination="World of Warcraft/_forever_/Interface/AddOns/WolkaraRoue"
files=$(cd "$addon" && ls -- *.toc *.lua *.xml 2>/dev/null)
[ -n "$files" ] || { echo "push_addon: nothing to copy in $addon" >&2; exit 1; }
echo "push_addon: $(echo "$files" | wc -l | tr -d ' ') file(s) to $destination"
if [ "$dry" = 1 ]; then echo "$files"; echo "push_addon: dry run, nothing copied"; exit 0; fi

for file in $files; do
    xcrun devicectl device copy to --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --source "$addon/$file" --destination "Documents/$destination/$file" > /dev/null
done
for file in $files; do
    DEVICE_LOG_FILE="$destination/$file" bash wolkaraforever/tools/device_log.sh 0 > /dev/null
    cmp -s "build/device-log-files/$file" "$addon/$file" ||
        { echo "push_addon: $file read back from the device is not the one copied" >&2; exit 1; }
done
echo "push_addon: done; every file read back identical. The game loads it at its next login or /reload."
