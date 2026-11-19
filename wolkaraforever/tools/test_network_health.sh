#!/bin/bash
# Build and exercise the bounded, anonymous TCP health counter module on macOS.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
build="$root/build/network-health"
mkdir -p "$build"
wolkaraforever/tools/prepare.sh
cd "$root/build/platform"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Iruntime runtime/NetworkHealth.m tests/test_network_health.m \
    -framework Foundation -o "$build/test_network_health"
"$build/test_network_health"
