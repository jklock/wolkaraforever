#!/bin/bash
# Regenerate and open the disposable Xcode project used for local development.
#
# usage: wolkaraforever/tools/open_xcode.sh [--no-open]
set -euo pipefail
cd "$(dirname "$0")/../.."

open_project=1
case "${1:-}" in
    "") ;;
    --no-open) open_project=0 ;;
    *) echo "usage: wolkaraforever/tools/open_xcode.sh [--no-open]" >&2; exit 2;;
esac

wolkaraforever/tools/generate.sh
project=build/platform/Tolkara.xcodeproj
[ -d "$project" ] || { echo "open_xcode: generator did not create $project" >&2; exit 1; }
xcodebuild -project "$project" -list >/dev/null

if [ "$open_project" = 1 ]; then
    open -a Xcode "$project"
fi
echo "open_xcode: $project"
