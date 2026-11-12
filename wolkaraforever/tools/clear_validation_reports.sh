#!/bin/bash
# Remove only local reports produced by validate.sh. These reports are a pre-release
# decision aid and must not become PR or release artifacts.
set -euo pipefail

cd "$(dirname "$0")/../.."
report_dir="$PWD/logs/validation"

if [ -d "$report_dir" ]; then
    find "$report_dir" -type f -name '*.md' -delete
    rmdir "$report_dir" 2>/dev/null || true
fi

echo "clear_validation_reports: local validation reports removed"
