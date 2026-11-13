# UI review: Touch Controller 2 — Simple layout, stick buttons, ability zones

## Classification

`additive`. Every existing launcher page, card, row, identifier, label, order, colour and
geometry in `UI_POLICY.md` stays exactly as v1.0.10 shipped it, and no golden image moves. The
reviewed touch surfaces gain optional states; nothing already on screen is moved, resized,
renamed or reordered.

Two surfaces change, both inside `wolkaraforever/Touch/` and both additively:

- **Touch control settings** (`wolkaraforever.controls.settings`) gains three rows below the
  rows it already has: **Simple layout**, **Stick buttons (L3/R3)** and an **Ability zones**
  count with add/clear buttons. They are appended to the options column, so every existing row
  keeps its position, identifier and label.
- **The on-screen gamepad** can draw the Simple arrangement, an L3/R3 press and up to six
  ability zones. These appear only after the user turns them on; a fresh install and every
  existing installation draw exactly what they draw today (Full, no stick buttons, no zones).

The launcher's **Controller Layout…** sheet gains four actions at the end of its existing list
(Simple layout, Stick buttons, Add ability zone, Clear ability zones). No launcher row, card,
image or identifier is added or changed; the sheet is the same sheet with more choices in it.

## What the states are

| State | Default | What a person sees |
| --- | --- | --- |
| Full | yes — every existing install | The layout every release through v1.0.10 has: both rings with their sectors, both triggers, both shoulders, the menu button. |
| Simple | no, opt-in | Both sticks, the four face buttons (A/B/X/Y), LB and RB at the far top corners with their *own* saved positions, and the menu button. LT, RT and the D-pad sectors are not drawn. |
| Stick buttons (L3/R3) | off, and not usable on Apple's virtual controller | A double tap on either stick presses that stick's own button for a bounded moment. Measured: the virtual controller's extended profile has no stick-button element, so the row is present, disabled, and says why; a gesture that asks for it is refused (`reason=unsupported`). Ordinary stick movement and camera drags are unchanged and delayed by nothing. |
| Ability zones | off — none exist | Up to six user-placed circles; each sends exactly one gamepad element while a finger is on it and releases it on lift. Nothing is sent that a touch did not cause. |

## End-user action

- **Turn Simple on or off**: Settings row, or Controller Layout… → *Simple layout*. Off restores
  Full with the positions it had; Simple's own positions are kept for next time.
- **Turn stick buttons on**: Settings row, or Controller Layout… → *Stick buttons*. Off by
  default; nothing on screen changes when it is off. On Apple's virtual controller the row is
  disabled and explains that this controller has no stick button.
- **Add or clear ability zones**: Settings row buttons, or Controller Layout…. A zone is dragged
  in the layout editor like any other control, and tapping one while editing cycles the element
  it sends, named on the zone itself.
- Nobody who does not open these rows sees a difference: the Full arrangement, the existing
  rows and every existing identifier are untouched.

## Risks and boundary

- Simple removes LT, RT and the D-pad from the screen. It is a deliberate, opt-in arrangement;
  turning it off restores them at their saved positions, and no saved setting is deleted.
- The stick-button row is disabled rather than hidden, because hiding it would move every row
  under it. Its hint says why: Apple's virtual controller has no stick-button element
  (measured 2026-11-13: the profile lists the face buttons, the shoulders, the triggers, the
  menu, the D-pad and the sticks' directions, and `-leftThumbstickButton` is nil). The
  positive path is therefore proved against a controller that does carry the element, and the
  app refuses the gesture on one that does not instead of pretending to send it.
- Ability zones duplicate an element on purpose (two surfaces, one button). The virtual
  controller's button value is 1 while *any* surface holds it and returns to 0 only when the
  last one lets go, so a release cannot cut another finger's press short.
- The gesture and press logging is bounded: one tag, a closed key list, values that cannot carry
  a coordinate, a path, a word the player typed, or any game interaction.
- No game command, macro, sequence, add-on or memory access is added. Every new path ends in a
  `GCVirtualController` button value caused by a finger the user put on the screen.
- VoiceOver: each new row announces its own label, its value and its hint; the ability zone
  announces the element it sends and that it is edited by tapping while editing. German and
  French strings are in the same tables as the existing touch strings, and the German UI run
  asserts nothing English is drawn on the settings panel.

## What did *not* change, and how that was checked

The direct-camera work is the one place this feature touches an existing gesture, so it was
reviewed against the code it wraps rather than from memory:

- `TouchTrackpad.c` keeps its own rule — `AKTrackpadCancel` releases a held button once and then
  suppresses the rest of the gesture until every finger lifts. A *cancelled touch* therefore
  keeps that suppression; only the exits the app causes (background, resign, a panel, a
  rotation, a controller, teardown) clear the gesture completely. The fixture asserts the two
  rules separately.
- `TouchControls` keeps `backgroundInput:` → `logInputSuspended` → `dismissKeyboard`, and the
  `input suspended (draftFirstResponder=…)` line it has always written.
- The launcher is unchanged: `check_ui_policy.sh --review UI-TOUCH-CONTROLLER-2026-11-13.md`
  passes on both simulators against the committed baselines.

## Tests

`test_touch_gamepad_ui.sh` (iPhone Duo and iPad Pro 13-inch (M5)) drives the layout migration,
both arrangements, the double tap, the ability zones, the press/release pairing and every
cancellation path; `test_touch_controls_ui.sh --self-test` covers the toolbar, keyboard and
lifecycle contracts it already covered, plus the direct-camera lifecycle; `test_translation_sim.sh`
covers the adapters around them. `check_ui_policy.sh --review UI-TOUCH-CONTROLLER-2026-11-13.md`
proves no launcher page moved.
