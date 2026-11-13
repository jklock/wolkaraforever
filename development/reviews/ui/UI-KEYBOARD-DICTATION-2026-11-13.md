# UI review: speech language in the in-game draft composer

## Classification

`additive`. One optional control is added to the in-game draft composer, which has no reviewed
golden image. Every launcher surface, identifier, label, row, card, order, colour, geometry,
safe-area treatment and default state is untouched, and every committed baseline image is
byte-for-byte unchanged - proven by the comparator on both matrix simulators, not asserted.

The speech-language control was first sketched on the Key / Button Configuration page. The
comparator refused it on the iPad Pro 13-inch (M5): `voice-settings.png` and `wow-voice-de.png`
differed in a region at the bottom of that page, because the taller iPad viewport shows the last
card. An additive feature may not change an existing golden image, and a UI-contract amendment
may not be folded into a feature pull request, so the control moved to the surface where the
language is actually used and where no baseline exists. This record is the account of that
decision, and of the evidence for it.

## Exact SHA

The commit on `feature/keyboard-dictation` that carries this record. This record was written
before the visible code, as the UI policy requires.

## Changed states

1. **Language** (`wolkaraforever.keyboard.language`) is new, in the draft composer's row, left of
   the clear and Replace controls. It shows the language the recogniser will use, and its menu
   offers `System`, `English`, `German`, `French` and `Spanish`, persisted as `system`, `en-US`,
   `de-DE`, `fr-FR` and `es-ES` under `AKVoiceSpeechLanguage`. `System` is the default and
   follows the iPad; the app's own language never changes it. Spanish is the game's fourth text
   locale and is offered as the current game-text locale choice.
2. The control reports its choice as `accessibilityValue` and keeps `Language` as its label, so
   VoiceOver reads "Language, German". Choosing is one bounded value posted to the shell: no key
   and no text reach the guest, and the draft is not changed.
3. Nothing else moves. The launcher's home page, Add-On Manager, the Key / Button Configuration
   page and the Test Voice page keep their identifiers, labels, order and geometry, and their
   baselines are unchanged.
4. A language this iPad cannot recognise on device falls back to System for that hold and says
   so; on-device recognition stays mandatory.

## End-user action

In game: open the keyboard so the draft composer is up, tap the language control, choose a
language. It affects the next dictation hold. Nothing is installed, no game file is written and
nothing is sent to the game.

## Screenshots

Recorded locally on the iPhone Duo and iPad Pro 13-inch (M5) simulators for the live-QA sequence
in the pull request: the composer with the language control, the draft editor with accented text,
a combining mark and an emoji, and the composer after choosing German. Generated captures stay
local, as the repository workflow requires; the reviewed launcher baselines are unchanged and
unmodified.

## Tests

- `wolkaraforever/tools/test_touch_controls_ui.sh --self-test`, both matrix simulators and both
  interface modes: the language control exists, is an accessibility element, is labelled, hinted
  and carries a value, its menu offers exactly five choices, choosing posts exactly one bounded
  value and changes neither the guest's text nor the draft, and a published value updates the
  control's title and value. The same run proves the committed Unicode sequence (`é`, combining
  acute, `ñ`, `ü`, emoji, deletion, cancelled composition, Return) and the
  `composition.commit`/`composition.cancel` order.
- `wolkaraforever/tools/test_voice.sh`, both matrix simulators: storage, validation, migration to
  System, the unavailable-locale fallback, request construction per capture, a mid-capture
  language change that cancels and restarts, stale-callback rejection, and the bounded
  `keyboard-dictation` record's order and absence of transcript.
- `wolkaraforever/tools/test_wow_launcher_ui.sh` in check mode, both matrix simulators: every
  reviewed image, including `voice-settings.png` and `wow-voice-de.png`, compares within
  tolerance. This is the evidence that the added control did not disturb the launcher.
- `wolkaraforever/tools/check_ui_policy.sh --review UI-KEYBOARD-DICTATION-2026-11-13.md` keeps the
  launcher contract and the reviewed images as they are.

## Risks and boundary

- The control is only reachable while the game's text field is up, because that is the composer.
  A player sets the language where they dictate; the setting persists for every later hold and
  survives export and import.
- It is recognition configuration, not app chrome: it never follows
  `WolkaraForeverAppLanguage`, and changing the app language never changes it.
- An unavailable language is not silently replaced for ever: the hold falls back to System, the
  event is recorded as `failure reason=languageUnavailable fallback=system`, and the user is told.
- The physical iPad was not used for this change; every result in the pull request names the
  simulator that produced it.
