#!/bin/bash
# Run the app: prepare the tree, then run the platform's own run script against it.
# `wolkaraforever/tools/run.sh sim` for the loader diagnostics in the simulator, or a device
# as that script documents.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
# Simulator runs use the matrix iPad (or `SIMULATOR=iphone`) and hand the platform's own script
# the device as a UDID, so it cannot pick a different simulator for itself. Device runs are
# unaffected: the physical iPad is the third row of the matrix and is named by DEVICE.
if [ "${1:-sim}" = sim ]; then
    simulator_use "${SIMULATOR:-ipad}"
fi
wolkaraforever/tools/prepare.sh
cd build/platform
exec tools/run.sh "$@"
