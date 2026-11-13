# Execute: Keyboard and dictation

Implement `PLAN.md` and every task in `TASKS.md` on one feature branch/worktree.
First prove committed Unicode behavior; then complete language selection,
recognizer lifecycle, settings migration, accessibility/localization and the
feature completion gate. Do not inspect game text/selection or synthesize keys.

Emit bounded `keyboard-dictation` log events for composition commit/cancel,
recognizer language/session/generation, permission/result/failure and audio
restoration. Never log transcript, draft text, audio, identifiers or keys. Add
fixture assertions for expected event order and absence of send after cancellation.

Create the required additive UI-review record before visible UI code; preserve
the existing launcher contract. Run `test_voice.sh`, `test_touch_controls_ui.sh --self-test` and
`test_translation_sim.sh` on iPhone Duo and iPad Pro 13-inch (M5), then
`check_layers.sh` and `check_docs.sh`. Perform live simulator QA on both with
accented text, combining mark, ñ, ü, emoji, deletion, Cancel, language switch
during capture, permission refusal and background/return. Capture screenshots
of keyboard/draft/language UI; keep them local and summarize their result in the
PR.

Open one PR for this feature with exact SHA, test results by simulator,
local-QA screenshot observations, log evidence, English/German/French locale
migration/rollback proof, privacy statement and known physical-iPad status.
Clear generated validation artifacts before handoff. Do not mark ready while any
completion gate is unproven.
