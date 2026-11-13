# Add-on Hub plan

## Outcome

The Add-ons screen is a native, CurseForge-style hub—not a web browser. It opens
on **My Add-ons** and has native **Discover** and **Browse** tabs. Browser,
API-key and Files import are acquisition routes only. Once an archive is
installed, it appears in the same first-class catalog regardless of where it
came from.

## Product model

### My Add-ons — the default screen

Show every installed add-on in one searchable/sortable native list or adaptive
iPad card grid. Each row has icon, name, installed filename/version, enabled
state, game/interface version, author, latest-version status, and an action:
Update, Up to date, Checking, Downloading, Needs browser confirmation,
Failed/Retry, or Update unavailable. Provider provenance is diagnostic detail,
not a visible category that changes the row's management controls.

Every visible control has a real action: Refresh recalculates record state;
Update/Retry starts a source-appropriate update; Update all builds one serialized
operation plan and reports each result; search/filter/sort change the rendered
records; Create Group creates local groups and membership; detail exposes
enable/disable, remove, source link and activity history. Groups are local
organization of the same records.

### Discover and Browse

Discover presents native featured, latest and popular sections. Browse presents
native query, sort, version/category filters, hide-installed option and paged
results. A project detail sheet shows description, author, compatible file,
installed state and Install/Update action.

The API-key client may supply this catalog when configured. Without a key, the
player can use the embedded CurseForge browser to find a project/download; that
browser is an acquisition fallback, not the Add-ons home UI. The browser may
use normal site login/cookies in WebKit but never exposes or copies credentials.

## Unified record contract

Extend managed records so every installed package has: stable local package ID,
folder set, display name, installed archive/version, interface versions, author,
icon cache key, enabled state, source project identity, release identity when
known, final archive URL when applicable, digest, install time, and last
update-check result/time. Provenance (`api`, `browser`, `files`, or `unmanaged`)
is retained only for diagnostics/audit.

An API-restricted add-on never becomes second-class: the native project's
Install/Update action automatically opens that exact project/download page inside
the WolkaraForever browser. The action carries the project identity through the
browser download delegate into the installed record. From then on it has the
same row, update checks, update history, groups, enable/remove, backup and
restore behavior as an API-downloaded add-on. Update routes back to that exact
in-app page when a direct API archive is unavailable; it never leaves the app.

Files/pre-existing packages without a reliable project identity are still fully
managed locally: enableable, removable, grouped, searchable, backed up and
health-checked. On first discovery the hub requires the player to select its
project through native/API search or the in-app browser before it participates in
updates. It must not guess an update from a name. Once linked, its user-visible
behavior is identical to every other installed record.

## Hard boundary

The source browser implementation proves no-key acquisition, not a native
catalog data feed. Do not scrape CurseForge HTML or reverse engineer the desktop
client to fabricate native results. The API-key client is the supported metadata
route. The no-key browser handles downloads; native management remains complete
from local package metadata. A future public, documented no-key catalog API may
be added only after its terms and behavior are verified.

## Acceptance

An API-installed, browser-installed, Files-imported and pre-existing unmanaged
add-on all appear in My Add-ons, survive restart/backup/restore and support the
same local management actions. A known-source package has the same visible row,
update state and update result regardless of acquisition route. The native screen
never degrades to a browser page. An unlinked package has an explicit Link
project action; an unavailable update is never a hidden or failing button.

## Completion gate

The old Add-ons route redirects to My Add-ons without losing installed records,
selections, credentials or backup data. Extend the current `AddonManager`,
`AddonStore`, `AddonPackage` and bundled `WolkaraRoue` recommendation; do not
replace their established behavior. A disabled feature falls back to the current
manager and leaves packages/data untouched. Localize every row/action/error in
English, German and French and expose stable VoiceOver labels, values and focus
order. Run archive, store, launcher and UI suites plus live flow on both required
simulators; Duo must retain one-column safe-area presentation while iPad preserves
its approved layout. Device Hub may additionally prove mixed API/browser/Files/
unmanaged records, link/project identity, update result, failed/cancelled recovery
and restart. Record only digest, provider and outcome—never WebKit credentials—
in PR Proof, keep captures local, and update documentation only with observed
behavior.
