# Independent review prompt

Independently audit the completed PR true-up without trusting its status text. Fetch GitHub and
the repository, inspect commit graphs/diffs, validation records, release tags, review records,
and Device Hub evidence. Report each finding with exact SHA/file/command evidence.

Confirm all of the following:

1. Current main and each PR head match the recorded review log at the time of its action.
2. #35 was closed without merge and no #35 code was copied.
3. UI baseline/policy v1.0.1 landed before retained features.
4. #27, #28, #23, and #26 are the original PRs that merged; each integrated main by normal merge
   commits and none rewrote branch history.
5. Each feature preserved existing golden screenshots and identifiers; every new UI state has a
   complete review record, both matrix images, documented default/toggle, and localization.
6. #23 and #26 preserved the CDN/startup contract and vendor/overlay boundary.
7. Each release tag points to a passing exact-main validation record for that same SHA.
8. Physical Device Hub evidence uses the matrix iPad and ends with WolkaraForever running at
   normal launcher home.

Treat missing evidence, a non-matrix simulator, source-only UI proof, a changed old baseline, a
direct `platform/` edit, or an undocumented default UI change as a blocking failure.
