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
simulator_ui_lock test_touch_gamepad_ui
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
APP=build/touch-gamepad-fixture/TouchGamepad.app
mkdir -p "$APP"
# The app's own language tables, as the app ships them: the gamepad's settings panel is
# WolkaraForever's interface even though it is compiled into a compatibility library.
for LANGUAGE in en de; do
    mkdir -p "$APP/$LANGUAGE.lproj"
    cp "launcher/App/$LANGUAGE.lproj/Localizable.strings" "$APP/$LANGUAGE.lproj/"
done
# TouchPlay's saved buttons as an iPad wrote them, for the iPad touch walk stick's checks.
# The older add-on's file (TouchPlay-v1.lua, keys on D, A and S) and the current one (none).
cp tests/fixtures/TouchPlay-v1.lua tests/fixtures/TouchPlay-v1-a22.lua "$APP/"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    translation/AppKit/TouchGamepad.m translation/AppKit/TouchGamepadLayout.m translation/AppKit/TouchHaptics.m \
    translation/AppKit/InterfaceMode.m translation/AppKit/LayoutStore.m translation/AppKit/AKHostLocalization.m \
    translation/AppKit/TouchCamera.m translation/AppKit/ControllerPointer.m translation/AppKit/TouchControllerLog.m translation/AppKit/TouchTrackpad.c \
    translation/AppKit/TouchAreas.m translation/AppKit/TouchContract.m tests/test_touch_gamepad_app.m \
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
    # ...and iOS on Duo and iPad touch ("--mobile-interface <mode>"): every stored mode runs the
    # same suite, and the iPad touch rules (its crash fallback) are gated on that one mode.
    for MODE in "" "--mobile-interface" "--mobile-interface iosduo" "--mobile-interface ipadtouch"; do
        LOG="build/touch-gamepad-fixture/self-test$(echo "${MODE:+ $MODE}" | sed -e 's/ --mobile-interface/-mobile/' -e 's/ /-/g').log"
        # simctl may report success even when the app aborts an assertion.
        xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-gamepad "$@" $MODE 2>&1 | tee "$LOG"
        grep -Eq 'TOUCH_GAMEPAD_(LIFECYCLE|INPUT)_PASS:' "$LOG"
        # The self-test ends through the process's real exit(); iPad touch's crash-fallback handler
        # must have run (it is what makes a quit from the game a clean exit).
        if [[ " $* " == *" --self-test "* ]]; then grep -q 'TOUCH_CRASH_GUARD_EXIT_PASS:' "$LOG"; fi
    done
    # ...and that Shell/main.m and the launcher call the crash fallback where they must (they have
    # no test of their own; this reads them).
    ../../wolkaraforever/tools/test_crash_guard_wiring.sh
fi
