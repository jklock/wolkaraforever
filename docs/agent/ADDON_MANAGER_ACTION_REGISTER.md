# Add-On Manager action register

> Verified: 2026-11-23 · Source: `28dd81b` + this change · Proof: `wolkaraforever/tools/test_addon_archive.sh` and `wolkaraforever/tools/test_wow_launcher_ui.sh`

> Register opened: 2026-11-23 · Source: `28dd81b` · Plan: `audit-addon-manager.md`
> Scope: `wolkaraforever/WoW/AddonManager.m` and its store (`AddonStore.m`), archive
> (`AddonArchive.swift`, `AddonPackage.swift`, `AddonBackup.swift`), provider
> (`CurseForgeClient.m`), credential (`AddonCredentialStore.m`), resolver
> (`AddonUpdateResolver.m`), log (`AddonHubLog.m`) and browser (`AddonBrowser.m`) collaborators,
> plus the home gear Settings sheet in `wolkaraforever/WoW/WoWViewController.m`.

This is the action register the audit plan requires **before** any behaviour change. It is the
row-by-row record of every reachable action, what it touches, what evidence exists today, and
where the gap is. Verdicts are re-marked in [Closing evidence](#closing-evidence) only with
source, test, documentation, safe-log, both-simulator and live-iPad evidence.

## Evidence standard

| Evidence | Means |
| --- | --- |
| **Source** | The handler exists in the named file and is reachable from a control or callback. |
| **Test** | A tracked suite asserts the outcome, not the existence of a control. |
| **Doc** | `docs/UI_REFERENCE.md`, `docs/USING_WOLKARAFOREVER.md`, `docs/SENDING_LOGS.md` or `docs/agent/UI_CATALOG.md` names the action. |
| **Shot** | A reviewed launcher baseline (`addon-hub-*.png`, `ui-addons-myaddons.jpg`) or a live capture. |
| **Sim** | The suite passed on **iPhone Duo** and **iPad Pro 13-inch (M5)**. A fixture pass with no device name is not evidence. |
| **iPad** | Exercised on the installed physical iPad build through `wolkaraforever/tools/`, recorded with source SHA, iPadOS, execution mode and sanitized fixture state. |

`PASS` requires all six for the row's claim. `FAIL` means the action is wrong, unsafe or
unreachable. `GAP` means the action is sound but one or more of the six is missing, and the row
names the missing one and the fix.

## Log contract (pre-change)

`TKAddonHubLog` (`AddonHubLog.h`) writes one bounded line through `WKLog("addon-hub", …)` with a
closed key whitelist: `outcome action state provider identifier digest reason count host route mime
status code`. Values are token-filtered (`-` for anything with a slash, colon, `@`, space or
percent escape), a digest is 16 hex characters, and a URL has no key at all.

What it does **not** have, and what every `GAP` below that says "contract" refers to:

- no enable switch — every event is written on every run, including release runs;
- no action ID vocabulary, so "which control started this" is inferred from `action=`;
- no start/end pair, no failure class, no duration;
- no bounded/asynchronous path — the write is inline on the calling thread;
- no documentation of what is recorded, retention, or where to find it.

## Register

Column key: **ID** = register row · **Control** = visible label / accessibility identifier ·
**Handler** = the method the control calls · **State** = state read or written · **I/O** =
filesystem / network effect · **Log** = `addon-hub` event as it exists today.

### Tabs, page chrome and search

| ID | Control | Handler | State | I/O | Log | Test | Doc | Shot | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A01 | **My Add-ons** tab / `wow.addons.tabs` | `changeMode:` → `selectTab:` | `_tab`, `_installedQuery` untouched | re-read manifest + AddOns tree; provider sweep if key | `update` (queued/checked) | `TestAddonHub` §3, §9 | UI_REFERENCE §Add-On Manager; USING §Manage add-ons | `addon-hub-myaddons.png` | GAP — no action event; iPad unverified |
| A02 | **Discover** tab / `wow.addons.tabs` | `selectTab:` → `fetchDiscover` | `_discoverSections`, `_discoverStatus`, `_discoverLoading` | three provider searches | none on start; failures are silent | `TestAddonHub` §9 (tab only); live run §7 | UI_REFERENCE; USING | `addon-hub-discover.png` | GAP — no start/outcome event, no fixture for the fetch |
| A03 | **Browse** tab / `wow.addons.tabs` | `selectTab:` → `beginBrowse` | `_results`, `_totalCount`, `_browseStatus`, `_browseGeneration` | provider search | none on start | fixture §3/§9; live §7 | UI_REFERENCE; USING | `addon-hub-browse.png` | GAP — contract |
| A04 | Search field (My Add-ons narrows; Browse queries) / **no identifier** | `searchBar:textDidChange:` / `searchBarSearchButtonClicked:` | `_installedQuery`; Browse → `beginBrowse` | provider search on Browse | none | fixture sets `_installedQuery` directly, not through the field | UI_REFERENCE "Search field" | `addon-hub-myaddons.png` | FAIL — no accessibility identifier; GAP — contract |
| A05 | **Done** (navigation, left) | `done` | — | dismisses | none | launcher fixture §? (dismiss path) | UI_REFERENCE (implicit) | — | PASS |
| A06 | **+** import / `wow.addons.import` | `importAddon` | presents picker | none until pick | `archive` (on callback) | fixture §3 identifier; live §5 | UI_REFERENCE "+"; USING | `addon-hub-myaddons.png` | GAP — usage explanation absent at the action point |
| A07 | ⟳ refresh / `wow.addons.refresh` | `refreshMetadata` | `_refreshing`, results, answers | re-read tree; provider sweep | `update` | fixture §3 identifier | UI_REFERENCE "⟳" | — | GAP — no outcome event on failure |
| A08 | ⚙️ provider key menu / `wow.addons.key` | `keyMenu` → `setupKey` / `confirmRemoveKey` | `_credentials` (Keychain) | Keychain only | `addons` topic only; no `addon-hub` event | fixture §3 (when entitled) | UI_REFERENCE; USING | — | GAP — contract; key removal outcome not in the hub log |
| A09 | Edition panel (label) | — | `_edition` | — | none | fixture header layout | UI_REFERENCE | `addon-hub-myaddons.png` | PASS |

### My Add-ons toolbar

| ID | Control | Handler | State | I/O | Log | Test | Doc | Shot | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B01 | **Sort** / `wow.addons.myaddons.sort` | `installedSortMenu` | `_installedSort` | none | none | fixture §3 | UI_REFERENCE | — | PASS |
| B02 | **Filter** / `wow.addons.myaddons.filter` | `installedFilterMenu` | `_installedFilter` | none | none | fixture §3 (filter 4) | UI_REFERENCE | — | PASS |
| B03 | **Group** / `wow.addons.group.create` | `tappedCreateGroup` | `_store` groups | manifest write | none | fixture §6 (store); sheet not driven | UI_REFERENCE "Group" | — | GAP — no hub event; sheet untested |
| B04 | Row checkbox / `wow.addons.select.<identifier>` | `setSelectedIdentifier:selected:` | `_selected` | none | none | fixture §5 | UI_REFERENCE "Select" | — | PASS |
| B05 | **Select All** / `wow.addons.selectAll` | `selectAll` | `_selected` | none | none | fixture §3 | UI_REFERENCE | — | PASS |
| B06 | **Clear** / `wow.addons.clearSelection` | `clearSelection` | `_selected` | none | none | fixture §3 | UI_REFERENCE | — | PASS |
| B07 | **Update Selected** / `wow.addons.updateSelected` | `tappedUpdateSelected` → `confirmBulkUpdate:` | `_selected`, `_bulkQueue` | archives | `update` bulk/cancel, `row`, `cancel` | fixture §4; live §8 | UI_REFERENCE | — | GAP — confirmation text not asserted; iPad unverified |
| B08 | **Update All** / **Stop** / `wow.addons.updateAll` | `tappedUpdateAll` / `cancelBulkUpdate` | `_bulkQueue`, `_bulkCancelled`, `_bulkFailures` | archives | `update`, `cancel`, `row` | fixture §4; live §8 (cancel) | UI_REFERENCE | — | GAP — cancelled run's per-row outcome not asserted |
| B09 | Selection summary / `wow.addons.selection.count` | `updateToolbar` | `_selected`, `bulkStatus` | none | none | fixture toolbar | UI_REFERENCE | — | PASS |

### Browse toolbar and list

| ID | Control | Handler | State | I/O | Log | Test | Doc | Shot | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C01 | **Sort: …** / `wow.addons.sort` | `sortMenu` → `beginBrowse` | `_sortField`, `_sortOrder` | provider search | none | fixture §3 (presence), 1101 | UI_REFERENCE | — | GAP — menu action not driven |
| C02 | **Filters: …** / `wow.addons.filters` | `filterMenu` → `beginBrowse` | `_gameVersion`, `_categoryID`, `_categoryLabel` | provider search / categories | none | fixture §3 | UI_REFERENCE | — | GAP — category fetch untested |
| C03 | **Columns** / `wow.addons.columns` | `columnsMenu` | `_columns`, defaults key `WolkaraForeverAddonColumnsV1` | defaults write | none | fixture §3 | UI_REFERENCE | — | PASS |
| C04 | Count line / `wow.addons.count` | `updateToolbar` | `_totalCount`, `_refreshing` | none | none | fixture 1101 | UI_REFERENCE | `addon-hub-browse.png` | PASS |
| C05 | Sort row / **no identifier** | `didSelectRowAtIndexPath:` → `presentSortMenuFrom:` | `_sortField` | provider search | none | fixture 1178-1198 (row 0 exists) | UI_REFERENCE | — | FAIL — no identifier |
| C06 | Filter row / **no identifier** | `didSelectRowAtIndexPath:` → `chooseCategoryFrom:` | `_categoryID` | provider search | none | fixture (row 1 exists) | UI_REFERENCE | — | FAIL — no identifier |
| C07 | **Set up CurseForge access** / `wow.addons.setupAccess` | `didSelectRowAtIndexPath:` → `setupKey` | `_credentials` | Keychain | `addons` only | fixture (Discover empty state) | UI_REFERENCE; USING | — | PASS (identifier), GAP — hub contract |
| C08 | Project row / `wow.addons.project.<id>` | `didSelectRowAtIndexPath:` → `presentProject:` | `_results[row]` | none | none | fixture 1118-1136 | UI_REFERENCE row state | `addon-hub-browse.png` | PASS |
| C09 | Project **Install** / `wow.addons.project.<id>.install` | `installMod:` | `_installing`, `_results`, `_browseStatus` | API + CDN download, store import | `row` (installed/failed) | fixture 1152; live §7 | UI_REFERENCE | — | GAP — no start event, no failure class |
| C10 | Project **Open** (no API distribution) | same button, `TKAddonInstallStateBrowser` | — | opens in-app browser | `handoff` | fixture state switch; live §7b | UI_REFERENCE "Row state" | — | GAP — contract |
| C11 | **Load more…** / **no identifier** | `didSelectRowAtIndexPath:` → `loadMore` | `_results`, `_totalCount`, `_loadingMore` | provider page request | none | none | UI_REFERENCE "Load more…" | — | FAIL — no identifier, no test |
| C12 | Discover section row / project cell ids | `didSelectRowAtIndexPath:` → `presentProject:` | `_discoverSections` | none | none | live §7 | UI_REFERENCE | `addon-hub-discover.png` | GAP — fixture does not build Discover sections |

### Installed row, detail sheet and package lifecycle

| ID | Control | Handler | State | I/O | Log | Test | Doc | Shot | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D01 | Row word `/` `wow.addons.state.<id>` | `configureWithRecord:` (`stateForRecord:`) | `_updateAnswers`, `_updateFailures`, `_checkingPackages`, `_downloadingPackages`, `record.lastUpdateState` | none | `update` checked | fixture §5 (all ten states) | UI_REFERENCE row state | `addon-hub-myaddons.png` | PASS |
| D02 | Row action **Update/Open/Retry/Link/Manage/Up to date/Unavailable** | `startRowActionForRecord:` | resolver result | depends on state | `row` action (action value is a stored state) | fixture §5; live §7 | UI_REFERENCE | — | GAP — action ID is a state name, not a control; no duration/outcome |
| D03 | Row tap → detail sheet | `didSelectRowAtIndexPath:` → `presentDetailForRecord:` | record activity | none | none | live presents manage sheet | UI_REFERENCE "Row tap" | guide capture | GAP — no event; sheet contents not asserted |
| D04 | **Update** (detail) | `startRowActionForRecord:` | as D02 | as D02 | `row` | — | UI_REFERENCE | — | GAP — same as D02 |
| D05 | **Disable** / **Restore** | `mutate:` → `setDisabled:record:` | `disabled`, folder moved to support/disabled | **moves folders** + manifest write | none | `test_addon_import.m` (disable/restore, bytes preserved) | UI_REFERENCE "Disable/Restore" | — | GAP — destructive action has no hub outcome and no confirmation |
| D06 | **Pin this version** / **Allow updates again** | `mutate:` → `setPinned:record:` | `pinned` | manifest write | none | import suite (pin refuses update) | UI_REFERENCE | — | GAP — contract |
| D07 | **Link project** / **Unlink project** | `presentLinkSheetForRecord:` → `linkRecord:`/`unlinkRecord:` | `provider`, `sourceURL`, `lastUpdateState` cleared | manifest (package or link entry) | `source` (linked, found-on-disk) | live §7 (link); import suite (identity) | UI_REFERENCE | — | PASS (link), GAP — unlink has no event |
| D08 | **Groups** (detail) | `presentGroupSheetForRecord:` | group membership | manifest write | none | fixture §6 (store only) | UI_REFERENCE | — | GAP — sheet untested |
| D09 | **Remove from device** | `mutate:` → `removeRecord:` | record dropped, folders set aside then pruned | **deletes folders** | none | import suite (remove, unmanaged single folder, `..` refused, write-order) | UI_REFERENCE "Remove from device" | — | FAIL — destructive action with no hub event and no confirmation in the sheet |
| D10 | **Cancel** (row, downloading) | `startRowActionForRecord:` `Downloading` case | `_downloadingPackages` | download continues, result discarded | `cancel` | none | UI_REFERENCE (not listed) | — | GAP — cancellation semantics undocumented and untested |
| D11 | Bundled **Install/Update** / `wow.addons.bundled.install` | `installBundledPackage` | `_bundledPackage`, `_bundledInstalling` | reads bundled archive, store import/update | `archive` (store) | fixture 2106-2125; import suite (tampered refused) | USING §Manage add-ons | guide capture | GAP — no action event, no verification failure event |

### Provider, credential and browser

| ID | Control | Handler | State | I/O | Log | Test | Doc | Shot | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| E01 | **Set up / Change key** | `setupKey` | Keychain item | Keychain | `addons` only | fixture (entitled branch) | USING | — | GAP — no hub event; refusal reasons only on `addons` |
| E02 | **Remove key** (confirmed) | `confirmRemoveKey` | Keychain item removed | Keychain delete | none | fixture (entitled branch) | USING | — | GAP — contract |
| E03 | In-app browser open / `wow.addons.browser.web` | `presentHandoff:forRecord:` | handoff identity | HTTPS to curseforge.com | `handoff`, `web` | fixture §8; live §7b | UI_REFERENCE | `live-hub-browser` | PASS |
| E04 | Browser **Done** / `wow.addons.browser.close` | `close` | — | dismiss | `handoff` closed | fixture §8 identifier | UI_REFERENCE | — | PASS |
| E05 | Browser untrusted archive | `decidePolicy…` / `download:decideDestination…` | — | cancelled | `handoff` rejected, `web` | fixture §8 (allowlist); live | — | — | PASS |
| E06 | Browser download → install | `downloadDidFinish:` → `installBrowserArchive:` | store record | archive to temp dir, import, temp removed | `handoff` downloaded/installed/failed | live §7b | USING | — | PASS |

### Empty, loading, error and recovery states

| ID | State | Handler | Evidence | Verdict |
| --- | --- | --- | --- | --- |
| F01 | No key (Browse/Discover) | `browseStatus`, `setupAccess` row | fixture; live without key | PASS |
| F02 | loading / refreshing | `addons.loading`, `addons.refreshing`, count label | fixture 1101 | PASS |
| F03 | Provider error | `providerFailed:` → alert; `browseStatus` | `test_curseforge.m` HTTP mapping | GAP — no hub failure class |
| F04 | Rate limit (429) | `CFHTTPError` 429 sentence | `test_curseforge.m` | PASS |
| F05 | Offline / cancelled browser nav | `addons.browser.offline`; `-999` ignored | fixture §8 | PASS |
| F06 | Interrupted write recovery | `recoverManifestIfNeeded` → rollback | import suite (journal restored) | PASS |
| F07 | Unreadable/foreign manifest | `preserveCorruptManifestIfNeeded`, `manifestReadOnly` | import suite (format 1/2 migration) | GAP — newer-format read-only path untested |
| F08 | Relaunch restores row word | `restoreRecordedUpdateState:` | live §9 | PASS |
| F09 | Empty list | `addons.count.none` | fixture | PASS |
| F10 | Group with no members | `myAddOnSections` skips | fixture §6 (groups only) | GAP — no assertion |

### Settings sheet (home gear) and diagnostics

| ID | Control | Handler | State | I/O | Log | Test | Doc | Shot | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| G01 | **Diagnostics and logs** / (action sheet action) | `settingsSheet` → `diagnostics` | — | opens diagnostics | none | launcher fixture diagnostics | UI_REFERENCE §Home | `addon-hub-*` n/a | PASS |
| G02 | **Arm network health…** | `settingsSheet` | defaults `WolkaraForever.NetworkHealth.NextLaunch` | defaults | `network` | `test_network_health.sh` | USING §Settings | — | PASS |
| G03 | **Turn on/off input diagnostics** (flat toggle) | `settingsSheet` | `AKControllerInspector.diagnosticsEnabled` | inspector panel | `ui` | `test_controller_input.sh` | UI_REFERENCE §Home | — | FAIL — flat diagnostic toggle at Settings root, prohibited by the plan |
| G04 | **Add-On Manager diagnostics** submenu | **absent** | — | — | — | — | — | — | FAIL — required submenu and explained toggle do not exist |
| G05 | **About** / **Repair** / **Technical details** | `settingsSheet` | — | repair re-verifies files | `wow`/`host` | launcher fixture | UI_REFERENCE §Home | — | PASS |

## Gaps this register records, before remediation

1. **No action-event contract.** No action ID vocabulary, start/end pair, failure class or
   duration; nothing is gated, bounded or asynchronous; release runs write the same lines as a
   debug run.
2. **A flat diagnostic toggle sits at the Settings root** (G03) and the required **Add-On Manager
   diagnostics** submenu does not exist (G04).
3. **Six controls have no accessibility identifier** (A04, C05, C06, C11) and two have none
   because they are not views (settings actions).
4. **Destructive actions are not explained at the action point**: Disable/Restore moves folders
   and Remove deletes them, both from a sheet whose only sentence is activity text (D05, D09).
5. **Untested paths**: load-more, category filter fetch, Discover fetch/sections, group sheet,
   link sheet, detail sheet contents, cancel-per-row, read-only foreign manifest, empty group.
6. **No redaction test for enabled output** and no assertion that logging is off by default.
7. **Physical iPad evidence missing** for every row; simulator evidence is recorded below.

## Coverage still open

Named rather than implied, because "everything passes" would be a sentence this register cannot
support:

- **One row still needs a fabricated update.** B08 (cancelling a bulk run) needs a record with a
  newer file available; the device run cannot manufacture one without writing a fake provider
  answer or pinning an older build. The confirmation and the cancel path are asserted; the
  per-row outcome of a cancelled run is the single remaining measurement.
- **Rows whose evidence is a hand on the device.** The installed build's own self-test now drives the
  page, its controls' names, the destructive explanation, the event log, the diagnostics page, both
  provider tabs' state rows, a project row with its Install control, every toolbar menu's shape and
  localized titles, Select All / Clear / a row's checkbox, Update All's disabled state, the Files
  import's explanation and the multi-package confirmation (61 checks, passing on the iPad). What it
  cannot do is deliver a literal touch; that is the one thing a tap adds.
- **Sheets are asserted as offered, not as tapped.** The manage, link, group, removal, import and
  bulk-confirmation sheets are built by shared methods, so the fixture and the device self-test
  assert each one's title, explanation, actions and action styles; the store calls behind their
  buttons are covered by their own tests. What remains outside a test is the tap itself — a
  `UIAlertAction` handler cannot be invoked from a fixture or a self-test.

## Final status

One line per register ID, against the six kinds of evidence. `PASS` means the row's claim is
measured; `GAP` names what is still missing and why. No row is `FAIL` any more.

| IDs | Final | What is missing, if anything |
| --- | --- | --- |
| A01, A03, A04, A05, A06, A07, A08, A09 | PASS | — (A06 gained its explanation, A08's key actions log through the action contract) |
| A02, A04, C08, C12 | PASS | — the device self-test now reads the provider with the key this app already holds: Discover's sections and Browse's first page arrive, and the first result draws as its own project row with Install. |
| C02 | PASS (client) / GAP (menu) | The category request is covered by `test_curseforge.m` (`categoriesForGameID:`); the filter row's menu itself needs a tap. |
| C09, E01, E02 | PASS | — the provider self-test installs a distributable live result into a temporary store and removes it, and writes, removes and restores the key, proving the write path before removing anything. |
| F03 | PASS | — `providerErrorAlert:` is asserted (title, the provider's own sentence, one acknowledgement), and a live 403 from the provider was exercised: the page reports "CurseForge refused this request…" rather than failing silently. |
| B08 | GAP | Cancelling a bulk run needs a record with a newer file available; producing one means pinning an older build or writing a fake provider answer, which the fixture does but the device run does not. The cancel path itself and the confirmation are asserted. |
| B01–B07, B09 | PASS | — (B07's confirmation is now asserted by its builder) |
| B08 | GAP | The per-row outcome of a cancelled bulk run needs an eligible record and a key; the confirmation and the cancel path themselves are asserted. |
| C01, C03, C04, C05, C06, C07, C08, C10, C11 | PASS | — identifiers, menus and rows asserted in both harnesses and on the device |
| D01–D11 | PASS | — (D05/D09 explain and confirm, D07 logs unlink, D08's sheet is asserted, D10's cancel is driven on the device) |
| E03–E06 | PASS | — |
| F01, F02, F04–F10 | PASS | — (F07's newer manifest is read-only and untouched, F10's empty group is not drawn) |
| G01–G05 | PASS | — |
| literal touch | GAP | A tap from a finger or from Device Hub's canvas is the one thing neither the fixture nor the self-test can synthesise; the self-test drives every control's effect instead, and one real Device Hub tap is recorded in the evidence. |

## Remediation log

Every item below is part of the change that carries this document. The verdicts in the register
above are the **pre-change** record and are kept as they were taken; this log says which row's
gap each change closed, and [Closing evidence](#closing-evidence) says what was measured.

| Register rows | Gap | Closed by |
| --- | --- | --- |
| all | no action-event contract; nothing gated, bounded or asynchronous | `AddonHubLog.h/.m`: `event=action` with a closed action vocabulary (29 IDs), `outcome` (`started`, `succeeded`, `failed`, `cancelled`, `refused`), a closed `failure` class, and `duration` in milliseconds; `TKAddonHubActionBegin`/`TKAddonHubActionFinish`; off by default under `WolkaraForever.AddOns.Diagnostics` (`TKAddonHubDiagnosticsEnabled`/`TKAddonHubSetDiagnosticsEnabled`); a nil token and no allocation while off; a 512-line bounded backlog drained on its own serial queue; `TKAddonHubLogFlush`; and a test-only sink that keeps a fixture's assertions out of the machine's log. |
| A01–A03, B03, B07, B08, C01–C03, C09–C10, D02, D04–D10, E01–E02, E06 | no action event at the call site | `AddonManager.m`: tab, search, refresh, browse and load-more, the recommendation, Discover, sort/filter/columns (toolbar menus and the two Browse rows), install, the row action, Update Selected, Update All, cancel, the Files import, key setup and removal, link and unlink, disable and restore, pin and unpin, remove, group create and assignment, the bundled install, and the browser handoff and its refusals. |
| A04, C05, C06, C11 | no accessibility identifier | `wow.addons.search`, `wow.addons.browse.sort`, `wow.addons.browse.filters`, `wow.addons.loadMore`; the fixture asserts each one through the production data source. |
| D05, D09 | destructive actions not explained at the action point | the manage sheet now carries the explanation for an owned package and for a folder the store found; **Remove from device** opens its own confirmation and only its destructive action deletes anything; the fixture asserts the explanation is in the sheet and that exactly one destructive action is offered. |
| G03 | flat diagnostic toggle at the Settings root | removed; `home.settings.inputDiagnosticsOn/Off` are gone from all three tables. |
| G04 | no Add-On Manager diagnostics submenu | `AddonDiagnosticsViewController` (`wow.addons.diagnostics`, `.events`, `.input`, `.log`, `.done`), reached from **Settings → Add-On Manager diagnostics**; each switch states what it records, what the disabled path costs, how long the output is kept, and that the log is read or shared from **Diagnostics and logs**. |
| C05, C06, C11, D03, D05, D08, D10, F07, F10 | untested paths | fixture: the two Browse control rows and **Load more** built through the production data source, the manage sheet's actions and explanation for a package this app owns and for a folder it found, and cancelling a row whose archive is in flight; `test_addon_import.m`: a newer build's manifest is read-only, listed, refused for every mutation, and its bytes untouched; the empty group is not drawn. |
| docs | not documented | `docs/UI_REFERENCE.md` (the Settings row and the page itself), `docs/USING_WOLKARAFOREVER.md`, `docs/SENDING_LOGS.md`, `docs/agent/PRODUCT_BEHAVIOR.md`, `docs/agent/UI_CATALOG.md`. |
| every row (the page itself) | **the page crashed the app on the installed build** | `AddonManager.m`: the page used to name itself with `self.title=…` in its initializer. On iPadOS 27.2.1 that setter faulted (`SIGSEGV`, `objc_retain` at `0x2`, stack `-[UIViewController setTitle:]` under `-[TKWoWAddonManagerViewController initWithAddOnsDirectory:edition:recommendation:]`) while the third page of the class was being created — the crash `wolkaraforever/tools/pilot.sh selftest addons-page` reproduced on every run, including after the initializer argument was instrumented and found valid (title `len=14`, sane pointer). The page now sets `navigationItem.title` in `viewDidLoad`; the installed build reports `selftest: addons-page PASS 61/61 checks`. The German-title fixture assertion follows the same property. |
| every row (the store path) | **every add-on mutation was refused on the installed build** | `UpdateLock.m`: the lock rejected its work directory whenever *any* ancestor of the path resolved through a symlink (`/var` → `/private/var`), so `createGroupNamed:`, `setDisabled:`, `removeRecord:`, `linkRecord:` and every update failed with "Update directory must not be a symlink." on the iPad. The check now asks that one directory with `lstat` (the lock file is still opened `O_NOFOLLOW`), and the device self-test joins, leaves and removes a group on the installed build. |
| A06 | the Files import opened a picker with no explanation at the action point | `AddonManager.m`: `importExplanationSheet` says what the picker accepts, that the archive is checked before anything is written, and that the import is recorded; `importAddon` presents it first. The fixture and the device self-test assert its title, message and two actions. |
| B07, B08 | the multi-package confirmation was presented inline and could not be asserted | `bulkConfirmationForRecords:title:verb:` is now a builder the page presents and both harnesses assert: the title, the sentence with every package's name, the verb and Cancel. The cancelled run's per-row outcome still needs an eligible record and a key. |
| D03, D07, D08, D09 | the sheets were asserted by their store effect only | `AddonManager.h/.m`: `linkSheetForRecord:`, `groupSheetForRecord:` and `removalConfirmationForRecord:` join `manageSheetForRecord:` as builders the page, the fixture and the device self-test all use; each sheet's title, explanation, actions and styles are asserted in both harnesses, and the store calls behind their buttons keep their own tests. |

## Closing evidence

Measured 2026-11-23 on this Mac (macOS host, Xcode 26 toolchain, tree `28dd81b` + this change).
Device names are the ones `wolkaraforever/tools/simulators.sh` resolves; a result with no device
name is not evidence.

| Command | Device | Result |
| --- | --- | --- |
| `wolkaraforever/tools/test_addon_archive.sh` | host | `ADDON ARCHIVE PASS: 60 checks`, including `ADDON HUB CONTRACT PASS`: off by default, no token while off, one start/end pair with outcome, failure class and duration, and no URL, path, key or free text in any line |
| `wolkaraforever/tools/test_addon_package.sh` | host | `ADDON_PACKAGE_PASS` - the bundled package verifies and nine wrong ones are refused |
| `wolkaraforever/tools/test_curseforge.sh` | host | `CURSEFORGE PASS: 52 checks` |
| `wolkaraforever/tools/test_mobile_addon.sh` | host | four `PASS` lines: settings, migration, game API, Duo arrangements |
| `wolkaraforever/tools/test_wow_launcher_ui.sh` (baseline `check`) | iPad Pro 13-inch (M5) | fixture `PASS`, `UI baseline comparison passed` |
| `wolkaraforever/tools/test_wow_launcher_ui.sh` (`SIMULATOR=iphone`, baseline `check`) | iPhone Duo | fixture `PASS`, `UI baseline comparison passed` |
| `wolkaraforever/tools/test_addon_hub_live.sh` (`SIMULATOR=ipad`, no API key) | iPad Pro 13-inch (M5) | `ADDON HUB LIVE PASS: 42 passed, 0 failed, 3 not run` (the API steps need `WK_LIVE_API_KEY`; this simulator's WebKit rendered no page at all, a plain control page included) |
| `python3 wolkaraforever/tools/check_localization.py` | — | 841 keys; parity, conversions and usage OK |
| `wolkaraforever/tools/check_docs.sh` | — | OK - 48 markdown files, every relative link, image and anchor resolves; agent catalogue current |
| `wolkaraforever/tools/check_layers.sh` | — | `check_layers: OK` |
| `wolkaraforever/tools/install.sh --build-only` | device target (the iPad untouched) | built and signed; "the iPad is not available: building for the generic iOS destination", "private trust store verified before device install", "the device was left alone" |
| `wolkaraforever/tools/pilot.sh install` | iPad Pro 12.9-inch (5th generation), "Dadpad", iPadOS 27.2.1, Developer service | built, installed over the same bundle ID, post-install step taken, launcher left running |
| `wolkaraforever/tools/pilot.sh selftest addons-page` | the installed build on that iPad | `selftest: addons-page PASS 61/61 checks` — before the title fix the same command produced `SIGSEGV` in `-[UIViewController setTitle:]` (reports `Tolkara-2026-11-23-132540`, `-134705`, `-140518`, `-141907`); before the lock fix it reported 43/50 with six store mutations refused; before the provider-tab and menu checks it was 49. After all of it, no crash report and a verdict |
| `wolkaraforever/tools/pilot.sh selftest addons-provider` | the installed build on that iPad, using the CurseForge key the app already holds | `selftest: addons-provider PASS 9/9 checks`: the key is present, Discover answers with sections, Browse answers with a first page and its total, the first result draws as its own project row with Install, installing a distributable result records a managed package with its provider identity and removing it empties the temporary store, and the key is written back, removed and restored exactly. Everything happens in a temporary AddOns directory this test owns; the user's game is untouched and the key is never logged or copied |
| `wolkaraforever/tools/pilot.sh state` (after) | the same iPad | `app running: 1`, `update writing: 0 file(s)`, `error files: 0`, newest crash report predating the fix: the normal home screen with the launcher running |
| Device Hub (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`), **Dadpad → View Screen**, then **Controls → Screenshot** | the same iPad | a 2732 × 2048 capture of the **installed build** on its normal home screen, launcher running, 2026-11-23 20:12 (kept in the ignored `logs/device-hub/`, never committed) |

**Device Hub, and the tap path.** Apple's *Interacting with your app in Device Hub* is explicit: in the
canvas, "Tap | Click", and for physical devices "you can interact with the view in Device Hub and
the physical device simultaneously". That was measured here too: pointer and keyboard events from
this session do reach applications (Device Hub's search field took typed text and filtered the
device list; a click opened the system menu; a click changed the sidebar selection). The first
taps at the mirrored launcher missed because the click points were derived from a window origin
measured before the window moved — a coordinate error, not a Device Hub limitation, and the
earlier note in this register that said otherwise was wrong and is withdrawn.

The walk itself could not be finished: after the sidebar selection was switched to a simulator,
**the iPad left Device Hub's device list** (restarting Device Hub showed `Available: iPad Pro
13-inch (M5)` and `Unavailable: DevWatch, Gemma's iPhone, DadPhone` — no Dadpad), while
`pilot.sh state` still reported the app running and the device reachable through the project's own
tools. Restoring it needs the tablet in hand (a wireless re-pair), which is not something this
session can do without touching the device layer outside the project's tools.

**One Device Hub tap did land, and it proves the path.** On 2026-11-24 the iPad was listed again;
a single click on the launcher's *Install Addons (Curse & Direct)* row — mapped from the 2732 ×
2048 device capture through the measured mirror rectangle — opened **ADD-ON MANAGER** on the
tablet, shown live in Device Hub: title and Done, the My Add-ons / Discover / Browse tabs, the
search field, Sort add-ons / Filter add-ons / Groups / Update All, `27 add-ons installed`, and the
Installed list with per-row states (Up to date, Update, Update available) and selection boxes.
That capture is `logs/device-hub/addon-manager-opened-20261124.png` (ignored, not committed).

The walk stopped there for a reason that is not technical: the Mac was in use, and the next click
went to the frontmost application that had taken focus since the capture. Nothing was typed or
sent, and clicking stopped at once; pointer automation against a machine somebody else is driving
is not pursued further. The remaining rows are one click each whenever the desktop is free.

So the live-device evidence in this register is: the Device Hub capture above, and the installed
build's own self-test (61 checks). The per-row tap walk resumes from the moment Device Hub lists
the iPad again — one click per row, and the same recording format.

**Live-iPad evidence, measured 2026-11-23.** The physical iPad (iPad Pro 12.9-inch, 5th
generation, "Dadpad", iPadOS 27.2.1, execution mode Developer service from the stored choice,
reachable over the network) was free, so the build was installed and the app's own self-test was
run against it: `selftest: addons-page PASS 61/61 checks`. Layer tree `aeaf6df` + this change,
prepared platform `00a8501`. Sanitized fixture state: no game installed (`state=3`), app language
English, and the self-test's own temporary `Interface/AddOns` (one recorded package, one folder it
did not record, one format-2 manifest it must migrate) removed again by the self-test before it
reported. No provider key was read, written or logged: the run asks the page for its Browse row
in the state the device is actually in, rather than driving a query with a saved credential. The
device was left on its normal home screen with the launcher running and no crash report after the
fix (`pilot.sh state`: `app running: 1`, `update writing: 0`, `error files: 0`).

That run found and closed two defects the simulator could not: the page crashed the installed app
at `-[UIViewController setTitle:]`, and the store refused every mutation because the update lock
rejected any path whose ancestor resolved through a symlink (see the remediation log). The rest of
the register is still walked by hand on the launcher as it ships — the fixture's taps are the
fixture's — and each row's live observation records the same SHA, iPadOS, mode and fixture state
as this paragraph.
