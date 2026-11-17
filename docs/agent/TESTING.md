# Testing

> Verified: 2026-11-13 · Source: `3c33543` · Proof: project test wrappers and simulator policy

Run the narrowest owning test first. `check_layers.sh` validates layer assembly; `check_docs.sh` validates documentation; source tests validate source behavior; simulator tests validate the project's UIKit fixtures. None substitutes for physical-device behavior.

`validate.sh` is the inventory, not a sample: every suite under `wolkaraforever/tools/` and `wolkaraforever/tools/tests/` has a row there, always or with `--full`, and a suite with no row is a file nothing runs. Three are unreferenced on purpose and say why in their own comments: the `test_emulation.sh` sweep, the `test_install.sh` dispatcher, and `test_launcher_matrix.sh`, which runs the same two lanes as `check_ui_policy.sh`. `test_emulation.sh` runs the platform's sanitizer suite and then every layer suite except the `*ui.sh` ones.

A layer suite that fails on an assertion whose defect is recorded in `wolkaraforever/tools/known_layer_failures.txt` is reported as `PASS (known layer failure: …)` and its own line is printed on every run. The record names the command *and* a line that must appear in the suite's output, so it cannot excuse a different failure; the platform's equivalent is `known_platform_failures.txt`.

Required simulator matrix: iPhone Duo and iPad Pro 13-inch (M5). The physical iPad Pro 12.9-inch (5th generation) is optional unless a specific claim requires it.

Use `test_launcher_matrix.sh --check` for reviewed launcher images. `record_ui_baselines.sh` requires deliberate approval. Keep approved baselines and deterministic fixtures tracked; keep reports, captures, logs, and temporary support bundles ignored.

## Refresh when

Refresh after a test command, matrix, baseline policy, fixture ownership, or evidence boundary changes.
