#!/bin/bash
# Make WoW Forever forget the Battle.net login it remembers, so its login screen starts empty.
#
# usage: wolkaraforever/tools/forget_login.sh [--dry-run]
#
# What the client remembers between launches is two lines of its WTF/Config.wtf: accountName
# (the e-mail in the login screen) and accountList (the game-account selector under it). It
# keeps no login token - its own Logs/Connection.log reports usedToken="false" - and nothing
# about the authenticator, which belongs to the Blizzard account. This removes those two lines
# and nothing else: portal and locales stay, and the login fails without them.
#
# The client rewrites Config.wtf when it exits, so this refuses while a game session is live;
# like every tool that writes the game's files, it also refuses while an update is writing.
# The file as it was is kept under build/wtf-backups/<time>/ (ignored and never committed: it
# holds the e-mail), and the result is read back from the device before success is reported.
# Restoring is a copy of that backup to the same place.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
. wolkaraforever/tools/env.sh
device=${DEVICE:-}
bundle=${TOLKARA_BUNDLE_ID:-local.tolkara.app}
[ -n "$device" ] || { echo "forget_login: set DEVICE in local.env (see local.env.example)" >&2; exit 2; }
dry=0
case "${1:-}" in
    '') ;;
    --dry-run) dry=1 ;;
    *) echo "usage: wolkaraforever/tools/forget_login.sh [--dry-run]" >&2; exit 2 ;;
esac

state=$(bash wolkaraforever/tools/pilot.sh state 2>&1) || { echo "$state" >&2; exit 1; }
if echo "$state" | grep -q "a game session is live"; then
    echo "forget_login: a game session is live; close the game first (it rewrites Config.wtf on exit)" >&2
    exit 1
fi
echo "$state" | grep -qE "update writing: 0 file" ||
    { echo "forget_login: an update may be writing; try again when it has stopped" >&2; exit 1; }

config="World of Warcraft/_forever_/WTF/Config.wtf"
backup="build/wtf-backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup"
DEVICE_LOG_FILE="$config" bash wolkaraforever/tools/device_log.sh 0 > /dev/null
cp build/device-log-files/Config.wtf "$backup/Config.wtf"
grep -vE '^SET (accountName|accountList) ' "$backup/Config.wtf" > "$backup/Config.forgotten.wtf" || true
before=$(wc -l < "$backup/Config.wtf" | tr -d ' ')
after=$(wc -l < "$backup/Config.forgotten.wtf" | tr -d ' ')
echo "forget_login: $((before - after)) remembered line(s); the original is kept at $backup/Config.wtf"
if [ "$before" -eq "$after" ]; then echo "forget_login: nothing is remembered; nothing written"; exit 0; fi
[ "$after" -gt 0 ] || { echo "forget_login: refusing to write an empty Config.wtf" >&2; exit 1; }
if [ "$dry" = 1 ]; then echo "forget_login: dry run, nothing written"; exit 0; fi

xcrun devicectl device copy to --device "$device" --domain-type appDataContainer \
    --domain-identifier "$bundle" --source "$backup/Config.forgotten.wtf" \
    --destination "Documents/$config" > /dev/null
DEVICE_LOG_FILE="$config" bash wolkaraforever/tools/device_log.sh 0 > /dev/null
if ! cmp -s build/device-log-files/Config.wtf "$backup/Config.forgotten.wtf"; then
    echo "forget_login: the file read back from the device is not the one written" >&2
    exit 1
fi
echo "forget_login: done; the login screen starts with no e-mail and no account selector"
