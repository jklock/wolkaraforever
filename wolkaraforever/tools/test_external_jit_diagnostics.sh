#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g -Iwolkaraforever/Shell -framework Foundation \
    wolkaraforever/Shell/ExternalJITDiagnostics.m wolkaraforever/Shell/tests/test_external_jit_diagnostics.m \
    -o "$work/test_external_jit_diagnostics"
"$work/test_external_jit_diagnostics"
wolkaraforever/tools/tests/test_classify_external_jit.sh
