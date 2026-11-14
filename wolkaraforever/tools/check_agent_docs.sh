#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# The proof line is provenance: it names the revision and the day the catalogue was generated
# against. It must exist, and it is not the gate.
#
# The gate used to require *today's* date and to compare the catalogue byte-for-byte, including
# the revision the generator stamps into every row. The generator writes the commit it ran at,
# so committing the catalogue changed the stamp it had just written: the check failed on the
# very commit that added the refreshed catalogue, and on any tree more than a day old, with
# nothing else wrong. Measured on main, 2026-11-13.
#
# What the catalogue promises is that it describes this tree: the same file set, and each file's
# own SHA-256. That is what is compared, with the revision and the date normalised away.
for doc in docs/agent/*.md docs/agent/roadmap/*.md docs/agent/catalog/*.md; do
    [ -f "$doc" ] || continue
    grep -qE '^> Verified: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$doc" || {
        echo "check_agent_docs: no verification line: $doc" >&2; exit 1; }
done

tmp=$(mktemp -d)
# This check reports; it never edits the working copy. The generator writes in place, so the
# catalogue is put back exactly as it was found - on success, on failure, and on interrupt.
cp -R docs/agent/catalog "$tmp/original"
restore() { rm -rf docs/agent/catalog && cp -R "$tmp/original" docs/agent/catalog; }
trap 'restore; rm -rf "$tmp"' EXIT INT TERM

python3 wolkaraforever/tools/generate_agent_docs.py

# Provenance out, content in: a row keeps its path, purpose, dependencies and file hash.
normalise() {
    rm -rf "$2"; mkdir -p "$2"
    for file in "$1"/*.md; do
        [ -f "$file" ] || continue
        sed -E 's/`[0-9a-f]{7,40}`/`REV`/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}/DATE/g' \
            "$file" > "$2/$(basename "$file")"
    done
}
normalise "$tmp/original" "$tmp/before"
normalise docs/agent/catalog "$tmp/after"
restore

if ! diff -ru "$tmp/before" "$tmp/after" >/dev/null; then
    diff -ru "$tmp/before" "$tmp/after" | head -40 >&2
    echo "check_agent_docs: catalogue is stale; run generate_agent_docs.py" >&2
    exit 1
fi

if rg -n '\]\([^)]*docs/agent/' README.md docs COMPATIBILITY.md CHANGELOG.md SECURITY.md NOTICE.md CONTRIBUTORS.md 2>/dev/null; then
    echo "check_agent_docs: human documentation links to agent documentation" >&2
    exit 1
fi

echo "check_agent_docs: OK"
