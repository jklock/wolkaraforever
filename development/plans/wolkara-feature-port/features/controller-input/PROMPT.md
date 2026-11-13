# Execute: Controller input

Implement `PLAN.md` and every task in `TASKS.md` on one feature branch/worktree.
Do not stop at a spike: resolve claim feasibility, command ingress, Composer
entry, settings/migration and completion gate. Do not edit `platform/`.

Create structured, bounded `controller-input` log events for mapping admission,
enqueue/dequeue sequence/timing, drop/overflow, claim restore and Composer-open
outcome. Never log text, speech, controller serials or user identifiers. Add
fixture assertions for those events and reset counters between runs.

Before code, create the required additive UI-review record if this changes a
visible control; preserve existing launcher UI. Run `test_voice.sh` and
`test_touch_controls_ui.sh --self-test` on both required simulators,
`test_translation_sim.sh`, `check_layers.sh`, and `check_docs.sh`.
Perform live simulator QA on iPhone Duo and iPad Pro 13-inch (M5): map a button,
open Composer, repeat/hold/release, disable claim, background/return and
disconnect. Capture a screenshot for each simulator showing the relevant UI and
keep captures local and summarize their result in the PR.

Open one PR named for this feature. Include source SHA, changed files, both
simulator commands/results, local-QA screenshot observations, log-event
evidence, known physical-iPad status, migration/rollback proof and
no-sensitive-data statement. Clear generated validation artifacts before
handoff. Do not mark it ready until every completion-gate item passes.
