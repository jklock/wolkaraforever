# Execute: Touch Controller

Implement `PLAN.md` and every task in `TASKS.md` on one feature branch/worktree.
Ship Full/Simple migration, shoulders, optional L3/R3, ability groups, direct
camera lifecycle behavior, localization/accessibility and rollback. Extend the
existing `InterfaceMode`, `LayoutStore`, `TouchGamepadLayout` and reviewed
`WolkaraRoue` mobile path rather than replace it. Do not add commands, macros or
automation; only virtual-controller input and the existing non-automating
companion contract.

Emit bounded `touch-controller` log events for layout migration/change, gesture
recognition, virtual press/release, drag-threshold handoff, cancellation and
lifecycle cleanup. Do not log game interaction or raw touch trails. Add fixture
assertions proving one press has one release and every cancellation clears state.

Create the required additive UI-review record before visible UI code; preserve
the existing launcher contract. Run `test_touch_gamepad_ui.sh`, `test_touch_controls_ui.sh --self-test` and
`test_translation_sim.sh` on iPhone Duo and iPad Pro 13-inch (M5), then
`check_layers.sh` and `check_docs.sh`. Perform live simulator QA on both for
Full/Simple, shoulders, L3/R3, camera drag threshold, rotation, resize,
background/return and cancellation. Capture screenshots for each layout/device
keep captures local and summarize their result plus log evidence in the PR.

Open one PR for this feature. Include source SHA, both-simulator proof,
local-QA screenshot observations, structured logs, migration/rollback evidence,
English/German/French accessibility/locales and known physical-iPad status. Clear
generated validation artifacts before handoff. The PR is not ready until all
completion gates pass.
