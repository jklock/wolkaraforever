# Validation: Controller Manager with a pad attached (`controller2`)

- Commit: recorded with the change; branch `controller2`, **not merged, no PR opened**
- Recorded: 2026-11-04
- Host: macOS (arm64), Xcode 27.2
- Device: iPad Pro (12.9-inch, 5th generation) — `iPad13,9`, UDID `00008103-000E09A10EC3001E`
- iPadOS: **27.0.1**
- Execution mode: `developer-service`
- Controller: **Xbox Bluetooth Gamepad (Xbox One)** over Bluetooth —
  `buttons=25 axes=6 dpads=3`, 34 controls reported by iPadOS, `menu=y options=y l3=y r3=y`,
  no Share button, no paddles
- Build: `GUEST_EXE=build/guest-probe/WorldOfWarcraft wolkaraforever/tools/install.sh --replace-running`

This record exists because the previous one had to say "no physical controller was attached".
A pad was attached for everything below.

## The new check, and what it found

`--selftest=controller-hardware` reads the pad in the hand rather than a fixture. It fails rather
than passes when nothing is attached, so a green line always means hardware was there. Nine
checks: the pad is present in a fresh process (waited for, not sampled once — a Bluetooth pad
arrives about 0.2–20 s after launch on this iPad), it has a model identity, iPadOS reports
controls for it, the manager reports a model for it, **every control iPadOS reports is a row this
pad has**, the guest is offered the virtual pad only with capture on, the pad is not in that list,
and with capture off the guest is offered the pad again.

First run: **7/9**, failing on the row check. That was a real gap, not a test artefact: rows came
from the standard twelve plus controls that had produced an event, so a control iPadOS *described*
but nobody had pressed was invisible. `-bindingsWithAvailability:reserved:` now builds its list as
the standard layout, then every source the attached pad reports (sorted, so the order is stable),
then anything seen only as an event; `-sourceElementsForPads:` is the one place that names a pad's
hardware, used by both the page and the check.

Second run: **8/9**, failing on the capture-off check — and that failure was the check's fault. It
demanded the hidden virtual pad be absent from the guest's list, but that pad exists in this
process only because the check connected it; in production it exists only for a guest session that
asked for the on-screen gamepad. The assertion now states what matters: the pad is offered, and
the guest is not being handed the virtual-only view.

Third run: **PASS 9/9** — *Xbox Bluetooth Gamepad / Xbox One: 34 controls reported, 48 page rows,
34 enabled.*

## Results, all on the device, with the pad attached

| Check | Result |
| --- | --- |
| `--selftest=controller-hardware` | **PASS 9/9** — 34 controls, 34 enabled rows, guest offered the virtual pad only |
| `--selftest=controller-manager` | **PASS 22/22** |
| `--selftest=controller-routing` | **PASS 22/22** |
| `--selftest=controller-situations` | **PASS 8/8** |
| `--selftest=controller-latency` | **PASS 3/3 — 600 samples, median 1.0 µs, worst 4.9 µs, none over 1 ms** |
| `check_layers.sh` | PASS — platform byte-identical, 538 localization keys |
| `check_docs.sh` | PASS — 94 documents, every link, image and anchor resolves |
| `check_controller_targets.sh` | PASS — 12 targets, each offered and writable |
| `git diff --check` | clean |

## Not run, and why

- **The simulator fixture suites (`test_controller_manager.sh`, `test_wow_launcher_ui.sh`)** were
  not run for this change. The simulator service on this Mac wedged during the change
  (`simctl install` hung for minutes, then `simctl list devices` hung), and the instruction is to
  validate on the device rather than in a simulator. The profile change they would cover is
  covered instead by `controller-hardware`, which reads the rows built from the real pad, and by
  `controller-manager`, which drives the page on the installed build. Their absence is stated
  rather than glossed.
- **A press on the pad.** Nothing here presses a button on the hardware — that is not something
  the app can do to itself, and automating the application is out of bounds. The latency figure is
  the same code path a real press takes (framework handler entry to the adapter's write); what a
  real press adds is GameController's own delivery, which this feature does not sit in.
