# Open PR audit and disposition

Audit basis: `origin/main` `550755f6dffcf15852ae76c8b206fe27b6da6461`, 2026-11-08. Direct
normal merge simulation was clean for #23, #27, #28, and #35; #26 conflicts. All branches permit
maintainer edits. All were blocked by required review, not failed checks; no review or unresolved
conversation existed at audit time.

| PR | Head | Release | UI classification | Disposition |
| --- | --- | --- | --- | --- |
| #27 | `c44ecadebd204bd7696c299246f3eb26c42e9f7d` | v1.0.2 | none | retain |
| #28 | `667b40d3004fb6c5b618a07e8b93c5c3fda2a021` | v1.0.3 | additive | retain after #27 |
| #23 | `08faa0580e34cc373d2bd9e62b28b7cd6796f0a9` | v1.0.4 | additive | retain after #28 |
| #26 | `806e3e0b3273ea66432189f6fcc96102f06570b2` | v1.0.5 | additive | retain after #23; resolve on its branch |
| #35 | `b652768987952203411c75f8f081f96075f17be5` | none | none | closed without merge on 2026-11-08 |

## #35 close record

At `b652768`, `git diff --check origin/main...HEAD`, `check_layers.sh`, `check_docs.sh`, and
`test_wow_launcher.sh` passed. Full validation, matrix UI fixtures, physical iPad, and Device Hub
were not run. #35 duplicates #27 and is rejected: it retries `NSURLErrorSecureConnectionFailed`
(which must fail closed), sleeps with `NSThread sleepForTimeInterval:` while retaining a bounded
downloader slot, cannot wake that sleep for cancellation/sibling terminal failure, and tests only
cancellation before a request starts. Preserve the PR as review history; copy no code from it.
The close comment records this evidence and the pull request is closed.

## Required per-PR records

Before requesting each retained merge, add `PR-27.md`, `PR-28.md`, `PR-23.md`, or `PR-26.md` to
this package. Each record names the exact integrated head, source delta, UI classification,
existing UI preserved, new states, end-user action/default, commands/results, simulator evidence,
physical Device Hub evidence, risks, and the exact-main tag/validation record.
