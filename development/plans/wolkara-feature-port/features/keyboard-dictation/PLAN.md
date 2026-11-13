# Keyboard and dictation plan

## Outcome

Committed Unicode arrives correctly in the game, editable marked text remains
native, and speech language is an explicit, safe user choice without weakening
on-device recognition or Composer review.

## Why

In-game text composition and dictation are unreliable because editable and
committed text boundaries are not proven end-to-end, while recognition is fixed
to one language. Source language UI is inspiration only; its direct key-submit
model is not acceptable here.

## Acceptance

Fixtures cover accent, combining mark, ñ, ü, emoji, deletion, cancelled
composition, Return, locale migration, unsupported locale and stale callbacks.
Both simulators verify one composition sequence and one mid-capture language
change; Device Hub is additional evidence if a physical claim is made.

## Completion gate

Language/settings migration preserves current recognition behavior on invalid or
unsupported values. Disabling the feature restores the existing final-only path;
no recognizer/audio session, marked text, draft or guest key remains active after
Cancel, error, background or scene teardown. Localize labels/errors and verify
VoiceOver focus. Run composition/voice/translation suites and live UI sequence
on both required simulators; Duo must cover safe-area keyboard movement and
Dynamic Type. Device Hub may additionally prove the complete Unicode sequence,
language switch during capture, permission refusal and audio restoration. Record
source SHA, both simulator/mode outcomes and physical status in PR Proof before
changing FEATURES or COMPATIBILITY documentation.
