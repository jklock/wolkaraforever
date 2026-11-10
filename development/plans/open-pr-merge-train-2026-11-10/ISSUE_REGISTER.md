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

