# Baseline completion record — 2026-11-09

The initial capture blocker is resolved. The launcher fixture was reconciled with the current
CDN metadata contract, current settings actions, localization, and deterministic device-profile
behaviour. A real compact-popup header geometry defect was fixed and asserted both in the
simulator fixture and on the installed iPad self-test.

Clean `--check` matrix evidence is retained at:

```text
logs/launcher-matrix/20261109T143450/
```

It records `WoW UIKit PASS:` and `UI baseline comparison passed` for both iPhone Duo and iPad
Pro 13-inch (M5). The complete 26-image inventory is committed under
`wolkaraforever/WoW/tests/ui-baselines/launcher/`. The physical iPad matrix separately passed
25 automated checks, including the add-ons-page header contract.

The matrix runner is the required repeatable entry point:

```sh
wolkaraforever/tools/test_launcher_matrix.sh --fixture
UI_BASELINE_RECORD=I_HAVE_APPROVED_THE_UI_CHANGE \
  wolkaraforever/tools/test_launcher_matrix.sh --record
wolkaraforever/tools/test_launcher_matrix.sh --check
```
