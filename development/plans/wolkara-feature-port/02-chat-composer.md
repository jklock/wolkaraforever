# Phase 2 — Chat Composer

## Outcome

One player-visible Composer owns the in-game message lifecycle.  It uses the
source's reviewed-draft idea but retains Forever's on-device-only, final-only
speech contract.

## What changes for a player

The player presses a mapped button or toolbar control and sees one Composer
panel, not an invisible attempt to type into whichever guest view happened to be
registered.  They can speak, edit with the keyboard, choose an optional saved
destination, Send, or Cancel.  The default is review-before-send.  Existing
direct dictation remains available behind the compatibility choice during rollout.

## Why this is not just a new button

The hard problem is ownership across three asynchronous systems: UIKit text/IME,
Speech callbacks, and guest key injection.  The current code solves pieces of
each but no object owns their joint lifecycle.  The source's toolbar controller
has the useful insight: capture callbacks may update a draft but may never submit
it.  Forever adds stricter requirements: on-device-only speech, final-only
delivery, existing audio-session restoration, accessibility/localization, and a
safe fallback keyboard.

## Public contract

`ChatComposer` exposes `openWithSource:`, `pauseForEditing`, `sendWithDestination:`,
`cancel`, `appDidBackground`, and a read-only state snapshot.  It receives a
small `AKChatTextTarget` protocol—not a generic UIView—that can:

1. open/close the game chat shortcut;
2. insert committed text; and
3. post an explicit special key.

The target is registered by the existing Touch layer.  Composer never searches
windows, reads guest text, infers chat state or touches guest memory.  A target
is valid only while it is the registered target and has a live window.

## Send transaction

1. Confirm the session generation and validate the displayed text.
2. Stop capture and invalidate every speech callback for that generation.
3. If Composer did not already open chat, open it and wait for the target’s
   confirmed readiness boundary; otherwise retain its owned chat session.
4. Insert the normalized committed string once.
5. Post Return once; only on that success post Escape once when Composer owns
   chat closure.
6. Clear the draft, release audio/claim state, publish idle.

Any failure before step 4 leaves the draft visible.  A failure after insertion
is reported explicitly and does not retry automatically, because retry could
send duplicate chat.  Text is bounded, strips control characters, preserves
valid composed Unicode and records no transcript in durable logs.

## UI and accessibility

The panel is hosted by `TouchControls`, so it shares keyboard avoidance,
localized labels and VoiceOver language.  State is readable: Listening,
Finalizing, Ready to send, Sending, Sent, and a concrete error.  Send is disabled
for an empty/provisional marked range.  Cancel is always reachable.  The panel
must not cover the physical controller claim/restoration indication.

## Configuration/migration

Add a delivery mode enum: `classicDirect`, `reviewBeforeSend`.  Existing users
migrate to `classicDirect`; new controller-driven Composer flows default to
review.  Destination records have a schema version and maximum count/label/
command lengths.  A bad record is ignored individually rather than preventing
the rest of configuration from loading.

## Current ownership to consolidate

- `TouchControls.m` owns `AKKeyboardTextView`, draft placeholders, Replace and
  custom fallback keyboard.
- `Dictation.m` owns recording, recognition and direct `touchInsertText:` / optional
  Return delivery to `AKDictation.gameTextTarget`.
- `InputRouter.m` owns mapped-button semantics but does not know whether chat is
  open or a draft exists.

The current direct voice route assumes an already registered target.  The draft
Replace action intentionally does not send Return.  The source controller is
better at the missing product problem: opening a draft, invalidating old speech
callbacks, reviewing text, and sending/closing exactly once.

## State machine

Create `wolkaraforever/Chat/ChatComposer.{h,m}` and map it into `launcher/Chat/`.
Its state is explicit and single-owner on main:

`idle → opening → capturing → reviewing → sending → idle`

Terminal paths are `cancelled` and `failed`, both returning to `idle`.  Each
session has a monotonically increasing generation.  Speech, keyboard and
controller callbacks carry it; a stale generation is ignored before touching UI
or game input.

### Actions

- **Open:** user trigger asks the registered text target to open chat once with
  Return.  Failure leaves no hidden session.
- **Capture:** start existing `AKDictation`; partials live only in the Composer
  draft; final result replaces the provisional segment.
- **Edit:** keyboard uses existing `AKKeyboardTextView` composition behavior;
  editing pauses/cancels capture before the user changes text.
- **Send:** validate the visible draft, invalidate capture callbacks, then issue
  one insert, one Return, one Escape.  Escape is sent only after a successful
  own-chat send, never after an unverified failure.
- **Cancel/background/disconnect:** cancel capture; close chat at most once when
  Composer opened it; never send text.

Keep existing direct final-only delivery as a compatibility setting during the
first release.  Default the new Composer to review-before-send for controller
and toolbar entry; do not silently alter a saved auto-submit preference.

## Chat destinations

Add `ChatDestination` records stored in `wolkaraforever-config.json` through
`Shell/WolkaraForeverConfig.*`: title, command text, enabled, display order.
Commands are user-entered, bounded, printable text and disabled by default.
Examples can be suggested but never assumed.  A destination tap is still an
explicit Send action and follows the same transaction.

## Files to change

| Area | Change |
| --- | --- |
| `Touch/TouchControls.*` | Replace direct draft sending with Composer presentation/actions; retain fallback keyboard and text target delegate. |
| `Voice/Dictation.*` | Add Composer client API; retain audio/recognition implementation and final-only guard. |
| `Voice/VoiceSettings.*`, `VoiceViewController.m` | Migrate auto-submit into an explicit delivery mode; show compatibility explanation. |
| `Input/InputRouter.*` | Trigger `Composer open` rather than invoking speech directly. |
| `Shell/WolkaraForeverConfig.*` | Validate/migrate destination records. |
| `Shell/WKLocalization.*`, string tables | Localize all state, send and failure wording. |
| `Touch/tests/test_touch_controls_app.m`, `Voice/tests/test_voice_app.m` | Add state-machine and composition fixture coverage. |

## Tests and proof

- every state transition; double Open, Send, Cancel and background;
- recognition final/partial/error/timeout and late callback after every action;
- exactly-once sequence assertions for insert, Return and Escape;
- Unicode/IME composition, empty draft, control-character stripping and edited draft;
- destination validation/migration and disabled-by-default behavior;
- Both simulators: controller open where supported, speech review, keyboard
  edit, Send, Cancel and language switch. Device Hub may add physical evidence
  but does not replace the dual-simulator matrix.

## Rollout

Ship Composer behind a saved feature flag for one release.  Preserve direct mode
and provide a clear “restore classic dictation” option.  Remove direct mode only
after device evidence and support data show it is no longer needed.
