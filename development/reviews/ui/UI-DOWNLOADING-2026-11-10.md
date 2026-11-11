# UI review: download speed and time remaining (v1.0.4)

## Classification

additive.

## Scope

PR #28 adds two fragments to one existing row: while the launcher is **Downloading new data**, the
status line that already carried `done / total` now carries the recent verified transfer rate and
the time that rate implies. Reviewed head `7c5e104`, the PR branch after the normal integration
merge of `5def12e`.

Nothing else on the page moves. No identifier, row, order, card, inset, popup, colour, font or
default state changed; the fragments are appended to a label that already existed, only in the
download phase, and only when each of them is a measurement.

## Changed states

One state is added to the fixture and to the baseline inventory, on both matrix devices:
`wow-downloading.png`.

- iPhone Duo: `wolkaraforever/WoW/tests/ui-baselines/launcher/iphone-duo/wow-downloading.png`
- iPad Pro 13-inch (M5):
  `wolkaraforever/WoW/tests/ui-baselines/launcher/ipad-pro-13-m5/wow-downloading.png`

The thirteen existing images are unchanged and are not rewritten by this PR: `git status` shows
only the two new files under `ui-baselines/`, and both check runs below compare every existing
image and pass.

The state is drawn from a real update held open by the fixture's updater stub at `40 GB / 70 GB`,
with the measured rate pinned to 4 MB/s. The rate is the one input a picture cannot prove - it
comes from the clock, and the fixture pins the clock for every other picture for the same reason.
The window, both fragments and the cases that withhold them are asserted as values by
`wolkaraforever/WoW/tests/test_wow_download_status.m`, which runs on this Mac without a simulator.

The recording used the approval phrase documented in `LAUNCHER_UI_BASELINE.md`
(`UI_BASELINE_RECORD=I_HAVE_APPROVED_THE_UI_CHANGE`) on both matrix simulators, and only the new
image from each run was committed.

## End-user action

None. The fragments appear and disappear inside a download the user already started, and no control,
setting or default changed. A download that is not being measured looks exactly as it did before.

## Evidence

Fixture captures, both matrix simulators, `UI_BASELINE_MODE=check`:

- iPhone Duo: `WoW UIKit PASS`, `UI baseline comparison passed` with `wow-downloading.png` present.
- iPad Pro 13-inch (M5): `WoW UIKit PASS`, `UI baseline comparison passed` with
  `wow-downloading.png` present.

The picture reads `Downloading new data · 40 GB / 70 GB · 4.0 MB/s · ~2h 5m left`, the progress bar
at 4/7, the primary button at **Updating…**, and every other element where it was.

Physical iPad (iPad Pro 12.9-inch, 5th generation; iPadOS 27.2), from the separately signed
`WolkaraForever Test` installation built from `7c5e104` for the merge train's test-install isolation:

- Installed and launched; the app's own log shows `home: the launcher is up`, the first appearance
  check running and finishing (`checked: state=3`), and no crash report or error file afterwards.
- A device screenshot taken after that launch shows the normal launcher home - **Ready to play**,
  game up to date at version 1.60.170888, *Checked 17:26* - with no fragment anywhere. That is the
  state the download fragments must not touch, and it is unchanged.
- The stable installation was not touched: `pilot.sh state` before and after each test-app
  operation reports the same app, the same zero error files and no update writes.

What the device cannot show: the download state itself. The test installation's game is up to date,
so no update exists to download, and producing one would mean moving the game language and pulling
about 70 GB. The state is therefore evidenced by the two committed baselines, and the device run
evidences the page around it. Device Hub was not driven by this run; the screenshot above came from
`devicectl device capture screenshot` after `pilot.sh` launched the installed build, and the log
verdict is the app's own.

## Tests

- `wolkaraforever/WoW/tests/test_wow_download_status.m` - 40 checks under ASan/UBSan: the window,
  the estimate and the words both are written in (see `PR-28.md` for the list).
- `wolkaraforever/tools/test_wow_launcher.sh` - every Mac-native suite, including the new one.
- `wolkaraforever/tools/test_wow_launcher_ui.sh` - the fixture on both matrix devices.
- `wolkaraforever/tools/check_ui_policy.sh --review UI-DOWNLOADING-2026-11-10.md` - policy and both
  matrices.

## Risks and boundary

- **The state depends on a clock.** The rate is an average over about thirty seconds of verified
  bytes, and it is withheld until a second of transfer exists. A reviewer looking at the fixture
  picture is looking at a pinned rate, not a measurement of this Mac's network; the arithmetic that
  turns reports into a rate is what the suite checks.
- **The estimate is an estimate.** It is withheld when the rate is unknown or stalled and when the
  remaining time would exceed a day, where the formatter's answer is `48h`. Nothing else about the
  download, verification, activation or Play eligibility changed.
- **The contributor's window was not bounded.** It appended one entry past a 31-entry array once a
  transfer ran longer than about half a minute, overwriting the window's own count and then reading
  and copying past the end of the struct. The bounded window drops its oldest sample instead, and
  the suite holds ten thousand reports plus a corrupt count against it.
- **Baseline sensitivity.** These images are compared per channel with a tolerance of five. The two
  new images were recorded on the simulators that compare them, and the check runs above reproduce
  them; a future change that moves so much as the detail line fails as a difference, not as a
  comment.
