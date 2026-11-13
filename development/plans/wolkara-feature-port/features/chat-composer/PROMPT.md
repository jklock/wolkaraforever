# Execute: Chat Composer

Implement `PLAN.md` and every task in `TASKS.md` on one feature branch/worktree.
Ship the complete state machine, all entry paths, persisted migration, Send,
Cancel, configurable destinations, rollback and completion gate. Do not edit
`platform/` or auto-send text outside the specified transaction.

Emit bounded `chat-composer` log events for state transition, generation,
entry source, Send/Cancel outcome, failure, lifecycle cleanup and rollback.
Do not log draft, dictated or game text. Add fixture assertions that every
terminal state emits the expected outcome and stale callbacks emit no send.

Create the required additive UI-review record before visible UI code; preserve
the existing launcher contract. Run `test_voice.sh` and `test_touch_controls_ui.sh --self-test` on iPhone Duo
and iPad Pro 13-inch (M5), then `check_layers.sh` and `check_docs.sh`. Perform
live simulator QA on both: toolbar mic, keyboard mic and controller entry; edit;
Send; Cancel; background/return; disconnect; failed send. Capture screenshots
of Composer idle/ready/error state; keep them local and summarize the result in
the PR.

Open one PR for this feature. Include exact SHA, test/device results, live-QA
local-QA screenshot observations, structured log evidence,
English/German/French localization/accessibility proof, migration/rollback proof
and known physical-iPad status. Clear generated validation artifacts before
handoff. Ready requires every completion-gate item, not just a passing unit
fixture.
