# Merge-blocking issue register

| ID | Blocker | Closure proof |
| --- | --- | --- |
| R-001 | v1.0.1 exact-main record is not tracked on main. | Generated bd0ed91 record committed through docs PR. |
| R-002 | No permanent stable/test isolation guard. | Wrapper mocked tests and stable-state before/after evidence. |
| R-003 | #27 and #36 overlap in Client.m. | #36 close comment; #27 selected tests pass. |
| R-004 | #37/#41/#23 patch names collide with main. | Renamed patches apply through check_layers.sh. |
| R-005 | #23/#26 can alter protected defaults. | iPadOS default screenshots and gated-mode tests. |
| R-006 | Launcher Manager changes golden UI. | Contract amendment, approved screenshots, Device Hub evidence. |
| R-007 | #40 reports stale failures. | Reproduce on current main or fix before merge. |
| R-008 | #37 needs physical External JIT evidence. | Test-bundle enabler log and Device Hub launch. |

Add every review comment, test failure, head change, baseline difference, and device observation. Any open entry blocks its dependent PR.
