#!/bin/bash
# The previous game session's log: WKGuestLogKeepPrevious on a real file system (moved, nothing to
# move, an obstructed destination), and the two places in main.m that open native-guest.log for
# writing keep the previous one first and say what happened to it.
set -euo pipefail
cd "$(dirname "$0")/../.."
build=build/guest-log-rotation
mkdir -p "$build"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Iwolkaraforever/Shell -framework Foundation \
    wolkaraforever/Shell/GuestLogRotation.m wolkaraforever/Shell/tests/test_guest_log_rotation.m \
    -o "$build/test_guest_log_rotation"
"$build/test_guest_log_rotation"
python3 -I wolkaraforever/tools/tests/test_guest_log_rotation_wiring.py
