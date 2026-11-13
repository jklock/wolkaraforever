# UI review: Add-on Hub

## Classification

`ui-page-amendment`, additive. The page behind the home page's add-on rows becomes a native
three-tab hub; the home page itself does not change, and no `wow-home*` baseline is re-recorded.

The protected launcher contract this record is written against is
`development/reviews/ui/UI-LAUNCHER-MANAGER-2026-11-12.md`: the six home-page cards, the
interface selector, and the recommendation row keep their identifiers, titles, order, insets and
default behaviour. The recommendation row still opens this same page, and still installs
nothing by itself.

## Scope

The Add-On Manager gains one native tab and keeps two it already had, and the native tab it
already had becomes the page's default:

1. **My Add-ons** — the default. One native, searchable, sortable list (adaptive card grid on a
   wide iPad layout) of every installed package, whichever route installed it: the CurseForge
   API client, the in-app browser's download, a ZIP the player picked in Files, or a folder that
   was already on disk. A row shows its icon, name, installed version, enabled state, declared
   interface versions, author, and one update word with one action. It is not a web page, and no
   web view is embedded in it.
2. **Discover** — native featured, latest and popular sections, drawn from the API client. It is
   empty with a named reason when no API key is configured; it is never a browser.
3. **Browse** — the existing native query, sort, game-version/category filter, column picker,
   hide-installed filter and paged results. Its layout, identifiers and behaviour are unchanged.

`Browse CurseForge` is an acquisition fallback inside this page, not a tab: when no API key is
configured, or when a project shown in native detail does not hand archives to the API, the
player's action opens **that exact project** in an in-app `WKWebView`. The browser may use the
site's own login and cookies. It never exposes, copies or exports them, and it never opens
Safari. A download the browser catches belongs to the project the action named, and returning to
the app installs it under that identity into the same catalog.

Nothing in this change installs, disables, removes or updates anything on its own. Every one of
those is a control the player presses.

## Changed states

The Add-ons page is drawn in the fixture and compared byte-for-byte. Two baselines move, on both
matrix devices, because the page genuinely has different content:

- `wow-addons-de.png` — the page in German with the three-tab header and My Add-ons selected.
- `wow-addons-recommended-wolkararoue.png` — the page the WolkaraRoue recommendation opens,
  now on My Add-ons with the bundled package as a row in that catalog rather than in a section of
  its own above it.

Every other baseline is unchanged, and `test_wow_launcher_ui.sh` fails if any of them differs.
The rows, detail sheet, group sheet, link sheet and browser handoff are asserted by identifier
and value in `test_wow_launcher_app.m`; translucency under a sheet is not deterministic to the
per-channel tolerance, so a sheet is not a baseline image.

## End-user action

Home page → `Add-ons` (or the recommendation row) → My Add-ons. From there: search, sort, filter,
**Refresh**, **Create Group**, a row's update action, **Update all**, the row's detail sheet
(enable/disable, remove, pin, Link project, group membership, activity), and the `+` button to
import a ZIP. Discover and Browse are reached with the tab control; Browse's `Browse CurseForge`
action opens the in-app browser for a project whose archive the API will not hand out.

## Risks and boundary

- **No physical iPad evidence in this record.** Every claim below is measured on the two matrix
  simulators. The iPad Pro 12.9-inch (5th generation) was not available for this change, and no
  simulator result is presented as a physical one.
- **The API client is the only native metadata route.** The browser is an acquisition route that
  proves no-key downloading works; it is not a catalog feed. Nothing scrapes CurseForge HTML and
  nothing reverse engineers the desktop client, because that is the boundary the plan sets.
- **An unlinked package has no update.** A package that arrived as files or was found on disk has
  no project identity, so no update is guessed from its name. It shows `Link project` and stays
  fully manageable locally until the player names the project.
- **The browser shares the site's session.** Login and cookies live in WebKit's own store, as
  they would in any web view, and the app never reads, copies or logs them. A player who signs in
  inside the app is signed in to that site in the app only.
- **The manifest gains a format.** A manifest written by a newer build is shown read-only rather
  than downgraded, and a manifest this build cannot use is copied aside before anything can
  rewrite it.

## Exact SHA

Branch `feature/addon-hub`, base `438bf348ddd13ae7a10cc0ea50ccd1b0751e03b6` (`origin/main`).
The record is committed with the change; the pull request states the head SHA it opened from.

## Tests

All of the following were run on `2026-11-12` from this branch:

- `wolkaraforever/tools/test_addon_archive.sh` - **PASS**: 59 archive checks plus the import and
  bundled-package lifecycles, now covering manifest formats 1, 2 and 3, the provenance a
  migration records, the digest's move to `digest`, and the adoption path for a linked folder.
  Output: `ADDON IMPORT PASS`, `BUNDLED PACKAGE PASS`, `ADDON ARCHIVE PASS: 59 checks`.
- `wolkaraforever/tools/test_wow_launcher.sh` - **PASS**, including a new
  `ADDON HUB RESOLVER PASS` built with AddressSanitizer and UBSan: the nine update states from
  facts alone, the stored round-trip, and a log line that cannot carry a URL, a cookie, a token
  or a path.
- `wolkaraforever/tools/test_wow_launcher_ui.sh` on **iPhone Duo** - **PASS**: fixture
  assertions plus `UI baseline comparison passed`.
- `wolkaraforever/tools/test_wow_launcher_ui.sh` on **iPad Pro 13-inch (M5)** - **PASS**:
  fixture assertions plus `UI baseline comparison passed`.
- `wolkaraforever/tools/check_ui_policy.sh --review UI-ADDON-HUB-2026-11-12.md` - **PASS**
  (`UI policy: PASS`), which runs the UI suite on both matrix devices itself.
- `wolkaraforever/tools/check_layers.sh` - **PASS**, 16 checks, including
  `check_localization: 646 keys`.
- `wolkaraforever/tools/check_docs.sh` - **PASS**: 117 markdown files, every relative link,
  image and anchor resolves.
- `wolkaraforever/tools/test_localization.sh` - **PASS**: 65 checks.

## Live QA

Simulator only, on both matrix devices. Captures of `My Add-ons`, `Discover` and `Browse` were
written to the simulator container by the UI run (`addon-hub-myaddons.png`,
`addon-hub-discover.png`, `addon-hub-browse.png`) and were **not** committed.

Observed, in the run:

- **My Add-ons is the default tab**, with the three tabs drawn as one native segmented control.
- The resting toolbar reads `Sort add-ons`, `Filter add-ons`, `Group`, `Update All` on both
  devices with no word clipped; the selection controls appear only once a package is selected.
- Search narrowed the list to one record and back; filter and sort reordered the same set and
  changed nothing else (asserted, and visible in the draw).
- An installed row shows icon, name, version, author, its one update word and one action. An
  unlinked package reads `No linked project` with a `Link` action in English and
  `Kein verknüpftes Projekt` / `Verknüpfen` in German.
- `Discover` with no API key is a named empty state with a hint, not a blank page and not a web
  view. `Browse` with no API key is one access row, with the sort, filter, column and count
  controls hidden until a key exists.
- The empty Add-ons page says `No add-ons installed` once, not twice.

**Not run, and not claimed:** an API install, an in-app browser download and its return, a
Files import from the document picker, grouping and update flows against live provider data,
and backup/restore on a device. No Core API key was configured and no game installation existed
in this environment; those paths are covered by the fixture's assertions and by
`test_addon_archive.sh`, not by a live run. The physical iPad was not available.

## Screenshots

Baselines re-recorded on both matrix devices for `addons-popup.png`, `wow-addons-de.png` and
`wow-addons-recommended-wolkararoue.png`. `wow-home*`, `wow-voice*`, `wow-launcher-*` and
`voice-*` are unchanged; a recording run rewrites them with sub-tolerance rounding noise and
those rewrites were reverted, so the diff carries only the three pages that really changed.

