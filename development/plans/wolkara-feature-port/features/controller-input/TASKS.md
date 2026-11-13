# Controller input tasks

## 1. Prove the claim seam

Branch `feature/controller-command-spike`. Read `ControllerInspector`,
`InputElement`, `InputInterest`, `InputRouter`, `Trigger`, Voice settings/UI,
and `Voice/tests/test_voice_app.m`. Add test-only plumbing for one canonical
button. It must suppress that one button before guest delivery, preserve every
other button, and restore on disconnect/background. Add claimed, unclaimed,
disconnect, background, and unsupported-controller tests. Run
`wolkaraforever/tools/test_voice.sh` and `wolkaraforever/tools/check_layers.sh`.
Run the spike fixture on both required simulators and record Device Hub status;
if a physical run occurs, verify one user-operated press. If no safe seam exists,
delete spike code and report `no safe hook found`; do not add UI.

## 2. Build the command path

Branch `feature/controller-command-ingress`. Add
`wolkaraforever/Input/ControllerCommandIngress.{h,m}` and register it in
`overlay.map`. Admit only mapped button edges; reject axes, d-pad values and
held repeats. Implement bounded FIFO, sequence numbers, one scheduled drain,
overflow counter and timestamp boundaries. Deliver to `InputRouter`; do not
refactor diagnostics or change default routing. Test ordering, duplicate
suppression, rejection, overflow and one-drain behavior. Run the focused test,
`test_voice.sh`, and `check_layers.sh`.

## 3. Ship optional claim only after task 1 passes

Branch `feature/controller-composer-claim`. Persist a per-controller/per-element
boolean in `VoiceSettings`, default false for every migration. Add a switch only
when the proven route supports the selected control; otherwise show explanatory
disabled text. Restore guest delivery on disable, disconnect, background, route
failure and app exit. Test migration and every restoration path; run voice/UI
fixtures, layer check, and physical Device Hub claimed/unclaimed proof.

## 4. Close the feature

Do not call this feature complete until tasks 1–3 have merged, every new source
file is mapped by `overlay.map`, and flags for ingress/Composer entry/claim each
restore pre-feature behavior when off. Run `test_voice.sh` on iPad Pro 13-inch
(M5) and iPhone Duo, then `check_layers.sh`. On Duo verify automatic/iOS-on-Duo
behavior; preserve iPad behavior. If available, repeat the baseline mapping/game-
state scenario on the physical iPad. Put p50/p95/max, overflow count, flags,
execution mode, SHA and physical status in PR Proof; keep generated evidence
local. Update documentation only with observed results.
