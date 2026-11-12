#!/bin/bash
# Run an approved WolkaraForever device tool against the separate test app only.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
die() { echo "test_install: $*" >&2; exit 2; }
usage() {
    echo "usage: wolkaraforever/tools/test_install.sh <preflight|install|pilot|device_log|push_game|device_matrix|verify_external_jit> [args]" >&2
    exit 2
}
command=${1:-}; [ -n "$command" ] || usage
shift
case "$command" in preflight|install|pilot|device_log|push_game|device_matrix|verify_external_jit) ;; *) usage;; esac
[ -f "$root/local.env" ] || die "missing local.env for the stable installation"
[ -f "$root/local.test.env" ] || die "missing local.test.env; copy local.test.env.example"

set -a
. "$root/local.env"
stable_bundle=${TOLKARA_BUNDLE_ID:-}
stable_group=${TOLKARA_KEYCHAIN_GROUP:-}
stable_device=${DEVICE:-}
stable_team=${DEVELOPMENT_TEAM:-}
. "$root/local.test.env"
set +a
test_bundle=${TOLKARA_TEST_BUNDLE_ID:-}
test_group=${TOLKARA_TEST_KEYCHAIN_GROUP:-}
test_display=${TOLKARA_TEST_DISPLAY_NAME:-WolkaraForever\ Test}
test_device=${TOLKARA_TEST_DEVICE:-$stable_device}
test_team=${TOLKARA_TEST_DEVELOPMENT_TEAM:-$stable_team}
[ -n "$stable_bundle" ] || die "stable TOLKARA_BUNDLE_ID is empty"
[ -n "$stable_group" ] || die "stable TOLKARA_KEYCHAIN_GROUP is empty"
[ -n "$test_bundle" ] || die "TOLKARA_TEST_BUNDLE_ID is empty"
[ -n "$test_group" ] || die "TOLKARA_TEST_KEYCHAIN_GROUP is empty"
[ "$test_bundle" != "$stable_bundle" ] || die "test bundle must differ from stable bundle"
[ "$test_group" != "$stable_group" ] || die "test Keychain group must differ from stable Keychain group"
[ -n "$test_device" ] || die "test device is empty"

if [ "$command" = push_game ]; then
    have_source=0
    for arg in "$@"; do [ "$arg" = --source ] && have_source=1; done
    [ "$have_source" = 1 ] || die "push_game requires explicit --source for the separate test container"
fi

stable_state() {
    env DEVICE="$stable_device" DEVELOPMENT_TEAM="$stable_team" \
        TOLKARA_BUNDLE_ID="$stable_bundle" TOLKARA_KEYCHAIN_GROUP="$stable_group" \
        "$root/wolkaraforever/tools/pilot.sh" state
}
run_test_tool() {
    env DEVICE="$test_device" DEVELOPMENT_TEAM="$test_team" \
        TOLKARA_BUNDLE_ID="$test_bundle" TOLKARA_KEYCHAIN_GROUP="$test_group" \
        TOLKARA_DISPLAY_NAME="$test_display" \
        PILOT_TEST_INSTALL=I_CONFIRM_TEST_BUNDLE_ONLY \
        "$root/wolkaraforever/tools/$command.sh" "$@"
}

echo "test_install: target $test_display ($test_bundle) on $test_device"
echo "test_install: stable state before"
stable_state
run_test_tool "$@"
echo "test_install: stable state after"
stable_state
