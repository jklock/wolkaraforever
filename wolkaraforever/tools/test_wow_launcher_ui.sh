#!/bin/bash
# Our own synthetic UI fixture. No game files, accounts or network requests.
#
# Modes:
#   (nothing)           assert the pages, then compare them with the reviewed baselines
#                       (`UI_BASELINE_MODE=check|record|off`)
#   --guide-captures    draw every page and sheet once for `docs/UI_REFERENCE.md` and exit;
#                       asserts nothing and compares nothing. See
#                       `wolkaraforever/tools/capture_ui_guide.sh`.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
guide=0
[ "${1:-}" = --guide-captures ] && guide=1
baseline_mode=${UI_BASELINE_MODE:-check}
[ "$guide" = 1 ] && baseline_mode=off
case "$baseline_mode" in check|record|off) ;; *) echo "invalid UI_BASELINE_MODE: $baseline_mode" >&2; exit 2;; esac
wolkaraforever/tools/prepare.sh
cd build/platform
# The matrix iPad, or the matrix iPhone with `SIMULATOR=iphone`. There is no fallback to
# whatever else this Mac happens to have: the page is laid out for both form factors, so a
# device that is not on the matrix is not a substitute, and the resolver says which device ran
# because "the fixture passed" without a device name is a sentence nobody can check.
simulator_use "${SIMULATOR:-ipad}"
# One UI suite per simulator, enforced by simulators.sh: two suites on one device install over
# each other's app, take the foreground from each other and interleave their sheets, and whatever
# runs second reports failures it does not have. Refusing to start is honest; a bogus red lane is
# not.
simulator_ui_lock test_wow_launcher_ui
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
APP=build/wow-launcher/WoWFixture.app
mkdir -p "$APP"
# The launcher is not a page on its own: it opens the add-on and voice pages, so the
# fixture has to link them. It did not, and the link had been failing since the voice
# pages were added - the fixture only ever got as far as the missing symbols.
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Ilauncher/App -Ilauncher/Voice -Ilauncher/Input -Ilauncher/Controller -Ilauncher/WoW -Itests \
    launcher/WoW/*.m launcher/App/LaunchProgressView.m launcher/App/WolkaraForeverTheme.m \
    launcher/App/WolkaraForeverLog.m launcher/App/WKLocalization.m launcher/App/WolkaraForeverConfig.m \
    launcher/Voice/*.m launcher/Input/*.m \
    launcher/Controller/ControllerInspector.m tests/test_wow_launcher_app.m \
    -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics \
    -framework Security -framework UniformTypeIdentifiers -framework GameController \
    -framework AVFAudio -framework Speech -framework WebKit -lz \
    -o "$APP/WoWFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.wow-launcher</string>
<key>CFBundleExecutable</key><string>WoWFixture</string>
<key>CFBundleName</key><string>WoW launcher fixture</string>
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
# The four documents the app's own target bundles, in the same layout and under the same
# names, because the About page reads them by name and by name is how it tells whose is
# whose: the app is a fork, so upstream's stay as LICENSE/NOTICE.md and ours are prefixed.
# A fixture that put them anywhere else would be testing a bundle nobody builds.
#
# This mirrors the app's packaging. That the *real* target carries all four is checked
# against the installed app on the iPad, in wolkaraforever/tools/device_matrix.sh, because a
# fixture that supplies the files can only ever prove how the page composes them.
# The app's own language tables, in the same place the app target puts them: the fixture has to
# be able to answer "which language" the same way the app does, or the German run below would be
# testing a bundle nobody builds.
for LANGUAGE in en de; do
    mkdir -p "$APP/$LANGUAGE.lproj"
    cp "launcher/App/$LANGUAGE.lproj/Localizable.strings" "$APP/$LANGUAGE.lproj/"
done
cp "$ROOT/LICENSE" "$APP/WolkaraForever-LICENSE"
cp "$ROOT/NOTICE.md" "$APP/WolkaraForever-NOTICE.md"
cp "$ROOT/platform/LICENSE" "$APP/LICENSE"
cp "$ROOT/platform/NOTICE.md" "$APP/NOTICE.md"
# And the artwork, compiled the way the app target compiles it. Until 2026-11-12 this fixture
# carried no asset catalog at all: -[WoWViewController markView] asks for "WolkaraForeverLogo",
# fell back to its gold WOLKAREFOREVER wordmark, and all 17 reviewed baselines recorded the
# fallback while a build that had lost the artwork looked exactly the same. A missing actool
# now fails here rather than quietly changing what the pages are made of.
mkdir -p build/wow-launcher
xcrun actool launcher/Assets.xcassets --compile "$APP" \
    --platform iphonesimulator --minimum-deployment-target 17.0 \
    --output-partial-info-plist build/wow-launcher/assets-partial.plist \
    > build/wow-launcher/actool.log 2>&1 || {
    echo "actool could not compile launcher/Assets.xcassets for the fixture" >&2
    tail -20 build/wow-launcher/actool.log >&2
    exit 1
}
[ -f "$APP/Assets.car" ] || { echo "actool produced no Assets.car" >&2; exit 1; }
codesign --force --sign - "$APP" > /dev/null
# The fixture deliberately creates corrupt/legacy metadata states. Start its synthetic app with
# a fresh container so one aborted fixture cannot become evidence for the next matrix run.
xcrun simctl uninstall "$SIM_ID" org.tolkara.tests.wow-launcher > /dev/null 2>&1 || true
xcrun simctl install "$SIM_ID" "$APP"
# `simctl install` can return before the new bundle is what the simulator launches, and a run
# then measures the *previous* build. Both halves of that were measured on 2026-11-12: a launch
# that reported "did not return a process handle" on the iPhone Duo, and an iPad run that
# recorded every baseline from a fixture which still carried no artwork. Compare what is
# installed with what was just built - the executable's size and the compiled catalog - and
# install again when they are not the same, so a recorded image is always the image this run
# compiled.
built_executable=$(stat -f %z "$APP/WoWFixture")
built_catalog=$(stat -f %z "$APP/Assets.car")
fixture_installed() {
    local installed
    installed=$(xcrun simctl get_app_container "$SIM_ID" org.tolkara.tests.wow-launcher app 2>/dev/null) || return 1
    [ -n "$installed" ] || return 1
    [ "$(stat -f %z "$installed/WoWFixture" 2>/dev/null)" = "$built_executable" ] || return 1
    [ "$(stat -f %z "$installed/Assets.car" 2>/dev/null)" = "$built_catalog" ]
}
for attempt in 1 2 3 4 5; do
    fixture_installed && break
    printf '[wrapper] the installed fixture is not the one just built; installing again (attempt %s)\n' "$attempt"
    xcrun simctl uninstall "$SIM_ID" org.tolkara.tests.wow-launcher > /dev/null 2>&1 || true
    xcrun simctl install "$SIM_ID" "$APP"
    sleep 1
done
fixture_installed || { echo "the fixture on the simulator is not the one just built" >&2; exit 1; }
# Keep every transcript when invoked directly; matrix runners pass TEST_LOG_PATH so their
# summary can link to the exact failing simulator log. Output still streams to the terminal.
#
# One writer per file, and always an absolute path. This code runs after `cd build/platform`,
# so a relative path lands in the prepared tree - and prepare.sh rebuilds that tree, which
# deleted the iPhone console before anyone could read it on 2026-11-09. The runner's own log
# is already absolute for the same reason.
if [ -n "${TEST_LOG_PATH:-}" ]; then
    LOG="${TEST_LOG_PATH%.log}.fixture.log"
else
    LOG="logs/ui-fixtures/$(date '+%Y%m%dT%H%M%S')-$(printf '%s' "${SIM_NAME:-ipad}" | tr ' ()' '__').log"
fi
case "$LOG" in /*) ;; *) LOG="$ROOT/$LOG";; esac
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
# `simctl install` can return before the simulator's launch database knows the bundle, and a
# launch in that window fails with "did not return a process handle nor launch error" and no
# console at all - measured on the iPhone Duo at 17:03 on 2026-11-12, where the same bundle
# launched on the next attempt without anything being rebuilt. Wait for the bundle to be
# listed, then retry a launch that never reached the fixture, so the verdict window below is
# spent on a fixture that ran instead of on one that was never started.
for _ in $(seq 1 40); do
    xcrun simctl listapps "$SIM_ID" 2>/dev/null | grep -q org.tolkara.tests.wow-launcher && break
    sleep 0.5
done
# The fixture exits after its assertions, but simctl can leave the console stream open after
# the process exits. Watch the fixture's explicit verdict so this automated wrapper cannot hang.
launch_fixture() {
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" \
        org.tolkara.tests.wow-launcher "$@" 2>&1 | tee -a "$LOG" &
    LAUNCH=$!
    # The fixture's own first line, written before any assertion runs.
    for _ in $(seq 1 40); do
        grep -q 'launcher fixture .* launched' "$LOG" && return 0
        kill -0 "$LAUNCH" 2>/dev/null || break
        sleep 0.25
    done
    return 1
}
attempt=1
while ! launch_fixture "$@"; do
    printf '[wrapper] launch attempt %s never started the fixture\n' "$attempt" >> "$LOG"
    kill "$LAUNCH" 2>/dev/null || true
    wait "$LAUNCH" 2>/dev/null || true
    if [ "$attempt" -ge 3 ]; then
        echo "the fixture could not be launched in 3 attempts" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 2
done
# The fixture guards itself against a hang and prints its own verdict (PASS, TIMEOUT, or FAIL,
# which it now prints itself when an assertion does not hold). Wait only until one of those
# arrives. Before the fixture owned its failure the wrapper waited out this whole window on a
# run that had already finished: abort() leaves simctl's console stream open, so nothing here
# could tell "still running" from "died at line 2891".
#
# How long the runner waits for the fixture's answer. The fixture carries its own hang guard and
# prints TIMEOUT when it fires, and this loop breaks on that too - so this only has to outlast the
# guard by enough that a slow machine is never killed here and reported as a failure it did not
# have. A false timeout costs more than a long run.
VERDICT_TIMEOUT=${VERDICT_TIMEOUT:-960}
verdict_re='WoW UIKit (PASS:|TIMEOUT|FAIL:)'
[ "$guide" = 1 ] && verdict_re='WoW UIKit (GUIDE: done|TIMEOUT|FAIL:)'
for _ in $(seq 1 "$VERDICT_TIMEOUT"); do
    if grep -qE "$verdict_re" "$LOG"; then break; fi
    sleep 1
done
kill "$LAUNCH" 2>/dev/null || true
wait "$LAUNCH" 2>/dev/null || true
# simctl can report success even if an assertion terminated the fixture, so the verdict decides.
# Say which one it gave, so a failure is a sentence rather than an exit code.
if grep -q 'WoW UIKit FAIL:' "$LOG"; then
    grep -m1 'WoW UIKit FAIL:' "$LOG" >&2
    exit 1
fi
if grep -q 'WoW UIKit TIMEOUT' "$LOG"; then
    echo "the launcher fixture hit its own hang guard" >&2
    exit 1
fi
if [ "$guide" = 1 ]; then
    grep -q 'WoW UIKit GUIDE: done' "$LOG" || {
        echo "the guide capture walk gave no verdict within ${VERDICT_TIMEOUT}s; last lines:" >&2
        tail -8 "$LOG" >&2
        exit 1
    }
else
if ! grep -q 'WoW UIKit PASS:' "$LOG"; then
    echo "the launcher fixture gave no verdict within ${VERDICT_TIMEOUT}s; last lines:" >&2
    tail -8 "$LOG" >&2
    exit 1
fi
fi
# The images the fixture drew are in its container, which is where anyone wanting to
# look at the launcher's pages has to go looking.
screenshots="$(xcrun simctl get_app_container "$SIM_ID" org.tolkara.tests.wow-launcher data)/Documents"
# The launcher fixture draws the Battery Saver submenu too, but a sheet's translucent backdrop
# carries a frozen picture of the page behind it - including the version line's wall clock, which
# the fixture pins only for the page itself. Compared across two identical iPhone runs the same
# message region differed by 11/255, so that sheet is asserted by its title, message and action
# list rather than by a baseline, and its capture in the fixture's Documents is a picture for the
# guide, not a reviewed layout.
states=(wow-home.png wow-home-large-text.png addons-popup.png voice-settings.png voice-test.png
        wow-home-de.png wow-addons-de.png wow-voice-de.png wow-voice-test-de.png
        wow-home-de-large-text.png wow-starting.png wow-running.png wow-startup-failed.png
        wow-downloading.png wow-launcher-ipados.png wow-launcher-duo.png
        wow-addons-recommended-wolkararoue.png)
# The baseline directory is named after the device that drew the pages, not after the
# selector that asked for it: simulator_use has replaced SIMULATOR with the UDID by
# now, and a UDID is not a directory name. Reading SIM_NAME also means a run that
# named the device directly lands in the same place the matrix does.
case "$SIM_NAME" in
    "iPhone Duo"*) baseline_device=iphone-duo;;
    "iPad Pro 13-inch"*) baseline_device=ipad-pro-13-m5;;
    *) echo "unexpected matrix device: $SIM_NAME" >&2; exit 2;;
esac
baseline="${ROOT}/wolkaraforever/WoW/tests/ui-baselines/launcher/$baseline_device"
if [ "$baseline_mode" = record ]; then
    mkdir -p "$baseline"
    for state in "${states[@]}"; do cp "$screenshots/$state" "$baseline/$state"; done
elif [ "$baseline_mode" = check ]; then
    comparator=build/wow-launcher/compare_ui_baselines
    # Absolute for the source: this runs after `cd build/platform`, where the tool path does
    # not exist. The binary stays beside the fixture app it is comparing. `-O` matters: the
    # comparison reads about 2.8 million pixels per page, and an unoptimised build took over
    # a minute per device.
    xcrun swiftc -O "$ROOT/wolkaraforever/tools/compare_ui_baselines.swift" -framework CoreGraphics -framework ImageIO -o "$comparator"
    "$comparator" "$baseline" "$screenshots" "${states[@]}"
fi
echo "screenshots: $screenshots"
