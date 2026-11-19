#!/bin/bash
# Build the unsigned generic TolkaraDiagnostics .ipa for External JIT (sideloaded, for
# example with SideStore): prepare the tree, then run the platform's own packaging
# script against it. Only our own code goes in - never application code.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
. wolkaraforever/tools/env.sh
wolkaraforever/tools/prepare.sh
# The platform packager is run after entering build/platform.  Resolve its output
# while we are still at the repository root, so a default or relative destination
# survives the next prepare and the release workflow uploads the file it asked for.
case "${1-}" in
    "") set -- "$root/Tolkara-unsigned.ipa" ;;
    /*) ;;
    *) set -- "$root/$1" ;;
esac
cd build/platform
exec tools/package_ipa.sh "$@"
