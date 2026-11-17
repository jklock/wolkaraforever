#!/bin/bash
# The battery features, as bare processes in the matrix simulator:
#   - the frame limit (Bridge/FramePacing.m in the Metal adapter): the launcher row's choice, the charger under
#     Automatic (30 on battery, 60 plugged in, live on UIDevice's battery notifications), Low Power Mode and
#     heat lowering it, presents turned into minimum-duration presents, the log lines, and the real Metal
#     command buffer class found from a CAMetalLayer's first drawable;
#   - the AFK saver (Touch/IdleSaver.m in the AppKit adapter): dimming after the row's minutes with no input on a
#     fixture clock, the first touch only waking, 10 frames a second while dimmed.
# A simulator, not the iPad: the panel's real refresh and battery are the device check's.
#
#   wolkaraforever/tools/test_battery_ui.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
wolkaraforever/tools/prepare.sh
cd build/platform
# The matrix iPad, or the matrix iPhone with `SIMULATOR=iphone`; anything else is refused.
simulator_use "${SIMULATOR:-ipad}"
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
OUT=build/battery-fixture
mkdir -p "$OUT"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
CFLAGS=(-target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations)

PACING="$OUT/FramePacingTest"
# The test first: its constructor watches UIDevice's battery-monitoring setter before the adapter's runs (Mach-O runs an
# image's constructors in link order).
xcrun --sdk iphonesimulator clang "${CFLAGS[@]}" -Itranslation/AKSupport -Itranslation/Metal \
    tests/test_frame_pacing.m translation/AKSupport/AKSupport.m translation/Metal/FramePacing.m \
    -framework Foundation -framework Metal -framework QuartzCore -framework UIKit -o "$PACING"
xcrun simctl spawn "$SIM_ID" "$PWD/$PACING" 2>&1 | tee "$OUT/pacing.log"
grep -q 'FRAME_PACING_PASS:' "$OUT/pacing.log"

IDLE="$OUT/IdleSaverTest"
xcrun --sdk iphonesimulator clang "${CFLAGS[@]}" -Itranslation/AKSupport -Itranslation/AppKit \
    translation/AKSupport/AKSupport.m translation/AppKit/IdleSaver.m translation/AppKit/AKHostLocalization.m \
    tests/test_idle_saver.m \
    -framework Foundation -framework UIKit -framework GameController -framework CoreGraphics -framework QuartzCore -o "$IDLE"
cp -R launcher/App/en.lproj launcher/App/de.lproj launcher/App/fr.lproj "$OUT/"   # the wake line reads the app's tables
xcrun simctl spawn "$SIM_ID" "$PWD/$IDLE" 2>&1 | tee "$OUT/idle.log"
grep -q 'IDLE_SAVER_PASS:' "$OUT/idle.log"

echo "test_battery_ui: PASS"
