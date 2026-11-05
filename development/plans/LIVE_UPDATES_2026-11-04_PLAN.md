# Live updates — 2026-11-04 execution plan

Status: implementation plan only.  Target branch: `liveupdates-11042026`.

## Scope and evidence baseline

This plan combines the reported live-playtest defects with the requested launcher cleanup.
It deliberately excludes Controller Manager: the request explicitly says to disregard that
work, and the current launcher has no Controller Manager home-card implementation to change.

The current implementation establishes these concrete gaps:

- `AddonManager.m` only exposes Install through `presentProject:` (the project-row tap opens an
  action sheet); `TKAddonProjectCell` has no action control.
- `AddonStore.m:65-98` rejects ZIPs without TOC interface `16001`, and
  `CurseForgeClient.m:80` refuses a project with no `1.60.1` file.  Those are version gates,
  not advisory compatibility information.
- The Add-ons refresh bar item only calls `reloadAddons`; it neither reloads browse results nor
  clears the in-memory category metadata.  Results and categories can therefore differ from the
  provider until the user changes another browse input.
- The toolbar menu creates sort field actions with raw localization keys (`option[1]`) at
  `AddonManager.m:565`; its button label is localized.  Every visible menu/action label must use
  the same explicit localized mapping.  Filter state must likewise use display labels, never
  version IDs or localization keys.
- Managed records retain folders, archive digest, version, disabled, and pinned state only.
  They do not retain CurseForge project/file identity, so a safe per-package Update / Update All
  cannot be implemented from the current manifest schema.
- The home grid currently includes the compatibility label in the Game Edition card and the
  Restore Performance Defaults row in the Performance Manager card.  The play stack contains
  both `wow.updates` and `wow.startup`, leaving two supporting lines below Play in idle state.
- `InputRouter`, `ControllerInspector`, and `TouchGamepad` are the input paths found by source
  inspection.  No source-level measurement identifies the reported controller-plus-pointer lag;
  the fix must begin with a reproducible device trace and frame/input timing evidence rather than
  guessing at a controller change.

The supplied CurseForge screenshots are a reference for interaction hierarchy: Browse rows have
an inline Install action; My Addons supports checkboxes, per-row Update, and Update All; sort and
filter names are human-readable.  They are not a license to copy CurseForge branding, ads, or
desktop geometry.  Use existing navy/gold WolkaraForever components and data from the supported
CurseForge API only.

## Implementation sequence

### 1. Establish regression fixtures and a measured input baseline

1. Read `development/guides/REPOSITORY_WORKFLOW.md`, launcher fixture setup, current screenshots,
   and `wolkaraforever/tools/` device workflow before modifying source.
2. Add deterministic CurseForge fixture data for: a matching-version file, only nonmatching files,
   an unavailable file, an update available, up-to-date, pinned, and API-distribution-disabled
   projects.  The fixture must not require a real API key or network.
3. On the designated iPad, use `wolkaraforever/tools/preflight.sh`, then the project launch/log
   tools to collect a baseline for pointer movement with no controller and with the affected
   controller connected.  Record source SHA, device/iPadOS, execution mode, controller model,
   pointer device, observed frame timing, input-event rate, and reproduction steps in a new
   ignored/log artifact or `development/validation/<sha>.md` as appropriate.  Leave the iPad at
   the normal home screen with WolkaraForever running after each run.
4. Do not change `TouchGamepad`, controller routing, or Controller Manager from this report alone.
   Use the trace to identify the responsible callback/queue/render path.  If it is in scope and
   reproducible, make the smallest fix there; otherwise document the measured blocker and do not
   claim a lag fix.

### 2. Make CurseForge metadata refreshable and display labels canonical

1. In `wolkaraforever/WoW/CurseForgeClient.h/.m`, define one typed/public mapping for supported
   CurseForge sort field IDs and their display-localization keys.  Keep wire IDs in the API
   request, but make all toolbar/menu/action text resolve through `WKLocalized`.  Match current
   CurseForge terms exactly where the API supports them: Featured, Popularity, Last Updated,
   Name, Author, Total Downloads, and Release Date.  Do not expose `addons.*`, numeric field IDs,
   or raw version IDs in visible controls.
2. In `AddonManager.m`, derive the toolbar title, menus, compact fallback rows, accessibility
   labels, and test expectations from that mapping.  Localize `UIAction` titles before creating
   them; retain a single selected sort and explicit ascending/descending state.
3. Replace the hard-coded `"1.60.1 (Forever)"` filter title with a localized display formatter.
   Distinguish the user-visible filter label from the API `gameVersion` parameter.  The filter
   menu must show clear human labels for All Game Versions, Forever, All Categories, the selected
   category, and Clear Filters in both supported app locales.
4. Split local filesystem reload from provider refresh.  Keep `reloadAddons` for filesystem and
   manifest state; add a `refreshMetadata` path for the navigation refresh control.  In Browse,
   it must invalidate the current result generation, clear/refresh categories and result count,
   fetch page zero with the current search/sort/filter choices, and ignore late callbacks from the
   old generation.  In Installed, it must reload installed records and recheck update metadata.
   Disable duplicate refresh/update actions while their generation is in flight, expose a
   localized progress/status, and preserve current search and selections.
5. Add no persistent response cache until cache policy, ETags, expiry, and offline behaviour are
   specified.  The explicit refresh must always issue fresh metadata requests; normal display may
   use current in-memory values only for the active view.

### 3. Remove compatibility denial while retaining safety boundaries

1. Replace `TKAddonStore compatibleFolders:from:error:` with structural package validation only:
   valid, bounded ZIP; safe extraction; at least one add-on folder with a readable TOC; duplicate
   protection; ownership journal/manifest; and shared update lock remain mandatory.
2. Parse and retain TOC interface versions as advisory metadata.  A mismatch or missing interface
   must produce a localized "unverified for Forever" state/warning, never block Import, Install,
   Update, Update All, selection, or Play.  Do not alter add-on contents, game bindings,
   `Config.wtf`, or `GamePadConfig_*.json`.
3. Refactor `latestFileForModID:gameVersion:` into a deterministic candidate selector: prefer the
   newest available Forever-tagged file; otherwise select the newest available file and return an
   advisory compatibility state.  A project with no matching file must not be denied solely on
   that basis.  Preserve the existing refusal for malformed responses, unavailable files,
   untrusted asset hosts, failed extraction, duplicate folders, and author-disabled API
   distribution.
4. Update all user-facing compatibility language so it never asserts verification when the file
   was merely selected or imported.  Keep API distribution errors distinct from compatibility
   state.

### 4. Persist provider identity and implement row actions, update, bulk selection, and Update All

1. Version the manifest in `AddonStore.m` (read existing format-1 records without data loss;
   write a documented new format).  Store package-level CurseForge project ID, installed file ID,
   downloaded filename/version/date, TOC interface metadata, and advisory compatibility state.
   Model multi-folder archives as one managed package so update/remove/disable cannot split a
   package.  Imported ZIPs and pre-existing folders stay selectable for permitted local actions
   but are clearly not provider-updatable without an associated CurseForge identity.
2. Extend `TKAddonRecord`/store APIs with transactional package replacement under the existing
   shared update lock: download to a bounded temporary path, extract/validate before mutation,
   reject folder collisions outside the owned package, stage old owned folders, atomically commit
   the new manifest, and restore the previous package on any error.  Preserve disabled and pinned
   state.  Never delete unowned folders.
3. Add an inline action button to `TKAddonProjectCell`.  It calls the same install pipeline as the
   details sheet, has a stable accessibility identifier (`wow.addons.project.<id>.install`), and
   reflects downloading/installed/error state.  Selecting the non-action part still opens project
   details.  API-distribution-disabled rows show an unavailable action and retain the supported
   project-page route.
4. Redesign Installed rows using the existing style: a leading checkbox, package name/version and
   state, and an inline Update button only when a non-pinned managed CurseForge package has a
   newer candidate.  Add a localized selection toolbar with Select All / Clear Selection and a
   bulk Update Selected action; add Update All for all updateable, non-pinned packages.  Checkbox
   changes must not implicitly mutate game files.
5. Compute available updates from freshly requested provider metadata, not version strings alone;
   use project/file IDs and published file ordering.  Limit requests with a bounded serial/batch
   coordinator, cancel/ignore stale generations, report partial failures by package, and continue
   unaffected packages.  Re-fetch/install exactly the selected file so the record and displayed
   state agree.
6. Use a confirmation sheet for any multi-package mutation.  Its content must be scrollable and
   constrained to at most 85% of the presenting screen in each dimension, with even margins and a
   reachable Cancel action.  Apply the same presentation helper/constraint policy to Add-ons,
   voice, preferences, and other launcher popup menus; do not depend on implicit iPad
   `UIAlertController` sizing.  Test regular iPad landscape, compact/narrow sheet, and largest
   supported Dynamic Type with long German labels.

### 5. Home-screen cleanup (visual/content only)

1. In `WoWViewController.m` and `Shell/{en,de}.lproj/Localizable.strings`, rename the existing
   localized heading keys without hard-coded English:
   - `home.box.edition` -> Game Settings Manager;
   - `home.box.voice` -> Dictation (V2T) Manager, retaining literal `V2T`;
   - `home.addons.macever` -> Download Mac-Ever (Perf Optimization).
2. Add localized format keys for the selected edition and region/locale rows.  In `render`, make
   every edition read `Game Edition: <edition>` and every region/locale read
   `Region / Locale: <region> <locale>`; retain the existing picker actions and persistence.
   Picker action labels themselves may stay concise, but the selected home-card value must always
   use these prefixes and no centered dot.
3. Remove `_compatibilityLabel` from the home card and its render/localization/test references.
   This removes passive helper copy only; it must not affect installation state, diagnostics, or
   detailed pages.  Do not change Controller Manager.
4. Remove `_restoreDefaultsButton`, `restorePerformanceDefaults`, its home-card accessibility ID,
   unused localization entries, and fixture/self-test expectations.  Keep Device Profile, Render
   Profile, and Performance Overlay behavior intact.  Do not move restore-default behaviour to a
   new control under this visual-only request.
5. Make the launch stack contain exactly `_updatesLabel` below Play in idle state.  Remove
   `_startupLabel` from that stack (and any idle layout reservation) rather than merely hiding it.
   Keep launch/error status inside the existing status container where it already belongs.  Verify
   the retained automatic-update line wraps/readably scales without adding a second line.
6. Change `sectionBoxWithIdentifier:rows:` and grid sizing so rows determine compact card height
   with the existing 14/16 insets and 8-point row spacing; do not preserve blank space with a
   flexible spacer when sibling cards no longer require it.  Ensure both cards in a two-column row
   share a clean row height while their internal controls remain top-aligned.  Verify Game
   Settings/Add-On, Dictation/Performance, and UI cards at landscape and compact widths without
   clipping or horizontal overflow.
7. Remove the Add-ons entry from the settings/wheel action menu in `settings`; retain the visible
   Add-On Manager card and its direct action.  Update its menu/self-test assertions so no hidden
   route remains above Play.

### 6. Localization, documents, and visual assets

1. Update both supported launcher locales (`en`, `de`) for every added/reworded/removed key.
   Preserve placeholder type/order and do not leave raw keys as fallbacks.  Do not modify game
   locale configuration semantics.
2. Search all launcher documentation and captured screenshots for the removed/renamed card text,
   old play line, Restore Performance Defaults, and obsolete card geometry.  Regenerate only the
   affected screenshots through the existing fixture or device workflow, update their references,
   and run `check_docs.sh` if anything changed.
3. Do not embed or commit the supplied CurseForge screenshots.  They are visual reference only;
   committed screenshots must show WolkaraForever and contain no third-party ads or credentials.

## Required automated proof

Run in this order; save long output as a validation artifact and report commands plus pass/fail,
not raw logs.

1. Add/update focused `test_curseforge.m` coverage for wire sort IDs, query encoding, localized
   display mapping at the manager boundary, refresh generation/stale callback handling, matching
   file preference, nonmatching available-file fallback, and malformed/unavailable/distribution
   refusal paths.  Run `wolkaraforever/tools/test_curseforge.sh`.
2. Add/update AddonStore/archive tests for format-1 migration, provider-identity persistence,
   unverified ZIP acceptance, structural rejection, package rollback, disabled/pinned preservation,
   per-package update, Update Selected, Update All partial failure, and never deleting unmanaged
   folders.  Run the narrow owning archive/store test command(s).
3. Extend `wolkaraforever/WoW/tests/test_wow_launcher_app.m` to press inline Install, refresh,
   Update, Update All, selection actions, and long-label/compact layouts.  Assert user-visible
   sort/filter strings contain no localization key or numeric API ID, project rows retain the
   detail route, and each popup has even in-bounds geometry and no dimension over 85% of the
   presenter.
4. Update launcher fixture assertions for all requested home UI changes: exact headings; every
   selectable edition/region/locale display format; renamed Mac-Ever action and URL route; one
   visible supporting Play line; absent old Play line; no passive muted manager text; absent
   restore-default control/selector/accessibility ID; retained controls/actions; two-column and
   compact grid bounds/heights; and removed settings/wheel Add-ons action.  Run
   `wolkaraforever/tools/test_wow_launcher_ui.sh`.
5. Add a targeted test or instrumentation regression for the measured pointer/controller fault.
   It must assert the diagnosed invariant (for example, no duplicate high-frequency handler or no
   main-queue work per motion event), then run its narrow owning test.  A simulator-only result is
   not evidence of physical pointer latency.
6. Run `wolkaraforever/tools/test_localization.sh`, then
   `python3 wolkaraforever/tools/check_localization.py`, `git diff --check`, and
   `wolkaraforever/tools/check_layers.sh`.  Run `wolkaraforever/tools/check_docs.sh` when docs or
   screenshots changed.

## Required device proof and completion gate

1. Build/install/launch only through `wolkaraforever/tools/` against the designated iPad.  Record
   exact SHA, tool command, device, iPadOS, game client build, and execution mode.
2. Inspect landscape and the supported narrow/compact presentation in English and German.  Change
   every edition and every region/locale selector; verify the formatted selected value persists
   after relaunch and game-locale writes retain their existing limited scope.
3. With an approved test API key, compare current provider metadata to the visible Browse list:
   manual refresh, sort/filter labels, inline install, unverified install warning but no version
   denial, update detection, per-row update, selected bulk update, Update All, pinned skip,
   disabled preservation, partial failure, and no unmanaged-folder loss.  Use synthetic/test
   add-ons or a disposable test install where mutation is needed.
4. Reproduce the mouse-pointer/controller scenario using the same baseline protocol.  Accept a
   fix only when post-change measurements meet the agreed threshold and the game remains usable;
   otherwise record the observed blocker rather than claiming resolution.
5. Inspect every popup for even spacing, in-bounds controls, readable Dynamic Type, and no more
   than 85% screen occupancy.  End with the app running at the normal home screen.

The implementation is ready to report only when source tests, fixture tests, localization/layer
checks, and the above device evidence pass.  "100% first time" is an outcome to validate, not a
claim this plan can make before implementation and physical testing.

## Final implementer report format

Changed:
- Files and externally visible behavior, including manifest migration policy.

Verified:
- Exact commands; pass/fail; focused check counts or failing test names only.

Device visual evidence:
- Exact SHA, device/iPadOS/client/execution mode; landscape/compact/locales exercised; captured
  artifacts; observed pointer/controller before/after measurements.

Result:
- Completed acceptance criteria and explicitly unverified items.

Risks:
- Provider/API constraints, data-migration rollback limits, and any physical-test blocker.
