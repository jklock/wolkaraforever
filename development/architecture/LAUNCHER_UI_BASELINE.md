# Launcher UI baseline

## Authority

The committed images in `wolkaraforever/WoW/tests/ui-baselines/launcher/` are the visual source
of truth for the WolkaraForever launcher at `550755f6dffcf15852ae76c8b206fe27b6da6461`.
They cover the iPhone Duo and iPad Pro 13-inch (M5) simulators. Pixel equality is intentional:
layout drift is a failure, not a subjective review comment.

## Required states

Each device directory contains these images:

```text
wow-home.png
wow-home-large-text.png
addons-popup.png
voice-settings.png
voice-test.png
wow-home-de.png
wow-addons-de.png
wow-voice-de.png
wow-voice-test-de.png
wow-home-de-large-text.png
wow-starting.png
wow-running.png
wow-startup-failed.png
```

The fixture also asserts the existing identifiers and layout contract. Missing, extra, or
dimension-mismatched images fail `test_wow_launcher_ui.sh`.

## Recording procedure

Baselines are not ordinary test output. A maintainer records them only in a dedicated
UI-contract-amendment release, after reviewing both simulator matrices and physical iPad evidence:

```sh
UI_BASELINE_RECORD=I_HAVE_APPROVED_THE_UI_CHANGE \
  wolkaraforever/tools/record_ui_baselines.sh
git diff -- wolkaraforever/WoW/tests/ui-baselines/
```

The recorder overwrites only the known baseline files. Commit the reviewed images, their review
record, exact source SHA, and validation evidence together. An additive feature must preserve
every existing file and may add a separately named optional-state baseline only.
