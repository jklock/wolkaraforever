#!/bin/bash
# The enrolment reference, in the simulator, against the real Keychain.
#
# The Mac suite (test_authorization_handoff.sh) proves the decision table with an
# injected backend. This proves the two things only a device can: that the
# reference really is a second item in our protected access group, and that it
# survives the container being replaced - which is the whole reason the file
# exists. `simctl uninstall` deletes the container exactly as a reinstall does,
# and the Keychain is left alone exactly as a reinstall leaves it.
#
# Our own synthetic record only: the storage probe's deterministic fixture, its
# reference, and the marker under the same identifier. No real enrolment, no
# pairing material and no game file is involved, and every mode removes what it
# wrote.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
simulator_use "${SIMULATOR:-ipad}"
wolkaraforever/tools/prepare.sh
cd build/platform
BUNDLE="${TOLKARA_BUNDLE_ID}.storageprobe"
DERIVED=build/storageprobe-enrollment
# This Mac's Xcode keeps products in a shared build directory, and other worktrees
# build there at the same time. The probe gets its own, so a run can neither read
# nor disturb what somebody else is building.
APP="$DERIVED/products/Debug-iphonesimulator/StorageProbe.app"
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
mkdir -p "$(dirname "$APP")"
xcodebuild -project Tolkara.xcodeproj -scheme StorageProbe -destination "platform=iOS Simulator,id=$SIM_ID" \
    -configuration Debug -derivedDataPath "$DERIVED" \
    SYMROOT="$PWD/$DERIVED/products" OBJROOT="$PWD/$DERIVED/intermediates" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" build \
    > build/storageprobe-enrollment.log 2>&1 || { tail -20 build/storageprobe-enrollment.log >&2; echo "the storage probe did not build" >&2; exit 1; }
[ -d "$APP" ] || { echo "the storage probe built no app at $APP" >&2; exit 1; }

install_probe() {
    xcrun simctl install "$SIM_ID" "$APP"
    # simctl can return before the launch database knows the bundle.
    for _ in $(seq 1 40); do
        xcrun simctl listapps "$SIM_ID" 2>/dev/null | grep -q "$BUNDLE" && return 0
        sleep 0.25
    done
    echo "the storage probe never appeared in the simulator's launch database" >&2
    return 1
}
uninstall_probe() { xcrun simctl uninstall "$SIM_ID" "$BUNDLE" > /dev/null 2>&1 || true; }

failures=0
report() { printf '%s %s\n' "$1" "$2"; }
# One mode, one process, one report file. The report is read back from the app's
# own container, which is what any later reader of this evidence would do.
probe() {
    local mode=$1 container text
    container=$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE" data 2>/dev/null || true)
    [ -n "$container" ] || { report "FAIL" "$mode: the probe is not installed"; failures=$((failures+1)); return 0; }
    rm -f "$container/Documents/storage-probe.txt"
    xcrun simctl launch --terminate-running-process "$SIM_ID" "$BUNDLE" "--storage-enrollment-$mode" > /dev/null 2>&1 || true
    for _ in $(seq 1 200); do
        [ -f "$container/Documents/storage-probe.txt" ] && break
        sleep 0.1
    done
    if [ ! -f "$container/Documents/storage-probe.txt" ]; then
        report "FAIL" "$mode: no report"; failures=$((failures+1)); return 0
    fi
    text=$(cat "$container/Documents/storage-probe.txt")
    case "$text" in
        PASS:*) report "PASS" "$mode: ${text#PASS: }";;
        *) report "FAIL" "$mode: $text"; failures=$((failures+1));;
    esac
}

uninstall_probe
install_probe
# An enrolled app derives its reference from the record it already trusts.
probe write
# A reinstall: the container, and with it the marker, is gone. The Keychain is not.
uninstall_probe
install_probe
# This is the one that could not pass before the reference existed: with no
# marker and a surviving record, the launcher said "not enrolled".
probe recover
# And the marker it put back is read by a later process, not just this one.
probe marker
# A reference that cannot be parsed is refused and removed, never used.
probe malformed
# Derived again, because a refused reference is not left half-usable.
probe write
probe lost-marker
# The reference outlived its record: nothing is restored.
probe stale
# A record for that identifier exists but is not the one the reference names:
# nothing is restored and the pin is not overwritten.
probe write
probe lost-marker
probe mismatch
# A marker that is not an identifier is never replaced.
probe invalid-marker
probe clean
uninstall_probe

if [ "$failures" -eq 0 ]; then
    echo "ENROLLMENT REFERENCE SIM PASS: derived, survived a reinstall, recovered, re-read by a later"
    echo "launch, and refused stale, mismatching, malformed and unusable-marker states; fixture removed."
else
    echo "ENROLLMENT REFERENCE SIM FAIL: $failures case(s) did not hold" >&2
    exit 1
fi
