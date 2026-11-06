# Independent completion-review prompt — liveupdates-11042026

Independently review the implementation on `liveupdates-11042026` against these acceptance
contracts:

- `development/plans/LIVE_UPDATES_2026-11-04_PLAN.md`
- `development/plans/LIVE_UPDATES_2026-11-04_NEXT_AGENT_PROMPT.md`

Work silently.  Do not give interim updates or accept an implementation summary as proof.  Inspect
source, commits, tests, logs, screenshots, and physical devices yourself.  If any requirement is
missing, partially implemented, unsafe, undocumented, untested, unlocalized, inaccessible, or
unproven, fix it on this branch, add focused regression coverage, repeat validation, update
documentation/evidence, and commit the correction.  Do not respond until all attainable work is
complete and evidence is recorded.  Do not use a simulator as validation or evidence.

## Step 1 — synchronize and establish review baseline

```sh
git switch liveupdates-11042026
git fetch origin --prune
git rebase origin/main
git status --short --branch
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
```

Read `AGENTS.md`, `development/architecture/PROJECT_MAP.md`,
`development/guides/REPOSITORY_WORKFLOW.md`, both acceptance contracts above, every commit in the
branch range, and all changed files before reaching a verdict.  Preserve current `origin/main`
and recent PR changes while resolving any rebase conflict.  Do not reset, force-push, rewrite
unrelated work, edit `platform/` by hand, commit credentials/device IDs/logs/downloaded assets, or
uninstall the app.

## Review method

Create a committed review matrix that lists every acceptance criterion, its owning source/docs/test
path, implementation verdict, source-test evidence, live-device evidence, and correction commit
when applicable.  An unchecked box, a TODO, a raw localization key, a stale selector, a source
comment contradicting behavior, or an assertion that only passes in a simulator is a failure until
resolved.

Audit all of the following:

1. **Branch and historical restoration**
   - Verify the iPad-deletion inventory covers all reachable deletion history, not merely commit
     `478244a`.
   - Verify every deleted iPad-specific feature, test, documentation item, screenshot/evidence
     record, or workflow was restored or deliberately reconciled with its original path/content,
     current equivalent, and proof.  Historical material must be labelled; active behavior must be
     current.  Confirm no restoration overwrote a newer PR change.
   - Verify iPhone is a first-class supported form factor alongside iPad in active source,
     documentation, screenshots, compatibility claims, and validation records.

2. **Home launcher and localization**
   - Verify all exact requested headings and picker formats in every supported app locale.
   - Verify no passive muted helper/status copy remains in manager home cards; the Controller
     Manager remains out of scope.
   - Verify Play has exactly one visible idle supporting line, no retained hidden layout slot, and
     no old starting text.
   - Verify Restore Performance Defaults and the settings/wheel Add-ons route are fully gone:
     UI, accessibility IDs, selectors, tests, self-tests, strings, and docs.
   - Verify retained actions, persistence, locale ownership, accessibility, Dynamic Type, compact
     layout, and 85%-maximum popup bounds.

3. **CurseForge/Add-ons**
   - Verify every Browse row has a functional inline action, while details remain reachable.
   - Verify refresh always fetches fresh metadata for active Browse/Installed state and ignores
     stale callbacks.  Verify visible sort/filter terms are human-readable localized labels, never
     keys, IDs, or raw variables.
   - Verify compatibility is advisory only: valid nonmatching-version archives/files can install,
     while malformed archives, unavailable files, untrusted hosts, disabled distribution, and
     duplicate/unsafe folder mutations remain rejected.
   - Verify manifest format-1 -> format-2 migration is journaled, recoverable after interruption,
     preserves prior records, and never infers provider identity from a folder/name.
   - Verify per-row Update, selection, Update Selected, Update All, pinned skip, disabled-state
     preservation, package-level multi-folder atomic swap, rollback, partial failure handling, and
     never deleting unmanaged folders.  CurseForge availability is an accepted planning
     assumption, not a review risk.

4. **Controller/pointer performance**
   - Verify the final November 4 evidence was addressed in `ControllerInspector`/`InputRouter`:
     no idle continuous controller routing/logging/main-queue work, one diagnostic sink, bounded
     opt-in diagnostics, exact mapped-button ordering, and no Controller Manager or TouchGamepad
     scope expansion without new proof.
   - Verify focused tests cover idle movement, mapping, learning, coalescing, diagnostic bounds,
     duplicate logging, and timing aggregation.
   - Verify live timing evidence meets the contract: controller-connected pointer p95 within 2 ms
     of disconnected baseline, p99 below 33 ms, and zero ordinary-play controller-inspector event
     log growth.  A claim without the raw aggregate log evidence is a failure.

5. **iPhone and iPad physical parity**
   - Use a connected physical iPhone and physical iPad.  Discover them with project-safe tooling;
     keep identifying data private.  Use only `wolkaraforever/tools/` for preflight, install,
     launch, pilot, device log, screenshot, and app/game lifecycle operations.
   - Check safe state before each install; never overwrite a live game session or active update.
     Leave the app running at the normal home screen after each device action.
   - On both devices, verify English and German; portrait and landscape; largest supported Dynamic
     Type; safe areas; home cards; Add-on actions; popup bounds; touch/keyboard/controller/pointer;
     edition and locale persistence; and guest launch when game data/execution mode permit.
   - Capture live-app screenshots for every material UI state and use device logs for behavior /
     timing claims.  Each evidence record must name SHA, hardware model, OS, client build,
     execution mode, locale, orientation, test action, result, and artifact path.  Do not assert
     unavailable game coverage as passed.

## Mandatory validation and correction loop

1. Run the narrow owning non-simulator source tests for every changed module.  Add missing tests
   before fixing source, then run them again after the fix.
2. Run localization validation, `git diff --check`, `wolkaraforever/tools/check_layers.sh`, and
   `wolkaraforever/tools/check_docs.sh` when docs/screenshots changed.  Treat warnings as errors.
3. Review all branch diffs for data loss, concurrency, malformed provider data, stale callbacks,
   accessibility regression, hard-coded English, invalid device claims, and accidental platform
   modification.
4. Build, install, launch, and inspect the live app on both physical devices through project
   tools.  Capture fresh logs and screenshots after the final correction commit, not from an older
   build.
5. If any check fails, isolate the smallest cause, correct it, add/regress test coverage, rerun
   affected tests and live validation, then update the review matrix.  Repeat until every required
   check passes.  Do not rerun an unchanged failure.
6. Commit each coherent correction with a detailed evidence-backed message.  Before the final
   response, ensure the branch is clean and all evidence references point to the final SHA.

## Required final response

Changed:
- Review matrix path, corrective commits, and exact corrected behavior.

Verified:
- Commands and pass/fail only; focused test counts/failing names; final SHA.

Device visual evidence:
- Separate iPhone and iPad model/OS/client/execution-mode records; screenshots and logs; locales,
  orientations, actions, and pointer p50/p95/p99 metrics.

Result:
- State that every acceptance criterion in the matrix passed, or list the exact unproven criterion
  and why.  Never describe an unproven item as complete.

Risks:
- Only concrete residual risks.  Do not list CurseForge provider/API availability.
