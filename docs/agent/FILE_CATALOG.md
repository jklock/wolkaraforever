# File catalog

> Verified: 2026-11-13 · Source: `3c33543` · Proof: `generate_agent_docs.py` and `check_agent_docs.sh`

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

Run `python3 wolkaraforever/tools/generate_agent_docs.py` after every tracked-file change. The checker rejects missing, stale, or duplicate catalog entries.
