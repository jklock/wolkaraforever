# Merge-blocking issue register

| ID | Blocker | Closure proof |
| --- | --- | --- |
| R-001 | v1.0.1 exact-main record is not tracked on main. | Generated bd0ed91 record committed through docs PR. |
| R-002 | No permanent stable/test isolation guard. | Wrapper mocked tests and stable-state before/after evidence. |
| R-003 | #27 and #36 overlap in Client.m. | Closed 2026-11-10 at `1a230d3`: #36 closed as a duplicate with the capability comment; #27 selected tests pass. |
| R-004 | #37/#41/#23 patch names collide with main. | Renamed patches apply through check_layers.sh. |
| R-005 | #23/#26 can alter protected defaults. | iPadOS default screenshots and gated-mode tests. |
| R-006 | Launcher Manager changes golden UI. | Contract amendment, approved screenshots, Device Hub evidence. |
| R-007 | #40 reports stale failures. | Closed 2026-11-11 by measurement: none of the three reproduces. `test_wow_launcher.sh` exit 0 (8 suite PASS lines) on the M5 and 0 (6) on the Duo; `test_voice.sh` `VOICE PASS: 352 checks` on the M5, the two mapping checks having been fixed on `main` by the any-device mapping in `TestInputInterest`; `test_authorization_handoff.sh` exit 0 with every managed-tunnel case PASS. The claims are removed from #40's record. |
| R-008 | #37 needs physical External JIT evidence. | Test-bundle enabler log and Device Hub launch. |
| R-009 | #28's throughput window writes past its array, and its evidence is an external device capture. | Closed 2026-11-10 at `7c5e104`: bounded window proved by `test_wow_download_status.m`; named fixture states replace the capture. |
| R-010 | The patch registry allocated #41 the number 0052, but v1.0.5 already shipped 0052 and 0053. | Closed 2026-11-11: #41 keeps the contributor's 0054; `RELEASE_SEQUENCE.md` records the drift and #23's row is re-planned at execution. |
| R-011 | The upstream translation suite aborts on the matrix iPhone Duo at `test_appkit_views.m:178` (`!plainHost.multipleTouchEnabled`). | Reproduced on untouched `main` (`092ecc0`) before #41; not a #41 regression, recorded and left for its own change. |
| R-012 | `wolkaraforever/tools/test_emulation.sh` always exits 1: its suite loop runs `test_install.sh` with no subcommand, which exits 2. | Reproduced at `1ef4429`'s loop; every suite it runs prints PASS. Fix is to skip dispatchers, owned by its own change. |
| R-013 | External JIT on the test iPad enters a self-mapped arena and iOS kills the first guest instruction (`CODESIGNING / Invalid Page`, `TolkaraDiagnostics-2026-11-11-151618.ips`). | Open; measured 2026-11-11 at `3fca304`. Proposal: `da_entry_allowed` must refuse an arena no enabler prepared, or the route must require the enabler's arena before entry. It belongs to the External JIT route (0052/0053), not to 0054: the guest dies before any AppKit call, so no content-view claim rests on it. |
| R-014 | The v1.0.6 device matrix reported 1 of 24 checks failed, and `validate.sh` keeps only the last 18 lines, so the record does not name which check. | Closed 2026-11-11 by measurement: `device_matrix.sh` re-run on the same commit and the same iPad reported `DEVICE MATRIX PASS: 24 checks`. The one failure was transient; the record is published as generated and this row names the pass that followed. A record that truncates the failure it reports is a tooling gap for its own change. |
| R-015 | `wolkaraforever/tools/test_touch_gamepad_ui.sh` aborted at `test_touch_gamepad_app.m:380` on both matrix simulators at `84b65dc`, on untouched `main` as well. | Closed 2026-11-11: a simulator-launched app reports `Inactive`, so the fixture's pad never connected. Both gamepad fixtures now post the activation the product reacts to; `--self-test` and `--self-test-input` PASS on iPad Pro 13-inch (M5) and iPhone Duo. |
| R-016 | `test_touch_controls_ui.sh --ui-progress-test` fails at `traffic=2` (a permanently occupied guest queue with no native surface open) on both matrix simulators, on untouched `main` at `84b65dc` and at the #40 head. | Open, measured 2026-11-11. Pre-existing and outside #40's retained scope (the tracking pump only services held buttons and open native surfaces); no #40 claim depends on this mode. Own change. |
| R-017 | On the iPhone Duo, four voice-settings layout assertions fail (`voice.takebutton`, `voice.mode`, `voice.words`, `voice.mapping.collision` laid out below the screen) and `test_touch_controls_ui.sh --self-test` fails the toolbar-centring assertion at `test_touch_controls_app.m:399`. Untouched `main` reports the same four of 341 and the same toolbar assertion at `84b65dc`. | Open, measured 2026-11-11. Pre-existing on the experimental iPhone layout, not a #40 regression; the mouse-callback checks and both new touch fixtures pass on the same device. Own change. |
| R-018 | #40's head branch is in a fork this repository cannot write to (`PorterHoskins/tolkara` is a fork of `tolkara/tolkara`; `git push` is refused with 403 to `jklock`), so the retained work cannot be added to the original branch as `COMMON_PROCEDURE.md` step 1 describes. | Closed 2026-11-11: the retained work is delivered on `pr-40-work` (integration commit `3085490`, no rebase or force-push) and #40 is closed with a comment naming that delivery, as #35 and #36 were (R-003). |
| R-019 | `test_wow_launcher_ui.sh` (and so both the "immutable launcher UI policy" and "launcher pages" validation steps) aborts at `test_wow_launcher_app.m:981`: `idleTimerDisabled` is not restored after the fixture posts `UIApplicationDidBecomeActiveNotification`. | Open, measured 2026-11-11 at the #40 head and on untouched `main` `84b65dc`. The cause is the resume guard, not the timer: the log shows both `[ui] home: back in front` callbacks and no `resuming interrupted check`, so `resumeCheckIfVisible` returned early on `applicationState != Active` in this simulator environment. The identical failure, at the identical line, is in the v1.0.6 exact-main record `development/validation/b3d39bd.md` (two entries), so it predates this work and no #40 claim depends on it. The v1.0.7 record is published as generated with this one step failing, as v1.0.6's was. Own change: the fixture must establish the activation it measures, as the gamepad fixtures now do (R-015). |

Add every review comment, test failure, head change, baseline difference, and device observation. Any open entry blocks its dependent PR.

## R-003 — #27 and #36 (closed 2026-11-10)

- #36 (`f8cd9fb`) closed as a duplicate of #27 with the documented capability comment; no code was
  copied and no tag was published for it. #35 was closed the same way on 2026-11-08.
- #27 head moved from `cf7dbfa` to `1a230d3` by normal merge (`a11f320`, current `origin/main`
  `1ef4429`) plus one integration commit. No rebase, reset or force-push; no review conversation
  existed at either head.
- Tests at `1a230d3`: `test_wow_launcher.sh` PASS (six suites), `check_layers.sh` OK,
  `check_docs.sh` OK, `git diff --check` clean.
- Simulators: iPad Pro 13-inch (M5) PASS including baselines; iPhone Duo PASS on two consecutive
  runs. One earlier iPhone Duo run differed by 3 pixels (worst channel delta 8) in
  `addons-popup.png` — rounding only, and #27 changes no UI.
- Test iPad (iPad Pro 12.9-inch, 5th generation; iPadOS 27.2; installed from `1a230d3`): startup
  check reached *Ready to play* at 15:08, stop and relaunch re-checked at 15:11 and stayed Ready;
  0 game error files, no new crash report, 0 files being written by an update. Left on the normal
  launcher home screen.


## R-009 — #28 download speed and estimate (closed 2026-11-10)

- Head moved from `667b40d` to `7c5e104` by normal merge (`da1aaf1`, current `origin/main`
  `5def12e`) plus one integration commit. No rebase, reset or force-push; no review conversation
  existed at either head. Only the review comment in the PR body was the contributor's own claim of
  an iPhone Duo run, which is not evidence this repository can check.
- Two findings, both fixed rather than carried:
  - The throughput window appended at index 31 of a 31-entry array once a transfer ran longer than
    about half a minute. That overwrites the window's own count and the next report reads and copies
    past the end of the struct. The window is now bounded and drops its oldest sample; the suite
    holds ten thousand reports and a corrupt count against it under ASan/UBSan.
  - The evidence was a 2.1 MB capture from the contributor's own device, referenced by nothing. It
    is removed, and the state is a named baseline (`wow-downloading.png`) drawn by the fixture on
    both matrix devices.
- Behaviour kept, exactly as the plan asked: the rate and the estimate are written after the byte
  counts, only in the download phase, and only when each is a measurement - unknown for the first
  second, nothing for a stalled rate, no estimate past a day. No other state, identifier or default
  changed, and every existing golden image is untouched.
- Tests at `7c5e104`: `test_wow_launcher.sh` PASS (seven suites, including the new
  `DOWNLOAD_STATUS_PASS` with 40 checks), `check_layers.sh` OK, `check_docs.sh` OK,
  `check_ui_policy.sh --review UI-DOWNLOADING-2026-11-10.md` PASS, `git diff --check` clean.
- Simulators: the launcher fixture passed on **iPad Pro 13-inch (M5)** and **iPhone Duo** including
  the fourteen images each now compares. After the image was recorded, eighteen of nineteen iPhone
  Duo runs and all four iPad runs matched it. One iPhone run differed (5015 pixels) and was not
  preserved for diagnosis; the residual known flake in this matrix is the 3-pixel `addons-popup.png`
  rounding difference already recorded at R-003, which appeared twice here with the same worst
  channel delta of 8.
- Test iPad (iPad Pro 12.9-inch, 5th generation; iPadOS 27.2), from the separately signed
  `WolkaraForever Test` installation built from `7c5e104`: installed and launched, its own log
  reached `home: the launcher is up` and `checked: state=3`, no crash report and no error file, and
  a device screenshot shows the normal launcher home (**Ready to play**, game up to date at
  1.60.170888, *Checked 17:26*) with no fragment anywhere. The stable installation was not touched:
  `pilot.sh state` before and after each test-app operation reports the same app, zero error files
  and no update writes. The download state itself cannot be produced on the device - the test
  installation's game is up to date - so it is evidenced by the two committed baselines.

## R-004 — #37 patch names (closed 2026-11-10)

- #37 head moved from `f0c1160` to `13ded3d` by normal merge (`c0c8f28`, current `origin/main`
  `9059a85`) plus one scope commit and one changelog commit. No rebase, reset or force-push; the
  PR had no review conversation at either head. The branch is `Morv:fix/external-jit-enabler-arena`
  in `Morv/wolkaraforever-fork` and is pushed normally.
- The PR's `0048`/`0049` collided with main's `0048-require-private-roots-before-device-install`
  and `0049-show-guest-alert-accessory-text`. They are now `0050-external-jit-clear-enabler-arena`
  and `0051-external-jit-unprepared-high-region`, as `RELEASE_SEQUENCE.md` allocated, and
  `check_layers.sh` reports 50 patches applying cleanly.
- Scope kept, exactly as the plan asked: clearing the enabler's arena before the image is placed,
  and giving back a region granted but not prepared. The original `0048` also unmapped the unused
  tail of the launch reservation (`nc_trim`); that is a memory measure, not part of either crash,
  so it is dropped rather than carried. Nothing else from the PR was removed.
- The debugger ban is unchanged: `0051` only refuses a region before it is adopted, and
  `da_entry_allowed` still ends every route into guest code with a detach.

## R-008 — #37 physical External JIT evidence (2026-11-11)

- Enabler: StikDebug 3.2.2 (`com.stik.stikdebug.7DJ75AWV5R`) on the test iPad, iPad Pro
  12.9-inch 5th generation, iPadOS 27.2, paired on-device, LocalDevVPN up, its bundled
  `universal.js` (the script that services `brk #0xf00d`, `x16=1` prepare region, `x16=0`
  detach) selected for the test bundle.
- Test bundle: `local.wolkaraforever.johnklock.test`, built from this branch with patches
  0050/0051 applied, development-signed (`get-task-allow`, both memory capabilities), installed
  by `devicectl`. The stable installation was never targeted: its state reads the same before
  and after (no error file, no crash report, no update write).
- **0051 is proven on the device.** The launcher log records the reported fault being handled:
  `[debugger] requesting 1073741824 bytes, attempt 1`; `region 0x7000000000 of 1073741824 bytes
  was granted but not prepared: it lies past the addresses the enabler writes to; given back`;
  `requesting 536870912 bytes, attempt 1`; `arena rx=0x109ef0000 ... protection=0x1`.
- **External JIT itself starts on the device.** In the final run the app came up in
  `execution mode=external-jit source=saved`, logged `[debugger] nothing has prepared this
  process; not trapping`, `[native] arena prepared outside this app address=0x10a8ac000
  size=99532800`, `[native] arena protection 0x5`, `[native] arena ready base=0x10a8ac000`, and
  its own diagnostics page reported 94.9 MiB of guest memory, 13,305 initializers and "Memory
  emulation checks passed".
- **Open, and outside this PR:** the enabler-provided arena does not survive the detach on this
  device. The same run that proved 0051 then logged `the arena is no longer executable
  (protection 0x1)` and `the reserved arena did not survive the detach`, so the runtime refused
  entry and the app fell back to mapping its own arena. `protection=0x5` in the contributor's
  log from the same enabler version means this is a device/enabler difference, not a regression
  from 0050/0051, and `da_release_debugger` behaved exactly as designed by refusing it. Because
  of it, **0050 was not exercised end-to-end on the device**; it is covered by the platform
  suite (`PASS: device-sized arena limit, adopted regions cleared before use`) and by the
  contributor's fifteen clean starts.
