#!/bin/bash
# Our own synthetic UI fixture. No game files, accounts or network requests.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
baseline_mode=${UI_BASELINE_MODE:-check}
case "$baseline_mode" in check|record|off) ;; *) echo "invalid UI_BASELINE_MODE: $baseline_mode" >&2; exit 2;; esac
wolkaraforever/tools/prepare.sh
cd build/platform
# The matrix iPad, or the matrix iPhone with `SIMULATOR=iphone`. There is no fallback to
# whatever else this Mac happens to have: the page is laid out for both form factors, so a
# device that is not on the matrix is not a substitute, and the resolver says which device ran
# because "the fixture passed" without a device name is a sentence nobody can check.
simulator_use "${SIMULATOR:-ipad}"
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
    -framework AVFAudio -framework Speech -lz \
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
codesign --force --sign - "$APP" > /dev/null
# The fixture deliberately creates corrupt/legacy metadata states. Start its synthetic app with
# a fresh container so one aborted fixture cannot become evidence for the next matrix run.
xcrun simctl uninstall "$SIM_ID" org.tolkara.tests.wow-launcher > /dev/null 2>&1 || true
xcrun simctl install "$SIM_ID" "$APP"
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
# The fixture exits after its assertions, but simctl can leave the console stream open after
# the process exits. Watch the fixture's explicit verdict so this automated wrapper cannot hang.
xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.wow-launcher "$@" 2>&1 | tee "$LOG" &
LAUNCH=$!
# The fixture guards itself against a hang and prints its own verdict (PASS or TIMEOUT).
# Wait longer than that guard, so the verdict this loop sees is always the fixture's and
# never this wrapper killing a healthy run: the iPad matrix device legitimately needs
# about a minute, and the guard is 180 seconds.
VERDICT_TIMEOUT=${VERDICT_TIMEOUT:-200}
for _ in $(seq 1 "$VERDICT_TIMEOUT"); do
    if grep -qE 'WoW UIKit (PASS:|TIMEOUT)' "$LOG"; then break; fi
    sleep 1
done
kill "$LAUNCH" 2>/dev/null || true
wait "$LAUNCH" 2>/dev/null || true
# simctl can report success even if an assertion terminated the fixture.
grep -q 'WoW UIKit PASS:' "$LOG"
# The images the fixture drew are in its container, which is where anyone wanting to
# look at the launcher's pages has to go looking.
screenshots="$(xcrun simctl get_app_container "$SIM_ID" org.tolkara.tests.wow-launcher data)/Documents"
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
