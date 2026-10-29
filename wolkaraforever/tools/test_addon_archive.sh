#!/bin/bash
# Exercise the production Swift extractor and the app's pinned ZIPFoundation.
#
# Built from the prepared tree rather than from the layer's own paths: the store and the archive
# reader are ours, they resolve each other the way the prepared tree lays them out, and a test
# that compiled them anywhere else would be testing a layout nobody builds.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
root=$PWD
build="$root/build/addon-archive"
mkdir -p "$build"
revision=$(sed -n 's/^+    revision: //p' wolkaraforever/patches/0010*.patch)
package=${ZIPFOUNDATION_SOURCE:-$build/ZIPFoundation}
if [ ! -d "$package/.git" ]; then
    git clone --quiet https://github.com/weichsel/ZIPFoundation.git "$package"
    git -C "$package" checkout --quiet "$revision"
fi
[ "$(git -C "$package" rev-parse HEAD)" = "$revision" ] || { echo 'ZIPFoundation revision differs from the app'; exit 1; }
[ -z "$(git -C "$package" status --porcelain)" ] || { echo 'ZIPFoundation checkout is dirty'; exit 1; }
xcrun swiftc -O -emit-library -emit-module -module-name ZIPFoundation \
    "$package"/Sources/ZIPFoundation/*.swift -o "$build/libZIPFoundation.dylib" \
    -emit-module-path "$build/ZIPFoundation.swiftmodule"
python3 wolkaraforever/tools/tests/make_addon_archives.py "$build/fixtures"

wolkaraforever/tools/prepare.sh
cd build/platform
for source in AddonStore UpdateLock; do
    xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -c "launcher/WoW/$source.m" -o "$build/$source.o"
done
# The store names the strings it shows through the app's localization service, so that file is
# compiled in as it is in the app. Its tables are not in this bundle: the messages are not what
# this test asserts, and the service answers with each key's own leaf name rather than a key.
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -c launcher/App/WKLocalization.m -o "$build/WKLocalization.o"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Ilauncher/WoW -c tests/test_addon_import.m -o "$build/import.o"
xcrun swiftc -warnings-as-errors -I "$build" -L "$build" -lZIPFoundation \
    -Xlinker -rpath -Xlinker "$build" launcher/WoW/AddonArchive.swift \
    tests/test_addon_archive.swift "$build/AddonStore.o" "$build/UpdateLock.o" "$build/import.o" \
    "$build/WKLocalization.o" -o "$build/test_addon_archive"
"$build/test_addon_archive" "$build/fixtures"
