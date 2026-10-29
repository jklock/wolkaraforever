#!/bin/bash
# The Forever UI operations' own tests: the Config.wtf rules and the archive.
#
# The archive tests use the production Swift writer/restorer against the same pinned ZIPFoundation
# the app links. No game, no simulator and no network beyond the package clone that the add-on
# archive test already performs.
#
# Built from the prepared tree, like every other suite that links layer code: the Config.wtf rules
# now name their messages through the app's own localization service, and that file lives beside
# the app's other sources in the prepared tree, not beside the rules.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
root=$PWD
build="$root/build/forever-ui"
mkdir -p "$build"

# Same pin as the app (patch 0010 declares it).
revision=$(sed -n 's/^+    revision: //p' wolkaraforever/patches/0010*.patch)
package=${ZIPFOUNDATION_SOURCE:-$root/build/addon-archive/ZIPFoundation}
if [ ! -d "$package/.git" ]; then
    git clone --quiet https://github.com/weichsel/ZIPFoundation.git "$package"
    git -C "$package" checkout --quiet "$revision"
fi
[ "$(git -C "$package" rev-parse HEAD)" = "$revision" ] || { echo 'ZIPFoundation revision differs from the app'; exit 1; }
[ -z "$(git -C "$package" status --porcelain)" ] || { echo 'ZIPFoundation checkout is dirty'; exit 1; }
if [ ! -f "$build/libZIPFoundation.dylib" ]; then
    xcrun swiftc -O -emit-library -emit-module -module-name ZIPFoundation \
        "$package"/Sources/ZIPFoundation/*.swift -o "$build/libZIPFoundation.dylib" \
        -emit-module-path "$build/ZIPFoundation.swiftmodule"
fi

wolkaraforever/tools/prepare.sh
cd build/platform

# The Config.wtf rules. The localization service is linked in as it is in the app; this bundle has
# no string tables, and the rules' own messages are not what this suite asserts.
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Ilauncher/WoW -c launcher/WoW/ForeverUI.m -o "$build/ForeverUI.o"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -c launcher/App/WKLocalization.m -o "$build/WKLocalization.o"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Ilauncher/WoW -c tests/test_forever_config.m -o "$build/test_forever_config.o"
xcrun clang -fobjc-arc "$build/ForeverUI.o" "$build/WKLocalization.o" "$build/test_forever_config.o" \
    -framework Foundation -o "$build/test_forever_config"
"$build/test_forever_config"

# The archive writer and restorer.
xcrun swiftc -warnings-as-errors -I "$build" -L "$build" -lZIPFoundation \
    -Xlinker -rpath -Xlinker "$build" \
    launcher/WoW/ForeverUIArchive.swift \
    tests/test_forever_ui_archive.swift \
    -o "$build/test_forever_ui_archive"
"$build/test_forever_ui_archive"
