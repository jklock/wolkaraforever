# Development documentation

This directory contains engineering documentation, test procedures, architecture notes,
and historical records. It is not part of the end-user guide.

| Area | Contents |
| --- | --- |
| [architecture/](architecture/) | Layer boundaries, execution architecture, authorization design, and the project map. |
| [guides/](guides/) | Build, maintenance, device, tooling, profile, contribution, and repository workflows. |
| [technical/](technical/) | Implementation notes for the launcher, input, graphics, performance, and adapters. |
| [testing/](testing/) | Test procedures and clean-install acceptance checks. |
| [archive/](archive/) | Completed design and investigation material retained for lineage; not current implementation instructions. |
| [wiki/](wiki/) | Repository-backed source material for published Wiki pages. |

For installation and everyday use, start with the [user guide](../docs/README.md).

## Test levels

Every result is at one of four levels, and it never moves up without a new run at
the higher level.

| Level | Produced by | Recorded in |
| --- | --- | --- |
| **Source** | Suites that build and run on a Mac with no iPad and no game: `check_layers.sh`, `check_docs.sh`, and the per-module test scripts. | The command result. |
| **Simulator** | Fixtures that install and drive our own screens in the iOS Simulator (`test_wow_launcher_ui.sh`, `test_touch_controls_ui.sh`, `test_touch_gamepad_ui.sh`, `test_voice.sh`, `test_translation_sim.sh`). | The command result. |
| **Device script** | A `wolkaraforever/tools/` script that drives the installed build on a named iPad and reads back what it wrote (`pilot.sh`, `device_matrix.sh`, the in-app self-tests). | The local pre-release report. |
| **Human full-game** | A person installing, launching and playing the real client, following [FRESH_INSTALL_TEST.md](testing/FRESH_INSTALL_TEST.md). | A dated observation kept outside the repository. |

A simulator result never stands in for a device result, and a device script never
stands in for a human one. A claim that skipped a level says so.

Key entry points: [project map](architecture/PROJECT_MAP.md),
[repository workflow](guides/REPOSITORY_WORKFLOW.md),
[layer architecture](architecture/WOLKARAFOREVER_LAYER.md),
[contributing](guides/CONTRIBUTING.md), [localization](guides/LOCALIZATION.md),
[profiles](guides/PROFILES.md), and the
[WoW Forever profile](guides/WOW_FOREVER_PROFILE.md). Historical plans and
investigations are retained only in [archive/](archive/).
