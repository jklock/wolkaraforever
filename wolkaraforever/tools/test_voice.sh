#!/bin/bash
# The input, voice and configuration rules, tested.
#
# Runs the focused suite in wolkaraforever/Voice/tests/test_voice_app.m as a tiny app in the
# simulator, because UIKit and GameController are what the code under test is made of.
# The recogniser and the audio session are faked through the protocols in Dictation.h,
# which is the only way to test final-result ordering, permission refusal and
# audio-session restoration without a microphone.
#
#   wolkaraforever/tools/test_voice.sh
#
# Exit status is the suite's: 0 all checks passed, 1 at least one failed (the failing
# checks are printed), 2 nothing could be run.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
. wolkaraforever/tools/fixtures.sh
# An unchanged prepared tree is reused (prepare.sh), so a second suite does not rebuild it.
WOLKARA_PREPARE_REUSE=1 wolkaraforever/tools/prepare.sh
cd build/platform
# The matrix iPad, or the matrix iPhone with `SIMULATOR=iphone`; anything else is refused.
simulator_use "${SIMULATOR:-ipad}"
# A first boot on a fresh machine can take minutes, so this step gets longer than the rest.
FIXTURE_STEP_LIMIT=900 fixture_step "boot of $SIM_NAME" xcrun simctl bootstatus "$SIM_ID" -b > /dev/null

APP=build/voice-tests/VoiceTests.app
mkdir -p "$APP"
# The app's own language tables, in the layout the app has them: the settings and test pages are
# drawn through the same service as the rest of the app, and a fixture without the tables would be
# testing the service's last resort instead of its copy.
for LANGUAGE in en de; do
    mkdir -p "$APP/$LANGUAGE.lproj"
    cp "launcher/App/$LANGUAGE.lproj/Localizable.strings" "$APP/$LANGUAGE.lproj/"
done
# Keep the fixture's bundle contract identical to the app target. The voice suite uses the
# shared host logger, which validates the notices that the packaged app exposes.
cp "$ROOT/LICENSE" "$APP/WolkaraForever-LICENSE"
cp "$ROOT/NOTICE.md" "$APP/WolkaraForever-NOTICE.md"
cp "$ROOT/platform/LICENSE" "$APP/LICENSE"
cp "$ROOT/platform/NOTICE.md" "$APP/NOTICE.md"
# The sources under test, and only those: the view controllers are exercised by the
# launcher fixture instead, and pulling them in would drag WolkaraForeverTheme along for
# nothing.
#
# launcher/WoW/BatterySaverPolicy.m is here because launcher/Input/InputRouter.m sends the
# battery-saver activity and dim notifications, and its symbols have to link. Every fixture that
# compiles the input router needs it; test_controller_input.sh carries the same two lines.
fixture_compile xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Ilauncher/Input -Ilauncher/Voice -Ilauncher/Controller -Ilauncher/App -Ilauncher/WoW -Itests \
    launcher/Input/*.m launcher/Voice/Dictation.m launcher/Voice/VoiceSettings.m \
    launcher/WoW/BatterySaverPolicy.m \
    launcher/Voice/AudioSessionCoordinator.m \
    launcher/Voice/VoiceViewController.m launcher/Voice/VoiceTestViewController.m \
    launcher/Voice/ControllerTouchpadViewController.m \
    launcher/App/WolkaraForeverTheme.m \
    launcher/Controller/ControllerInspector.m launcher/App/WolkaraForeverLog.m \
    launcher/App/WKLocalization.m \
    launcher/App/WolkaraForeverConfig.m tests/test_voice_app.m \
    -framework Foundation -framework UIKit -framework QuartzCore -framework GameController \
    -framework AVFAudio -framework Speech -framework CoreGraphics -lz \
    -o "$APP/VoiceTests"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.voice</string>
<key>CFBundleExecutable</key><string>VoiceTests</string>
<key>CFBundleName</key><string>WolkaraForever voice tests</string>
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
fixture_refuse_if_running org.tolkara.tests.voice || exit 1
fixture_step "install of $APP" xcrun simctl install "$SIM_ID" "$APP"
# In the prepared tree, not the system temp folder: the simulator's app cannot write there, and
# its output would be lost.
LOG=build/voice-tests/run.log
# The suite exits by itself; the limit is only so a hang cannot look like a pass. Its output
# comes from files and its own system log, not the console relay, which drops the end of a run
# (fixtures.sh).
FIXTURE_STEP_LIMIT=60 fixture_launch "$LOG" org.tolkara.tests.voice || true
grep -E '^FAIL' "$LOG" | head -40 || true
if grep -q 'VOICE PASS' "$LOG"; then
    grep 'VOICE PASS' "$LOG"
    exit 0
fi
if grep -q 'VOICE FAIL' "$LOG"; then
    grep 'VOICE FAIL' "$LOG"
    exit 1
fi
echo "the suite did not finish; its output is above"
exit 2
