#!/bin/bash
# Verify the app AltStore installed, and optionally require its External-JIT runtime evidence.
#
# usage: wolkaraforever/tools/verify_external_jit.sh [--bundle-id identifier] [--require-runtime] [--classify-termination]
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh

bundle=${TOLKARA_BUNDLE_ID:-local.tolkara.app}
require_runtime=0
classify_termination=0
while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-id) shift; bundle=${1:-};;
        --require-runtime) require_runtime=1;;
        --classify-termination) classify_termination=1;;
        -h|--help) sed -n '2,5p' "$0"; exit 0;;
        *) echo "verify_external_jit: unknown option $1" >&2; exit 2;;
    esac
    shift
done
[ -n "${DEVICE:-}" ] || { echo "verify_external_jit: DEVICE is not set" >&2; exit 2; }
[ -n "$bundle" ] || { echo "verify_external_jit: bundle identifier is empty" >&2; exit 2; }

catalogue=$(mktemp)
trap 'rm -f "$catalogue"' EXIT
xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$bundle" --json-output "$catalogue" >/dev/null
python3 - "$catalogue" "$bundle" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    apps = json.load(source).get("result", {}).get("apps", [])
if not any(app.get("bundleIdentifier") == sys.argv[2] for app in apps):
    raise SystemExit("verify_external_jit: app is not installed: " + sys.argv[2])
PY
echo "verify_external_jit: installed $bundle"

if [ "$require_runtime" = 1 ]; then
    log=$(mktemp)
    trap 'rm -f "$catalogue" "$log"' EXIT
    TOLKARA_BUNDLE_ID="$bundle" wolkaraforever/tools/device_log.sh 400 '\[debugger\]|\[native\]' > "$log"
    grep -q '\[debugger\] the arena is still executable' "$log" || {
        echo "verify_external_jit: no executable arena after debugger detachment" >&2; exit 1
    }
    grep -q '\[native\] arena ready' "$log" || {
        echo "verify_external_jit: native arena was not ready" >&2; exit 1
    }
    if grep -Eq 'something is still attached|guest entry blocked|arena is not executable' "$log"; then
        echo "verify_external_jit: runtime refused External-JIT entry" >&2
        exit 1
    fi
    echo "verify_external_jit: External-JIT runtime evidence passed"
fi

if [ "$classify_termination" = 1 ]; then
    TOLKARA_BUNDLE_ID="$bundle" wolkaraforever/tools/device_log.sh 400 . >/dev/null
    native="$PWD/build/device-log/native-guest.log"
    DEVICE_LOG_FILE=external-jit-diagnostics.log TOLKARA_BUNDLE_ID="$bundle" \
        wolkaraforever/tools/device_log.sh 100 . >/dev/null
    host="$PWD/build/device-log-files/external-jit-diagnostics.log"
    outcome=$(python3 wolkaraforever/tools/classify_external_jit.py --native "$native" --host "$host")
    echo "verify_external_jit: termination=$outcome"
    case "$outcome" in
        native-return-success|native-return-stopped) ;;
        *) echo "verify_external_jit: collect both files with the source SHA and report this outcome before retrying" >&2; exit 1;;
    esac
fi
