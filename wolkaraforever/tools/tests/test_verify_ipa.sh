#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."

# The packager refuses a roots-less build before it builds anything, so this costs no compile.
if TOLKARA_SYSTEM_ROOTS=NO wolkaraforever/tools/package_ipa.sh "$PWD/build/test-ipa-refused.ipa" \
        > /dev/null 2>&1; then
    echo "FAIL: package_ipa.sh built with TOLKARA_SYSTEM_ROOTS=NO" >&2
    exit 1
fi

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
# The public root certificates a source build carries. Their contents do not matter here; that
# the package has them does.
python3 - "$app" <<'PY'
import plistlib, sys
with open(sys.argv[1] + "/CompatibilityRootCertificates.plist", "wb") as target:
    plistlib.dump([b"\x30\x03\x02\x01\x01", b"\x30\x03\x02\x01\x02"], target)
PY
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
grep -q '^System root certificates: present (2)$' "$tmp/report.txt"

# The roots are the difference this test exists for: without them no login can succeed.
mv "$app/CompatibilityRootCertificates.plist" "$tmp/roots.plist"
(cd "$tmp" && rm -f roots.ipa && zip -qry roots.ipa Payload)
if wolkaraforever/tools/verify_ipa.sh "$tmp/roots.ipa" > /dev/null 2>&1; then
    echo "FAIL: verifier accepted a package with no system root certificates" >&2
    exit 1
fi
python3 - "$app" <<'PY'
import plistlib, sys
with open(sys.argv[1] + "/CompatibilityRootCertificates.plist", "wb") as target:
    plistlib.dump([], target)
PY
(cd "$tmp" && zip -qry roots.ipa Payload)
if wolkaraforever/tools/verify_ipa.sh "$tmp/roots.ipa" > /dev/null 2>&1; then
    echo "FAIL: verifier accepted an empty system root certificate list" >&2
    exit 1
fi
mv "$tmp/roots.plist" "$app/CompatibilityRootCertificates.plist"

touch "$app/embedded.mobileprovision"
(cd "$tmp" && zip -qry invalid.ipa Payload)
if wolkaraforever/tools/verify_ipa.sh "$tmp/invalid.ipa" >/dev/null 2>&1; then
    echo "FAIL: verifier accepted a provisioning profile" >&2
    exit 1
fi
echo "PASS: verify_ipa accepts the source-build package and rejects a missing or empty root list and a profile"
