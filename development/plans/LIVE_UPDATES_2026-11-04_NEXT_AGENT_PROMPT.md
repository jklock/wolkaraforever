# Next-agent execution prompt — liveupdates-11042026

You own completion of the full live-playtest remediation.  Work silently.  Do not provide interim
status, ask for routine confirmation, or return a partial implementation.  Complete, audit,
validate, document, and commit the work before responding.  Do not use a simulator for any
validation or evidence: final acceptance is on a physical iPhone and the designated physical
iPad.  If a required physical device is unavailable after completing every non-device action,
do not substitute a simulator or claim success; report the exact missing-device blocker and the
completed proof.

## Step 1 — select and synchronize the branch

```sh
git switch liveupdates-11042026
git fetch origin --prune
git rebase origin/main
git status --short --branch
```

Resolve rebase conflicts by preserving the current `origin/main` behavior and every committed plan
artifact already on this branch.  Do not reset, force-push, discard unrelated work, or edit
`platform/` directly.  Read `AGENTS.md`,
`development/architecture/PROJECT_MAP.md`,
`development/guides/REPOSITORY_WORKFLOW.md`, and
`development/plans/LIVE_UPDATES_2026-11-04_PLAN.md` completely before changing source.

## Authority and non-negotiable boundaries

- Implement the entire committed plan, including the iPhone/iPad parity and historical-restoration
  section.  The plan is the acceptance contract; do not omit an item because a later issue seems
  unrelated.
- CurseForge availability is an accepted continuous dependency.  Do not list it as a risk or block
  on it.  Retain validation of malformed responses, unavailable files, integrity, ownership,
  migration rollback, and transaction failure because those protect data.
- Do not implement Controller Manager.  Do implement the narrowly specified controller-inspector /
  input-router reduction of idle controller work; it is not Controller Manager work.
- Do not alter game executable bytes, game automation, bindings, `Config.wtf`, or
  `GamePadConfig_*.json` outside existing explicitly retained UI/locale/gamepad behavior.  Never
  uninstall the app.  Use only `wolkaraforever/tools/` for device install, launch, log collection,
  and game lifecycle actions.
- Preserve unmanaged add-ons and game/user data.  Never infer a CurseForge identity from an add-on
  name or folder.  Never place keys, device IDs, pairing records, logs, or downloaded game/add-on
  assets in commits.

## Required execution order

1. **Inventory and restore iPad history.**  Before implementation, audit every reachable deletion
   affecting iPad source, tests, docs, screenshots, workflows, or validation evidence.  Start with
   `478244a`, then use `git log --all --diff-filter=D --name-status`, `-S'iPad'`, `-S'iPhone'`,
   `-G'iPad|iPhone'`, parent-path `git show`, and merge-base/range-diff.  Add a committed
   restoration matrix with each deletion, original content/path, current equivalent, destination,
   reconciliation, and proof.  Restore all missing iPad material without overwriting recent PR
   changes: apply a deliberate three-way reconciliation, preserve historically superseded records
   in a clearly labelled history location, and update active source/docs/tests at their current
   paths.  Never blind-revert a deletion commit.
2. **Make iPhone and iPad peers.**  Audit every iPad assumption across launcher, Add-ons, touch,
   rendering/window geometry, device profiles, accessibility, assets, scripts, tests, README,
   docs, compatibility, and validation.  Implement a documented device contract for both form
   factors.  iPad retains its two-column layout when it fits; iPhone gets safe-area-aware
   portrait/landscape one-column layout, current-window rendering, no fixed iPad viewport, no
   horizontal overflow, and reachable controls at largest supported Dynamic Type.
3. **Implement all Add-on changes.**  Deliver inline Browse Install, forced fresh metadata refresh,
   human-readable CurseForge-equivalent sort/filter labels, advisory—not blocking—version
   compatibility, format-2 journaled manifest migration and recovery, package-level provider
   identity, transactional per-package Update, Update Selected, Select All/Clear, and Update All.
   Preserve pinned/disabled state, restore old folders/manifest on failure, and never remove an
   unmanaged folder.  Keep all popups evenly spaced and <=85% of the presenting screen.
4. **Implement the measured pointer/controller remediation.**  The final November 4 device log
   proves 12,658 duplicated controller events in each of two log sinks and unnecessary main-queue
   work.  In `ControllerInspector.m`/`InputRouter.m`, implement the plan’s interest snapshot,
   early return before allocation/dispatch/logging for uninteresting input, lossless selected
   button handling, display-interval coalescing only for interested continuous inputs, silent
   normal play, bounded opt-in diagnostics, one diagnostic sink, and aggregate timing counters.
   Do not touch TouchGamepad or Controller Manager unless new evidence proves a separate owner.
5. **Implement every home-screen requirement.**  Follow the committed plan exactly: names,
   localized picker formats, compact cards, single Play support line, removed restore-default row,
   removed wheel/settings Add-ons route, retained actions, all locales, dynamic type, and card-grid
   geometry.  Do not hard-code English.
6. **Update all documentation and assets.**  Bring README, installation/user guides, compatibility,
   architecture/testing/tooling docs, screenshots, and active validation references into agreement
   with iPhone+iPad support and the new UI.  Do not use third-party CurseForge screenshots or ads.

## Physical-device proof protocol

1. Discover and identify the connected iPhone and iPad using project-safe tooling.  Record model,
   OS, source SHA, client build, and execution mode in validation evidence; keep IDs private.
2. Before install, run the safe preflight/pilot state checks.  Do not replace a live guest session
   or write over an active update.  Install and launch with project tools only, leaving each device
   on the normal home screen with WolkaraForever running when a device action ends.
3. On **both** devices exercise English and German, portrait and landscape, largest supported
   Dynamic Type, all home cards/actions, edition and region/locale persistence, Add-ons Browse/
   refresh/filter/sort/inline install/selection/update flows, popup geometry, touch/keyboard/
   controller/pointer behavior, and a guest launch where the device has the required game data.
   Device-specific unavailable game coverage must be named as unavailable, never invented.
4. For pointer latency, execute three five-minute live sweeps: controller disconnected baseline,
   controller connected, and post-fix repeat.  Capture aggregate pointer-dispatch-to-present and
   controller-handoff timing; acceptance requires connected p95 within 2 ms of baseline, p99 below
   33 ms, and zero normal-play controller-inspector event-log growth.  Record failed metrics rather
   than claiming a fix.

## Required proof before response

- Run the narrow owning source tests for CurseForge client/store/archive, input routing, launcher
  behavior, localization, and the layer gate.  Do not use or cite simulator output.  Add focused
  tests first for every changed behavior, including format-1->2 interruption recovery and restored
  iPad behavior.
- Run `python3 wolkaraforever/tools/check_localization.py`, `git diff --check`,
  `wolkaraforever/tools/check_layers.sh`, and `wolkaraforever/tools/check_docs.sh` when docs/assets
  change.  Run the project’s physical-device install/pilot/validation paths on both devices.
- Audit accessibility identifiers, removed selectors, localization references, stale self-tests,
  `rg` matches for old text, and every restored path.  Build warnings are errors.
- Commit logically separated implementation/docs/evidence changes with detailed messages.  Keep the
  branch clean.  Do not push or open a PR unless separately instructed.

## Response format after all work is actually complete

Changed:
- Exact files and behavior, including historical restoration matrix and manifest migration.

Verified:
- Commands, pass/fail, focused test counts/failures only; include source SHA.

Device visual evidence:
- iPhone and iPad model/OS/client/execution mode, orientations/locales/actions exercised,
  screenshots/validation artifacts, and pointer p50/p95/p99 results.

Result:
- Acceptance criteria completed; explicitly list any criterion that cannot be proven.

Risks:
- Only concrete remaining risks.  Do not list CurseForge availability.
