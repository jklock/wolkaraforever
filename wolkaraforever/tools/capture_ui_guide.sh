#!/bin/bash
# Draw every launcher page and sheet once, for the user guide, and put the pictures in
# docs/screenshots/ as `ui-<name>.jpg`.
#
#   usage: wolkaraforever/tools/capture_ui_guide.sh
#
# This is a capture walk, not a test: `test_wow_launcher_ui.sh --guide-captures` asserts nothing
# and compares nothing. The reviewed baselines stay where they are, and `check_ui_policy.sh` is
# still the gate on them.
#
# One device, always the matrix iPad: the guide's pictures are of one layout, and two form factors
# interleaved in one folder would make the guide describe whichever ran last. `iPhone Duo` is where
# [Use WolkaraForever on iPhone](../docs/IPHONE.md) sends a reader, and the phone layout it
# documents is drawn by the same pages at a narrower size.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "$#" -eq 0 ] || { echo "usage: wolkaraforever/tools/capture_ui_guide.sh" >&2; exit 2; }
. wolkaraforever/tools/env.sh
. wolkaraforever/tools/simulators.sh

# The images the guide embeds. A name that the walk did not draw fails this script, so a page that
# stopped opening cannot leave the guide pointing at a picture of the page underneath it.
names=(home edition preferences language device-profile render-profile battery-saver
       interface-mode layout-create layout-editor voice-page touchpad-page
       addons-myaddons settings settings-failed about)

output=$(wolkaraforever/tools/test_wow_launcher_ui.sh --guide-captures)
printf '%s\n' "$output" | tail -2
screenshots=$(printf '%s\n' "$output" | sed -n 's/^screenshots: //p' | tail -1)
[ -n "$screenshots" ] && [ -d "$screenshots" ] || {
    echo "capture_ui_guide: the walk did not say where its pictures are" >&2; exit 1; }

mkdir -p docs/screenshots
missing=0
for name in "${names[@]}"; do
    source="$screenshots/guide-$name.png"
    if [ ! -s "$source" ]; then echo "capture_ui_guide: no guide-$name.png" >&2; missing=1; continue; fi
    # 1400 px wide is enough to read every row and keeps the tracked file small; the full-size
    # PNG stays in the simulator container for anyone who wants to look closely.
    sips -Z 1400 -s format jpeg -s formatOptions 80 "$source" \
        --out "docs/screenshots/ui-$name.jpg" > /dev/null
    printf '  docs/screenshots/ui-%s.jpg\n' "$name"
done
[ "$missing" = 0 ] || { echo "capture_ui_guide: some pages did not open; see the fixture log" >&2; exit 1; }
echo "capture_ui_guide: ${#names[@]} pages written"
