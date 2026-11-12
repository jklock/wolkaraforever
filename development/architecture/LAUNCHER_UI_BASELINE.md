# Launcher UI baseline

## Authority

The committed images in `wolkaraforever/WoW/tests/ui-baselines/launcher/` are the visual source
of truth for the WolkaraForever launcher at `550755f6dffcf15852ae76c8b206fe27b6da6461`.
They cover the iPhone Duo and iPad Pro 13-inch (M5) simulators. The comparator decodes RGBA
pixels and permits only a per-channel difference of five or less, reporting every tolerated
difference. This accommodates measured renderer rounding only; a larger difference, missing
or extra state, dimension mismatch, identifier mismatch, or layout-contract failure is a test
failure. Layout drift is a failure, not a subjective review comment.

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
wow-downloading.png
wow-launcher-ipados.png
wow-launcher-duo.png
wow-addons-recommended-macever.png
wow-addons-recommended-wolkararoue.png
```

The four Launcher Manager states were added by the v1.0.9 UI-contract amendment:

- `wow-launcher-ipados.png` - the ready page in its default interface: the Launcher Manager
  card reads `Interface Mode: iPadOS` and the recommendation row reads
  `Install Recommended Add-ons (Mac-Ever)`.
- `wow-launcher-duo.png` - the same page after choosing `iOS on Duo`: the card reads
  `Interface Mode: iOS on Duo` and the recommendation row reads
  `Install Recommended Add-ons (WolkaraRoue)`. No add-on was installed, disabled, removed or
  updated by the switch.
- `wow-addons-recommended-macever.png` - the Add-On Manager the Mac-Ever recommendation opens,
  on Browse, filtered to CurseForge project 1733200, in the missing-key state (the explicit
  key prompt is the existing one).
- `wow-addons-recommended-wolkararoue.png` - the Add-On Manager the WolkaraRoue recommendation
  opens, showing the bundled package's release and SHA-256 and its own explicit Install action.

The selector's two choices are asserted as values by `test_wow_launcher_app.m` (exactly
`iPadOS` and `iOS on Duo`, with the current one marked, and persisted to
`WolkaraForeverInterfaceModeV1`). They are not drawn as a baseline image because an action
sheet's translucent backdrop is not deterministic to the per-channel tolerance; the page
states it produces are.

The fixture also asserts the existing identifiers and layout contract. Missing, extra, or
dimension-mismatched images fail `test_wow_launcher_ui.sh`.

`wow-downloading.png` is the state a download is in, and the only one whose status line carries a
speed and an estimate. The fixture draws it from a real update held open by the updater stub
(`40 GB / 70 GB`) with the measured rate pinned to 4 MB/s, because the rate itself comes from the
clock and a picture of a clock proves nothing; the window, both fragments and the cases that
withhold them are asserted as values by `wolkaraforever/WoW/tests/test_wow_download_status.m`,
which runs without a simulator.

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
