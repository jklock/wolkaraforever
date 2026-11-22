#!/bin/bash
# Battery Saver: the shared policy on the Mac, then the presentation pacing and the AFK
# coordinator in the simulator.
#
#   wolkaraforever/tools/test_battery_saver.sh                    # the matrix iPad
#   SIMULATOR=iphone wolkaraforever/tools/test_battery_saver.sh   # the matrix iPhone
#
# Three fixtures, because there are three decisions and each has one place it can be measured:
#
#   test_battery_saver_policy  the stored choice, the launch snapshot and the frame rule,
#                              on the Mac, under ASan/UBSan. No device is involved in a rule
#                              about numbers.
#   test_metal_pacing          what the Metal adapter asks the system for, per presentation
#                              path, in a process with a real CAMetalLayer and command queue.
#   test_battery_saver_idle    the AFK timeout, held input, every wake source, the first-input
#                              rule, the configuration UI, background/foreground and the
#                              cap that comes back on waking - with a clock the fixture owns.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
wolkaraforever/tools/prepare.sh
cd build/platform
mkdir -p build/battery-saver

# 1. The policy. Foundation only: a rule about what a stored value means does not need a
#    simulator, and running it here puts it under the sanitizers.
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation \
    launcher/WoW/BatterySaverPolicy.m tests/test_battery_saver_policy.m \
    -o build/battery-saver/test_battery_saver_policy
build/battery-saver/test_battery_saver_policy

# 2. The adapters, in the simulator. One matrix device, chosen by simulators.sh; no fallback.
simulator_use "${SIMULATOR:-ipad}"
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
# -Wno-unused-variable: upstream's Metal adapter keeps its presented-frame counter behind
# `#if !TARGET_OS_SIMULATOR`, so in a simulator build that one static is unused. It is not our
# code and not a finding, and the device build uses it.
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" \
    -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-variable \
    -Wno-deprecated-declarations -Itranslation/AKSupport -Itranslation/Metal \
    translation/Metal/Presentation.m translation/Metal/RenderDiagnostics.m \
    translation/Metal/BatterySaverPolicy.m translation/AKSupport/AKSupport.m \
    tests/test_metal_pacing.m \
    -framework Foundation -framework Metal -framework QuartzCore -framework CoreGraphics \
    -framework ImageIO -framework UIKit \
    -o build/battery-saver/test_metal_pacing
# One process cannot be two configurations - the presentation swizzles are installed once - so
# each case is its own run.
for case in off disabled immediate30 immediate30-fallback attime30 attime30-late minimum30 minimum-longer; do
    xcrun simctl spawn "$SIM_ID" "$PWD/build/battery-saver/test_metal_pacing" "$case"
done

xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" \
    -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Itranslation/AKSupport -Itranslation/AppKit \
    translation/AppKit/BatterySaverIdle.m translation/AppKit/BatterySaverPolicy.m \
    tests/test_battery_saver_idle_app.m \
    -framework Foundation -framework UIKit -framework QuartzCore \
    -o build/battery-saver/test_battery_saver_idle
xcrun simctl spawn "$SIM_ID" "$PWD/build/battery-saver/test_battery_saver_idle"

echo "test_battery_saver: PASS (${SIM_NAME:-device})"
