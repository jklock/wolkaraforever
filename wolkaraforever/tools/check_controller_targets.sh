#!/bin/bash
# Every virtual target the Controller Manager can offer is one the adapter can actually write.
#
# Why this exists: the catalogue lives in the app (ControllerProfile.m, which the page and the
# stored profile read) and the translation lives in the media adapter dylib
# (TouchGamepad.m, which turns a target into a GCInput* element). The two are in different
# binaries, so nothing at runtime compares them and no fixture links both. If they drift, the
# failure is silent and looks like the feature simply not working: the user picks "Menu" in the
# page, the profile stores `virtual.button.menu`, and the adapter has no element for it, so the
# press goes nowhere and nothing anywhere reports it.
#
# So this compares the two lists as source. It is deliberately dumb - no build, no simulator -
# because it is the kind of mistake a build cannot catch.
set -eu
cd "$(dirname "$0")/../.." || exit 2

catalogue=wolkaraforever/Controller/ControllerProfile.m
adapter=wolkaraforever/Touch/TouchGamepad.m

[ -f "$catalogue" ] || { echo "check_controller_targets: missing $catalogue" >&2; exit 2; }
[ -f "$adapter" ] || { echo "check_controller_targets: missing $adapter" >&2; exit 2; }

# What the page can offer: the identifiers passed to -initWithIdentifier:.
offered=$(grep -oE 'initWithIdentifier:@"[^"]+"' "$catalogue" | sed 's/.*@"\(.*\)"/\1/' | sort -u)
# What the adapter can write: the keys of the target-to-element table.
writable=$(grep -oE '@"virtual\.[a-z.]+":' "$adapter" | sed 's/@"\(.*\)":/\1/' | sort -u)

if [ -z "$offered" ]; then
    echo "check_controller_targets: no targets found in $catalogue - this check would pass on an empty list" >&2
    exit 2
fi
if [ -z "$writable" ]; then
    echo "check_controller_targets: no targets found in $adapter - this check would pass on an empty list" >&2
    exit 2
fi

unroutable=$(comm -23 <(printf '%s\n' "$offered") <(printf '%s\n' "$writable"))
unreachable=$(comm -13 <(printf '%s\n' "$offered") <(printf '%s\n' "$writable"))

if [ -n "$unroutable" ]; then
    echo "check_controller_targets: FAIL - the page offers targets the adapter cannot write:" >&2
    printf '  %s\n' $unroutable >&2
    echo "  A user can choose these and the press will go nowhere. Add them to $adapter." >&2
    exit 1
fi
if [ -n "$unreachable" ]; then
    echo "check_controller_targets: FAIL - the adapter writes targets the page cannot offer:" >&2
    printf '  %s\n' $unreachable >&2
    echo "  These are dead entries: nothing can map onto them. Remove them or add them to $catalogue." >&2
    exit 1
fi

count=$(printf '%s\n' "$offered" | grep -c .)
echo "check_controller_targets: PASS - $count targets, every one offered and writable."
