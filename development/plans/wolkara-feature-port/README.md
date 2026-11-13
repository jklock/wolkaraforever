# Wolkara feature-port inventory

## Scope

This is an audit and planning inventory, not an integration branch. It compares
`fJavierLasso/main` at `ebc51c6140935765075a40747813592f4cdbe8c8` with
WolkaraForever `main` at `438bf348ddd13ae7a10cc0ea50ccd1b0751e03b6`
(2026-11-12). The source remote was fetched on 2026-11-10.

This inventory was revalidated against the v1.0.10 product foundation and then
rebased on the current mainline after all earlier WolkaraForever PRs and issues
were closed. The intervening External-JIT diagnostics change does not alter any
feature-port contract. This inventory is historical inspiration, not a
backlog dependency: each feature task must re-prove its gap against `HEAD` and
must extend the current iPhone Duo foundation (`InterfaceMode`, `LayoutStore`,
mobile touch layouts, `WolkaraRoue`, and the existing Add-on Manager) rather
than recreate or replace it.

The source is now **45 commits ahead** of the shared base `fc270359`; the earlier
37-commit count excluded the eight commits subsequently merged as source PR #19.
Twelve of the 45 are merge commits with no independent implementation. No feature
can be merged wholesale: source changes mix engine files with launcher/product code,
while WolkaraForever keeps `platform/` byte-identical and owns changes through
`wolkaraforever/`, patches, and the prepare pipeline.

## Dispositions

Read the complete [PR audit](PR_AUDIT.md) before choosing any work.  Keyboard,
draft and dictation conclusions are separated in [Keyboard and dictation](KEYBOARD_AND_DICTATION.md).
The recommended product-level outcome is in [Recommended product roadmap](RECOMMENDED_PRODUCT_ROADMAP.md).
The implementation-ready sequence is [Plan](PLAN.md).
Concrete defaults and PR cuts are in [Completion specification](07-completion-spec.md).
The current-mainline compatibility and iPhone Duo review is in
[Current-mainline review](CURRENT_MAINLINE_REVIEW.md).
Use the feature-specific plan/task pairs in [Plan](PLAN.md) for implementation
handoff.

| Priority | Source change(s) | Disposition | Product comparison and required next action |
| --- | --- | --- | --- |
| P0 | `ecf7e93` reclaimable install capacity | **Already covered; retain ours** | `TKWoWUpdater` already uses `NSURLVolumeAvailableCapacityForImportantUsageKey`, falls back safely to raw filesystem capacity, and `test_wow_update.m` covers reclaimable-space cases. |
| P0 | `01eade2`, `6ad2858` bounded concurrent archive ranges | **Already covered; retain ours** | Our client tests explicitly cover bounded concurrent transfers, serial consumption, cancellation, staging and CDN repair. Do not replace the downloader; compare only a demonstrated missing edge case. |
| P1 | `7cb348c` enrollment reference recovery | **Assess for targeted port** | Useful reinstall resilience, but it modifies authorization/platform-facing code. Design a narrow layer patch with pairing-storage tests; do not copy the source startup hook. |
| P1 | `0a91425` resumable verification and iPhone display fixes | **Mostly covered; gap review** | Current Forever verification, backing-scale and display patches supersede much of this. Diff specific CASC resume and display edge cases against the layer before deciding on a patch. |
| P1 | `04fbc09` scene servicing while native startup sleeps | **Candidate** | This is a real startup-responsiveness fix in runtime/launcher code. Reproduce it on the two permitted simulators, then implement as a narrowly owned patch with startup-sleep and UI coverage. |
| P1 | `f47931f` composed text and shader temporary lifetime | **Candidate** | Current touch tests already exercise marked/composed text; the bounded Metal-autorelease lifetime needs a separate reproduction. Split into AppKit composition and Metal lifetime PRs if either gap is real. |
| P1 | `3aad8e8` large database add-on TOC manifests | **Candidate** | Our add-on store already models TOC interface arrays and has validation. Add the source fixture first; port only the parser limit/handling required by that fixture. |
| P2 | `bb8ad20` dictation language selector | **Decision required** | Forever deliberately owns a final-only dictation path and currently fixes recognition to `en-US`. A language control must first define whether it follows app language, game locale, or a separate persisted setting; never import the source key-event submission behavior without that contract. |
| P2 | `bb8ad20` stable camera restart | **Assess for targeted port** | Our touch path already has direct-camera tests. Port only a failing restart sequence, preserving the current input-routing ownership. |
| P2 | `bb8ad20` performance HUD | **Already covered; retain ours** | WolkaraForever has its own optional `AKPerformanceOverlay`, frame-attribution patches and touch-control tests. No source UI port. |
| P2 | `7f4241e` double-tap L3/R3 | **Candidate** | This is additive touch-controller behavior. Specify mapping, discoverability, collision with existing triggers, and persistence before implementation; validate on both simulators and physical iPad if shipped. |
| P2 | `4077d08`, `ed3109e`, `da87790` editable ability zones/modifier groups | **Candidate, separate discovery** | Valuable concept, but source implements it inside its touch gamepad and action overlay. It must be redesigned for Forever's input/controller boundary; do not import the action-add-on experiment. |
| P2 | `0a20a66`, `ecfc521`, `3c2231d`, `f06674b` camera drag, Simple controller, shoulder positions/defaults | **Candidate, package together** | Source's Simple mode and saved layouts are one feature family. Compare it against the current on-screen gamepad and Controller Manager, then make one product decision rather than cherry-picking layout constants. |
| P2 | `a8a6082`, `27f61a3` experimental WolkaraTouch add-on, then removal | **Exclude as a source port** | The feature was added and removed upstream. Preserve the current reviewed `WolkaraRoue` package only as a non-automating mobile companion; do not import the source experiment, commands, or automation. |
| P2 | `c243f5b`, `ebc7345` completed USB-import detection, then revert | **Exclude** | The source itself reverted it. No viable feature remains. |
| P2 | `245c4e1`, `e4d2b64` trigger defaults/docs | **Fold into Simple-mode decision** | These are preference/default churn, not standalone product ports. |
| P2 | `fdc4e76` External JIT/StikDebug startup | **Already superseded; retain ours** | Forever supports explicit execution modes and documents External JIT without making the source's isolated coordinator the product contract. Preserve current security constraints. |
| P2 | `49e2ed9` launch phase progress | **Already covered; retain ours** | The product owns `LaunchProgressView` and localization. Do not replace its launcher shell. |
| P2 | `4a3a78f`, `d6a21c5` bulk imported Forever features and bundle audit | **Already covered/superseded** | These are mostly an earlier import of features now owned by Forever: localization, voice, add-ons, UI archive, logging and bundle checks. Treat them as provenance only. |
| P3 | `4b34d2a` Files import guide | **Assess UX only** | Add a Files import affordance only if it fits the current safe game-data workflow and device scripts. Documentation alone is not a reason to port. |
| P3 | `53e7ebd`, source documentation commits | **No port** | Source-specific validation and wording are not evidence for a different repository or SHA. |
| P3 | `6027980`, `dbe9a35` fixture maintenance | **No direct port** | Use their test ideas only when a targeted port introduces the corresponding behavior. |
| P3 | `0822463` guarded serial add-on installs | **Assess invariant, not code** | Forever already has managed package state and guarded update operations. Prove whether concurrent installs can violate its safety rules; port only the missing serialization invariant and tests. |
| P1 | `dea2eb3` automatic CurseForge web downloads | **Adopt as an acquisition route, not the primary UI** | Make native Add-on Hub the default screen. Use normal CurseForge `WKWebView` browser/download flow for no-key acquisition, preserve API-key and Files alternatives, and place every installed package in the same managed catalog. See `features/addon-hub/`. |

## Commit accounting

The following accounts for every non-merge commit in the source delta.  A merge
commit is recorded only as integration provenance: `7ed479e` (#6), `1e282f0`
(#7), `4d1a911` (#8), `4f1a14b` (#9), `e8c9869` (#11), `c1f945a` (#12),
`64643d1` (#14), `5bc6240` (#15), `9bb9d7d` (#16), `d68b784` (#17),
`846312a` (#18), and `ebc51c6` (#19).

| Commit | Feature family | Decision |
| --- | --- | --- |
| `ecf7e93` | storage capacity | covered by current updater/test |
| `a8a6082`, `27f61a3` | experimental touch add-on / removal | exclude |
| `c243f5b`, `ebc7345` | USB import / revert | exclude |
| `01eade2`, `6ad2858` | concurrent downloader | covered |
| `7cb348c` | enrollment recovery | assess |
| `245c4e1`, `e4d2b64` | trigger defaults | fold into Simple mode |
| `fdc4e76`, `49e2ed9` | External JIT / progress | superseded |
| `0a91425`, `6027980`, `dbe9a35` | display, verification, fixtures | gap review / no direct port |
| `4a3a78f`, `d6a21c5` | prior Forever import / audit | provenance |
| `4b34d2a`, `53e7ebd` | Files guide / validation record | UX assess / no port |
| `4077d08`, `ed3109e`, `da87790` | ability zones | discovery candidate |
| `0a20a66` | direct camera drag | targeted gap review |
| `ecfc521`, `3c2231d`, `f06674b` | Simple controller and shoulders | package candidate |
| `04fbc09` | startup fold responsiveness | candidate |
| `bb8ad20` | dictation language, camera restart, HUD | decision / assess / covered |
| `7f4241e` | double-tap sticks | candidate |
| `f47931f` | composition and Metal lifetime | candidate |
| `0822463` | serial add-on installs | invariant review |
| `dea2eb3` | automatic provider replacement | exclude source implementation; separate explicit-URL provider planned |
| `3aad8e8` | large TOC manifests | candidate |

## Execution order

1. Write reproductions for P0/P1 items; close anything already covered with a link to
   the owning Forever test.
2. Make independent PRs for confirmed engine/patch changes. Each must keep
   `platform/` untouched, add its focused test, run `check_layers.sh`, and record
   the two simulator results.
3. Decide the P2 product contracts (dictation language, Simple mode, ability zones,
   L3/R3) before implementation. These are feature decisions, not source ports.
4. Run every visible flow on both required simulators: iPhone Duo and iPad Pro
   13-inch (M5). Physical Device Hub work is additional user-operated evidence:
   record it when available, never substitute it for the two-simulator matrix,
   and never make an unmeasured physical claim.

## Explicit non-goals

- Do not merge source history or edit `platform/`.
- Do not import source documentation, device claims, credentials, or game add-ons.
  The existing reviewed `WolkaraRoue` source package is a WolkaraForever-owned
  exception: changes must retain its no-command/no-automation contract.
- Do not weaken the existing execution-mode, add-on-provider, game-data, or
  no-automation safety boundaries.
