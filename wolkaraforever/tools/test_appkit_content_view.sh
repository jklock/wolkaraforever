#!/bin/bash
# The content-view sizing proof for patch 0054, in the simulator: prepare the
# tree, build the test against the prepared adapters, and run it on the matrix
# device. No app and no scene are needed - a bare process takes the pre-host
# path, and the test attaches a host view itself for the hosted path.
#
#   wolkaraforever/tools/test_appkit_content_view.sh             # the matrix iPad
#   SIMULATOR=iphone wolkaraforever/tools/test_appkit_content_view.sh   # the matrix iPhone
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
wolkaraforever/tools/prepare.sh
cd build/platform
simulator_use "${SIMULATOR:-ipad}"
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p build/emulation
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Itranslation/AKSupport -Itranslation/AppKit \
    translation/AKSupport/AKSupport.m translation/AppKit/*.m translation/AppKit/*.c \
    tests/test_appkit_content_view.m \
    $(cat translation/AppKit/ldflags) -o build/emulation/test_appkit_content_view
xcrun simctl spawn "$SIM_ID" "$PWD/build/emulation/test_appkit_content_view"
