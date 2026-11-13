# Feature-port execution prompt

Use `PLAN.md` for prerequisite order, then the feature's `PLAN.md` and
`TASKS.md` as the acceptance contract. Complete every task and the feature's
completion gate; do not substitute a partial implementation or say it is done
pending device evidence. First prove the specific gap against current
WolkaraForever behavior. Do not cherry-pick or merge the source repository.

Work in one short-lived branch and worktree.  Keep `platform/` byte-identical;
put product behavior in `wolkaraforever/` or an explicitly maintained patch.
Add the narrowest owning test before or with the behavior change, run it on the
required simulators—iPhone Duo and iPad Pro 13-inch (M5)—run
`wolkaraforever/tools/check_layers.sh`, and update documentation only when user
behavior or setup changes. Treat Duo as a first-class mobile target: exercise
its automatic/iOS-on-Duo interface behavior, safe areas, Dynamic Type and
one-column layout while preserving iPad's existing layout. Start each UI change
with the required UI-policy review record; UI work is additive-only unless a
separate approved contract amendment exists.

Physical Device Hub work is additional user-operated evidence. Record its
status, never present simulator work as physical proof, and leave the device at
its normal home screen with the app running when used. Preserve game data and
never automate the game. Keep generated screenshots, logs and validation output
local-only; put exact SHA, commands, both simulator/mode outcomes, local-QA
observations, physical status and cleanup confirmation in the PR Proof section.
Do not commit, attach, or link generated validation artifacts; run
`wolkaraforever/tools/clear_validation_reports.sh` before handoff.
