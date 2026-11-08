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

- **A dropped connection no longer stops the game download.** One request that lost its
  connection, timed out, or briefly could not reach the CDN used to fail the whole update, so
  on an unsteady link each attempt kept about 1 GB and a full Forever install took dozens of
  retries by hand. That request is now retried up to five times, 2 to 30 seconds apart; any
  other failure, and cancellation, still stop the update as before.
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
