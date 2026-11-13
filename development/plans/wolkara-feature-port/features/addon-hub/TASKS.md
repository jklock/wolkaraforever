# Add-on Hub tasks

## 1. Inventory and normalized records

Branch `feature/addon-hub-records`. Read `AddonManager`, `AddonStore`,
`AddonArchive`, `UpdateLock`, `ForeverUIArchive`, existing CurseForge client and
all Add-on tests. Add the normalized record fields from `PLAN.md`, with a
versioned migration. Import existing API records unchanged; browser installs
must carry the project identity from their native action into the download
delegate before archive activation. Discover Files and unmanaged packages from
on-disk TOC/folder data without deleting or claiming ownership of unknown files.
Test migration, duplicate folders, multi-folder packages, missing TOC, project
identity retention, invalid provenance and backup/restore.

## 2. Native My Add-ons

Branch `feature/addon-hub-my-addons`. Make My Add-ons the default Add-ons route.
Build a native searchable/sortable adaptive list/card layout; do not embed a web
page. Each row shows the fields/states in `PLAN.md`. Implement Refresh, per-row
Update/Retry, Update all, enabled state, Remove, detail sheet, Link project and
local groups. Every displayed control must produce a tested state change or an
explicit progress/result sheet; never ship decoration controls. Update all must
snapshot eligible records, serialize activation through `UpdateLock`, report
per-record results, and never make a browser/API/Files install disappear. Test
mixed providers, partial update failure, cancellation, stale result, duplicate
tap, every toolbar action and restart.

## 3. Discovery, Browse and source linking

Branch `feature/addon-hub-discover`. Keep the existing API client as the native
metadata source when an API key is configured: Discover sections, native Browse,
search, sorting, game-version/category filters, hide-installed, paging and
project detail. When no API key exists, expose **Browse CurseForge** as an
acquisition flow using `WKWebView`; it may render normal site pages but it is not
the home screen. For an API-restricted file shown in native project detail, the
Install/Update action opens that exact project page with a pending project/release
token. The delegate accepts the player's clicked ZIP only when it matches the
trusted browser flow, then installs it under that identity. Do not scrape HTML
or copy WebKit credentials. Test API/no-key transitions, native-to-browser
handoff, project-identity retention, link/unlink, trusted redirects, cancellation
and browser install.

## 4. First-class update semantics

Branch `feature/addon-hub-update-status`. Define a resolver result enum:
up-to-date, update-available, checking, downloading, needs-browser-confirmation,
unlinked, unavailable-no-compatible-file, failed-retryable, and failed-terminal.
API-linked records use the existing API client. A known browser project uses the
same resolver but routes Update into the in-app page when the archive cannot be
obtained by API. Files/unmanaged records become update-eligible after explicit
source link; do not infer identity from names. Test all states and ensure Update
all handles browser-confirmation records in a visible serialized queue rather
than dropping them or opening external Safari.

## 5. Device proof

Run archive, store, launcher and UI fixtures plus the same live sequence on both
required simulators; then, when available, use Device Hub on the physical iPad
with one API install, one browser install, one Files import and
one unmanaged existing package. Confirm all four rows appear together, remain
after restart, have correct update status, and preserve their files after a
failed/cancelled update. For an API-restricted browser project, tap Update and
confirm its exact CurseForge page opens inside WolkaraForever, returns to the
same row after download, and records an ordinary update result. Return the
device to the normal home screen with the app running.

## 6. Close the feature

Add migration/downgrade fixtures for all record versions, corrupted records,
lost browser-token state, API-key absence/revocation, untrusted redirects,
interrupted install/update and feature disable. Add English/German/French strings
and VoiceOver focus/value assertions for every toolbar, row and detail action.
Run archive/store/launcher/UI suites on iPad Pro 13-inch (M5) and iPhone Duo,
then `check_layers.sh` and relevant privacy/bundle checks. Record Device Hub
status and, if run, complete the mixed-provider script in task 5 including
relaunch/backup/restore. Put exact SHA, simulator/mode, package digests and
outcomes in PR Proof; keep generated evidence local.
