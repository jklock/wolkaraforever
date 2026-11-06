#!/bin/bash
# The UIKit-backed adapters' tests, in the simulator: prepare the tree, then run the
# platform's own translation-simulator suite against it. Our touch controls, gamepad,
# haptics and fonts are in that tree by overlay, so the suite exercises them too.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh
# The platform's script is happy with any simulator on the machine, so resolve the matrix one
# here and pass it down as a UDID. Anything off the matrix is refused before anything builds.
simulator_use "${SIMULATOR:-ipad}"
wolkaraforever/tools/prepare.sh
cd build/platform
exec tools/test_translation_sim.sh "$@"
