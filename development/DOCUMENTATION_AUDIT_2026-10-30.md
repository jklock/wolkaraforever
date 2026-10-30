# Documentation audit — 2026-10-30

This review covers every tracked Markdown document outside the vendored `platform/` tree.
It verifies current paths against the checkout, resolves local links/images with
`wolkaraforever/tools/check_docs.sh`, and preserves evidence boundaries.

| Area | Status | Treatment |
| --- | --- | --- |
| Repository root and `docs/` | Current | User-facing install, usage, compatibility, security, licence, and asset references are current for `prostatus`. |
| `development/architecture`, `guides`, `technical`, and `testing` | Current with dated evidence | Current commands use fully qualified layer paths where they are run from the repository root; historical measurements remain dated rather than being represented as new proof. |
| `development/github` and `wiki` | Current | Repository-management and Wiki publication work is tracked here; the Wiki points back to canonical sources. |
| `development/archive/` | Historical | Retained for lineage and not rewritten as current instructions. |
| `development/validation/` | Immutable evidence | Preserved verbatim; each record remains evidence only for its recorded SHA and date. |
| `profiles/` | Current data documentation | No profile README is owned outside the vendor tree. |
| `platform/` | Vendored | Not edited; integrity is checked by `check_layers.sh`. |

## Assets

The five user-guide screenshots are tracked JPEGs and resolve from the guide; the three displayed
screens were recaptured from the passing launcher simulator fixture on 2026-10-30. The repository
logo is a tracked 512×341 PNG and resolves from the root README. The simulator fixtures remain
the validation path for current UI behavior. This review does not relabel a simulator artifact as
physical-device or gameplay proof.

## Evidence boundary

The source and simulator commands recorded by this branch prove only their named scope. Device
and human-gameplay entries stay deferred until a coordinated run identifies the installed SHA,
device, iPadOS, client build, and execution mode.
