# File catalog

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: `generate_agent_docs.py` and `check_agent_docs.sh`

The catalog is a complete, generated inventory of tracked files. A row provides the path, immediate owner, type, purpose, function, dependencies, human-documentation impact, SHA-256 proof, source revision, and verification date. Descriptions are conservative classifications from path and file type; agents must inspect source before changing behavior.

- [Root](catalog/root.md)
- [GitHub configuration](catalog/github.md)
- [Add-ons](catalog/addons.md)
- [Human documentation](catalog/docs.md)
- [Immutable platform](catalog/platform.md)
- [Profiles](catalog/profiles.md)
- [Product layer](catalog/wolkaraforever.md)
- [Migration record](catalog/development.md)

## Refresh when

Run `python3 wolkaraforever/tools/generate_agent_docs.py` after every tracked-file change.
`check_agent_docs.sh` requires a `> Verified:` line in every file of this directory and then
regenerates the catalog in place, compares it with a saved copy while ignoring the revision and
date stamps, and puts the saved copy back: a missing row, a stale SHA-256, or a changed
description fails the check. It also fails when a human document links into `docs/agent/`.
