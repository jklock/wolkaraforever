#!/bin/bash
# Preserve one device log as a named, immutable gameplay-capture artifact.
#
# usage: wolkaraforever/tools/capture_gameplay_log.sh <baseline|candidate|label>
#
# device_log.sh intentionally refreshes build/device-log on every invocation.
# This wrapper copies the complete raw log before the next fetch can replace it.
set -euo pipefail
cd "$(dirname "$0")/../.."

label=${1:-}
case "$label" in
    ''|*[!A-Za-z0-9_-]*)
        echo "usage: wolkaraforever/tools/capture_gameplay_log.sh <baseline|candidate|label>" >&2
        echo "label may contain only letters, digits, _ and -" >&2
        exit 2
        ;;
esac

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
revision=$(git rev-parse --short HEAD)
capture_dir="build/gameplay-captures/${timestamp}-${label}-${revision}"
mkdir -p "$capture_dir"

wolkaraforever/tools/device_log.sh 0
cp build/device-log/native-guest.log "$capture_dir/native-guest.log"

{
    printf 'label=%s\n' "$label"
    printf 'captured_at_utc=%s\n' "$timestamp"
    printf 'git_revision=%s\n' "$(git rev-parse HEAD)"
    printf 'device=%s\n' "${DEVICE:-from-local.env}"
    printf 'launch_arguments=record separately; required for comparison\n'
} > "$capture_dir/metadata.txt"

echo "gameplay capture: $capture_dir/native-guest.log"
echo "metadata: $capture_dir/metadata.txt"
