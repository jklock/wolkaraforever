#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
classify() {
    printf '%s\n' "$1" > "$work/native.log"
    printf '%s\n' "$2" > "$work/host.log"
    actual=$(python3 wolkaraforever/tools/classify_external_jit.py --native "$work/native.log" --host "$work/host.log")
    [ "$actual" = "$3" ] || { echo "FAIL: expected $3, got $actual" >&2; exit 1; }
}
classify '[native] guest entry blocked' '' startup-refused
classify '[debugger] something is still attached' '' debugger-attached
classify '[native] arena is not executable' '' arena-unavailable
classify '[native] all 1 initializers returned; entering original main' '1 native-return success' native-return-success
classify '[native] all 1 initializers returned; entering original main' '1 memory-warning' interrupted-after-memory-warning
classify '[native] all 1 initializers returned; entering original main\nFrame readback failed: Error' '' metal-failure-after-original-main
classify '[native] all 1 initializers returned; entering original main' '' interrupted-after-original-main
echo 'PASS: External-JIT log classification'
