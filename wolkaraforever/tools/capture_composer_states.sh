#!/bin/bash
# Capture the Composer card's three states - idle, ready, error - on a matrix simulator.
#
# This is local evidence, not a source asset: the PNGs land under build/ and are never committed.
# It needs the fixture the touch controls suite builds, so run that first (or let this build it).
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
cd build/platform
simulator_use "${SIMULATOR:-ipad}"
APP=build/touch-controls-fixture/TouchControls.app
if [ ! -d "$APP" ]; then
    echo "capture_composer_states: $APP is missing; run test_touch_controls_ui.sh --self-test first" >&2
    exit 2
fi
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
OUT="build/touch-controls-fixture/composer-states/${SIM_NAME// /-}"
mkdir -p "$OUT"

# The fixture opens a guest window, so simctl sees two displays and refuses to guess. Display 1 is
# the device's own screen on both matrix devices (simctl calls it "LCD (primary)"; the other is the
# guest window's surface), which is the one to capture.
shot() {
    xcrun simctl io "$SIM_ID" screenshot --display=1 "$1" > /dev/null
}

xcrun simctl uninstall "$SIM_ID" org.tolkara.tests.touch-controls 2> /dev/null || true
xcrun simctl install "$SIM_ID" "$APP"
LOG="$OUT/console.log"
xcrun simctl launch --terminate-running-process --console "$SIM_ID" \
    org.tolkara.tests.touch-controls --composer-visual > "$LOG" 2>&1 &
RUNNER=$!

# The fixture holds each state for five seconds and says so first, so the capture is taken from
# the marker rather than from a stopwatch.
wait_for() {
    local marker=$1 deadline=$((SECONDS + 40))
    while [ "$SECONDS" -lt "$deadline" ]; do
        grep -q "CHAT_COMPOSER_VISUAL $marker" "$LOG" && return 0
        sleep 0.2
    done
    echo "capture_composer_states: never saw CHAT_COMPOSER_VISUAL $marker" >&2
    return 1
}

for STATE in idle ready error; do
    wait_for "$STATE"
    sleep 0.7
    shot "$OUT/composer-$STATE.png"
    echo "captured $STATE: $OUT/composer-$STATE.png"
done
wait $RUNNER || true
grep -q 'CHAT_COMPOSER_VISUAL done' "$LOG" || echo "capture_composer_states: the run did not finish" >&2
echo "capture_composer_states: $OUT"
