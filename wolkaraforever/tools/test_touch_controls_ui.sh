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
simulator_ui_lock test_touch_controls_ui
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
# TouchPlay's saved buttons as an iPad wrote them, for the iPad touch run's host checks.
cp tests/fixtures/TouchPlay-v1.lua "$APP/"
# ...and the add-on's newer key set, whose Interact has a hold key (the aim's "stop" button).
cp tests/fixtures/TouchPlay-v1-stopkey.lua "$APP/"
# ...and the add-on's current key set (no key on W, A, S or D), for the walk stick's host checks.
cp tests/fixtures/TouchPlay-v1-a22.lua "$APP/"
# ...and the same keys as the add-on binds them now, in the game's own order (ALT-CTRL-SHIFT-).
cp tests/fixtures/TouchPlay-v1-altorder.lua "$APP/"
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
# Install over a container that carries nothing. `simctl install` keeps the app's data, and this
# fixture writes NSUserDefaults (the delivery mode, the Composer's flag); a run that aborted
# mid-case leaves those behind and the next run starts from the previous case's world. Measured:
# with a stale container the self-test fails in the 64-edit draft loop (a draft that is not the
# one it typed), and on a clean one the same build passes on both interfaces, on both simulators,
# and a pristine main checkout with the same stale container fails in the same place.
xcrun simctl uninstall "$SIM_ID" org.tolkara.tests.touch-controls 2> /dev/null || true
xcrun simctl install "$SIM_ID" "$APP"
if [[ " $* " == *" --stay "* ]]; then
    # Visual inspection is explicit so the documented test command cannot hang.
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-controls "$@"
else
    if [[ " $* " != *" --self-test "* ]]; then
        set -- --self-test "$@"
    fi
    # iPad touch: TouchPlay's button list (contract v1). Its reader is Foundation-only, so it is a bare
    # process in the simulator, given the fixtures (an iPad's own saved file, the same from a newer
    # TouchPlay, and the file cut short) as a folder on the command line.
    CONTRACT=build/touch-controls-fixture/TouchContractTest
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
        -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -Itranslation/AppKit \
        translation/AppKit/TouchContract.m translation/AppKit/InterfaceMode.m tests/test_touch_contract.m \
        -framework Foundation -framework UIKit -framework CoreGraphics -o "$CONTRACT"
    xcrun simctl spawn "$SIM_ID" "$PWD/$CONTRACT" "$PWD/tests/fixtures" 2>&1 | tee build/touch-controls-fixture/contract.log
    grep -q 'TOUCH_CONTRACT_PASS:' build/touch-controls-fixture/contract.log
    # TouchPlay's buttons played by the fingers (glow, tap on lift, hold, drag off, Jump): a bare UIKit
    # process with a recorder for the keys and a fixture clock, given the same fixtures folder.
    AREAS=build/touch-controls-fixture/TouchAreasTest
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
        -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -Itranslation/AppKit \
        translation/AppKit/TouchAreas.m translation/AppKit/TouchContract.m translation/AppKit/InterfaceMode.m \
        translation/AppKit/AKHostLocalization.m tests/test_touch_areas.m \
        -framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$AREAS"
    cp -R launcher/App/en.lproj launcher/App/de.lproj launcher/App/fr.lproj "$(dirname "$AREAS")/"   # the notice reads the app's tables beside it
    xcrun simctl spawn "$SIM_ID" "$PWD/$AREAS" "$PWD/tests/fixtures" 2>&1 | tee build/touch-controls-fixture/areas.log
    grep -q 'TOUCH_AREAS_PASS:' build/touch-controls-fixture/areas.log
    # The chat keyboard and the game's password box (typed by hand): the bridge's field, with a recorder for the
    # host's text path; a bare UIKit process, its own stderr captured to prove nothing typed is logged.
    TEXT=build/touch-controls-fixture/TouchTextTest
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
        -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -Itranslation/AKSupport -Itranslation/AppKit \
        translation/AKSupport/AKSupport.m translation/AppKit/TouchTextBridge.m translation/AppKit/InterfaceMode.m \
        translation/AppKit/AKHostLocalization.m tests/test_touch_text.m \
        -framework Foundation -framework UIKit -framework CoreGraphics -o "$TEXT"
    xcrun simctl spawn "$SIM_ID" "$PWD/$TEXT" 2>&1 | tee build/touch-controls-fixture/text.log
    grep -q 'TOUCH_TEXT_PASS:' build/touch-controls-fixture/text.log
    # The in-world gate: the add-on's secure-input pulses read on a fixture clock - one short pulse enters the
    # world, two leave it, three are a window open, a held secure input is a password box - and the password
    # field's debounce agrees with the pulse limit. A bare Foundation process.
    WORLD=build/touch-controls-fixture/TouchWorldTest
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
        -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -Itranslation/AKSupport -Itranslation/AppKit \
        translation/AKSupport/AKSupport.m translation/AppKit/TouchWorldSignal.m translation/AppKit/TouchTextBridge.m \
        translation/AppKit/InterfaceMode.m translation/AppKit/AKHostLocalization.m tests/test_touch_world.m \
        -framework Foundation -framework UIKit -framework CoreGraphics -o "$WORLD"
    xcrun simctl spawn "$SIM_ID" "$PWD/$WORLD" 2>&1 | tee build/touch-controls-fixture/world.log
    grep -q 'TOUCH_WORLD_PASS:' build/touch-controls-fixture/world.log
    # The reader is compiled into the app and into the adapter library, and one process loads both.
    # Two images defining one Objective-C class make the runtime warn and pick one, so the app's copy
    # has its own class names: load both in one simulator process and look for the warning.
    DUP=build/touch-controls-fixture/two-images
    mkdir -p "$DUP"
    cat > "$DUP/main.m" <<'SRC'
#import <Foundation/Foundation.h>
#include <dlfcn.h>
int main(int argc, char **argv) {
    @autoreleasepool {
        if (!dlopen(argv[1], RTLD_NOW)) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 2; }
        Class adapter = NSClassFromString(@"AKTouchContract"), app = NSClassFromString(@"AKAppTouchContract");
        Class adapterArea = NSClassFromString(@"AKTouchArea"), appArea = NSClassFromString(@"AKAppTouchArea");
        if (!adapter || !app || !adapterArea || !appArea || adapter == app || adapterArea == appArea) { fprintf(stderr, "classes: %p %p %p %p\n", adapter, app, adapterArea, appArea); return 1; }
        printf("TOUCH_CONTRACT_TWO_IMAGES_PASS: the adapter's AKTouchContract and the app's AKAppTouchContract load side by side\n");
    }
    return 0;
}
SRC
    CFLAGS=(-target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations)
    xcrun --sdk iphonesimulator clang "${CFLAGS[@]}" -dynamiclib -Itranslation/AppKit translation/AppKit/TouchContract.m translation/AppKit/InterfaceMode.m \
        -framework Foundation -framework UIKit -framework CoreGraphics -o "$DUP/libadapter.dylib"
    xcrun --sdk iphonesimulator clang "${CFLAGS[@]}" -Ilauncher/WoW launcher/WoW/TouchContract.m launcher/WoW/InterfaceMode.m "$DUP/main.m" \
        -framework Foundation -framework UIKit -framework CoreGraphics -o "$DUP/twoimages"
    codesign --force --sign - "$DUP/libadapter.dylib" "$DUP/twoimages" > /dev/null 2>&1
    xcrun simctl spawn "$SIM_ID" "$PWD/$DUP/twoimages" "$PWD/$DUP/libadapter.dylib" > "$DUP/run.log" 2>&1 || { cat "$DUP/run.log"; exit 1; }
    cat "$DUP/run.log"
    if grep -q 'implemented in both' "$DUP/run.log"; then echo "one class in two images: $DUP/run.log" >&2; exit 1; fi
    grep -q 'TOUCH_CONTRACT_TWO_IMAGES_PASS:' "$DUP/run.log"
    # ...and that the app loads it at game start (Shell/main.m has no test of its own; this reads it).
    ../../wolkaraforever/tools/test_touch_contract_wiring.sh
    # Every stored interface: the default (iPadOS, what every release through v1.0.7 has), the
    # mobile one the launcher selects with WolkaraForeverInterfaceModeV1 (iOS), iOS on Duo, and
    # iPad touch. The first three run the same suite they always ran; iPad touch adds its own checks.
    for MODE in "" "--mobile-interface" "--mobile-interface iosduo" "--mobile-interface ipadtouch"; do
        # self-test.log, self-test-mobile.log (as before), self-test-mobile-iosduo.log, self-test-mobile-ipadtouch.log
        NAME="$(echo "${MODE:+ $MODE}" | sed -e 's/ --mobile-interface/-mobile/' -e 's/ /-/g')"
        LOG="build/touch-controls-fixture/self-test$NAME.log"
        # simctl may report success even when the app aborts an assertion.
        xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-controls "$@" $MODE 2>&1 | tee "$LOG"
        grep -q 'TOUCH_UI_SELF_TEST_PASS:' "$LOG"
        # The iPad touch run types a password nothing else could hold by chance; it is in no log line.
        # (An `if`, not `! grep`: set -e does not stop on a negated command.)
        if grep -q 'Tp9-Zx!qv7' "$LOG"; then echo "a password reached the log: $LOG" >&2; exit 1; fi
        # iPad touch keeps its own chat and never uses the Composer (its self-test above checks that the
        # review mode is not in force there), so the Composer's card runs in the other interfaces only.
        if [ "$MODE" = "--mobile-interface ipadtouch" ]; then continue; fi
        # The Composer's card and a real guest, in the same interface: the assertions the state
        # machine's own fixture cannot make because it has no window.
        CLOG="build/touch-controls-fixture/composer$NAME.log"
        xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-controls --composer-test $MODE 2>&1 | tee "$CLOG"
        grep -q 'TOUCH_UI_SELF_TEST_PASS: the Composer card' "$CLOG"
        # The same card at an accessibility text size: it has to grow rather than clip, and the
        # editor has to keep its height. UIKit reads the category from this launch argument, so
        # this is the player's own setting, not a stub.
        ALOG="build/touch-controls-fixture/composer$NAME-dynamic-type.log"
        xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.touch-controls \
            --composer-test $MODE -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL 2>&1 | tee "$ALOG"
        grep -q 'TOUCH_UI_SELF_TEST_PASS: the Composer card' "$ALOG"
        grep -q 'chat composer: Dynamic Type UICTContentSizeCategoryAccessibility' "$ALOG"
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
# Same reason as the card's fixture above: the state machine's own defaults have to start empty,
# or the migration case reads a mode a previous run chose.
xcrun simctl uninstall "$SIM_ID" org.tolkara.tests.chat-composer 2> /dev/null || true
xcrun simctl install "$SIM_ID" "$COMPOSER"
COMPOSER_LOG="build/touch-controls-fixture/chat-composer.log"
xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.chat-composer 2>&1 | tee "$COMPOSER_LOG"
grep -q 'CHAT_COMPOSER PASS:' "$COMPOSER_LOG"
# Structured events, asserted from outside the process that printed them: every terminal
# outcome and every entry source has to be visible in the log, and the stale-callback rule has
# to be visible as a refusal rather than as silence.
for EVENT in \
    'chat-composer: open source=0' \
    'chat-composer: open source=1' \
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
