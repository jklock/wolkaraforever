# Testing

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: project test wrappers and simulator policy

Run the narrowest owning test first. `check_layers.sh` validates layer assembly; `check_docs.sh` validates documentation; source tests validate source behavior; simulator tests validate the project's UIKit fixtures. None substitutes for physical-device behavior.

`validate.sh` is the inventory, not a sample: every suite under `wolkaraforever/tools/` and `wolkaraforever/tools/tests/` has a row there, always or with `--full`, except three. `test_install.sh` is a dispatcher for the separate test app rather than a suite — with no subcommand it prints its own usage and exits 2 — so the sweep skips it and `wolkaraforever/tools/tests/test_test_install.sh` is the row that covers it. `test_battery_saver.sh` and `test_network_health.sh` have no row of their own and are reached only by the `test_emulation.sh` sweep, so a `validate.sh`-only run does not cover Battery Saver or network health; name that when a change touches either. Two more scripts are deliberately not rows, and `validate.sh` says why beside its neighbours: `test_emulation.sh` is the run-everything wrapper and would re-run every row, and `test_launcher_matrix.sh` runs the same two lanes the `check_ui_policy.sh` row already runs.

`test_emulation.sh` prepares the tree and runs `check_layers.sh`, the platform's own sanitizer suite, and then every layer `test_*.sh` except the `*ui.sh` ones, the sweep itself, and the `test_install.sh` dispatcher. A layer suite failing fails the run; otherwise the platform suite's status is what it reports, and `validate.sh` judges that against `known_platform_failures.txt`.

Run one preparing script at a time. Every simulator suite, `check_layers.sh` and `validate.sh` re-create `build/platform`, so two started together delete each other's tree: the survivor fails with `getcwd: cannot access parent directories` and `ld: open() failed ... build/wow-launcher/compare_ui_baselines`. That is a self-inflicted red, not a product failure, and it is reproduced by pairing `check_layers.sh` with `check_ui_policy.sh` (2026-11-21).

Required simulator matrix: iPhone Duo and iPad Pro 13-inch (M5). The physical iPad Pro 12.9-inch (5th generation) is optional unless a specific claim requires it. Every simulator suite resolves its device through `wolkaraforever/tools/simulators.sh`, which refuses an off-matrix name or UDID.

Use `test_launcher_matrix.sh --check` for reviewed launcher images; it is the same two lanes `check_ui_policy.sh` runs, with durable transcripts. `record_ui_baselines.sh` requires `UI_BASELINE_RECORD=I_HAVE_APPROVED_THE_UI_CHANGE`. Keep approved baselines and deterministic fixtures tracked; keep reports, captures, logs, and temporary support bundles ignored.

`capture_ui_guide.sh` is the one launcher run that is not a gate: it draws the pages and sheets for
`docs/UI_REFERENCE.md` into `docs/screenshots/ui-*.jpg`, asserts nothing, and compares nothing. A
reviewed baseline that needs to change goes through `record_ui_baselines.sh`, never through it.

## Refresh when

Refresh after a test command, matrix, baseline policy, fixture ownership, or evidence boundary changes.
