# Historical restoration matrix — iPad and iPhone material

> Audit performed 2026-11-05 on `liveupdates-11042026` after rebasing onto the then-current
> `origin/main`. Every row was produced by the Git commands listed under [Method](#method);
> nothing here is a recollection.

The live-playtest review asked for one thing before any product change: find everything about
iPad support that had been removed from reachable history, decide honestly what its current
equivalent is, and restore what is still load-bearing without undoing the later work that
superseded it.

## Summary

| Count | Outcome |
| --- | --- |
| 48 | Files restored byte-identical into [`development/archive/history/`](../archive/history/README.md) |
| 1 | Restored at its active path after three-way reconciliation (`docs/IPHONE.md`) |
| 0 | Product source files for iPad that were deleted and not superseded |
| 9 | Deletions audited and deliberately **not** restored, each with its reason below |

The most important finding is the last-but-one: apart from the pre-`TouchGamepad` touch add-on,
no iPad or iPhone *source* was ever deleted. What was lost was **evidence and documentation** —
the measured-device records that made claims about iPad support checkable, and the iPhone
support page. That is why the restoration is concentrated in `development/archive/history/` and
in `docs/IPHONE.md` rather than in `.m` files.

## Restored at an active path

| # | Deleted path | Deleting commit | Original content | Current equivalent | Destination | Reconciliation | Proof |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `docs/IPHONE.md` | `f149066` (2026-10-22, "Docs and tooling: one owners' guide, and the device scripts that back it") | iPhone build/install guide, the physical iPhone 16 Pro Max / iOS 27.0 Developer-service session, Classic Era cinematic result, the cellular-only startup recovery | Partial mentions only: `wolkaraforever/WoW/DeviceProfile.m` phone records, `docs/INSTALLATION.md`, `development/guides/BUILDING.md`; no page that states the iPhone contract | `docs/IPHONE.md` (rewritten) | Three-way: keep the measured claims verbatim, keep today's tool names (`wolkaraforever/tools/…`), drop instructions that no longer exist (`tools/enroll.sh` before the layer rename is now `wolkaraforever/tools/`), and add the iPhone/iPad device contract so the page is a contract and not only a history | `wolkaraforever/tools/check_docs.sh`; the page is linked from `docs/README.md` and `COMPATIBILITY.md` |

## Restored as clearly-labelled history

Each file below is the last committed version before its deletion, restored byte-identical.
The history index explains the rules for the directory.

| # | Deleted path(s) | Deleting commit | Why it is history and not current | Destination | Proof |
| --- | --- | --- | --- | --- | --- |
| 2 | `development/{AUDIT,NOTES,PLAN,HANDOFF,TAKEOVER,VALIDATION,DIVERGENCE,ICON,README,REPORT_FOR_REVIEW,REPORT_OUTCOME}.md`, `development/STABILITY_AUDIT_2026-10-16{,_METHOD}.md`, `development/VOICE_AUDIT_2026-10-20.md`, `development/DEVICE_HUB_STABILITY_TEST_PLAN.md` (15 files) | `478244a` (2026-10-21, "Deleted old dev docs") | Superseded engineering records. Their *findings* live on in `development/technical/FEATURES.md`, `development/architecture/*` and `development/testing/*`; their iPad/iPadOS measurements are the only record of those specific runs | `development/archive/history/development/` | `git show 478244a^:<path>` byte comparison |
| 3 | `development/validation/*.md` (16 exact-SHA records) | `478244a` | Exact-SHA device records naming iPad models, iPadOS builds and measured results. A later SHA does not validate an earlier one, so these cannot be folded into current records | `development/archive/history/validation/` | `git show 478244a^:<path>` byte comparison |
| 4 | `docs/ADAPTERS/*` (12 files) | `4934e20` (2026-10-28, "docs: establish contributor governance and project map") | Adapter documentation folded into `development/technical/` | `development/archive/history/docs/ADAPTERS/` | `git show 4934e20^:<path>` |
| 5 | `docs/GETTING_STARTED.md` | `982a0f0` (2026-10-28, "docs: separate user guides from development records") | Superseded by `docs/INSTALLATION.md` and `development/guides/FROM_ZERO.md` | `development/archive/history/docs/` | `git show 982a0f0^:docs/GETTING_STARTED.md` |
| 6 | `docs/TOUCH_ADDON.md`, `addons/WolkaraTouch/{Circle.tga,LICENSE,WolkaraTouch.lua,WolkaraTouch.toc}`, `launcher/WoW/TouchAddon.{h,m}` | `27f61a3` (2026-11-01, "Return to automatic controllers and compact touch settings") | The Lua touch add-on and the host that carried it were replaced by the in-app `wolkaraforever/Touch/TouchGamepad`. The replacement is current product; the add-on is history | `development/archive/history/docs/`, `…/addons/WolkaraTouch/`, `…/launcher/WoW/` | `git show 27f61a3^:<path>` |

### Two restorations withdrawn after the gate ran

`docs/WINDOWS.md` and `development/DIVERGENCE.md` were restored byte-identical and then
removed again: both name another game, and `wolkaraforever/tools/check_layers.sh` refuses to let
anything outside `platform/` name one. The repository's rule is narrower than the audit's
question, and the rule wins - so those two are recorded here as **not restored**, with the
reason being the layer gate rather than anything about iPad support. Their content survives in
Git (`git show 32686f1^:docs/WINDOWS.md`, `git show 478244a^:development/DIVERGENCE.md`).

## Audited and deliberately not restored

| # | Path | Deleting commit | Reason |
| --- | --- | --- | --- |
| 8 | Two other-game profile directories (four files each) | `813c1ec`, `066118a` ("deleting other games") | Other games' profiles. Their removal was a deliberate scope decision and carries nothing about iPad support. Restoring them would re-add material the repository decided not to carry. The names are elided here because `check_layers.sh` forbids naming another game anywhere outside `platform/`. |
| 9 | `profiles/wow-classic-era/*`, `profiles/wow-forever/install.py`, `PERFORMANCE_UI_PLAN.md` | `f149066`, `1d94b66` | `profiles/wow-forever/` still exists with its documentation; the Python installer was replaced by `wolkaraforever/tools/push_game.sh`. The Classic Era profile is an edition record, not an iPad record, and the launcher only carries Forever. |
| 10 | Two other-game engineering notes under `docs/` | `813c1ec`, `066118a` | Other games' notes. Names elided for the same reason as row 8. |
| 11 | `.github/ISSUE_TEMPLATE/*`, `.github/dependabot.yml` | `60d3468` ("chore: remove unrequested repository scaffolding") | Repository scaffolding the owner removed on purpose. |
| 12 | `.github/workflows/verify.yml` | `1257be1` | Removed because the macOS job never acquired a runner and failed after fifteen minutes on every push; the documented replacement is the local gate scripts. Restoring it would restore a check that cannot pass. See `development/guides/REPOSITORY_WORKFLOW.md`. |
| 13 | `wolkaraforever/patches/0022-metal-drawable-scale.patch` | `2acc142` | Its function was folded into the upstream ingest; keeping the patch would break `check_layers.sh`. |
| 14 | `wolkaraforever/tools/check_controller_actions.sh`, `wolkaraforever/tools/test_tooling_docs.sh` | `6efa03d`, `60d3468` | Superseded checks; the Controller Manager contract and the documentation gate replaced them. |
| 15 | `development/technical/CONTROLLER_OUTPUT_PLAN.md`, `development/validation/*-controller-manager.md` | `aaff946`, `680dee5`, `70796b3`, `e58de9a`, `2ffdca9` | Controller Manager material. This branch is explicitly instructed not to implement Controller Manager; restoring its plan as current documentation would misstate scope. |
| 16 | `launcher/*`, `authorization/*`, `runtime/*`, `translation/*`, `tests/*`, `docs/…/…` top-level trees | various | **Relocations, not deletions.** These paths moved into the vendored `platform/` tree. `git log --diff-filter=D` reports them as deletions because the path changed. Nothing is missing. |

## Method

```sh
git fetch origin --prune
git rebase origin/main                     # already up to date on this branch
git log --all --diff-filter=D --name-status --pretty=format:'%h %ad %s' --date=short
git log --all --diff-filter=D --name-only --pretty=format: | sort -u
git log --all --oneline --diff-filter=D -- <path>
git log --all --oneline -S'iPhone' -- wolkaraforever
git log --all --oneline -S'iPad'   -- wolkaraforever
git log --all --oneline -G'iPad|iPhone' -- .
git show <deletion>^:<path>
```

Findings that shaped the table:

- `git log --all --diff-filter=D --name-only -- wolkaraforever | sort -u` returns four paths:
  `README.md`, `patches/0022-metal-drawable-scale.patch`, `tools/check_controller_actions.sh`,
  `tools/test_tooling_docs.sh`. **No iPad or iPhone product source is in that list**, which is
  what makes the "evidence, not code" conclusion above a measurement rather than a guess.
- `git log -S'iPhone' -- wolkaraforever` shows iPhone work arriving and staying: `9770d64`,
  `08741d9` (render scale and window resizing), `225d8c2`, and the phone records in
  `DeviceProfile.m`. Current phone support is therefore a live feature with a thin
  documentation trail, which is what `docs/IPHONE.md` restores.
- `478244a` is a single-purpose commit that deleted 32 files and 9,511 lines of development
  records and exact-SHA validation. It is the largest single loss of device evidence and is
  fully restored above.
- The `-S'iPhone'` history also confirmed that no **iPad**-named source path was ever deleted;
  iPad assumptions were implicit rather than named, which is why the audit continued into the
  idiom/size assumptions in `development/architecture/DEVICE_CONTRACT.md`.

## Regression requirements this creates

Every restored behaviour is a regression requirement, not a historical note:

| Restored material | Requirement it creates | Owning check |
| --- | --- | --- |
| `docs/IPHONE.md` measured session | iPhone remains a supported device with a documented contract; a change that makes the iPhone layout unsupported is a regression | read the contract only — the physical iPhone run is a device item |
| Restored iPad validation records | The current iPad layout (two columns where they fit, whole page visible) may not regress | `wolkaraforever/tools/test_wow_launcher_ui.sh` |
| `docs/TOUCH_ADDON.md` + `WolkaraTouch` | The in-app gamepad must remain the supported touch input; a re-introduced Lua add-on route is not a fix | `wolkaraforever/tools/test_touch_gamepad_ui.sh` |
| Restored adapter docs | The adapters' documented behaviour is the baseline the technical docs must still match | `wolkaraforever/tools/check_docs.sh` |
