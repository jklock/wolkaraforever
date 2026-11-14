# Repository map

> Verified: 2026-11-13 · Source: `3c33543` · Proof: tracked-file catalog

| Path | Role |
| --- | --- |
| `platform/` | Immutable, byte-identical Tolkara vendor tree. Never edit directly. |
| `wolkaraforever/` | Product overlay: launcher behavior, input, add-ons, patches, tests, and project tools. |
| `addons/` | Bundled WoW add-on source. |
| `profiles/` | Product-owned data-only profiles. |
| `docs/` | Standalone human documentation and approved public images. |
| `docs/agent/` | Agent-only current documentation and catalog. |
| `build/`, `logs/` | Ignored generated output. |

`prepare.sh` copies `platform/` to `build/platform/`, applies maintained patches, overlays product files, and generates the prepared project. `check_layers.sh` proves that assembly boundary; it does not prove runtime behavior.

## Refresh when

Refresh after a top-level layout, ownership, overlay, patch, or generated-output change.
