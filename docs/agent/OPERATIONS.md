# Operations

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: project-owned tool scripts

Run project-owned device and game operations only through `wolkaraforever/tools/`.

That sentence is a prohibition, not a summary. No `xcrun simctl`, `simctl`, `xctrace`,
`instruments`, `killall` or `pkill` against a simulator, WebKit, SpringBoard or
`com.apple.CoreSimulator.CoreSimulatorService` process, and no shutting down, erasing, rebooting or
restarting anything this run did not start - including "read-only" probes such as `simctl openurl`,
`simctl io screenshot` or `simctl listapps`. A script that hangs is reported with what it printed,
not repaired by hand and not routed around. `AGENTS.md` carries the same rule; it was broken on
2026-11-21 and is recorded here so it cannot be argued away.

| Task | Command |
| --- | --- |
| Prepare and validate assembly | `prepare.sh`, `apply.sh`, `overlay_map.sh`, `check_layers.sh`, `update_tolkara.sh --check`, `adopt.sh` |
| Configure a Mac or device | `install_prerequisites.sh --check`, `device_variables.sh --write`, `preflight.sh`, `setup_simulators.sh --apply`; `simulators.sh` is the resolution library every simulator suite uses, directly or through `test_wow_launcher_ui.sh` |
| Build and install | `install.sh` (`--build-only` compiles and signs without touching the device), `after_install.sh` (each mode's own step), `generate.sh`, `open_xcode.sh` |
| Run and observe | `run.sh sim\|device`, `launch.sh`, `pilot.sh`, `running_app.sh`, `device_matrix.sh` (the physical-iPad checks a Mac can drive alone) |
| Game data lifecycle | `push_game.sh`, `remove_game.sh` |
| Diagnostics and evidence | `device_log.sh`, `capture_gameplay_log.sh`, `capture_composer_states.sh`, `classify_external_jit.py`, `perf_sweep.py`, `validate.sh` (with `known_platform_failures.txt`) |
| Packaging | `package_ipa.sh`, `package_altstore_ipa.sh`, `verify_ipa.sh`, `verify_external_jit.sh`, `package_addon_zip.py` |
| Launcher UI baselines | `check_ui_policy.sh`, `record_ui_baselines.sh`, `test_launcher_matrix.sh`, `compare_ui_baselines.swift`; `capture_ui_guide.sh` redraws `docs/screenshots/ui-*.jpg` for the user guide (not a gate) |
| Documentation, assets and repository gates | `generate_agent_docs.py`, `check_agent_docs.sh`, `check_docs.sh`, `check_localization.py`, `check_origin.sh`, `make_wolkaraforever_icon.py` |
| Tests | `test_*.sh` beside the tools and `tests/test_*.sh` under them; `test_emulation.sh` runs the sweep |
| Cleanup | `clear_validation_reports.sh` |
| Shared internals | `env.sh` (reads `local.env`), `xcrun_device_timeout.sh` (a bounded `devicectl` shim) |

Execution mode is decided by `TOLKARA_MODE` (`developer-service`, `local-signing`, or empty, which
leaves a development launch to the mode chooser; a plain launch of the shipped home always resolves
to the route its build carries). `install.sh` and the platform's run script accept the first two;
the mode chooser takes `external-jit` only in the `TolkaraDiagnostics` build, which is what
`package_ipa.sh` produces, and no post-install enrollment happens for it. [Build and run
WolkaraForever](../BUILDING.md) is the human guide.

Do not use raw device file operations. Do not uninstall or force-stop a user’s running app without explicit coordination. See [Installation](../INSTALLATION.md) for user-run setup.

## Refresh when

Refresh after any tool interface, safety guard, command prerequisite, package, or device workflow changes.
