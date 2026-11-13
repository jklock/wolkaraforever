# Chat Composer tasks

## 1. State machine and draft

Branch `feature/chat-composer-core`. Add `wolkaraforever/Chat/ChatComposer.{h,m}`
and overlay entries. Integrate it with `TouchControls` and existing
`AKKeyboardTextView`; keep Speech/audio ownership in `Dictation`. Implement Open,
partial/final draft update, edit-pauses-capture, Cancel, background and failure.
Do not inject guest text, add destinations, or change controller claim in this
branch. Add state-transition and stale-generation tests. Run `test_voice.sh`,
`test_touch_controls_ui.sh --self-test`, and `check_layers.sh`.

## 2. Controller opens Composer

Branch `feature/chat-composer-controller-entry`. Wire the existing trigger
callback to Composer Open. Preserve current hold/toggle semantics. A repeated
down edge must make one Composer; release must make none. Instrument callback to
visible boundary. Do not add Send, claim changes, or language changes. Run task-1
tests plus physical timing measurement with diagnostics off and bounded trace.

## 3. Send, Cancel and destinations

Branch `feature/chat-composer-send`. Add at most four disabled-by-default,
player-configured destination records. Validate title/command limits from
`../../07-completion-spec.md`; do not hard-code channels. Send invalidates the
generation, injects text once, Return once, then Escape once only if Composer
opened chat. Failure keeps draft; Cancel sends no text. Test empty/control text,
duplicate Send, late final, Cancel/background and invalid records.

## 4. Close the feature

Add migration fixtures for existing Classic-direct settings, malformed
destinations and downgrade-safe unknown keys. Add English/German/French strings
and VoiceOver assertions for every state/control. Run `test_voice.sh` and
`test_touch_controls_ui.sh --self-test` on iPad Pro 13-inch (M5) and iPhone Duo,
plus `check_layers.sh`; Duo live QA includes keyboard safe area and Dynamic Type.
Record Device Hub status and, if run, prove mic, controller and keyboard entry;
edit; Send; Cancel; background; disconnect; and failed injection without a
duplicate message. Put SHA/simulator/mode and outcomes in PR Proof, keep
generated evidence local, and update docs only with observed results.
