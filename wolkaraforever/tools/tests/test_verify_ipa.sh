#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
app="$tmp/Payload/TolkaraDiagnostics.app"
mkdir -p "$app"
cp /usr/bin/true "$app/TolkaraDiagnostics"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TolkaraDiagnostics</string>
<key>TolkaraPreselectedExecutionMode</key><string>external-jit</string>
<key>TolkaraGuestRuntime</key><string>emulated</string>
</dict></plist>
PLIST
cat > "$tmp/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.developer.kernel.increased-memory-limit</key><true/>
<key>com.apple.developer.kernel.extended-virtual-addressing</key><true/>
</dict></plist>
PLIST
codesign -f -s - --entitlements "$tmp/entitlements.plist" "$app"
(cd "$tmp" && zip -qry valid.ipa Payload)
wolkaraforever/tools/verify_ipa.sh "$tmp/valid.ipa" "$tmp/report.txt"
grep -q '^Execution mode: external-jit$' "$tmp/report.txt"
grep -q '^Signing team: absent$' "$tmp/report.txt"

touch "$app/embedded.mobileprovision"
(cd "$tmp" && zip -qry invalid.ipa Payload)
if wolkaraforever/tools/verify_ipa.sh "$tmp/invalid.ipa" >/dev/null 2>&1; then
    echo "FAIL: verifier accepted a provisioning profile" >&2
    exit 1
fi
echo "PASS: verify_ipa accepts the required unsigned package and rejects a profile"
