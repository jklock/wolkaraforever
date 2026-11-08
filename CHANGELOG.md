# Changelog

> **Documentation index current as of 2026-10-30 · branch `main`.**

This page names no source revision on purpose: it describes whatever commit you are
reading, and a pinned hash here would be stale by the next commit. Physical results are
kept as dated records under [development/validation/](development/validation/), where
they name the revision that actually ran.

This changelog records release history. It is not a compatibility guarantee: read the current
[installation guide](docs/INSTALLATION.md), [user guide](docs/USING_WOLKARAFOREVER.md), and
[compatibility boundary](COMPATIBILITY.md) for the current project state.

## Unreleased

- **iPhone Duo layout.** On an iPhone Duo (`iPhone19,4`) the touch controls and the WolkaraRoue
  add-on switch to a layout made for its screen. The app: sticks that appear under the thumb, an
  L-shaped move area and a camera area that curve around a corner skill fan, a corner Jump, auto-run
  (hold forward, slide onto the lock), a toolbar folded into a handle at the top, and a typing bar
  with Send. The add-on: a corner skill fan with a slot edit mode and three presets, a quick bar
  (5 slots, 5 pages), a chat button with a peek and a full chat in WoW's own layout, a quick menu,
  a buff row and panel, party frames, cast bars, and one Mobile UI settings window that holds
  pookee's options and the new ones. Everything Duo-specific sits behind the layout switch, which
  is on by default only on the Duo: other devices keep the existing layout, and the system Done key
  still replaces, as [the iPhone guide](docs/IPHONE.md#iphone-duo-layout) and the touch-controls
  assertion say. Health, auras, cooldowns and names that newer clients return as secret values no
  longer stop the HUD. The add-on's source strings are now English, with French, Spanish and German
  tables, and its tests read the English source text. Duo UI by scarrdi94, built on pookee's Mobile
  Interface.
- **The iPhone interface work is on `main`.** French as both an app and a game language, the
  WolkaraRoue mobile add-on (turning wheels, cooldowns, bags, minimap, windows, chat), direct
  touch as tap/hold/drag/pinch, the mobile keyboard, and the device-safe helper scripts
  (`push_addon.sh`, `forget_login.sh`). Rebased onto `main` rather than merged as it stood:
  the French table predated #11 (35 keys added, 10 that #17 removed), the keyboard's system
  Done key had been rerouted from Replace to chat — contradicting `docs/TOUCH_INPUT.md` and
  the touch-controls assertion, which now says Done replaces and the explicit Return key
  sends — and `0048` needs a two-finger pinch, so `multipleTouchEnabled` assertions that pinned
  single-touch were updated (patch 0053). `test_touch_gamepad_ui.sh` no longer depends on
  machine speed: one pump call is not guaranteed to reach a before-waiting observer.
- **A guest crash in a system library now names the function, not just the dylib.** Issue #13
  arrived as `EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x198` with frame 0 in
  `libsystem_pthread.dylib`. The client's own crash handler prints a frame outside the guest
  arena as an image name and nothing else, and layer patch 0039 had stopped writing dlsym
  resolution to the guest log, so a symbol that was not found left no trace either. The
  guest's `dladdr` now answers a system frame as `image+offset symbol=name`, and a `dlsym`
  that found nothing is logged without tracing; both are bounded to 64 lines and neither
  changes what the guest is returned. Asking `dladdr` for the same distance from
  `_pthread_start` in an iOS 27.2 runtime gives
  `libsystem_pthread.dylib+0x88 symbol=pthread_rwlock_rdlock` — the line that report was
  missing. It puts the fault in a read lock taken on a null object, not in the loader.
- **A first run no longer starts in Europe whatever the device is.** The launcher's region
  defaulted to `eu` on every device, and the first install writes that portal into the
  client's own `Config.wtf` once and never rewrites it. An account outside Europe then sat
  at "Connecting" for ever with nothing on screen saying why (issue #16, a US iPhone Duo
  player, resolved by changing the region by hand). `TKWoWDefaultRegion` now takes the
  region from the device's own locale: the US portal for the Americas and Oceania, `kr` and
  `tw` for their own regions, Europe for everywhere else and for a locale with no country.
  A region the user chose is still never replaced, and an unusable stored value still falls
  back to Europe. Covered by `test_wow_launcher_ui.sh`, which now stands a locale in for
  the device so the assertion means the same thing on any Mac.
- **Dictation interest no longer depends on the pad being connected.** The router told the
  controller inspector about the mapped button only for controllers already connected, so a mapping
  made for a pad that connected later left the inspector uninterested and the first press was
  missed. `AKTrigger +mappedElementsInDefaults:` reads every stored mapping instead, which is what
  `DEVICE_CONTRACT.md` §5 already promised. Found by `test_voice.sh` the moment the simulator
  worked again: 2 of 341 checks, now `VOICE PASS: 341 checks`.
- **Simulator device data is no longer moved onto a disk image.**
  `setup_simulators.sh` used to mount an APFS sparse bundle on `/Volumes/Storage` at
  `~/Library/Developer/CoreSimulator`. Every device booted from it hung on the Apple logo: SpringBoard
  got a PID but never registered `com.apple.springboard.services`, the screen never changed and the
  writes stopped. The same device on the boot volume reaches the home screen in seconds — measured
  2026-11-06 on both matrix simulators. The script now only ensures the two matrix simulators exist,
  refuses to run while such an image is mounted, and prints the way back; `BUILDING.md` documents
  why device data has to stay on the boot volume.
- **One test matrix: three devices, enforced by the tools.** The suites used to take whichever
  iPad or iPhone happened to be installed, and to keep trying devices until one booted. Now
  `wolkaraforever/tools/simulators.sh` names the only devices this project measures —
  **iPhone Duo** and **iPad Pro 13-inch (M5)** in the simulator, and the **iPad Pro 12.9-inch
  (5th generation)** on hardware — and every simulator suite and both platform wrappers resolve
  through it. Anything else is refused, including a `SIMULATOR=` value, so a fixture can no
  longer pass on a device nobody chose. `setup_simulators.sh` no longer resets the simulator set:
  it creates at most those two, reuses them if they exist, and deletes nothing. Its mount probe
  also stopped reading a mounted image as unmounted (`hdiutil info | grep -q` reports failure
  under `pipefail` when grep exits early and hdiutil dies of SIGPIPE), which had sent it down the
  branch that moves a live mount point aside.
- **Add-ons: install, update and select from the list.** A Browse row now has its own
  **Install** action with a stable accessibility identifier, so installing is one tap instead of a
  trip through a details sheet. The installed list has a checkbox, an inline **Update** that only
  appears when the provider really has a newer file, a **Select All / Clear / Update Selected**
  toolbar and **Update All**. Every multi-package change is confirmed first and is bounded to
  85 % of the presenting screen. Nothing here changes an unmanaged folder.
- **Add-ons: version compatibility is advice, not a gate.** A ZIP whose TOC does not declare
  Forever's interface version is imported, shown and used, and marked *not verified for Forever*;
  a project with no Forever-tagged file is offered with its newest available file instead of being
  refused. Malformed responses, unavailable files, untrusted asset hosts, failed extraction,
  duplicate folders and author-disabled API distribution are still refused.
- **Add-ons: a format-2 manifest with a journalled migration.** Records now carry a stable package
  identity, the owned folders, the archive digest, disabled/pinned state, the TOC interface numbers
  and an optional CurseForge identity (project, file, filename, version, publication date,
  compatibility). A format-1 manifest is migrated through a backup and a journal, and an
  interrupted migration is rolled back on the next launch rather than shown half-applied. A
  provider update stages the old folders, validates the new archive, swaps them and commits the
  manifest under the existing update lock; any failure restores both the folders and the revision.
  An identity is never inferred from a display name or a folder name.
- **Add-ons: the refresh control refreshes the provider.** It no longer just rereads the
  filesystem: in Browse it clears the cached categories, starts again from page zero with the
  current inputs and ignores replies from a superseded generation; in Installed it reloads the
  records and rechecks update metadata. Sort and filter names come from one typed table, so a
  visible control can no longer show a localization key or a numeric API id.
- **Input: the controller inspector is silent in normal play.** A controller callback now returns
  before it allocates an event, dispatches a block or writes a log line unless the element is
  interesting: the exact mapped element, any pressable element while the mapping learner is
  armed, or everything while input diagnostics are switched on. An interested continuous source
  is coalesced to one report per display interval. Diagnostic events go to one sink instead of
  both, and the panel's history is only maintained while the panel is on screen. This is the
  remediation for the 2026-11-04 device log, which recorded 12,658 duplicated controller-inspector
  event lines in one five-minute run with voice off. Aggregation-only counters (count, max,
  p50/p95/p99) now cover controller-callback admission, main-queue handoff and pointer
  dispatch-to-next-frame.
- **Home page: the requested cleanup.** The cards are *Game Settings Manager*, *Add-On Manager*,
  *Dictation (V2T) Manager*, *Performance Manager* and *UI Manager*; every edition reads
  `Game Edition: …` and the second row reads `Region / Locale: … …`; the passive compatibility
  note and the *Restore performance defaults* row are gone, as is the Add-ons entry that was
  hidden in the settings menu; exactly one supporting line sits below Play. Card height now comes
  from the rows rather than a flexible spacer, and two cards in a row still share a clean height
  with their controls top-aligned.
- **iPhone is a supported device alongside the iPad.** One contract now covers both form factors
  — display geometry, Dynamic Type, input, performance-profile policy and popup bounds — in
  [the supported-device contract](development/architecture/DEVICE_CONTRACT.md), and the measured
  iPhone evidence is restored in [iPhone support](docs/IPHONE.md). The iPad keeps its two-column
  page; the iPhone gets a one-column, safe-area-aware page at every width.
- **Restored historical device evidence.** Forty-six deleted documents and exact-SHA validation
  records are back under [development/archive/history/](development/archive/history/README.md),
  byte-identical, with an audited
  [restoration matrix](development/architecture/RESTORATION_MATRIX.md) naming each deletion, its
  current equivalent and the reason anything was deliberately not restored.

- A launch through the iPad Developer service that cannot be prepared now says **which
  step refused**, in the app's language, instead of reporting a dead helper: not enrolled,
  pairing identity did not verify, no usable debugger service, local service unreachable,
  or memory preparation finished without a confirmed detach. A launch on an iPad that holds
  no enrolment is stopped before the route is even started, rather than after a timeout.
  Nothing gains a fallback and no check is weakened — every path still refuses and the game
  is not started.
- Added a separate **App language** setting for everything WolkaraForever draws: English, German,
  or the iPad's preferred language. It takes effect without a relaunch and covers rows, alerts,
  menus, status and progress lines, accessibility strings, the performance overlay and the touch
  keyboard. Game language and app language stay independent, and the first German selection
  offers once — never silently — to put the game into German through the existing validated
  writer and update gate. The German launcher was checked on an iPad (iPadOS 27.0.1) at `56ddc87`;
  see [the record](development/archive/validation/56ddc87-german-app-localization.md) and
  [the localization guide](development/guides/LOCALIZATION.md).
- Rebuilt the public documentation around the current source tree.
- Moved development-only layer, profile, contribution, and adapter material under
  `development/`; `docs/` now contains user-facing material only.
- Documented the current Forever launcher feature set, including background-aware frame
  pacing, current locale behavior, add-on management, voice controls, and UI recovery.

## Historical releases

Earlier release claims and dated validation evidence are retained in Git history and in
[`development/validation/`](development/validation/). They apply only to the revisions,
devices, and game builds they name.
