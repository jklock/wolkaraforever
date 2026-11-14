#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# A proof line must exist, and it is provenance: it names the revision and the day the catalog
# was generated against. It is not the gate.
#
# It used to require *today's* date, and the freshness check below compared the catalog
# byte-for-byte including the revision the generator stamps into every row. Both made the gate
# impossible to pass on a committed tree: the generator writes the commit it ran at, so
# committing the catalog changes the stamp it wrote, and a tree verified yesterday failed today
# with nothing changed. Measured on main at 8c1-follow, 2026-11-13: `check_agent_docs.sh`
# reported "catalog is stale" on the commit that had just added the refreshed catalog.
#
# What the catalog actually promises is that it describes the tree: the same file set, and each
# file's own SHA-256. That is what is compared, with the revision and the date normalised away.
for doc in docs/agent/*.md docs/agent/roadmap/*.md docs/agent/catalog/*.md; do
    [ -f "$doc" ] || continue
    grep -qE '^> Verified: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$doc" || {
        echo "check_agent_docs: no verification line: $doc" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R docs/agent/catalog "$tmp/catalog-before"
python3 wolkaraforever/tools/generate_agent_docs.py

# Provenance out, content in: a row keeps its path, purpose, dependencies and file hash.
normalise() {
    rm -rf "$2"; mkdir -p "$2"
    for file in "$1"/*.md; do
        [ -f "$file" ] || continue
        sed -E 's/`[0-9a-f]{7,40}`/`REV`/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}/DATE/g' "$file" > "$2/$(basename "$file")"
    done
}
normalise "$tmp/catalog-before" "$tmp/before"
normalise docs/agent/catalog "$tmp/after"
if ! diff -ru "$tmp/before" "$tmp/after" >/dev/null; then
    diff -ru "$tmp/before" "$tmp/after" | head -40 >&2
    echo "check_agent_docs: catalog is stale; run generate_agent_docs.py" >&2
    exit 1
fi

if rg -n '\]\([^)]*docs/agent/' README.md docs COMPATIBILITY.md CHANGELOG.md SECURITY.md NOTICE.md CONTRIBUTORS.md 2>/dev/null; then
    echo "check_agent_docs: human documentation links to agent documentation" >&2
    exit 1
fi

echo "check_agent_docs: OK"
