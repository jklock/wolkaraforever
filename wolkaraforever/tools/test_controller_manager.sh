#!/bin/bash
# The Controller Manager's deterministic suite: profile, routing, lifecycle, learning and
# gesture ownership, with no hardware and no game.
#
# It builds our own fixture and nothing else, so it is safe to run anywhere, and it drives
# the same entry points GameController's handlers call - which is what makes it evidence
# about the real pipeline rather than about a mock of it.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
wolkaraforever/tools/prepare.sh
cd build/platform
SIM=${SIMULATOR:-iPad Pro 13-inch (M5)}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"], d["udid"])]
devices.sort(key=lambda d: d["state"] != "Booted")
print(devices[0]["udid"] if devices else "")' "$SIM")
[ -n "$SIM_ID" ] || { echo "No matching simulator; set SIMULATOR."; exit 2; }
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
APP=build/controller-manager-fixture/ControllerManager.app
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Ilauncher/Controller -Ilauncher/App -Ilauncher/Input \
    launcher/Controller/ControllerManager.m launcher/Controller/ControllerProfile.m \
    launcher/Controller/ControllerIdentity.m launcher/Input/InputElement.m \
    launcher/App/WolkaraForeverLog.m \
    tests/test_controller_manager_app.m \
    -framework Foundation -framework UIKit -framework GameController -framework CoreGraphics \
    -framework QuartzCore -o "$APP/ControllerManagerFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.controller-manager</string>
<key>CFBundleExecutable</key><string>ControllerManagerFixture</string>
<key>CFBundleName</key><string>Controller Manager fixture</string>
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
# simctl may report success even when the fixture aborts an assertion, so the fixture's own
# verdict line is what decides.
LOG=build/controller-manager-fixture/self-test.log
xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.controller-manager 2>&1 | tee "$LOG"
grep -q 'CONTROLLER_MANAGER_PASS:' "$LOG"
