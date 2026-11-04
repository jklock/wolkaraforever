# Validation: Controller Manager, claim model (`controller2`)

- Commit: `63d63fd` (branch `controller2`, **not merged, no PR opened**)
- Recorded: 2026-11-04
- Host: macOS (arm64), Xcode 27.2
- Device: iPad Pro (12.9-inch, 5th generation) — `iPad13,9`, UDID `00008103-000E09A10EC3001E`
- iPadOS: **27.0.1**
- Execution mode: `developer-service`
- Build: `GUEST_EXE=build/guest-probe/WorldOfWarcraft wolkaraforever/tools/install.sh --replace-running`
  (which includes the guest GameController adapter, because the build is told which application it
  is for and routing needs it)

## Results

| Check | Result |
| --- | --- |
| `test_controller_manager.sh` | PASS — including `CONTROLLER_MANAGER_CLAIM_PASS` |
| `test_gamecontroller_facade.sh` | PASS |
| `test_touch_gamepad_ui.sh --self-test` | PASS |
| `test_touch_gamepad_ui.sh --self-test-input` | PASS (real `GCVirtualController`) |
| `test_wow_launcher_ui.sh` | PASS — 76 s, twice consecutively |
| `test_voice.sh` | PASS — 307 checks |
| `check_layers.sh` | PASS — platform byte-identical, 536 localization keys |
| `check_docs.sh` | PASS — 92 documents, every link resolves |
| `check_controller_targets.sh` | PASS — 12 targets, each offered and writable |
| `check_controller_actions.sh` | PASS — 1 action, offered by the page, named in English and German |
| `git diff --check` | clean |
| device `--selftest=controller-manager` | **PASS 17/17** |
| device `--selftest=controller-routing` | **PASS 22/22** |
| device `--selftest=controller-situations` | **PASS 8/8** |
| device `--selftest=controller-latency` | **PASS 3/3 — 600 samples, median 1.0 µs, worst 9.8 µs, 0 over 1 ms** |
| physical pad: routing off, pass-through, analog, sticks, D-pad, claims, disable-while-held, disconnect/reconnect | **NOT RUN — no controller attached** (`inspector: 0 controller(s) connected`) |

## What each device test asserts

`controller-manager` (17) — the card and the page: the card exists on the home page with its own
switch and status sentence; the switch is off until asked; the page draws its switch; switching on
stores only `WolkaraForeverControllerRouting`; the manager follows; the page says what this build
can do; switching off clears both; the disclosure is present; reassigning is inert with no
controller connected. The user's own value is restored.

`controller-routing` (22) — the chain with no hardware: a hidden virtual controller connects and a
second is refused; a routed reserved button has its gesture released, an ordinary button is left
alone, unrouting gives it back; a press on a real element arrives as the mapped virtual button; the
adapter's calls move the controller a guest would enumerate; a reassignment changes the target and
the old one produces nothing; trigger analog, stick and D-pad are carried; routing on offers the
guest exactly one controller and never the pad being read; routing on with no virtual pad offers
nothing; switching off releases every value and gives every gesture back; nothing is left held.

`controller-situations` (8) — the three situations, named: no pad (capture on and off, Tolkara's
gamepad in both), pad with capture on (virtual only), pad with capture off (the real pad again).

`controller-latency` (3) — 300 presses and 300 releases: exactly 600 samples, every one below 1 ms,
median and worst reported.

## Defects this validation found, and fixed

1. **Releases were routed twice.** A button carries both a `pressedChangedHandler` and a
   `valueChangedHandler`; repeat suppression applied only while pressed, so every release posted a
   second identical value. Now a value is sent when it differs from the last one sent — a release is
   still never missed, because either the value changed or nothing was held.
2. **The latency measurement was not measuring.** The entry tick was thread-local and set in one
   handler but read on a path the other handler also takes, so the replay after a profile change
   subtracted from zero and reported a sample of 294 billion microseconds. The routing step now
   times itself, one sample per value it actually sends.
3. **Choosing a target for a claimed control left the dictation trigger behind**, so one press would
   have routed *and* started dictation. Binding a control to a target now forgets a trigger that
   covers it.
4. **The launcher fixture's hang guard was 60 s** and a full pass now takes 76 s measured; it sat at
   the exact boundary, so the suite failed intermittently. The guard is 180 s, with the measurement
   in the comment.

## Limitations, stated rather than papered over

- **No physical controller was attached during any of this.** Every check above is about what the
  app does with the input it is given; none of them is evidence about a specific pad's hardware, its
  reserved buttons, or about a live World of Warcraft session binding the virtual controller.
- **Developer-service enrolment failed on this install** (`Enrollment failed at SRP server proof`);
  the app installed and the launcher runs, and the four device self-tests ran against it, but a
  guest session could not be started, so no in-game check was possible.
- The claim model has exactly one action, dictation. The behaviours excluded and the reason for each
  are in `development/technical/CONTROLLER_OUTPUT.md`.

## Review

This branch is deliberately left unmerged and without a pull request, for review before either.
