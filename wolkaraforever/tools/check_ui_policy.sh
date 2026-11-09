#!/bin/bash
# Enforce the immutable WolkaraForever launcher baseline and its review record.
set -euo pipefail
cd "$(dirname "$0")/../.."

review=""
while [ $# -gt 0 ]; do
    case "$1" in
        --review) shift; review=${1:-};;
        *) echo "usage: $0 [--review <record>]" >&2; exit 2;;
    esac
    shift
done

test -f development/architecture/UI_POLICY.md
test -f development/architecture/LAUNCHER_UI_BASELINE.md
test -x wolkaraforever/tools/record_ui_baselines.sh
test -f wolkaraforever/tools/compare_ui_baselines.swift
rg -q 'bounds.*700|700 points' development/architecture/DEVICE_CONTRACT.md
rg -q 'WKPopupMaximumScreenFraction.*0\.85|0\.85' wolkaraforever/Shell/WolkaraForeverTheme.m

if [ -n "$review" ]; then
    case "$review" in
        /*) review_path=$review;;
        *) review_path="development/reviews/ui/$review";;
    esac
    test -f "$review_path"
    rg -q '^# UI review:' "$review_path"
    rg -q '^## Classification' "$review_path"
    rg -q '^## End-user action' "$review_path"
    rg -q '^## Risks and boundary' "$review_path"
fi

SIMULATOR=iphone UI_BASELINE_MODE=check wolkaraforever/tools/test_wow_launcher_ui.sh
SIMULATOR=ipad UI_BASELINE_MODE=check wolkaraforever/tools/test_wow_launcher_ui.sh
echo "UI policy: PASS"
