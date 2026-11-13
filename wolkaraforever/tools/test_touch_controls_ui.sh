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
APP=build/touch-controls-fixture/TouchControls.app
mkdir -p "$APP"
# The app's own language tables, in the layout the app has them. The keyboard and the overlay are
# WolkaraForever's own interface even though they are compiled into a compatibility library, so
# their fixture gets the same resources the app ships; without them every label would fall back to
# the service's last resort and this fixture would be testing that instead.
for LANGUAGE in en de; do
    mkdir -p "$APP/$LANGUAGE.lproj"
    cp "launcher/App/$LANGUAGE.lproj/Localizable.strings" "$APP/$LANGUAGE.lproj/"
done
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Itranslation/AKSupport -Itranslation/AppKit translation/AKSupport/AKSupport.m \
    translation/AppKit/*.m translation/AppKit/*.c tests/test_touch_controls_app.m \
    $(cat translation/AppKit/ldflags) -o "$APP/TouchControlsFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.touch-controls</string>
<key>CFBundleExecutable</key><string>TouchControlsFixture</string>
<key>CFBundleName</key><string>Touch input fixture</string>
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
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-controls "$@"
else
    if [[ " $* " != *" --self-test "* ]]; then
        set -- --self-test "$@"
    fi
    # Both interfaces: the default (iPadOS, what every release through v1.0.7 has) and the
    # mobile one the launcher selects with WolkaraForeverInterfaceModeV1.
    for MODE in "" "--mobile-interface"; do
        LOG="build/touch-controls-fixture/self-test${MODE:+-mobile}.log"
        # simctl may report success even when the app aborts an assertion.
        xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-controls "$@" $MODE 2>&1 | tee "$LOG"
        grep -q 'TOUCH_UI_SELF_TEST_PASS:' "$LOG"
        # The Composer's card and a real guest, in the same interface: the assertions the state
        # machine's own fixture cannot make because it has no window.
        CLOG="build/touch-controls-fixture/composer${MODE:+-mobile}.log"
        xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-controls --composer-test $MODE 2>&1 | tee "$CLOG"
        grep -q 'TOUCH_UI_SELF_TEST_PASS: the Composer card' "$CLOG"
    done
fi

# The Composer's own state machine, in a process with no guest, no microphone and no window.
# It is a separate app because it has its own main, and it runs on every invocation: the rules
# it covers (generations, exactly-once send, terminal outcomes) are what the card depends on.
COMPOSER=build/touch-controls-fixture/ChatComposerTests.app
mkdir -p "$COMPOSER"
for LANGUAGE in en de fr; do
    mkdir -p "$COMPOSER/$LANGUAGE.lproj"
    cp "launcher/App/$LANGUAGE.lproj/Localizable.strings" "$COMPOSER/$LANGUAGE.lproj/"
done
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -Itranslation/AppKit -Itranslation/AKSupport translation/AKSupport/AKSupport.m \
    translation/AppKit/ChatComposer.m tests/test_chat_composer_app.m \
    -framework Foundation -framework UIKit -framework CoreGraphics -o "$COMPOSER/ChatComposerTests"
cat > "$COMPOSER/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.chat-composer</string>
<key>CFBundleExecutable</key><string>ChatComposerTests</string>
<key>CFBundleName</key><string>WolkaraForever composer tests</string>
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
codesign --force --sign - "$COMPOSER" > /dev/null
xcrun simctl install "$SIM_ID" "$COMPOSER"
COMPOSER_LOG="build/touch-controls-fixture/chat-composer.log"
xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.chat-composer 2>&1 | tee "$COMPOSER_LOG"
grep -q 'CHAT_COMPOSER PASS:' "$COMPOSER_LOG"
# Structured events, asserted from outside the process that printed them: every terminal
# outcome and every entry source has to be visible in the log, and the stale-callback rule has
# to be visible as a refusal rather than as silence.
for EVENT in \
    'chat-composer: open source=2' \
    'chat-composer: state 2 -> 4' \
    'chat-composer: Send outcome=sent destination=direct' \
    'chat-composer: Send outcome=sent destination=party' \
    'chat-composer: Send outcome=failed stage=insert' \
    'chat-composer: Send outcome=failed stage=return' \
    'chat-composer: stale capture callback' \
    'chat-composer: cancel generation=' \
    'chat-composer: background generation=' \
    'chat-composer: disconnect generation=' \
    'chat-composer: rollback complete' \
    'chat-composer: delivery mode review (migrated: a new installation)' \
    'chat-composer: delivery mode classicDirect (migrated: an existing installation)' \
    'chat-composer: 1 destination(s) stored, 1 enabled'
do
    if ! grep -qF "$EVENT" "$COMPOSER_LOG"; then
        echo "the composer log is missing: $EVENT"
        grep 'chat-composer' "$COMPOSER_LOG" | head -40
        exit 1
    fi
done
# Nothing the player wrote may be in the log. These are the fixture's own drafts.
for SECRET in 'hello there' 'keep me' 'unsent words' 'spoken words' 'half a sentence' '/p hi'; do
    if grep -qF "$SECRET" "$COMPOSER_LOG"; then
        echo "the composer log contains draft text: $SECRET"
        exit 1
    fi
done
echo "chat composer: state machine, generations, send transaction and destinations PASS"
