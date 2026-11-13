# Phase 3 — Keyboard, speech and Touch Controller 2

This phase improves three related player-facing surfaces, but keeps them as
separate PRs so a touch-layout change cannot hide a text-input regression.

## 3A. Keyboard and composed text

### What, why and how

The player must see the same committed Unicode in the game that they saw on the
native keyboard.  The failure to avoid is turning a composed sequence into guessed
hardware keycodes: accents, IMEs and emoji then disappear or duplicate.  Keep
provisional marked text entirely inside `AKKeyboardTextView`; on commit pass one
immutable string through a narrowly tested adapter seam.  Retain current ASCII
and special-key delivery, and keep Return/Tab/Escape/delete as explicit controls
rather than characters hidden in a text payload.

### Current code

`Touch/TouchControls.m` provides `AKKeyboardTextView`, UIKit marked-text
handling, a secure guest-facing `UIKeyInput`, special keys and a fallback custom
keyboard.  The adapter delegate ultimately emits guest key events.  Existing
tests exercise draft marking; they do not establish real guest-field composition.

### Change

Add an adapter-facing committed-text seam rather than enumerating Unicode into
arbitrary virtual keycodes.  It must preserve the existing ASCII/special-key
route, retain explicit Return, and deliver a committed composed sequence in
order.  The Composer owns the editable draft; the guest route receives only
committed text.

### Required tests

`é`, combining acute, `ñ`, `ü`, emoji/ZWJ sequence, deletion, marked-text
replacement, cancelled composition and Return. Run against the existing
`test_touch_controls_app.m` fixture and a guest-text-target fixture on both
required simulators. Add physical Device Hub evidence for the same sequence only
when making a physical claim.

## 3B. Speech language and quality

### What, why and how

Speech language is recognition configuration, not app chrome.  Add a validated
persisted `speechLanguage` setting with `system` and explicit supported BCP-47
values; app language must never silently change it.  Construct the recognizer
for the selected locale at session start, availability-guard dictation hints and
punctuation, and record capabilities—not audio or words—in diagnostics.  A
language change creates a new Composer generation before cancelling the old task.

### Current code

`Voice/Dictation.m` constructs `SFSpeechRecognizer` as `en-US`; `VoiceSettings`
persists words/mode/auto-submit but not speech language.  It requires on-device
recognition and rejects partial results for direct delivery.

### Change

Add a validated `speechLanguage` setting with `system`, supported game-text
locale, and explicit language options.  Do not tie it silently to app language.
In the recognizer request, evaluate `SFSpeechRecognitionTaskHintDictation` and
punctuation support with availability guards.  Changing language while Composer
is active cancels the old task, increments its generation and restarts capture
without another chat-open key.

### Tests

Settings migration, unavailable locale fallback, request construction, language
switch during partial/final callbacks, no duplicate chat keys, and on-device-only
refusal.  Device proof records the selected locale and result state, never audio
or transcript content.

## 3C. Touch Controller 2

### What, why and how

Build one layout model rather than a pile of toggles: versioned mode, per-mode
positions, gesture preferences and ability-group records in `AKGamepadLayout`.
Existing layouts migrate to Full; Simple begins from product defaults.  Gesture
recognizers fail before touching the virtual pad if motion crosses the direct
camera threshold; every background/configuration/disconnect path reaches one
`releaseAll` implementation.  Ability groups publish only explicit native
virtual-controller events—never game commands or automated sequences.

### Scope

Use source ideas as one native interaction package:

- Full and Simple layouts; Simple has its own saved LB/RB positions/defaults.
- Optional double-tap L3/R3 with drag-threshold rejection and no added delay to
  ordinary camera/stick movement.
- Configurable ability zones/modifier groups, only where they produce a
  user-triggered virtual-controller event.
- Direct-camera gesture ownership that survives guest cursor recentering and
  repeated drags.

### Existing owners

`Touch/TouchGamepad.*`, `Touch/TouchGamepadLayout.*`,
`Touch/TouchControls.*`, and the AppKit touch patches.  Source's implementation
belongs mostly in `translation/AppKit`; Forever must instead own replacements in
`wolkaraforever/Touch/` and add only narrow patches where the platform hook is
unavoidable.

### Design constraints

- Full/Simple positions are versioned preferences; existing layout keys migrate
  to Full and no control jumps on update.
- L3/R3 recognizes a double tap only after motion remains beneath the existing
  drag threshold.  It releases virtual buttons after a bounded duration and on
  background/configuration/disconnect.
- Ability groups cannot synthesize a sequence without an explicit user touch.
- Controller claims from phase 1 always win over overlapping touch controls.

### Tests/proof

Extend `test_touch_gamepad_app.m`, `test_touch_controls_app.m`, direct-camera
fixtures and `test_translation_sim.sh`.  Prove settings migration, layout
isolation, gesture cancellation, virtual-controller release and no direct-camera
regression on both simulators; use Device Hub on the physical iPad when
available for gesture feel and controller coexistence.
