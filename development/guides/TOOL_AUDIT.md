# Layer tool audit

> **Reviewed 2026-10-30 · branch `prostatus`.**

This is the complete inventory for executables owned by `wolkaraforever/tools/`. The vendored
`platform/tools/` tree is documented upstream and remains byte-identical. `test_tooling_docs.sh`
fails if a tracked layer tool is absent from this page.

| Tool | Inputs | Side effect and safety boundary | Automated evidence | Reference |
| --- | --- | --- | --- | --- |
| `adopt.sh` | Tolkara checkout | Mutates only the supplied checkout; use a copy | `check_layers.sh` | `TOOLING.md` |
| `after_install.sh` | execution mode, prepared tree | Post-install state only; unit-tested without a build | `tools/tests/test_after_install.sh` | `TOOLING.md` |
| `apply.sh` | target tree | Mutates only the supplied tree through patches/overlay | `check_layers.sh` | `TOOLING.md` |
| `capture_gameplay_log.sh` | device/log options | Reads and redacts app logs; never drives the game | dry-run argument validation | `TOOLING.md` |
| `check_docs.sh` | repository | Read-only documentation link/image/anchor validation | `check_docs.sh` | `TOOLING.md` |
| `check_layers.sh` | repository/upstream ref | Read-only layer and vendor-integrity gate | `check_layers.sh` | `PROJECT_MAP.md` |
| `check_localization.py` | string tables/source | Read-only localization consistency check | `test_localization.sh` | `TOOLING.md` |
| `check_origin.sh` | remote/ref options | Read-only unless explicit `--fetch`; never merges | `--help` and source review | `TOOLING.md` |
| `device_log.sh` | device, line/pattern options | Reads app log only | `tools/tests/test_running_app.sh` | `TOOLING.md` |
| `device_matrix.sh` | configured device | Coordinated device checks; leaves normal launcher running | device-only, not run here | `TOOLING.md` |
| `device_variables.sh` | optional device selector | `--write` updates ignored `local.env`; otherwise read-only | `tools/tests/test_device_variables.sh` | `TOOLING.md` |
| `env.sh` | ignored `local.env` | Sources local configuration; never prints secrets | consumers and source review | `TOOLING.md` |
| `generate.sh` | project/config arguments | Rebuilds ignored prepared Xcode project | `check_layers.sh` | `TOOLING.md` |
| `install.sh` | configured device | Refuses a live game unless explicit replacement consent | `tools/tests/test_after_install.sh` | `TOOLING.md` |
| `install_prerequisites.sh` | check/install options | Check-only by default; no silent sudo/Xcode/Homebrew install | `tools/tests/test_install_prerequisites.sh` | `TOOLING.md` |
| `launch.sh` | device/options | Refuses unsafe session changes | `tools/tests/test_pilot.sh` | `TOOLING.md` |
| `make_wolkaraforever_icon.py` | approved artwork | Rewrites committed icon assets; previews are ignored | `test_icon_assets.sh` | `TOOLING.md` |
| `open_xcode.sh` | optional `--no-open` | Regenerates ignored project before opening Xcode | `check_layers.sh` | `TOOLING.md` |
| `overlay_map.sh` | layer file tree | Rewrites `overlay.map`; review before commit | `check_layers.sh` | `TOOLING.md` |
| `package_altstore_ipa.sh` | optional output path | Requires clean tree; outputs ignored IPA/report | `tools/tests/test_verify_ipa.sh` | `TOOLING.md` |
| `package_ipa.sh` | packaging arguments | Outputs ignored unsigned generic IPA only | `tools/tests/test_verify_ipa.sh` | `TOOLING.md` |
| `perf_sweep.py` | device/settings variants | Refuses live session without `--stop-first`; logs ignored | device-only, not run here | `PERFORMANCE_THERMAL.md` |
| `pilot.sh` | safe device subcommand | Preserves/restores app state and refuses unsafe writes | `tools/tests/test_pilot.sh` | `TOOLING.md` |
| `preflight.sh` | local config/source options | Read-only readiness inspection | `tools/tests/test_preflight.sh` | `TOOLING.md` |
| `prepare.sh` | repository | Recreates ignored `build/platform` only | `check_layers.sh` | `TOOLING.md` |
| `push_game.sh` | source/device options | `--dry-run` copies nothing; live copy protects active store | `tools/tests/test_push_game.sh` | `TOOLING.md` |
| `remove_game.sh` | explicit edition or `--all` | Refuses a running app and names removals; destructive on device | dry-run only, not run here | `TOOLING.md` |
| `run.sh` | simulator/device arguments | Delegates through prepared tree; device mode needs coordination | source/simulator suites | `TOOLING.md` |
| `running_app.sh` | configured device | Reads installed process state only | `tools/tests/test_running_app.sh` | `TOOLING.md` |
| `setup_simulators.sh` | explicit `--apply` | Destructive simulator reset is opt-in | argument/source review, not run here | `TOOLING.md` |
| `test_addon_archive.sh` | repository | Creates ignored test output only | self | `TOOLING.md` |
| `test_authorization_handoff.sh` | repository | Synthetic local peer only | self | `TOOLING.md` |
| `test_curseforge.sh` | repository | Uses fixtures; no account credential | self | `TOOLING.md` |
| `test_emulation.sh` | repository | Source-only umbrella suite | self | `TOOLING.md` |
| `test_forever_ui.sh` | repository | Fixture/archive source test only | self | `TOOLING.md` |
| `test_icon_assets.sh` | repository | Read-only icon validation | self | `TOOLING.md` |
| `test_local_service_retry.sh` | repository | Synthetic service test only | self | `TOOLING.md` |
| `test_localization.sh` | repository | Source table/service test only | self | `TOOLING.md` |
| `test_tooling_docs.sh` | repository | Read-only tool-inventory contract | self | `TOOLING.md` |
| `test_touch_controls_ui.sh` | simulator | Simulator fixture only | self | `TOOLING.md` |
| `test_touch_gamepad_ui.sh` | simulator | Simulator fixture only | self | `TOOLING.md` |
| `test_translation_sim.sh` | simulator | Simulator adapter suite only | self | `TOOLING.md` |
| `test_voice.sh` | simulator | Fake microphone/audio services; no hardware claim | self | `TOOLING.md` |
| `test_wow_launcher.sh` | repository | Source-only launcher suite | self | `TOOLING.md` |
| `test_wow_launcher_ui.sh` | simulator | Synthetic launcher fixture; no game/network | self | `TOOLING.md` |
| `update_tolkara.sh` | upstream options | `--check` is read-only; ingest needs a clean dedicated branch | `check_layers.sh` | `TOOLING.md` |
| `validate.sh` | clean candidate/options | Writes scrubbed evidence only for exact candidate SHA | `tools/tests/test_validate.sh` | `TOOLING.md` |
| `verify_external_jit.sh` | device/bundle options | Reads installed-app/runtime evidence only | argument/source review | `TOOLING.md` |
| `verify_ipa.sh` | IPA/report path | Reads IPA; optional report is explicit output | `tools/tests/test_verify_ipa.sh` | `TOOLING.md` |
| `xcrun_device_timeout.sh` | CoreDevice invocation | Bounds a hung device command; never bypasses safeguards | `tools/tests/test_xcrun_device_timeout.sh` | `TOOLING.md` |
| `tests/make_addon_archives.py` | fixture output path | Generates test-only archives | `test_addon_archive.sh` | `TESTING.md` |
| `tests/test_after_install.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_device_variables.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_install_prerequisites.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_pilot.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_preflight.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_push_game.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_running_app.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_validate.sh` | repository | Mocked shell contract | self | `TOOLING.md` |
| `tests/test_verify_ipa.sh` | repository | Fixture IPA contract | self | `TOOLING.md` |
| `tests/test_xcrun_device_timeout.sh` | repository | Mocked CoreDevice timeout contract | self | `TOOLING.md` |

The review deliberately does not convert source, simulator, dry-run, or mocked-shell coverage
into physical-device or human-gameplay evidence. Those claims require a coordinated run recorded
against the installed SHA.
