# Changelog

> Verified: 2026-11-21 · Source: `8375cbb`

## Unreleased

- **Performance.** Controller sticks and d-pads no longer format an element id and a detail
  string for every raw sample when nothing is interested in them, stick values are reported in
  half-unit steps again, and the diagnostic panel updates once per batch instead of once per
  event. A pass that had 13,304 startup-initializer lines and 3,184 one-line-per-bitmap traces
  in a single log is now quiet: both are available behind `TOLKARA_TRACE_INITIALIZERS` and
  `TOLKARA_TRACE_IMAGES`.
- **Battery Saver Mode.** The frame limit and the AFK dim now sit behind one switch. Off is full
  performance: no cap, no dim, and no presentation hook installed at all. The two choices live on
  a page of their own (**Battery Saver Options**) that opens whether the switch is on or off, and
  they are remembered either way. An installation that had already chosen either option keeps it,
  and its switch starts on. Device temperature no longer lowers the cap: only Low Power Mode does,
  and only because the user turned it on.
- **Battery-saving sound** is always on and is no longer a setting; it is a performance fix, not
  a battery preference.
- **Gamepad UI** now keeps its state in the launcher and writes `GamePadEnable` again immediately
  before every start, so an in-game rewrite of `Config.wtf` cannot lose it; the game's own gamepad
  camera settings are left exactly as it wrote them.
- **Test Voice & Dictation** is back at the end of the Input Manager card.
- **Every control has a picture and two pages.** [What every control
  does](docs/UI_REFERENCE.md) lists every row, switch, button and sheet with what it does and how to
  use it, and every launcher page and sheet now has a picture drawn by the project's own fixture
  (`wolkaraforever/tools/capture_ui_guide.sh`, `docs/screenshots/ui-*.jpg`). The build-and-test side
  of each control — its code, strings, stored keys and tests — is the contributor UI catalog. The
  fixture's capture walk is a separate mode and is not a gate; the reviewed baselines are unchanged.
- **Sideloading is documented for the person holding the iPad.** [Install the unsigned External JIT
  app](docs/SIDELOADING.md) says what the package can and cannot do, how it is signed, the JIT
  enabler each launch needs, how a game is added, and what each failure means.
- **The app logs the choices it used to take silently**: arming or disarming network health, turning
  input diagnostics on or off, choosing a device profile, and the controller-touchpad pointer and its
  speed. [Send us a log](docs/SENDING_LOGS.md) now lists what each log topic means.
- **Two suites that were not really running now are.** The voice suite failed to link the Battery
  Saver symbols its input router uses and had been reporting a linker error instead of running; it
  now compiles the policy and passes 421 checks. The network-health suite printed nothing on success,
  so a silent exit 0 looked like a suite that never ran; it now prints its check count and verdict
  like the others.
- **Battery Saver.** **Performance Manager → Battery Saver** offers two choices, both applied by
  the next game start and never to a running session. **Frame limit** is **Off** by default;
  **Automatic** is 60 frames per second on power and 30 on battery, and **30 FPS** and **60 FPS**
  are fixed. iPadOS's Low Power Mode, or a device running hot, lowers any cap to 30. **AFK saver**
  is **Off** by default; after the chosen time without input — 2, 5 or 10 minutes — the screen
  dims and the game is held at 10 FPS, and the first touch, key, mouse action or controller
  action only wakes it. Neither setting writes a game CVar or any other game file. The launcher
  also stops offering the in-game performance overlay switch; the overlay is opened from the
  in-game settings page while a game runs.
- **The experimental Battle.net login can keep one game password.** With that opt-in feature on, a
  yellow key on the keyboard's row appears while the game's password field has the keyboard: it
  types a password you chose to save on the device, behind Face ID or the device passcode, and
  holding it forgets it. The password is a Keychain item on this device only - never synchronised,
  never logged, never written into the game's files - and it is deleted when the feature is turned
  off or **Clear sign-in data** is used. **Sign in with the saved password** starts the game
  without opening the browser. The key is part of that feature, so it does not exist anywhere else,
  and its row now stays inside the safe area instead of running under a phone's camera cut-out.
- **The unsigned `.ipa` can log in.** It was built without this Mac's public root certificates, so
  the client could not validate Battle.net's certificate and answered `BLZ51900003` on every
  attempt, with the experimental Battle.net login on and off. A package this toolchain builds now
  carries the same certificates as a build from your own Mac, and `verify_ipa.sh` refuses one that
  does not.
- **The published package is named after the app.** The release workflow, the verification report
  and `package_altstore_ipa.sh` call it `wolkaraforever-unsigned.ipa`. `package_ipa.sh` on its own
  still writes `Tolkara-unsigned.ipa` in the repository root, because that is the engine
  packager's own default name and the app inside is still `TolkaraDiagnostics.app`.
- **Network health, on request.** **Settings** (the home screen's gear) can arm anonymous TCP
  health counters for the next game launch, which records for at most 15 minutes and disarms
  itself. It records no addresses, ports, names, payloads, credentials or game data.
- **An add-on folder with several manifests is read correctly.** The manager uses the manifest
  named for Forever, or one that declares Forever's interface, for a package's title and version,
  and still considers every manifest when it reports compatibility.
- **The game's sound survives an interruption.** If a phone call interrupts Forever, returning to
  the game restores its active audio session when iPadOS says playback may resume.
- **Touch-controls settings switches stay whole and inside their panel** on every layout.
- **Developer service starts faster**, with the same zero-verified reservation before the first
  guest page is written.
- **The repository gates.** `package_ipa.sh` now resolves its default and relative output at the
  repository root, which is the path the release workflow uploads. CI runs the layer,
  documentation and localization gates and nothing that needs a simulator or a device.
- **An add-on whose manifest is a large database installs whole.** The manager reads only the
  head of each `.toc`, so a folder such as QuestieDB, whose manifest is an 18 MB baked database,
  is no longer skipped as "not an add-on" when its package is imported or updated.

## v1.0.21 — 2026-11-19

- **Push-to-talk works on iOS again.** Dictation's hold-to-talk activation was rewritten to the
  form iOS accepts, so holding the mapped button starts capture and releasing it ends capture.

## v1.0.20 — 2026-11-19

- **Experimental Battle.net Login.** An opt-in compatibility path in **Game Settings Manager**: it
  opens Battle.net's official sign-in page and hands the one successful result to the next Forever
  launch. Off by default, acknowledged before it can be turned on, and it can stop working without
  notice.
- **Controller touchpad handoff.** The controller touchpad and a physical mouse or trackpad hand
  off when the controller contact ends, and iPadOS's duplicate mouse stream for the controller
  surface is ignored while that contact or click is active.
- **Typing a password on an iPhone.** The Chat Composer stands aside while a password field has
  the keyboard, and Send recovers after Cancel.
- **The game's sound without iOS's audio device layer.** The game's sound is answered from a
  model of the output device, so a Bluetooth part that kept a quarter of a processor core busy is
  no longer loaded into the game. **Battery-saving sound** is the switch, on by default.
- **A dropped connection no longer stalls the game download.** The retry wait now always has a
  real scheduler, so it cannot spin while holding the download lock and block transfers or Cancel.
- **The iPad Pro 11-inch (M5) has its own device profile.** It was not in the table, so it got the
  fallback: Performance only (908 × 626). Its measured record (`iPad17,1`) also offers Balanced
  (1210 × 834) and **Quality at the panel's own 2420 × 1668**, which asks first. The default stays
  Performance, so nothing changes until Quality is picked.
- **The render-profile confirmation says what a choice costs, on every device.** It now says what
  Quality or Balanced draws and that it takes more graphics work, then adds a measured sentence
  only where that device's record has one (the 12.9-inch M1 keeps its missed budget; the 11-inch
  M5 says about 2.5 times the graphics work of Performance). In en, de and fr.
- Reviewed launcher baselines for the pages the touchpad change draws, and every pull-request
  contributor acknowledged in [Contributors](CONTRIBUTORS.md).

## v1.0.19

- **Controller touchpad as mouse.** In **Input Manager**, configure and test an opt-in DualSense or DualShock touchpad pointer with saved speed, live coordinates, one-finger movement, two-finger scrolling, and physical-click buttons. DualSense and DualShock use iPadOS's controller profile touchpad path; DualSense Edge users whose Bluetooth connection omits touch reports can use USB-C.
- **Input Manager organization.** Dictation is now under **Key / Controller Button Configuration**, and controller-touchpad setup has its own **Controller Touchpad Configuration** page.
- **UI Manager cleanup.** Gamepad UI is first, retains its selected state while saving, Backup appears before Restore, and the reset action is named **Reset to Default Wow UI Configuration**.
- **Add-on access controls.** CurseForge key controls moved to the top-bar menu and correctly save edited keys.
- **Operational documentation.** Added a plain-language guide for sending logs and audited the build/run surface.

## v1.0.18

- Documentation now separates standalone user guidance from the agent-only operational catalog.
- **My Add-ons no longer sits on "Updating…".** "Never asked" is its own state, **Not checked yet**, with a **Check** action that runs the check; *Checking…* appears only while a request is genuinely in flight, and a sweep with no key clears its own in-flight marks and says why. Opening **My Add-ons**, and **Refresh**, still ask the provider about every linked package.
- **Update All settles.** The batch used to advance before each archive write committed and re-asked the packages it had just reported, so every row returned to **Not checked yet**. It now finishes on the archive transaction, keeps the settled answer, and ends with every row up to date.
- **Installed rows carry their CurseForge thumbnail.** The project's artwork is kept with the package's provider identity, and the whole page is filled in one provider query rather than one request per row; a package with no recorded identity keeps the neutral placeholder.
- **A first run without a provider key has a door.** Browse and Discover each offer **Set up CurseForge access**, which opens the key sheet; with a key the Sort and Filter rows open the sheets they name.
- **Backup Add-ons and Restore Add-ons**: the whole add-on folder as one ZIP under `WTF/Backups/`, restorable transactionally, and neither row reaches the network.
- **The four Controller Layout decisions are four rows**: create, edit, restore and back up, the last through the system share sheet.
- **The in-app add-on browser no longer opens during a transition**, which removes UIKit's unbalanced begin/end appearance transitions.
- A disabled Voice page stays readable while its controls remain off.

## v1.0.16

- Added a native Add-on Hub.
- Added explicit dictation-language controls.
- Added touch-controller and bounded controller-command improvements.
- Added review-then-send Chat Composer behavior.
- Improved enrollment, stale-log, and reliability handling.

## Earlier releases

Earlier releases established the Forever launcher, interface modes, localization, add-on handling, UI recovery, voice, diagnostics, and source-built installation. Use the current guides for supported behavior rather than historical release notes.
