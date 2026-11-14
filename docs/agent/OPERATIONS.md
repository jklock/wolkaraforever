# Operations

> Verified: 2026-11-13 · Source: `3c33543` · Proof: project-owned tool scripts

Run project-owned device and game operations only through `wolkaraforever/tools/`.

| Task | Command |
| --- | --- |
| Prepare and validate assembly | `prepare.sh`, `check_layers.sh`, `update_tolkara.sh --check` |
| Configure a Mac/device | `install_prerequisites.sh --check`, `device_variables.sh --write`, `preflight.sh` |
| Build and install | `install.sh`, `launch.sh`, `running_app.sh` |
| Game data lifecycle | `push_game.sh`, `remove_game.sh` |
| Diagnostics | `device_log.sh`, `pilot.sh`, `validate.sh` |
| Packaging | `package_ipa.sh`, `package_altstore_ipa.sh`, `package_addon_zip.py` |
| Cleanup | `clear_validation_reports.sh` |

Do not use raw device file operations. Do not uninstall or force-stop a user’s running app without explicit coordination. See [Installation](../INSTALLATION.md) for user-run setup.

## Refresh when

Refresh after any tool interface, safety guard, command prerequisite, package, or device workflow changes.
