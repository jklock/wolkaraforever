# UI review: the bounded controller command path

## Classification

`none`. No launcher surface is added, removed, moved, renamed, recoloured or
resized. The Voice page's mapping card, its *Keep the game from seeing it*
switch, and the note under it are exactly as v1.0.10 shipped them, and every
approved identifier (`voice.mapping`, `voice.mapping.collision`, `voice.takebutton`,
`voice.takebutton.note`, `voice.mode`, …) is untouched.

The one question this feature had to answer about a visible control is whether
the completion specification's *Use this button for Composer* switch is offered.
It is not, and the answer is the same as the sentence already on the page: a
pad's button cannot be taken from the game in this build. Offering a switch that
cannot change anything would be the failure the specification names, so nothing
is added. See [`../../technical/CONTROLLER_INPUT.md`](../../technical/CONTROLLER_INPUT.md)
for the measurement.

## Scope

`wolkaraforever/Input/ControllerCommandIngress.{h,m}` and the wiring in
`ControllerInspector.m`, `InputRouter.m`, `Voice/VoiceSettings.{h,m}`,
`Touch/TouchControls.{h,m}` and `Shell/main.m`.

Two files in that list are view-adjacent, and neither draws anything new:

- `Voice/VoiceViewController.m` and `Voice/VoiceTestViewController.m` are **not** modified at all - verified
  with `git diff main...HEAD` over both, which is empty. No key is added to or removed from
  `en`/`de`/`fr`.
- `Touch/TouchControls.m` gains one method that posts a notification carrying the outcome of a
  Composer open. It adds no subview, no constraint, no colour, no string and no layout branch; the
  card it sits beside is the one the Composer already draws (see
  [chat composer](../../technical/CHAT_COMPOSER.md)).

## Changed states

None. The launcher fixture's seventeen reviewed states per matrix simulator are
unchanged, because none of them draws anything this feature touches: the Voice
page's text and layout are byte-identical in the build.

## End-user action

None. A mapped button that already opened the Composer still opens it; it now
gets there without a diagnostic block in front of it. A player who mapped a pad
button and looked for a way to keep it from the game still finds the note that
says it cannot be done.

## Tests

- `wolkaraforever/tools/test_controller_input.sh` - both matrix simulators.
- `wolkaraforever/tools/test_voice.sh` - both matrix simulators.
- `wolkaraforever/tools/test_touch_controls_ui.sh --self-test` - both matrix
  simulators, both interface modes.
- `wolkaraforever/tools/test_translation_sim.sh`.
- `wolkaraforever/tools/check_layers.sh`, `wolkaraforever/tools/check_docs.sh`.
- `wolkaraforever/tools/test_wow_launcher_ui.sh` in `UI_BASELINE_MODE=check` - the whole launcher
  assertion suite **and** the 17-image baseline comparison pass on **both** matrix simulators
  (`UI baseline comparison passed` on iPhone Duo and on iPad Pro 13-inch (M5)), which is the proof
  that no reviewed launcher state moved.

Captures of the Voice page drawn by this branch (mapping card, plus the two voice pages the
fixture opens) are kept locally under `logs/controller-input-qa/` and are never committed.

## Exact SHA

The commit that carries this record on the feature branch; the new module, the
wiring, the fixture, this record and the technical note are in that one commit.

## Risks and boundary

- The ingress changes *ordering*, not behaviour: the same edge reaches the same
  router and fires the same trigger. The fixture proves ordering, duplicate
  suppression, rejection, the overflow bound and one drain per batch, and that
  turning the flag off hands every edge back to the previous path.
- The claim switch is withheld rather than disabled, so the page cannot describe
  a state the app is not in. The record format it would write is implemented and
  tested, with the seam forced on by a test-only property, so the restore paths
  are exercised now instead of being written blind later.
- The Voice page's existing note is what tells a player that a pad button cannot
  be taken. That sentence is asserted to stay on the page by the voice fixture;
  if it is ever removed, the fixture fails rather than a promise going quiet.
- No physical pad is attached to either required simulator. The timings this
  branch records are simulator timings and are reported as such; a physical iPad
  run remains the only evidence for the device targets.
