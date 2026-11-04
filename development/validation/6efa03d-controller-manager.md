# Validation: Controller Manager, one owner per question and discovery (`controller2`)

- Commit: `6efa03d` (branch `controller2`, **not merged, no PR opened**)
- Recorded: 2026-11-04
- Host: macOS (arm64), Xcode 27.2
- Device: iPad Pro (12.9-inch, 5th generation) — `iPad13,9`, UDID `00008103-000E09A10EC3001E`
- iPadOS: **27.0.1**
- Execution mode: `developer-service` — enrolment succeeded on this install
  (`Trusted USB enrollment: SRP server proof verified`)
- Build: `GUEST_EXE=build/guest-probe/WorldOfWarcraft wolkaraforever/tools/install.sh --replace-running`
  (which includes the guest GameController adapter, because the build is told which application it
  is for and routing needs it)

## What changed in this commit

The earlier build kept its own action catalogue and made dictation a Controller Manager action,
duplicating a decision the Voice & Input layer already stores and fires. This commit removes that
duplication and replaces the fixed model list with discovery. Nothing about routing, latency, the
three situations or the guest contract changed; the tests below are the same ones, plus the two
new facts.

| Question | Answered by | Where |
| --- | --- | --- |
| Does the game see this control? | Controller Manager | `rebuildRoutes`, from the profile's `map` |
| What does this control do instead? | Voice & Input | `AKTrigger` for the model, read by `withholdsForIdentity:profile:` |
| What controls does this pad have? | the pad | the physical input profile, plus first-sighting events, stored in `observed` |

## Results

| Check | Result |
| --- | --- |
| `test_controller_manager.sh` | PASS — including `CONTROLLER_MANAGER_WITHHOLD_PASS` |
| `test_gamecontroller_facade.sh` | PASS |
| `test_touch_gamepad_ui.sh --self-test` | PASS (`TOUCH_GAMEPAD_ROUTING_PASS`) |
| `test_wow_launcher_ui.sh` | PASS |
| `test_voice.sh` | PASS — 307 checks |
| `check_layers.sh` | PASS — platform byte-identical, 538 localization keys |
| `check_docs.sh` | PASS — 93 documents, every link, image and anchor resolves |
| `check_controller_targets.sh` | PASS — 12 targets, each offered and writable |
| `git diff --check` | clean |
| device `--selftest=controller-manager` | **PASS 22/22** (was 17; the two new checks are below) |
| device `--selftest=controller-routing` | **PASS 22/22** |
| device `--selftest=controller-situations` | **PASS 8/8** |
| device `--selftest=controller-latency` | **PASS 3/3 — 600 samples, median 1.0 µs, worst 16.2 µs, 0 over 1 ms** |
| guest end to end: launch into the client with routing on | **PASS** — login screen reached, `routing=on state=1`, `virtual controller connected`, no new error file and no new crash report |
| physical pad: pass-through, analog, sticks, D-pad, withheld control, disable-while-held, disconnect/reconnect | **NOT RUN — no controller attached** |

## The two new device checks

`controller-manager` grew from 17 to 22 checks, and the new ones are the point of this commit. On
the device, with the app's own code:

1. With no trigger stored for a model, nothing is withheld.
2. Storing the voice page's push-to-talk `AKTrigger` for `controller.button.x` is enough for the
   manager to report that control as withheld — read from the trigger, not copied from it.
3. Removing that trigger gives the control back to the game.
4. A control the pad sends that iPadOS never listed (`controller.button.paddle` in the fixture) is
   discovered and remembered for that model.
5. That control gets a row on the page, which could not have been listed before.

## Defects this validation found, and fixed

1. **Discovery only ran on a later main-queue turn.** The first sighting was always dispatched,
   so a caller already on main could not read the fact when the call returned, and the device
   check failed 20/22. Discovery now does its work inline when the event arrives on main and
   dispatches only when it does not; a caller on either thread sees a consistent result.
2. **The pad's source string was spelled out five times.** `AKControllerPhysicalSource` now names
   it and every caller uses it — which is also how the device check came to pass a real source
   instead of a nil one.
3. **`profileForIdentity:` had been deleted** by a bad edit while the claim API was removed; it is
   restored and the suite that exercises it (profile, routing, lifecycle, learning, gestures) is
   green.

## Limitations, stated rather than papered over

- **No physical controller was attached during any of this.** Every check above is about what the
  app does with the input it is given; none is evidence about a specific pad's hardware or its
  reserved buttons.
- **The guest check left the client at the login screen**, and ending it needed more than a
  signal: the client ignored `SIGTERM` for 20 s at that screen, so `pilot.sh stop` escalated to
  `SIGKILL`. Nothing was writing to the game's store at the time (`update writing: 0 file(s)`),
  and afterwards the launcher came up normally, with no new error file and no new crash report.
  The launcher's own automatic data check then started, as it does on any launch.
- Nothing here is a claim about a live World of Warcraft session *binding* the virtual controller:
  the client was reached, and it runs behind the façade, but no character was played and no
  binding was set in game.

## Review

This branch is deliberately left unmerged and without a pull request, for review before either.
