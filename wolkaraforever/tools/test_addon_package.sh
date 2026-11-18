#!/bin/bash
# The bundled add-on packages: the committed archives are exactly what the reviewed sources in
# addons/WolkaraRoue (the Interface mobile add-on) and addons/TouchPlay (iPad touch's) produce,
# and the app's verifier refuses every package that is not that one.
#
# The archive and its manifest are built by the same script here, so a source change that
# reaches the ZIP without a new artifact - or an artifact nobody can rebuild - is a
# failure, not a stale file that ships.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
root=$PWD
build="$root/build/addon-package"
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

# 1. The committed artifacts are what the sources produce.
python3 wolkaraforever/tools/package_addon_zip.py --check
python3 wolkaraforever/tools/package_addon_zip.py --addon TouchPlay --check

# 2. ...and the wrong packages the verifier has to refuse. The output directory is cleared
# first: the packager writes the release the TOC names and does not delete what an earlier
# run left behind, so a stale manifest made the glob below expand to two releases and the
# suite handed the verifier the wrong one - it failed on a tree whose sources were fine.
rm -rf "$build/fixtures" "$build/package" "$build/fixtures-touchplay" "$build/package-touchplay"
python3 wolkaraforever/tools/package_addon_zip.py --output "$build/package" \
    --fixtures "$build/fixtures" > /dev/null
release=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["release"])' \
    "$build/package"/WolkaraRoue-*.json)
python3 wolkaraforever/tools/package_addon_zip.py --addon TouchPlay --output "$build/package-touchplay" \
    --fixtures "$build/fixtures-touchplay" > /dev/null
touchplay=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["release"])' \
    "$build/package-touchplay"/TouchPlay-*.json)

# 3. The app's own verifier, from the prepared tree, so it is the code that ships.
wolkaraforever/tools/prepare.sh > /dev/null
cd build/platform
xcrun swiftc -warnings-as-errors -I "$build" -L "$build" -lZIPFoundation \
    -Xlinker -rpath -Xlinker "$build" launcher/WoW/AddonPackage.swift \
    tests/test_addon_package.swift -o "$build/test_addon_package"
"$build/test_addon_package" "$build/fixtures" "$release"
"$build/test_addon_package" "$build/fixtures-touchplay" "$touchplay" TouchPlay
