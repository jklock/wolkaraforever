#!/bin/bash
# The app's own language: resolving it, reading the tables, choosing a plural, formatting a
# string, and announcing a change.
#
# Foundation only, on the Mac: none of that has any UI in it, and a suite that needed a booted
# simulator would be run less often than the thing it protects. The parts that do need UIKit -
# the config file's migration and the German screen flow - are in the launcher fixture
# (wolkaraforever/tools/test_wow_launcher_ui.sh) and are named in the PASS line there.
#
#   wolkaraforever/tools/test_localization.sh
#
# Exit status is the suite's: 0 all checks passed, 1 at least one failed, 2 nothing could be run.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
root=$PWD
build="$root/build/localization"
mkdir -p "$build"

wolkaraforever/tools/prepare.sh
cd build/platform

xcrun --sdk macosx clang -fobjc-arc -O1 -g -arch arm64 -mmacosx-version-min=14.0 \
    -Wall -Wextra -Werror -Wno-deprecated-declarations -Ilauncher/App \
    launcher/App/WKLocalization.m tests/test_localization.m \
    -framework Foundation -o "$build/test_localization"

# The tables, in the layout the app has them: a command-line tool's main bundle is the folder its
# executable lives in, so the copies beside it are what the service reads - the prepared tree's own
# en.lproj and de.lproj, so what is read is what ships.
cp -R launcher/App/en.lproj launcher/App/de.lproj "$build/"
cd "$build"
./test_localization
