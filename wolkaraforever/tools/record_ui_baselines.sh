#!/bin/bash
# Record the reviewed launcher baselines. This deliberately refuses accidental updates.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ "${UI_BASELINE_RECORD:-}" != "I_HAVE_APPROVED_THE_UI_CHANGE" ]; then
    echo "record_ui_baselines: set UI_BASELINE_RECORD=I_HAVE_APPROVED_THE_UI_CHANGE" >&2
    exit 2
fi

for simulator in iphone ipad; do
    SIMULATOR="$simulator" UI_BASELINE_MODE=record wolkaraforever/tools/test_wow_launcher_ui.sh
done
