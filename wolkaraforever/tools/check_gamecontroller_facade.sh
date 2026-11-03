#!/bin/bash
# Does the guest-facing GameController façade cover everything World of Warcraft imports?
#
# Why this exists: the façade (translation/GameController/GameController.m, from
# wolkaraforever/Bridge/GameControllerFacade.m) is a "standalone" adapter, so classify.py
# plans *every* GameController import for it and build_shims.py generates a stub for
# anything the adapter does not define. A stub is not a failure the guest can see - it is
# worse than one: a stubbed class silently shadows Apple's, so the game's controller reads
# return nothing and look like "the pad does not work". A stubbed notification constant is
# never posted, so the game never learns a controller connected. Either way hardware or
# absence leaks past the façade untested, which is exactly what the Controller Manager is
# not allowed to do.
#
# So this refuses to pass without evidence. It reads the application's real import list
# with the platform's own probe tool, compares it with what the façade defines, and fails
# when anything is uncovered - naming the symbols rather than describing them.
#
# Selectors cannot be checked this way (they are not symbols), so the façade is written to
# return Apple's own controller objects while routing is off and the manager's virtual
# controller while it is on. The classes are the part that has to be declared, and that is
# what this check measures.
#
# usage: check_gamecontroller_facade.sh [<executable>]
#        With no argument, GUEST_EXE from local.env is used.
set -eu
cd "$(dirname "$0")/../.." || exit 2

facade=wolkaraforever/Bridge/GameControllerFacade.m

# Argument, then the environment, then local.env - the same precedence env.sh gives the
# rest of the tools, so `GUEST_EXE=… install.sh` checks the application it is about to build.
exe=${1:-${GUEST_EXE:-}}
if [ -z "$exe" ]; then
    exe=$(set -a; . ./local.env 2>/dev/null; printf '%s' "${GUEST_EXE:-}")
fi
if [ -z "$exe" ] || [ ! -f "$exe" ]; then
    echo "check_gamecontroller_facade: no application to inspect, so nothing is proven." >&2
    echo "  usage: $0 /path/to/GameExecutable   (or set GUEST_EXE in local.env)" >&2
    echo "  The façade is only safe for a build whose imports have been measured." >&2
    exit 2
fi

# The symbols this file defines. Constants and classes are the whole surface a shim can
# honestly provide; anything else it provides is a generated stub, which this check exists
# to catch.
defined=$(
    {
        grep -oE '^NSString \*const [A-Za-z0-9_]+' "$facade" | awk '{print "_"$3}'
        grep -oE '^const float [A-Za-z0-9_]+' "$facade" | awk '{print "_"$3}'
        grep -oE '^@implementation [A-Za-z0-9_]+' "$facade" | awk '{print $2}' | while read -r name; do
            printf '_OBJC_CLASS_$_%s\n' "$name"
            printf '_OBJC_METACLASS_$_%s\n' "$name"
        done
    } | sort -u
)

# dyld_info prints an offset column for some binaries and not for others, so the symbol is
# taken as the first field of every line that names the library.
imports=$(dyld_info -arch arm64 -imports "$exe" 2>/dev/null |
          awk '/\(from GameController\)/ {print $1}' | sort -u)
if [ -z "$imports" ]; then
    # No arm64 slice, or no GameController imports at all. The second is a real answer
    # (the application does not use controllers) and the first is not; say which.
    if dyld_info -imports "$exe" 2>/dev/null | grep -q '(from GameController)'; then
        echo "check_gamecontroller_facade: $(basename "$exe") imports GameController only from a slice this check does not read." >&2
        exit 1
    fi
    echo "check_gamecontroller_facade: $(basename "$exe") imports nothing from GameController."
    echo "check_gamecontroller_facade: the façade would be unused; nothing to cover."
    exit 0
fi

missing=$(comm -23 <(printf '%s\n' "$imports") <(printf '%s\n' "$defined"))

if [ -n "$missing" ]; then
    echo "check_gamecontroller_facade: FAIL — $(printf '%s\n' "$missing" | grep -c .) import(s) the façade does not define:" >&2
    printf '%s\n' "$missing" | sed 's/^/  /' >&2
    echo "" >&2
    echo "  A standalone adapter's uncovered import becomes a generated stub, which shadows" >&2
    echo "  Apple's class or constant for the guest. Add each symbol above to $facade" >&2
    echo "  (a constant with its real value, a class as a real model of what the guest" >&2
    echo "  reads) before building this application with the adapter enabled." >&2
    exit 1
fi

echo "check_gamecontroller_facade: PASS — $(printf '%s\n' "$imports" | grep -c .) GameController import(s) covered by the façade."
