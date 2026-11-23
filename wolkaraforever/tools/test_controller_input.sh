#!/bin/bash
# The bounded controller command path, the claim record and their log events, tested.
#
# Runs wolkaraforever/Input/tests/test_controller_input_app.m as a tiny app in the simulator,
# because UIKit, GameController and the log the assertions read are what the code under test is
# made of. It needs no controller: the ingress is handed edges at exactly the boundary the
# inspector calls it from, which is the interface that has to be proved.
#
#   wolkaraforever/tools/test_controller_input.sh
#
# SIMULATOR=iphone selects the matrix iPhone; the default is the matrix iPad. Anything off the
# matrix is refused rather than substituted. Exit status is the suite's: 0 all checks passed, 1 at
# least one failed (the failing checks are printed), 2 nothing could be run.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
. wolkaraforever/tools/fixtures.sh
# An unchanged prepared tree is reused (prepare.sh), so a second suite does not rebuild it.
WOLKARA_PREPARE_REUSE=1 wolkaraforever/tools/prepare.sh
cd build/platform
simulator_use "${SIMULATOR:-ipad}"
# A first boot on a fresh machine can take minutes, so this step gets longer than the rest.
FIXTURE_STEP_LIMIT=900 fixture_step "boot of $SIM_NAME" xcrun simctl bootstatus "$SIM_ID" -b > /dev/null

APP=build/controller-input-tests/ControllerInputTests.app
mkdir -p "$APP"
# The sources under test, and only those. The view controllers are exercised by the voice and
# launcher fixtures; pulling them in would drag the theme along for nothing.
fixture_compile xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Ilauncher/Input -Ilauncher/Voice -Ilauncher/Controller -Ilauncher/App -Ilauncher/WoW -Itests \
    launcher/Input/*.m launcher/Voice/VoiceSettings.m launcher/WoW/BatterySaverPolicy.m \
    launcher/Controller/ControllerInspector.m launcher/App/WolkaraForeverLog.m \
    tests/test_controller_input_app.m \
    -framework Foundation -framework UIKit -framework QuartzCore -framework GameController \
    -o "$APP/ControllerInputTests"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.controller-input</string>
<key>CFBundleExecutable</key><string>ControllerInputTests</string>
<key>CFBundleName</key><string>WolkaraForever controller input tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/><key>UISceneConfigurations</key><dict/></dict>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" > /dev/null
fixture_refuse_if_running org.tolkara.tests.controller-input || exit 1
fixture_step "install of $APP" xcrun simctl install "$SIM_ID" "$APP"
# In the prepared tree, not the system temp folder: the simulator's app cannot write there, and
# its output would be lost.
LOG=build/controller-input-tests/run.log
# The suite exits by itself; the limit is only so a hang cannot look like a pass. Its output
# comes from files and its own system log, not the console relay, which drops the end of a run
# (fixtures.sh).
FIXTURE_STEP_LIMIT=60 fixture_launch "$LOG" org.tolkara.tests.controller-input || true
grep -E '^FAIL' "$LOG" | head -40 || true
if grep -q 'CONTROLLER-INPUT PASS' "$LOG"; then
    grep 'CONTROLLER-INPUT PASS' "$LOG"
    exit 0
fi
if grep -q 'CONTROLLER-INPUT FAIL' "$LOG"; then
    grep 'CONTROLLER-INPUT FAIL' "$LOG"
    exit 1
fi
echo "the suite did not finish; its output is above"
exit 2
