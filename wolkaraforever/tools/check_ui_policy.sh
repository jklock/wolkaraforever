#!/bin/bash
# Enforce the reviewed launcher baseline and its review record.
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

# The reviewed baselines are the policy: they are tracked source, and the two runs at the end
# compare each matrix device against them. The documents that used to state the rule were
# removed from the tracked set, so this asserts what still exists and still runs - otherwise
# the check failed forever on files nobody could restore, and its real work stopped running.
test -x wolkaraforever/tools/record_ui_baselines.sh
test -f wolkaraforever/tools/compare_ui_baselines.swift
test -d wolkaraforever/WoW/tests/ui-baselines/launcher/iphone-duo
test -d wolkaraforever/WoW/tests/ui-baselines/launcher/ipad-pro-13-m5
rg -q 'WKPopupMaximumScreenFraction.*0\.85|0\.85' wolkaraforever/Shell/WolkaraForeverTheme.m

if [ -n "$review" ]; then
    review_path=$review
    [ -f "$review_path" ] || {
        echo "check_ui_policy: no review record at $review_path (pass the record's path)" >&2
        exit 1
    }
    rg -q '^# UI review:' "$review_path"
    rg -q '^## Classification' "$review_path"
    rg -q '^## End-user action' "$review_path"
    rg -q '^## Risks and boundary' "$review_path"
fi

SIMULATOR=iphone UI_BASELINE_MODE=check wolkaraforever/tools/test_wow_launcher_ui.sh
SIMULATOR=ipad UI_BASELINE_MODE=check wolkaraforever/tools/test_wow_launcher_ui.sh
echo "UI policy: PASS"
