#!/bin/bash
# The Add-on Hub's live run, in the simulator, against the real things.
#
# It builds a small app out of the production page (plus the Swift archive half, so backup and
# restore are the shipped ones), fabricates the installation a player's own folder is - every
# directory the client and the launcher use, with the game's code replaced by a placeholder file -
# and then drives the hub the way a person does: a real CurseForge search, Discover, a real API
# install, a real downloaded archive through the in-app browser, a real Files import, a folder
# found on disk, Link project, Update, Update All, a cancel, a relaunch, and the launcher's own
# backup and restore of the installation.
#
# The page is opened on that fabricated installation's own Interface/AddOns, which is the path the
# launcher's manageAddons route resolves for it.
#
# The whole screen is recorded while it runs. A web view draws in another process, so no in-process
# capture can show its page; a recording of the device can, and it is also the honest record of
# what the run did.
#
# The API key is read from WK_LIVE_API_KEY and handed to the app in its environment. It is never
# written to the repository, the container or the log, and the run asserts the last of those.
#
#   WK_LIVE_API_KEY='$2a$10$...' wolkaraforever/tools/test_addon_hub_live.sh
#   SIMULATOR=ipad WK_LIVE_API_KEY=... wolkaraforever/tools/test_addon_hub_live.sh
#
# Without a key the API steps report NOT RUN and every other step still runs.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
root=$PWD
wolkaraforever/tools/prepare.sh
cd build/platform
simulator_use "${SIMULATOR:-ipad}"
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null

APP=build/addon-hub-live/AddonHubLive.app
APP_ABS=$PWD/$APP
OBJ=build/addon-hub-live/obj
OUT=$PWD/build/addon-hub-live
rm -rf build/addon-hub-live
mkdir -p "$APP" "$OBJ"
# The pinned ZIPFoundation the app itself uses. The archive suite already clones it; reuse that
# checkout and insist on the same revision, so this run links the library the app ships with.
revision=$(sed -n 's/^+    revision: //p' "$root"/wolkaraforever/patches/0010*.patch)
ZIP=${ZIPFOUNDATION_SOURCE:-$root/build/addon-archive/ZIPFoundation}
if [ ! -d "$ZIP/.git" ]; then
    git clone --quiet https://github.com/weichsel/ZIPFoundation.git "$ZIP"
    git -C "$ZIP" checkout --quiet "$revision"
fi
[ "$(git -C "$ZIP" rev-parse HEAD)" = "$revision" ] || { echo 'ZIPFoundation revision differs from the app'; exit 1; }

TARGET="-target arm64-apple-ios17.0-simulator"
SYSROOT=$(xcrun --sdk iphonesimulator --show-sdk-path)
CFLAGS="$TARGET -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-deprecated-declarations -isysroot $SYSROOT"
SFLAGS="$TARGET -sdk $SYSROOT"
INCLUDES="-Ilauncher/App -Ilauncher/Voice -Ilauncher/Input -Ilauncher/Controller -Ilauncher/WoW -Itests"

sources=(launcher/WoW/*.m launcher/App/LaunchProgressView.m launcher/App/WolkaraForeverTheme.m
         launcher/App/WolkaraForeverLog.m launcher/App/WKLocalization.m launcher/App/WolkaraForeverConfig.m
         launcher/Voice/*.m launcher/Input/*.m launcher/Controller/ControllerInspector.m
         tests/addon_hub_live.m tests/addon_hub_live_main.m)
objects=()
for source in "${sources[@]}"; do
    object="$OBJ/$(basename "${source%.*}").o"
    # shellcheck disable=SC2086
    xcrun clang $CFLAGS $INCLUDES -c "$source" -o "$object"
    objects+=("$object")
done

# The Swift half: the ZIP extractor the store finds by name, the archive the launcher's backup and
# restore use, and the bundled-package verifier. Built for the simulator with the same pinned
# ZIPFoundation the app ships.
# shellcheck disable=SC2086
xcrun swiftc $SFLAGS -O -wmo -parse-as-library -emit-object -emit-module \
    -module-name ZIPFoundation -module-link-name ZIPFoundation \
    -emit-module-path "$OBJ/ZIPFoundation.swiftmodule" \
    "$ZIP"/Sources/ZIPFoundation/*.swift -o "$OBJ/ZIPFoundation.o"
# shellcheck disable=SC2086
xcrun swiftc $SFLAGS -O -wmo -parse-as-library -emit-object -emit-module -module-name TolkaraLayer \
    -I "$OBJ" -emit-module-path "$OBJ/TolkaraLayer.swiftmodule" \
    launcher/WoW/ForeverUIArchive.swift launcher/WoW/AddonPackage.swift launcher/WoW/AddonArchive.swift \
    -o "$OBJ/TolkaraLayer.o"

# shellcheck disable=SC2086
xcrun swiftc $SFLAGS -O -I "$OBJ" "${objects[@]}" "$OBJ/ZIPFoundation.o" \
    "$OBJ/TolkaraLayer.o" \
    -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics \
    -framework Security -framework UniformTypeIdentifiers -framework GameController \
    -framework AVFAudio -framework Speech -framework WebKit -framework CryptoKit -lz \
    -o "$APP/AddonHubLive"

cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.addon-hub-live</string>
<key>CFBundleExecutable</key><string>AddonHubLive</string>
<key>CFBundleName</key><string>Add-on Hub live</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST

# The add-on's own language tables, so the page draws its sentences rather than keys.
for LANGUAGE in en de fr; do
    mkdir -p "$APP/$LANGUAGE.lproj"
    cp "launcher/App/$LANGUAGE.lproj/Localizable.strings" "$APP/$LANGUAGE.lproj/"
done
# A real archive for the Files import: a small add-on built here with zip(1), so the run imports
# something that is not already in the fabricated installation.
staging=build/addon-hub-live/staging/LiveImported
mkdir -p "$staging"
printf '## Title: Live Imported\n## Version: 3.0\n## Author: Nobody\n## Interface: 16001\n' > "$staging/LiveImported.toc"
printf -- '-- lua\n' > "$staging/Core.lua"
( cd build/addon-hub-live/staging && zip -qr "$APP_ABS/LiveAddon.zip" LiveImported )
codesign --force --sign - "$APP" > /dev/null
xcrun simctl uninstall "$SIM_ID" org.tolkara.tests.addon-hub-live > /dev/null 2>&1 || true
xcrun simctl install "$SIM_ID" "$APP"
# The page pulls in the launcher's voice source, which asks for the microphone at launch, and a
# WolkaraForever build left by an earlier session can have its own permission alert on the spring
# board. Both are cleared so the recording shows the page and not a system alert.
for bundle in org.tolkara.tests.addon-hub-live local.wolkaraforever.johnklock local.tolkara.app; do
    xcrun simctl privacy "$SIM_ID" grant microphone "$bundle" > /dev/null 2>&1 || true
    xcrun simctl terminate "$SIM_ID" "$bundle" > /dev/null 2>&1 || true
done

echo "add-on hub live: $(simulator_name "$SIM_ID")"
if [ -n "${WK_LIVE_API_KEY:-}" ]; then
    echo "add-on hub live: running with the stored API key"
else
    echo "add-on hub live: no WK_LIVE_API_KEY - the API steps will report NOT RUN"
fi

# The whole screen, recorded. `recordVideo` finishes on SIGINT and writes the file then.
video=$OUT/live-run.mp4
console=$OUT/console.log
: > "$console"
xcrun simctl io "$SIM_ID" recordVideo --codec h264 --force "$video" > /dev/null 2>&1 &
record_pid=$!
sleep 2
started=$(date +%s)

# The key goes in the app's environment, not on disk. `--terminate-running-process` so a previous
# run cannot be what answers.
WK_LIVE_API_KEY="${WK_LIVE_API_KEY:-}" xcrun simctl launch --console-pty \
    --terminate-running-process "$SIM_ID" org.tolkara.tests.addon-hub-live --live-addons \
    > "$console" 2>&1 &
launch_pid=$!
documents="$(xcrun simctl get_app_container "$SIM_ID" org.tolkara.tests.addon-hub-live data)/Documents"
browser_at=""
for _ in $(seq 1 600); do
    if [ -z "$browser_at" ] && [ -f "$documents/browser-ready" ]; then
        browser_at=$(( $(date +%s) - started ))
        : > "$documents/browser-shot-taken"
    fi
    kill -0 "$launch_pid" 2>/dev/null || break
    sleep 0.5
done
wait "$launch_pid" || true
kill -INT "$record_pid" 2>/dev/null || true
wait "$record_pid" 2>/dev/null || true
cat "$console"
if ! grep -q "ADDON HUB LIVE PASS" "$console"; then
    echo "add-on hub live: FAILED" >&2
    grep -E "^LIVE " "$console" || true
    exit 1
fi

# A frame of the in-app browser, from the recording, at the moment the run said the real page was
# on screen. Two seconds in, so the sheet has finished animating under it.
if [ -n "$browser_at" ] && [ -f "$video" ] && command -v ffmpeg > /dev/null; then
    ffmpeg -loglevel error -y -ss "$((browser_at + 2))" -i "$video" -frames:v 1 \
        "$OUT/live-hub-browser-screen.png" || true
fi
echo "add-on hub live: PASS - recording and captures under $OUT"
[ -f "$OUT/live-hub-browser-screen.png" ] && echo "add-on hub live: the in-app browser's page is in $OUT/live-hub-browser-screen.png"
[ -f "$video" ] && echo "add-on hub live: the run is recorded in $video"
echo "--- addon-hub events ---"
grep -F "[addon-hub]" "$documents/wolkaraforever.log" | tail -40 || true
echo "--- captures ---"
ls -1 "$documents"/*.png 2>/dev/null || true
