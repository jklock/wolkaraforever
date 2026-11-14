#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

today=$(date +%F)
for doc in docs/agent/*.md docs/agent/roadmap/*.md docs/agent/catalog/*.md; do
    [ -f "$doc" ] || continue
    grep -q "Verified: $today" "$doc" || { echo "check_agent_docs: stale or missing proof: $doc" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R docs/agent/catalog "$tmp/catalog-before"
python3 wolkaraforever/tools/generate_agent_docs.py
if ! diff -ru "$tmp/catalog-before" docs/agent/catalog >/dev/null; then
    echo "check_agent_docs: catalog is stale; run generate_agent_docs.py" >&2
    exit 1
fi

if rg -n '\]\([^)]*docs/agent/' README.md docs COMPATIBILITY.md CHANGELOG.md SECURITY.md NOTICE.md CONTRIBUTORS.md 2>/dev/null; then
    echo "check_agent_docs: human documentation links to agent documentation" >&2
    exit 1
fi

echo "check_agent_docs: OK"
