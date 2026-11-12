#!/bin/bash
# Builds/tests our own input fixture, never an imported application.
# The default is automated; pass --stay for visual inspection.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
wolkaraforever/tools/prepare.sh
cd build/platform
# The matrix iPad, or the matrix iPhone with `SIMULATOR=iphone`; anything else is refused.
simulator_use "${SIMULATOR:-ipad}"
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
APP=build/touch-gamepad-fixture/TouchGamepad.app
mkdir -p "$APP"
# The app's own language tables, as the app ships them: the gamepad's settings panel is
# WolkaraForever's interface even though it is compiled into a compatibility library.
for LANGUAGE in en de; do
    mkdir -p "$APP/$LANGUAGE.lproj"
    cp "launcher/App/$LANGUAGE.lproj/Localizable.strings" "$APP/$LANGUAGE.lproj/"
done
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    translation/AppKit/TouchGamepad.m translation/AppKit/TouchGamepadLayout.m translation/AppKit/TouchHaptics.m \
    translation/AppKit/InterfaceMode.m translation/AppKit/AKHostLocalization.m tests/test_touch_gamepad_app.m \
    -framework Foundation -framework UIKit -framework GameController -framework CoreGraphics -framework QuartzCore -o "$APP/TouchGamepadFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.touch-gamepad</string>
<key>CFBundleExecutable</key><string>TouchGamepadFixture</string>
<key>CFBundleName</key><string>Touch gamepad fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/><key>UISceneConfigurations</key><dict/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP" > /dev/null
xcrun simctl install "$SIM_ID" "$APP"
if [[ " $* " == *" --stay "* ]]; then
    # Visual inspection is explicit so the documented test command cannot hang.
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-gamepad "$@"
else
    if [[ " $* " != *" --self-test "* && " $* " != *" --self-test-input "* ]]; then
        set -- --self-test "$@"
    fi
    # Both interfaces: the default (iPadOS, what every release through v1.0.7 has) and the
    # mobile one the launcher selects with WolkaraForeverInterfaceModeV1.
    for MODE in "" "--mobile-interface"; do
        LOG="build/touch-gamepad-fixture/self-test${MODE:+-mobile}.log"
        # simctl may report success even when the app aborts an assertion.
        xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-gamepad "$@" $MODE 2>&1 | tee "$LOG"
        grep -Eq 'TOUCH_GAMEPAD_(LIFECYCLE|INPUT)_PASS:' "$LOG"
    done
fi
