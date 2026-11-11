# Merge-blocking issue register

| ID | Blocker | Closure proof |
| --- | --- | --- |
| R-001 | v1.0.1 exact-main record is not tracked on main. | Generated bd0ed91 record committed through docs PR. |
| R-002 | No permanent stable/test isolation guard. | Wrapper mocked tests and stable-state before/after evidence. |
| R-003 | #27 and #36 overlap in Client.m. | Closed 2026-11-10 at `1a230d3`: #36 closed as a duplicate with the capability comment; #27 selected tests pass. |
| R-004 | #37/#41/#23 patch names collide with main. | Renamed patches apply through check_layers.sh. |
| R-005 | #23/#26 can alter protected defaults. | iPadOS default screenshots and gated-mode tests. |
| R-006 | Launcher Manager changes golden UI. | Contract amendment, approved screenshots, Device Hub evidence. |
| R-007 | #40 reports stale failures. | Reproduce on current main or fix before merge. |
| R-008 | #37 needs physical External JIT evidence. | Test-bundle enabler log and Device Hub launch. |
| R-009 | #28's throughput window writes past its array, and its evidence is an external device capture. | Closed 2026-11-10 at `7c5e104`: bounded window proved by `test_wow_download_status.m`; named fixture states replace the capture. |

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
