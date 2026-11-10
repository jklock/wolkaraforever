#!/bin/bash
# Run the complete supported launcher matrix with terminal streaming and durable transcripts.
set -euo pipefail
cd "$(dirname "$0")/../.."

mode=${1:---check}
case "$mode" in
    --fixture) baseline_mode=off;;
    --record)
        [ "${UI_BASELINE_RECORD:-}" = "I_HAVE_APPROVED_THE_UI_CHANGE" ] || {
            echo "--record requires UI_BASELINE_RECORD=I_HAVE_APPROVED_THE_UI_CHANGE" >&2; exit 2; }
        baseline_mode=record;;
    --check) baseline_mode=check;;
    *) echo "usage: $0 [--fixture|--record|--check]" >&2; exit 2;;
esac

run_id=$(date '+%Y%m%dT%H%M%S')
log_dir="logs/launcher-matrix/$run_id"
mkdir -p "$log_dir"
summary="$log_dir/SUMMARY.txt"
printf 'launcher matrix: %s\nmode: %s\n' "$run_id" "$mode" | tee "$summary"

run_one() {
    local selector=$1 name=$2
    local log="$log_dir/$name.log"
    printf '\n===== %s (%s) =====\n' "$name" "$selector" | tee -a "$summary"
    if TEST_LOG_PATH="$log" SIMULATOR="$selector" UI_BASELINE_MODE="$baseline_mode" \
        wolkaraforever/tools/test_wow_launcher_ui.sh 2>&1 | tee "$log"; then
        echo "PASS $name" | tee -a "$summary"
    else
        local rc=${PIPESTATUS[0]}
        echo "FAIL $name (exit $rc); transcript: $log" | tee -a "$summary" >&2
        exit "$rc"
    fi
}

run_one iphone iphone-duo
run_one ipad ipad-pro-13-m5
echo "PASS launcher matrix; transcripts: $log_dir" | tee -a "$summary"
