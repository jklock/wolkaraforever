# Release sequence and patch registry

Do not begin a later feature release before prior exact-main validation, tag, GitHub release, and evidence-record docs PR are complete.

| Work | Patch allocation |
| --- | --- |
| #37 | 0050 external-JIT clear arena; 0051 unprepared high region |
| #41 | 0054 AppKit content-view sizing |
| #23 | renumber prior 0048–0054 upward when it lands (re-plan at execution) |
| #40 | modifies existing 0047 only |
| #26 | no platform patch permitted |

Allocation notes, in the order they were corrected:

- v1.0.5 (PR #51, "External JIT is a route of this build too") shipped two patches
  as `0052-external-jit-arena-executable` and `0053-external-jit-in-every-build`.
  They were not in this table, and the tag `v1.0.5` is `092ecc0`, so their names
  are fixed: renaming a released patch would make the tagged tree unreproducible.
- #41 therefore takes 0054, the number its contributor already used, not the 0052
  this table allocated before v1.0.5 landed. Recorded as R-010.
- #23's row was written when the highest number was 0053; it must be re-planned
  against the tree it actually lands on, because 0052–0054 now belong to other
  patches.

Versions are v1.0.2 through v1.0.10 in README.md. Evidence-only docs PRs receive no tag.

Landed: #40 shipped as the in-place modification of `0047-pump-native-control-tracking` in
**v1.0.7** (`bd234b9`), with its record in `development/validation/bd234b9.md` and its
execution notes in `PR-40.md`.
