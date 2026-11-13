#!/bin/bash
# Inactive Metal submission, in the simulator, through the adapter's own hook.
#
# The product caps drawable acquisition while another app is in front and leaves
# the foreground rate alone. That is a claim about timing, so it is measured on
# the same -[CAMetalLayer nextDrawable] the guest renders through, on both matrix
# simulators, rather than read off the source. No guest binary, game file or
# account is involved: one off-screen layer, the app's own lifecycle
# notifications, and the numbers.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
simulator_use "${SIMULATOR:-ipad}"
wolkaraforever/tools/prepare.sh
cd build/platform
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p build/emulation
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" \
    -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Itranslation/AKSupport \
    translation/AKSupport/AKSupport.m translation/Metal/BackgroundPacing.m \
    tests/test_background_pacing.m \
    $(cat translation/Metal/ldflags) -o build/emulation/test_background_pacing
xcrun simctl spawn "$SIM_ID" "$PWD/build/emulation/test_background_pacing"
