#!/bin/bash
# Build the unsigned generic TolkaraDiagnostics .ipa for External JIT (sideloaded, for
# example with SideStore): prepare the tree, then run the platform's own packaging
# script against it. Only our own code goes in - never application code.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
. wolkaraforever/tools/env.sh
# A package built without the public trust roots is not what a source build of this tree
# produces, and the client refuses every login on it (`BLZ51900003`) because it cannot validate
# Battle.net's certificate against macOS's system roots. install.sh refuses the same switch.
if [ "${TOLKARA_SYSTEM_ROOTS:-YES}" = "NO" ]; then
    echo "package_ipa: refusing TOLKARA_SYSTEM_ROOTS=NO; every .ipa this toolchain builds carries" >&2
    echo "the same public root certificates as a source build." >&2
    exit 2
fi
export TOLKARA_SYSTEM_ROOTS=YES
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
