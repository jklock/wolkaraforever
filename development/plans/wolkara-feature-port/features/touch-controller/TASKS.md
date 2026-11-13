# Touch Controller tasks

## 1. Layout migration

Branch `feature/touch-controller-2`. Read `TouchGamepad`, `TouchGamepadLayout`,
`TouchControls`, haptics, touch fixtures and settings persistence. Version
the current `InterfaceMode`, `LayoutStore`, `TouchGamepadLayout` and
`WolkaraRoue` contract; version only the owning persisted layout value, migrate
every old value to Full, make Simple opt-in, and give
Simple independent shoulders. Do not change existing Full defaults. Test old
config migration, layout switching, rotation and lifecycle cleanup.

## 2. L3/R3 and ability groups

In the same feature only after task 1 tests pass, add optional-off L3/R3
double-tap with a drag threshold. Ensure press/release pairing on every lifecycle
exit. Add ability groups only as explicit virtual-controller press/release events;
never issue game commands. Run `test_touch_gamepad_ui.sh`,
`test_touch_controls_ui.sh --self-test` and translation simulation on both
required simulators; record Device Hub status and add gesture proof if run.

## 3. Close the feature

Add fixtures for corrupt/newer layout values, downgrade-safe defaults, Dynamic
Type, VoiceOver focus/order, rotation, resize, scene background/foreground,
cancel and virtual-controller disconnect. Add English/German/French labels/hints.
Run the gamepad/touch/translation suites on iPad Pro 13-inch (M5) and iPhone Duo,
then `check_layers.sh`; on Duo verify current mobile mode/layout rather than
iPad defaults. Record Device Hub status and, if run, prove every shipped
gesture/layout with no stuck virtual press after each lifecycle transition. Put
SHA/simulator/mode and outcomes in PR Proof; keep generated evidence local and
update docs only with observed results.
