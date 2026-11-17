# Operations

> Verified: 2026-11-16 · Source: `9680e63` · Proof: project-owned tool scripts

Run project-owned device and game operations only through `wolkaraforever/tools/`.

| Task | Command |
| --- | --- |
| Prepare and validate assembly | `prepare.sh`, `apply.sh`, `overlay_map.sh`, `check_layers.sh`, `update_tolkara.sh --check`, `adopt.sh` |
| Configure a Mac or device | `install_prerequisites.sh --check`, `device_variables.sh --write`, `preflight.sh`, `setup_simulators.sh --apply` |
| Build and install | `install.sh` (`--build-only` compiles and signs without touching the device), `after_install.sh` (each mode's own step), `generate.sh`, `open_xcode.sh` |
| Run and observe | `run.sh sim\|device`, `launch.sh`, `pilot.sh`, `running_app.sh` |
| Game data lifecycle | `push_game.sh`, `remove_game.sh` |
| Diagnostics and evidence | `device_log.sh`, `capture_gameplay_log.sh`, `classify_external_jit.py`, `perf_sweep.py`, `validate.sh` |
| Packaging | `package_ipa.sh`, `package_altstore_ipa.sh`, `verify_ipa.sh`, `verify_external_jit.sh`, `package_addon_zip.py` |
| Documentation gates | `generate_agent_docs.py`, `check_agent_docs.sh`, `check_docs.sh`, `check_origin.sh`, `check_ui_policy.sh` |
| Cleanup | `clear_validation_reports.sh` |

Execution mode is decided by `TOLKARA_MODE` (`developer-service`, `local-signing`, or empty to
ask). `install.sh` and the platform's run script accept the first two; External JIT exists only
in the unsigned `TolkaraDiagnostics` `.ipa` that `package_ipa.sh` builds, and no post-install
enrollment happens for it. [Build and run WolkaraForever](../BUILDING.md) is the human guide.

Do not use raw device file operations. Do not uninstall or force-stop a user’s running app without explicit coordination. See [Installation](../INSTALLATION.md) for user-run setup.

## Refresh when

Refresh after any tool interface, safety guard, command prerequisite, package, or device workflow changes.
