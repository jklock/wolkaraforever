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

- **A finished download no longer ends at "Startup unavailable".** A build made in
  Xcode has no `TOLKARA_MODE`, and the launcher resolved its execution mode
  without the route the build was compiled with: the log said `execution mode=none
  source=none`, and the completed installation correctly showed a disabled
  "Startup unavailable" button with nothing in the public home to change it.
  Reported on an iPhone Duo running a build made in Xcode. The launcher now
  resolves the way the platform does - an explicit `--execution-mode`, then the
  saved choice, then the build's `TOLKARA_MODE` - and only then falls back to the
  route the build includes: Developer service in Tolkara, External JIT in
  TolkaraDiagnostics. An unusable `--execution-mode` or `TOLKARA_MODE` still keeps
  its own diagnostic rather than being replaced by the fallback.

- **The Launcher Manager, and the interface it drives.** A sixth card now sits beside UI
  Manager (and after it on a phone): `wow.launcher.interfaceMode`, with exactly two choices,
  `iPadOS` and `iOS on Duo`, remembered across launches. Choosing a mode writes that one key
  and nothing else - it never installs, disables, removes or updates an add-on. The
  recommendation row keeps its identifier and its explicit, never-silent install: on iPadOS it
  reads `Install Recommended Add-ons (Mac-Ever)` and opens the Add-On Manager filtered to
  CurseForge project 1733200, with the existing Core API key and Install flow; on iOS on Duo
  it reads `Install Recommended Add-ons (WolkaraRoue)` and opens the bundled package, its
  release and SHA-256, and its own Install action. The bundled package is verified against its
  manifest - including the release inside the archive's own TOC - before it is offered, and a
  malformed, missing or unexpected archive is refused with nothing extracted. Every other
  card keeps its position, width and behaviour; the amendment is recorded in
  [the UI policy](development/architecture/UI_POLICY.md) and
  [the baseline](development/architecture/LAUNCHER_UI_BASELINE.md).

- **French, for the app and for the game.** The app's own labels now come in French as well
  as English and German: a complete `fr.lproj` (548 keys, every one of them answered), the
  language in the settings row and the picker, and `fr` in an exported settings file, so a
  French choice survives export and import instead of being refused. World of Warcraft's own
  download language offers French between English and Spanish, in the app's language, and a
  first choice now starts from the language the installed game is already in - a copy pushed
  from a Mac keeps its `Config.wtf` - instead of planning an English download over a French
  installation. The one-time "put the game in the same language too" offer, which used to be
  German-only, covers French. Nothing changes for an English or German setup: the same keys
  answer the same words, and `check_localization.py` holds all three tables to the same
  rules.

- **The iPhone interface's foundation, dormant.** The mobile arrangement the phone needs -
  a toolbar folded into a handle at the bottom centre, a keyboard whose Send puts the line in
  the game's chat, sticks and jump without the other buttons, tap/hold/drag/pinch instead of
  a cursor - is now in the build and switched off. One key decides it,
  `WolkaraForeverInterfaceModeV1`, read wherever a decision depends on it; iPadOS is what a
  missing, `ipados`, or hand-edited value means, and Standard is indistinguishable from
  v1.0.7 - the same toolbar geometry, the same keyboard key, the same gamepad, the same
  multi-touch contract, and the launcher's baseline comparison passes unchanged on both
  matrix simulators. Choosing the mobile interface is the next release's job; this one only
  makes it possible.

- **The Interface mobile add-on, packaged and verifiable.** `addons/WolkaraRoue` (release
  0.9.1) ships with twelve Lua suites, and as a versioned ZIP plus manifest in the app
  bundle: the archive, its release, its interface and every file's SHA-256 are recorded, a
  fixture rebuilds both from the sources and compares them byte for byte, and the app's
  verifier refuses any package that is not that one - tampered, truncated, a stale per-file
  hash, extra or missing files, a path outside the folder, another release, a missing
  manifest, a missing archive, another add-on's manifest. Nothing installs it yet, and no
  row or card was added.

- **A function key is never text, and secure input is real.** F12's invisible U+F70F could be
  inserted ahead of whatever followed it in a focused field - a login screen's password field
  included, because the mobile keyboard sends F12 before a chat line. The reserved function
  key characters are no longer inserted, commands are unchanged, and the Apple logo still
  types (patch 0057). Carbon's secure event input, which a game turns on when a password
  field has the keyboard, is now real and reference counted instead of a generated stub, and
  announces each change so the keyboard can type exactly what was written there (0058). A
  held local-service refusal now repeats the last attempt's own report, and a launch on
  mobile data names how iOS classifies the route (0056).

- **The launcher's own fixture runs again, end to end.** `resumeCheckIfVisible` refused to
  resume an interrupted check whenever `UIApplication.applicationState` was not `Active`,
  which a simctl-launched process never reports - so the fixture's resume step aborted, and
  with it every step after it, in the v1.0.6 and v1.0.7 exact-main records too. The page now
  keeps the activation its own foreground/background notifications tell it about, and asks
  that instead: on a device the two agree, and the fixture now verifies the rest of the page,
  including the baseline comparison it had stopped reaching. Also fixes two things found
  while carrying the work: a nil toolbar handle could abort every touch on a Standard guest,
  and v1.0.7's controller-arrival guard had to be kept, not dropped.

- **A held mouse button drags continuously, and native control surfaces keep tracking.**
  Two faults combined to make a physical trackpad drag update only when the button was
  released. The input inspector installed the same `mouseMovedHandler` and per-button
  handlers the AppKit bridge owns, so an input-device refresh could leave its no-op motion
  handler in place and the game saw no movement until the next button edge; it now observes
  the profile's `valueDidChangeHandler`, which nothing else uses. And the event loop returned
  a queued guest event before it ever reached the tracking pump, so UIKit's default and
  tracking modes never ran while events were flowing; the pump now covers a held left, right
  or middle button as well as the touch-controls editor and the on-screen keyboard, and runs
  before the guest queue is scanned (patch `0047`, edited in place). The gamepad settings
  panel also stays open on a device that already has a controller: it used to close on any
  keyboard, window or application notification, not only when a controller connected. Both
  fixtures pass on the two matrix simulators, including 18 held-button cases per device.

- **The game's window is the size of the game's content, from the first frame.** AppKit
  documents that the content view "is resized to fit precisely within the content area of
  the window", and the adapter only did that once the window had a host view. A view made
  by `-[NSView init]` therefore stayed 0×0 until the window was on screen, so a guest that
  sizes its window right after `setContentView:` — which Forever 1.60.1 does, before
  showing it — read `convertSizeToBacking:{0, 0}`, clamped its window to its 320×240
  minimum, and grew the height 0.5 pt per pass for about three seconds. Its `CAMetalLayer`
  ended up 320 wide and ~4.69 million points tall, and the render target was 320 pixels
  wide. `setContentView:` now sizes the view to the content rect when there is no host
  yet; with a host, `ak_attach` still sizes it from the host's bounds (patch 0054). The
  layer's own test runs on both matrix simulators and fails against the unpatched adapter.
- **External JIT: a JIT enabler's memory is cleared before the game is placed in it.** The
  runtime assumed the region an enabler hands back is zero-filled, but StikDebug writes one
  byte, `0x69`, at the start of every page it prepares. Only the pages the game image has bytes
  for were written afterwards, so every zero-initialised page of the image began with that
  byte. Reported on an iPhone Duo outside this project's test matrix (iOS 27.2, AltStore with
  a free Apple ID, StikDebug 3.2.2): Forever 1.60.1 (70862) closed about 35 seconds after its
  window appeared, on every launch, with `ERROR #132` at address `0x71`. The image's extent is
  now cleared through the writable view before the image is placed across it (patch 0050).
- **External JIT: memory an enabler granted but never prepared is handed back.** Reported on
  the same phone: about one launch in three closed the moment the game was entered. StikDebug,
  and the StikJIT library other enablers share, write their page-preparation packets with nine
  hex digits of address, so a region at or above 2^36 is granted and reported ready while the
  writes go elsewhere. The kernel puts the region there, at `0x7000000000`, whenever nothing
  lower down has room for it, and the launch reservation asks for up to 1 GiB. Such a region
  is now given back and a smaller one asked for, and what was asked and granted is written to
  `wolkaraforever.log` under `[jit]` (patch 0051).
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
