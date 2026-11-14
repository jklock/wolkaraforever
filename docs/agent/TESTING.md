# Testing

> Verified: 2026-11-13 · Source: `3c33543` · Proof: project test wrappers and simulator policy

Run the narrowest owning test first. `check_layers.sh` validates layer assembly; `check_docs.sh` validates documentation; source tests validate source behavior; simulator tests validate the project's UIKit fixtures. None substitutes for physical-device behavior.

Required simulator matrix: iPhone Duo and iPad Pro 13-inch (M5). The physical iPad Pro 12.9-inch (5th generation) is optional unless a specific claim requires it.

Use `test_launcher_matrix.sh --check` for reviewed launcher images. `record_ui_baselines.sh` requires deliberate approval. Keep approved baselines and deterministic fixtures tracked; keep reports, captures, logs, and temporary support bundles ignored.

## Refresh when

Refresh after a test command, matrix, baseline policy, fixture ownership, or evidence boundary changes.
