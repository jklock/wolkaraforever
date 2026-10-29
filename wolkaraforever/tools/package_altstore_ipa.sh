#!/bin/bash
# Build and verify the local External-JIT IPA for AltStore Classic.
#
# usage: wolkaraforever/tools/package_altstore_ipa.sh [output.ipa]
set -euo pipefail
cd "$(dirname "$0")/../.."

output=${1:-build/ipa/Tolkara-unsigned.ipa}
[ "$#" -le 1 ] || { echo "usage: wolkaraforever/tools/package_altstore_ipa.sh [output.ipa]" >&2; exit 2; }
case "$output" in /*) ;; *) output="$PWD/$output";; esac

[ -z "$(git status --porcelain)" ] || {
    echo "package_altstore_ipa: refusing a dirty source tree; commit the exact source first" >&2
    exit 1
}
mkdir -p "$(dirname "$output")"
TOLKARA_SYSTEM_ROOTS=NO wolkaraforever/tools/package_ipa.sh "$output"
wolkaraforever/tools/verify_ipa.sh "$output"
