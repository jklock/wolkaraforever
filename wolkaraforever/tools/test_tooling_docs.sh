#!/bin/bash
# Ensure every tracked layer tool has an audited purpose, safety boundary, and test owner.
set -euo pipefail
cd "$(dirname "$0")/../.."

audit=development/guides/TOOL_AUDIT.md
failures=0

[ -f "$audit" ] || { echo "FAIL missing $audit"; exit 1; }
for heading in 'Inputs' 'Side effect and safety boundary' 'Automated evidence' 'Reference'; do
    if ! grep -Fq "$heading" "$audit"; then
        echo "FAIL $audit is missing $heading"
        failures=$((failures + 1))
    fi
done

while IFS= read -r tool; do
    name=${tool#wolkaraforever/tools/}
    if ! grep -Fq "\`$name\`" "$audit"; then
        echo "FAIL $name is absent from $audit"
        failures=$((failures + 1))
    fi
done < <(git ls-files 'wolkaraforever/tools/*.sh' 'wolkaraforever/tools/*.py' \
    'wolkaraforever/tools/tests/*.sh' 'wolkaraforever/tools/tests/*.py' | sort)

if [ "$failures" -ne 0 ]; then
    echo "TOOLING DOCS FAIL: $failures problem(s)"
    exit 1
fi
echo "TOOLING DOCS PASS: every tracked layer tool is audited"
