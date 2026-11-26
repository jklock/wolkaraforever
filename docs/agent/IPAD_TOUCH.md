# iPad touch implementation

> Verified: 2026-11-26 · Source: `9e0dc4e` plus this layer · Proof: `check_layers.sh`, `test_touch_contract_wiring.sh`

The stored interface mode `ipadtouch` selects the TouchPlay input path. It is an explicit choice and Automatic never resolves to it. Until the launcher offers that choice, tests can select it through `WolkaraForeverInterfaceModeV1`. Every input change is gated by `AKInterfaceModeIsTouchPlay()`; the other modes retain their existing controls.

TouchPlay is installed by the player with the existing add-on manager. It is not bundled. The add-on writes button rectangles, chord keys, hand preference and walk settings to its SavedVariables. `TouchContract` reads that file at game start. `TouchAreas` owns touches inside the buttons, posts their individual keys and draws press feedback. A missing contract leaves plain game touches available and shows `touch.contract.missing` once per start.

`TouchWorldSignal` decodes the add-on's short secure-input pulses: in world, out of world, sheet and window-open states. `TouchAreas` enables buttons according to that state. `TouchGamepad` supplies a separate walk stick using W, A, S and D, with a deliberate auto-run lock. The host patches route the remaining touches to world gestures, keep button chords through a game frame, let the walk stick yield to a pinch, and release held input when the app leaves the foreground.

`TouchTextBridge` provides the game's text field and a password field for typing by hand. `TouchControls` adds the iPad touch toolbar, chat channel chips, Send button, a separate trackpad preference, and one release path for held input. It does not create a controller overlay in this mode.

`InterfaceMode` contains the crash guard: two consecutive unclean starts cause a fallback to iPadOS. A clean exit, a failed start and a backgrounded session are counted according to the session helpers. The picker change wires the shell helpers at start and exit and presents the fallback notice in the launcher.

## Layer files and patches

The layer carries `Touch/{InterfaceMode,TouchAreas,TouchContract,TouchTextBridge,TouchWorldSignal,TouchControls,TouchGamepad}.{h,m}` and the focused fixtures under `Touch/tests/`. Patches `0080` through `0088` update the prepared host view. Patch `0079` makes the host's mobile gate follow the stored interface mode. `overlay.map` maps the layer files to their prepared paths.

## Verification

`test_touch_contract_wiring.sh` checks the shell's contract load. `test_crash_guard_wiring.sh` checks the session and launcher call sites. `test_touch_controls_ui.sh` and `test_touch_gamepad_ui.sh` run the input fixtures on the matrix simulators. `check_layers.sh`, `check_agent_docs.sh`, `check_docs.sh` and `test_localization.sh` check assembly and documentation. Device and simulator operations use the project scripts only.
