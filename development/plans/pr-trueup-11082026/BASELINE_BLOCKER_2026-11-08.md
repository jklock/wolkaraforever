# Baseline capture blocker — 2026-11-08

The initial baseline capture did not complete. This is a release blocker, not an approval to
record incomplete or manually fabricated images.

On the iPhone Duo, the existing `test_wow_launcher_ui.sh` fixture aborts before its capture
phase in `wolkaraforever/WoW/tests/test_wow_launcher_app.m`. The first observed failure is its
stale unmanaged-add-on removal expectation at line 337; later diagnostic attempts exposed stale
ready-state and add-on install-button assertions as well. The test log reports `Invalid install
metadata` before the ready-state assertion. No baseline image was created or accepted.

Required repair, on this same branch before release: reconcile each fixture assertion with the
current product contract, add focused tests for the CDN/startup fixture setup, run the corrected
fixture cleanly on both allowed simulators, inspect every captured state, then use the explicit
recorder command. Do not weaken baseline comparison, change default mode to bypass it, or copy
images from a different build/device. After the two directories contain the complete inventory,
run `check_ui_policy.sh --review UI-BASELINE-11082026.md` and the full release procedure.
