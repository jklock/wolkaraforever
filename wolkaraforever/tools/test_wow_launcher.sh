#!/bin/bash
# The WoW launcher's suites, run against the prepared tree (build/platform), where the
# layer's files are overlaid at the platform's own paths.
set -euo pipefail
cd "$(dirname "$0")/../.."
. wolkaraforever/tools/env.sh
wolkaraforever/tools/prepare.sh
cd build/platform
mkdir -p build/wow-launcher
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m tests/test_wow_manifest.m \
    -o build/wow-launcher/test_wow_manifest
build/wow-launcher/test_wow_manifest
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m tests/test_wow_client.m \
    -o build/wow-launcher/test_wow_client
build/wow-launcher/test_wow_client
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/Installation.m tests/test_wow_installation.m \
    -o build/wow-launcher/test_wow_installation
build/wow-launcher/test_wow_installation
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m launcher/WoW/UpdateLock.m launcher/WoW/Updater.m \
    launcher/WoW/Installation.m tests/test_wow_update.m \
    -o build/wow-launcher/test_wow_update
build/wow-launcher/test_wow_update
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m tests/test_wow_verification.m \
    -o build/wow-launcher/test_wow_verification
build/wow-launcher/test_wow_verification
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O2 -framework Foundation -lz \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m launcher/WoW/Client.m tools/wow_cdn.m \
    -o build/wow-launcher/wow_cdn
# The device-profile table: which hardware this build knows, what each may be offered, and what
# an unlisted device gets instead. No UIKit, so it runs here.
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation \
    launcher/WoW/DeviceProfile.m tests/test_device_profile.m \
    -o build/wow-launcher/test_device_profile
build/wow-launcher/test_device_profile
# The download speed and the estimate beside the byte counts. No UIKit either: the window, the
# estimate and the words both are written in are values, and a value with one right answer is
# checked here rather than by looking at a picture of it.
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation \
    launcher/WoW/DownloadStatus.m tests/test_wow_download_status.m \
    -o build/wow-launcher/test_wow_download_status
build/wow-launcher/test_wow_download_status
# The Add-on Hub's update resolver and its log line. Foundation only, and under the sanitizers:
# this is the decision every row, the bulk run and the browser handoff read, and the one place a
# value could reach the log that must never be there.
for source in AddonStore AddonUpdateResolver AddonHubLog UpdateLock; do
    xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -O1 -g \
        -fsanitize=address,undefined -fno-omit-frame-pointer -c "launcher/WoW/$source.m" -o "build/wow-launcher/$source.o"
done
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -c launcher/App/WKLocalization.m \
    -o build/wow-launcher/WKLocalization.o
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -c launcher/App/WolkaraForeverLog.m \
    -o build/wow-launcher/WolkaraForeverLog.o
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -Ilauncher/WoW \
    tests/test_addon_resolver.m build/wow-launcher/AddonStore.o build/wow-launcher/AddonUpdateResolver.o \
    build/wow-launcher/AddonHubLog.o build/wow-launcher/UpdateLock.o \
    build/wow-launcher/WKLocalization.o build/wow-launcher/WolkaraForeverLog.o \
    -o build/wow-launcher/test_addon_resolver
build/wow-launcher/test_addon_resolver
