#!/bin/bash
# The closing page ends the process without exit()'s teardown: WKEndProcess in a spawned child
# (an atexit handler that aborts is skipped, the status is kept, the notification is delivered,
# buffered stdout is flushed), and a wiring check that showClosingPage: calls it on all three ends.
set -euo pipefail
cd "$(dirname "$0")/../.."
build=build/process-end
mkdir -p "$build"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Iwolkaraforever/Shell -framework Foundation \
    wolkaraforever/Shell/ProcessEnd.m wolkaraforever/Shell/tests/test_process_end.m \
    -o "$build/test_process_end"
"$build/test_process_end"
echo "PROCESS_END_PASS"
python3 -I wolkaraforever/tools/tests/test_process_end_wiring.py
