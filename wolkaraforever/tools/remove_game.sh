#!/bin/bash
# Remove a World of Warcraft edition, or a whole installation, from
# WolkaraForever's Documents on the device.
#
# Why this exists: a copy into the app container only ever adds and overwrites.
# `push_game.sh` says so itself - "the copy is one-way; nothing on the iPad is
# deleted" - which is wrong for the one transition that needs deletion: the game
# moved from the beta (`_classic_beta_`, product `wow_classic_beta`) to the
# release (`_forever_`, product `wowf`). Pushing the release over a beta install
# leaves the beta's client and its product data behind: tens of gigabytes the
# game cannot use, and a `.build.info` that still names the beta until the new
# copy overwrites it.
#
# Deletion goes through the app's own file-sharing service (AFC, via
# `afcclient` from libimobiledevice) - the same service Finder's Files tab uses
# for the app - because devicectl has no delete command. AFC's remove is not
# recursive, so paths are removed deepest first, from one listing taken before
# anything is touched.
#
# usage: wolkaraforever/tools/remove_game.sh --all [--dry-run] [options]
#        wolkaraforever/tools/remove_game.sh --edition <folder> [--product <id>]
#
#   --all                Remove Documents/World of Warcraft (client, Data,
#                        settings and add-ons) and the updater's snapshot beside
#                        it (Documents/.tolkara-updates).
#   --edition <folder>   Remove one edition folder, e.g. _classic_beta_.
#   --product <id>       Also remove Data/<id>, the edition's product data. Read
#                        from the edition's .flavor.info when omitted.
#   --dry-run            Report what is there, in files and bytes; remove nothing.
#   --device <UDID>      Override DEVICE for this run.
#   --bundle <id>        Override TOLKARA_BUNDLE_ID for this run.
#   -h, --help           Show this text.
#
# It refuses while WolkaraForever is running: the app and its updater own those
# files. It never touches the Mac's game installation.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
root=$PWD
. wolkaraforever/tools/env.sh

all=0
dry_run=0
edition=
product=
device=${DEVICE:-}
bundle=${TOLKARA_BUNDLE_ID:-}

die() { printf 'remove_game: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --all) all=1;;
        --dry-run) dry_run=1;;
        --edition) [ $# -ge 2 ] || die "--edition needs a folder name"; edition=$2; shift;;
        --product) [ $# -ge 2 ] || die "--product needs a product id"; product=$2; shift;;
        --device) [ $# -ge 2 ] || die "--device needs a UDID"; device=$2; shift;;
        --bundle) [ $# -ge 2 ] || die "--bundle needs a bundle id"; bundle=$2; shift;;
        -h|--help) sed -n '2,39p' "$0"; exit 0;;
        *) die "unknown option: $1 (see --help)";;
    esac
    shift
done

[ "$all" = 1 ] || [ -n "$edition" ] || die "nothing to remove: pass --all or --edition <folder>"
[ -n "$device" ] || die "DEVICE is not set. Run: wolkaraforever/tools/device_variables.sh --write"
[ -n "$bundle" ] || die "TOLKARA_BUNDLE_ID is not set in local.env."
command -v afcclient >/dev/null 2>&1 || \
    die "afcclient is missing; install it with: brew install libimobiledevice"

# The app writes into the very files being removed. Refuse rather than race it.
if xcrun devicectl device info processes --device "$device" 2>/dev/null |
        grep -Fq '/Tolkara.app/Tolkara'; then
    die "WolkaraForever is running on the device. Close it first (wolkaraforever/tools/pilot.sh stop)."
fi

# AFC needs to know whether to reach the device over the network.
link=$(bash wolkaraforever/tools/device_variables.sh --json --device "$device" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("link",""))' 2>/dev/null || true)
afc=(afcclient -u "$device" --documents "$bundle")
[ "$link" = Network ] && afc+=(-n)

listing=$(mktemp)
trap 'rm -f "$listing" "$removals" 2>/dev/null' EXIT
removals=$(mktemp)

say() { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

step "reading what is installed (device $device, $link link)"
if ! xcrun devicectl device info files --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --username mobile --subdirectory Documents \
        --json-output "$listing" >/dev/null 2>&1; then
    die "could not list Documents in the app container"
fi

# What to remove, as paths relative to Documents. Nothing outside Documents is
# ever named here, and every path is checked again before it is sent.
targets=()
if [ "$all" = 1 ]; then
    targets=("World of Warcraft" ".tolkara-updates")
else
    case "$edition" in
        */*|..*|"") die "the edition must be one folder name inside Documents/World of Warcraft";;
    esac
    targets=("World of Warcraft/$edition")
    if [ -z "$product" ]; then
        # The edition's product id is the last line of its own .flavor.info;
        # read it from the device rather than guessing from the folder name.
        pulled=$(mktemp)
        if xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
                --domain-identifier "$bundle" --source "Documents/World of Warcraft/$edition/.flavor.info" \
                --destination "$pulled" >/dev/null 2>&1; then
            product=$(tail -n 1 "$pulled" 2>/dev/null | tr -d '\r\n')
        fi
        rm -f "$pulled"
    fi
    [ -n "$product" ] && targets+=("World of Warcraft/Data/$product")
fi

python3 - "$listing" "$removals" "${targets[@]}" <<'PY'
import json, os, sys
listing, removals, targets = sys.argv[1], sys.argv[2], sys.argv[3:]
files = json.load(open(listing))['result']['files']
def under(path, target):
    return path == target or path.startswith(target + '/')
lines = []
for target in targets:
    chosen = [f for f in files if under(f['relativePath'], target)]
    count = sum(1 for f in chosen if not f['resources']['isDirectory'])
    size = sum(f['metadata']['size'] for f in chosen if not f['resources']['isDirectory'])
    if not chosen:
        print(f'  absent   {target}')
    else:
        print(f'  present  {target}: {count} files, {size/1e9:.2f} GB')
    lines += [(f['relativePath'].count('/'), f['relativePath']) for f in chosen]
# Deepest first: a file before the folder that holds it. AFC's remove is not
# recursive, so ordering is what makes the walk work.
lines.sort(key=lambda item: (-item[0], item[1]))
with open(removals, 'w') as out:
    for _, path in lines:
        out.write(path + '\n')
print(f'  total    {len(lines)} entries to remove')
PY

if [ ! -s "$removals" ]; then
    step "nothing to remove"
    exit 0
fi

if [ "$dry_run" = 1 ]; then
    step "dry run: nothing was removed"
    exit 0
fi

# One AFC session for the whole walk: a round trip per entry, which is fine at
# this size (thousands, not millions) and much faster than a session per entry.
step "removing ${targets[*]}"
{
    while IFS= read -r path; do
        printf 'rm "/Documents/%s"\n' "$path"
    done < "$removals"
    printf 'quit\n'
} | "${afc[@]}" > "$listing" 2>&1
errors=$(grep -c "Error:" "$listing" 2>/dev/null || true)
[ -z "$errors" ] && errors=0
if [ "$errors" -ne 0 ]; then
    printf '%s\n' "remove_game: $errors removals reported an error; the first few:" >&2
    grep "Error:" "$listing" | head -5 | sed 's/^/         /' >&2
fi

# Measured again, from a fresh listing: the claim is that the paths are gone.
step "checking the result"
if ! xcrun devicectl device info files --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --username mobile --subdirectory Documents \
        --json-output "$listing" >/dev/null 2>&1; then
    die "could not list Documents again, so the result is unverified"
fi
python3 - "$listing" "${targets[@]}" <<'PY'
import json, sys
files = json.load(open(sys.argv[1]))['result']['files']
left = 0
for target in sys.argv[2:]:
    chosen = [f for f in files if f['relativePath'] == target or f['relativePath'].startswith(target + '/')]
    print(f'  {"still there" if chosen else "gone":<12}{target}' + (f': {len(chosen)} entries' if chosen else ''))
    left += len(chosen)
sys.exit(1 if left else 0)
PY
[ $? -eq 0 ] || die "some entries remain on the device"
step "done: ${targets[*]} removed"
