# UI review: Chat Composer (in-game review-then-send card)

## Classification

`additive`. It adds one optional in-game surface — a Composer card that replaces the draft
card's action row while the Composer is active — and adds no launcher element. Every frozen
launcher contract value is untouched: no card, row, inset, popup, identifier or baseline image
changes, and the existing draft/Replace/Clear controls keep their identifiers, geometry and
default behaviour. The Composer is off in substance for anyone whose settings predate it (see
`Delivery mode` below), so a v1.0.10 user sees exactly the interface they had.

## Exact SHA

Recorded in the pull request's Proof section against `feature/chat-composer`; this record is
written before the visible UI code, as the policy requires.

## Changed states

1. **Composer card — idle/ready.** While review-then-send is the delivery mode and the Composer
   is open, the draft card's bottom row shows `Cancel`, the configured destination chips, the
   microphone, the Composer settings and `Send`. The classic row (`Clear`, `Replace`) is hidden
   only while that state is on screen, and the card grows by one 44-point row so nothing moves
   horizontally.
2. **Composer card — listening.** The state line reads `Listening…`; `Send` is disabled while
   the recogniser is provisional, exactly as it is for an empty draft.
3. **Composer card — error.** The state line reads the concrete failure (`Message was not sent.`)
   and the draft is retained; the row keeps `Cancel` reachable.
4. **Composer settings sheet.** A sheet opened from the card's gear: delivery mode
   (`Review then Send` / `Classic direct`), the four destination rows (title, command, enabled,
   add/remove) and `Done`. This is where a player opts in or restores classic dictation, so the
   launcher Voice page needs no new row and no baseline changes.

## End-user action

Controller button, the layer keyboard's microphone key, or the system keyboard microphone opens
the Composer; type or dictate; `Send` sends once, `Cancel` sends nothing. The gear → delivery
mode restores classic dictation, which is also what a pre-existing installation keeps.

## Screenshots

Captured locally for QA on iPhone Duo and iPad Pro 13-inch (M5): Composer idle, Composer ready
and Composer error. They are QA evidence and are not committed, per
`development/guides/REPOSITORY_WORKFLOW.md`; no approved launcher baseline is re-recorded by
this change.

## Tests

`wolkaraforever/tools/test_touch_controls_ui.sh --self-test` (both interfaces, both matrix
simulators) carries the in-game assertions: the classic row is unchanged, the Composer row
appears only in review mode, Send injects once, Cancel injects nothing.
`wolkaraforever/tools/test_voice.sh` carries the speech bridge and the destination/migration
rules.

## Risks and boundary

- **One row taller while composing.** The card grows from 82 to 134 points above the keyboard.
  On the iPhone Duo in landscape the card stays inside the safe area and above the keyboard;
  the assertion in the touch fixture measures it rather than asserting the number.
- **No physical iPad evidence.** The visible claim is exercised on the two matrix simulators
  only; the iPad Pro 12.9-inch (5th generation) status is reported as not run unless Device Hub
  is used.
- **Nothing in the launcher moves.** The delivery-mode and destination controls live in the
  in-game sheet precisely so that no approved launcher baseline has to change in a feature PR.
