#!/bin/bash
# The synthetic guest against the GameController façade.
#
# This fixture deliberately does NOT link Apple's GameController: the façade *is*
# `GCController` for the guest, and the real framework's class of the same name in one
# process would be exactly the ambiguity the adapter exists to avoid. A stand-in publishes
# the same notifications the Controller Manager does, so what is proven is the guest's view:
# the direct path when routing is off, and one virtual controller - with no physical pad or
# its events - when it is on.
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
APP=build/gamecontroller-facade-fixture/Facade.app
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Itranslation/AKSupport \
    translation/GameController/GameController.m translation/AKSupport/AKSupport.m \
    tests/test_gamecontroller_facade_app.m \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    -o "$APP/FacadeFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.gamecontroller-facade</string>
<key>CFBundleExecutable</key><string>FacadeFixture</string>
<key>CFBundleName</key><string>GameController façade fixture</string>
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
LOG=build/gamecontroller-facade-fixture/self-test.log
xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.gamecontroller-facade 2>&1 | tee "$LOG"
grep -q 'GAMECONTROLLER_FACADE_PASS:' "$LOG"
