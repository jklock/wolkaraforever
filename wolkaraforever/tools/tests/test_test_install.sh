#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
work=$(mktemp -d -t test-install)
trap 'rm -rf "$work"' EXIT
tree="$work/tree"
mkdir -p "$tree/wolkaraforever/tools"
cp "$root/wolkaraforever/tools/test_install.sh" "$tree/wolkaraforever/tools/"
for tool in pilot preflight install device_log push_game device_matrix verify_external_jit; do
    cat > "$tree/wolkaraforever/tools/$tool.sh" <<'EOF'
#!/bin/bash
printf '%s:%s:%s:%s:%s\n' "$(basename "$0" .sh)" "${TOLKARA_BUNDLE_ID:-}" "${TOLKARA_KEYCHAIN_GROUP:-}" "${TOLKARA_DISPLAY_NAME:-}" "$*" >> "${TEST_INSTALL_LOG:?}"
EOF
    chmod +x "$tree/wolkaraforever/tools/$tool.sh"
done
cat > "$tree/local.env" <<'EOF'
DEVICE=STABLE-DEVICE
DEVELOPMENT_TEAM=STABLE-TEAM
TOLKARA_BUNDLE_ID=stable.bundle
TOLKARA_KEYCHAIN_GROUP=stable.bundle.authorization
EOF
cat > "$tree/local.test.env" <<'EOF'
TOLKARA_TEST_BUNDLE_ID=test.bundle
TOLKARA_TEST_KEYCHAIN_GROUP=test.bundle.authorization
TOLKARA_TEST_DISPLAY_NAME="WolkaraForever Test"
EOF
log="$work/log"
TEST_INSTALL_LOG="$log" "$tree/wolkaraforever/tools/test_install.sh" preflight
[ "$(grep -c '^pilot:stable.bundle:stable.bundle.authorization::state$' "$log")" = 2 ]
grep -q '^preflight:test.bundle:test.bundle.authorization:WolkaraForever Test:$' "$log"
if TEST_INSTALL_LOG="$log" "$tree/wolkaraforever/tools/test_install.sh" push_game --dry-run >/dev/null 2>&1; then exit 1; fi
if TEST_INSTALL_LOG="$log" "$tree/wolkaraforever/tools/test_install.sh" remove_game >/dev/null 2>&1; then exit 1; fi
printf 'TOLKARA_TEST_BUNDLE_ID=stable.bundle\nTOLKARA_TEST_KEYCHAIN_GROUP=test.bundle.authorization\n' > "$tree/local.test.env"
if TEST_INSTALL_LOG="$log" "$tree/wolkaraforever/tools/test_install.sh" preflight >/dev/null 2>&1; then exit 1; fi
echo "TEST_INSTALL PASS: stable guard, allowed routing, test identity, explicit game source"
