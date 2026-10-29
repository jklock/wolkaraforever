#!/bin/bash
# Verify a locally built unsigned External-JIT IPA before it is handed to a sideloader.
#
# usage: wolkaraforever/tools/verify_ipa.sh <Tolkara-unsigned.ipa> [report-path]
set -euo pipefail
cd "$(dirname "$0")/../.."

ipa=${1:-}
report=${2:-}
[ -n "$ipa" ] && [ -f "$ipa" ] || { echo "usage: wolkaraforever/tools/verify_ipa.sh <ipa> [report-path]" >&2; exit 2; }
[ "$#" -le 2 ] || { echo "verify_ipa: too many arguments" >&2; exit 2; }
case "$ipa" in /*) ;; *) ipa="$PWD/$ipa";; esac
if [ -z "$report" ]; then
    report="${ipa%.ipa}.verification.txt"
elif [[ "$report" != /* ]]; then
    report="$PWD/$report"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -tqq "$ipa"
unzip -qq "$ipa" -d "$tmp"

app="$tmp/Payload/TolkaraDiagnostics.app"
[ -d "$app" ] || { echo "verify_ipa: Payload/TolkaraDiagnostics.app is missing" >&2; exit 1; }
[ "$(find "$tmp/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' | wc -l | tr -d ' ')" = 1 ] || {
    echo "verify_ipa: expected exactly one app under Payload" >&2; exit 1
}
[ ! -e "$app/embedded.mobileprovision" ] || { echo "verify_ipa: provisioning profile present" >&2; exit 1; }
[ ! -d "$app/PlugIns" ] || { echo "verify_ipa: External-JIT IPA must not carry an app extension" >&2; exit 1; }
[ -z "$(find "$app" -name CompatibilityRootCertificates.plist -print -quit)" ] || {
    echo "verify_ipa: Mac root certificates were packaged" >&2; exit 1
}

mode=$(plutil -extract TolkaraPreselectedExecutionMode raw "$app/Info.plist")
runtime=$(plutil -extract TolkaraGuestRuntime raw "$app/Info.plist")
[ "$mode" = external-jit ] || { echo "verify_ipa: expected external-jit, got $mode" >&2; exit 1; }
[ "$runtime" = emulated ] || { echo "verify_ipa: expected emulated guest runtime, got $runtime" >&2; exit 1; }

entitlements="$tmp/entitlements.plist"
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
python3 - "$entitlements" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as source:
    entitlements = plistlib.load(source)
for key in ("com.apple.developer.kernel.increased-memory-limit",
            "com.apple.developer.kernel.extended-virtual-addressing"):
    if entitlements.get(key) is not True:
        raise SystemExit("verify_ipa: missing entitlement " + key)
PY

signature=$(codesign -dvv "$app" 2>&1) || { echo "verify_ipa: app signature is invalid" >&2; exit 1; }
printf '%s\n' "$signature" | grep -qx 'TeamIdentifier=not set' || {
    echo "verify_ipa: IPA carries a signing team" >&2; exit 1
}

sha=$(shasum -a 256 "$ipa" | awk '{print $1}')
revision=$(git rev-parse HEAD)
mkdir -p "$(dirname "$report")"
{
    echo "IPA: $ipa"
    echo "SHA256: $sha"
    echo "Source revision: $revision"
    echo "Bundle: TolkaraDiagnostics.app"
    echo "Execution mode: $mode"
    echo "Guest runtime: $runtime"
    echo "Profile: absent"
    echo "Signing team: absent"
    echo "System root certificates: absent"
    echo "Entitlements: increased-memory-limit, extended-virtual-addressing"
} > "$report"
echo "verify_ipa: PASS ($report)"
