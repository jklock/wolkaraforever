# Keyboard and dictation audit

This is the first feature family to evaluate.  The source work is useful, but it
must not be copied as a whole because WolkaraForever already has a more deliberate
ownership model for input, drafts and speech.

## What is already in WolkaraForever

- `wolkaraforever/Touch/TouchControls.m` supplies the keyboard toggle, secure
  native `UIKeyInput`, Escape/Tab/arrows/Return, trackpad and a custom fallback
  keyboard when iPadOS suppresses the software keyboard.  Its input reaches the
  guest only through the product-owned delegate; it does not inspect guest text
  or selection.
- The same class has an editable native draft (`AKKeyboardTextView`).  It keeps
  marked text and dictation placeholders separate from committed text, and its
  explicit **Replace** action sends sanitized committed text without synthesizing
  a Return.
- `wolkaraforever/Voice/Dictation.m` requires on-device recognition, records to
  a local file, waits for a final result, sends exactly once to the registered
  text target, and sends Return only when the user enabled auto-submit.  It does
  **not** itself open chat, maintain a reviewed game-chat draft, or close chat.
- `VoiceSettings` persists enablement, hold/toggle mode, trigger mappings,
  auto-submit, trailing space, and bounded custom words.  There is no persisted
  recognition-language setting; the real recognizer currently uses `en-US`.

## Source review

| Source | What it actually changes | Comparison | Disposition |
| --- | --- | --- | --- |
| PR #1, `5c017d0` | Secure `UIKeyInput`, composed-character enumeration, accessory editing keys, keyboard and touch trackpad. | The current controls retain these core capabilities and add the custom fallback keyboard, draft editor, haptics, configuration, localized UI and safe text-target registration. | **Do not port.** Treat it as provenance; keep current implementation. |
| PR #19, `bb8ad20` | Adds speech task hint/punctuation; passes an explicitly selected locale; language switch cancels the old recognizer, invalidates callbacks, clears the reviewed draft and restarts without extra Enter/Escape. | Current code has no locale setting and no reviewed-toolbar controller. It has a native draft, but dictation normally delivers final text directly to the registered game target. | **Split candidate.** Task hint/punctuation can be evaluated independently. Language selection requires a product contract and draft-flow integration. |
| PR #19, `f47931f` | Sends composed host text to the current responder instead of relying on virtual key code 255. | Current draft editor preserves UIKit marked text. The game text route still delegates text to the adapter, so this must be tested with accents, combining marks and emoji at the actual guest target. | **Reproduction first.** Port only a demonstrated composition gap, not its memory-journal bundle. |
| PR #20, `651bd26f` | Closes chat after typed/dictated channel drafts; guards duplicate/late sends. | Current Replace deliberately does not send Return. Voice auto-submit is separate. The source opens chat once, reviews the text, sends once, and closes once. | **High-priority opt-in candidate.** Keep Replace unchanged; add a distinct Send action behind a toggle. |
| PR #20, `9f87823` | Adds six fixed chat destinations, command construction and colored buttons. | Current product has no destination model. Fixed channel numbers and slash bindings must not be assumed. | **Opt-in candidate.** Ship no hard-coded channels; let the player enable individual destinations and set their command text. |

## Recommended implementation sequence

1. Add a regression fixture that exercises current keyboard delivery to a game-text
   target with `é`, combining accent, `ñ`, `ü`, emoji, deletion, Return and a
   cancelled composition.  Run it on iPhone Duo and iPad Pro 13-inch (M5).
2. If composition fails, make the smallest adapter/target change that preserves
   UIKit's committed text ordering.  Do not read game text, selection or chat state.
3. Add `SFSpeechRecognitionTaskHintDictation` and punctuation only behind focused
   fake-request coverage and a physical on-device speech check.  Keep
   `requiresOnDeviceRecognition` mandatory.
4. Add an opt-in **review then send** path modelled on the source controller:
   open chat once at the user's request, keep speech in a visible native draft,
   cancel/invalidate late callbacks before Send, then insert text, Return and
   Escape once.  Keep the current Replace action unchanged.  This directly
   addresses the current path's weakness: it requires chat already to be open
   and a game target already to be registered, so it can feel unreliable during
   play even when speech recognition itself succeeds.
5. Add opt-in configurable chat destinations to that reviewed draft.  Each is a
   user-entered command (for example `/say`), disabled by default; no assumed
   channel number, binding or game state.
6. Design the language setting before coding it: separate persisted **speech
   language**, defaulting to the game text locale only when supported, with the
   app language never silently changing it.  Changing language must cancel a
   current session, invalidate stale results, and never open/send/close chat twice.
7. Decide whether final dictation should remain direct-to-target or become a
   reviewed draft.  Preserve the final-only and exactly-once guarantees either
   way.  A reviewed-draft mode is safer for language switching; it must be an
   explicit user choice rather than a silent replacement of auto-submit.

## Acceptance evidence

- Focused keyboard/composition and voice suites pass on **iPhone Duo** and
  **iPad Pro 13-inch (M5)**.
- Device Hub, when available, proves keyboard, dictation start/stop, a language
  switch and one send path on the **iPad Pro 12.9-inch (5th generation)**
  without input automation. It does not replace the required simulator matrix.
- The test proves stale callbacks do not insert text, no failed/partial result
  is delivered, and a mapped input remains governed by the existing ownership
  switch.
- It separately proves: one request opens chat once, Send emits exactly one
  insert/Return/Escape sequence, Cancel emits at most one Escape, and no default
  or configured destination can send without an explicit user tap.
