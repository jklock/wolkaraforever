# UI catalog

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: `wolkaraforever/WoW/tests/test_wow_launcher_app.m` and `wolkaraforever/tools/capture_ui_guide.sh`

The map from every user-facing control in [What every control does](../UI_REFERENCE.md) to the
code that builds it, the strings that label it, the state it reads or writes, the test that covers
it, and the picture of it. When a control changes, the reference page, this table and the fixture
change together.

- **Launcher page:** `wolkaraforever/WoW/WoWViewController.m` (overlaid as `launcher/WoW/`).
- **Strings:** `wolkaraforever/Shell/en.lproj/Localizable.strings` (and `de`, `fr`), read through
  `WKLocalized`/`WKLocalizedFormat`. The in-game side reads the same tables through `AKHostLocalized`.
- **Tests:** `wolkaraforever/WoW/tests/test_wow_launcher_app.m` is the launcher fixture. It presses
  every control and asserts its label, identifier, enabled state and order; `check_ui_policy.sh`
  compares its reviewed pictures. `wolkaraforever/tools/check_localization.py` proves every table
  value exists and reports the keys nothing asks for (as `TODO`, not as a failure).
- **Pictures:** `wolkaraforever/tools/capture_ui_guide.sh` runs the same fixture with
  `--guide-captures` and writes `docs/screenshots/ui-*.jpg`. The capture walk asserts nothing and is
  not part of the gate.

## Rules a new control must satisfy

1. A label from the strings tables, never a literal (`LOCALIZATION_AND_ACCESSIBILITY.md`).
2. An `accessibilityIdentifier` of the form `wow.<card>.<thing>`, so the fixture can find it by name
   rather than by position.
3. The page's own enabled rule in `-render` — a row that looks usable must be usable.
4. A press in the fixture's chain, an entry on this page, and a row in
   [What every control does](../UI_REFERENCE.md).
5. If it opens a sheet, a `--guide-captures` step for that sheet, so the guide cannot silently
   show the page underneath.

## Home page

Built in `-viewDidLoad` (rows, cards), `-localize` (all labels), `-render` (state, titles, enabled).

| Control (identifier) | Label key(s) | Handler | Reads / writes | Test | Picture |
| --- | --- | --- | --- | --- | --- |
| Check for updates (`wow.refresh`, left bar item, `arrow.clockwise`) | `home.refresh` | `-refresh` → `-checkForUpdatesAndLaunch:` | the current edition's check | fixture presses it | `ui-home` |
| Settings (`wow.settings`, right bar item, `gearshape`) | `home.settings` | `-settings` → `-settingsSheet` | — | fixture taps it for every Settings row | `ui-settings`, `ui-settings-failed` |
| Game Edition row (`wow.edition`) | `home.edition.row`; sheet `home.edition.title` | `-chooseEdition` → `-selectProduct:` | defaults `WoWProduct` | selects Classic Era and back | `ui-edition` |
| Region / Locale row (`wow.preferences`) | `home.preferences.row`, `.title`, `.region`, `.language`, `.downloadLanguage` | `-preferences` → `-choosePreference:` → `-setGameLocale:` | defaults `WoWRegion`, `WoWLocale`; writes `WTF/Config.wtf` | picks a region and a locale | `ui-preferences` |
| App language row (`wow.language`) | `lang.row`, `lang.title`, `lang.message`, `lang.confirm.*`, `lang.gameChanged.title` | `-chooseAppLanguage` → `-applyAppLanguage:` | `WKAppLanguageDefaultsKey`; `WolkaraForeverGameLanguageOfferShown` | switches to German and back | `ui-language` |
| Battle.net Login row (`wow.browserLogin`) | `login.row`, `login.status.off/on/onSaved`; sheet `login.title`, `login.explanation`, `login.enable*`, `login.disable`, `login.savedPassword.*`, `login.clear`, `login.cleared.*` | `-browserLoginSettings`; `-enableBrowserLogin`; `-signInWithSavedPassword`; `-forgetSavedPassword`; `-clearBrowserLoginDataWithMessage:` | defaults `WoWBrowserLogin`; Keychain item and flag `WolkaraForeverBattleNetSavedPassword` | asserted by the login block in the fixture | not captured (see below) |
| Install Addons (`wow.addons.manage`) | `home.addons.install`, `.needsgame`; `home.addons.unavailable.*` | `-manageAddons` | — | fixture opens the page from it | `ui-addons-myaddons` |
| Install Recommended Add-ons (`wow.addons.macEver`) | `home.addons.recommended.wolkaraRoue` | `-openRecommendedAddons` | — | fixture asserts it exists and is **hidden** | `wow-addons-recommended-wolkararoue` |
| Open Add-on Directory (`wow.addons.directory`) | `home.addons.directory`, `.needsgame` | `-openAddonDirectory` | creates `Interface/AddOns` if missing | fixture presses it | `ui-home` |
| Backup Add-ons (`wow.addons.backup`) | `home.addons.backup`, `.needsgame`, `.done.*`, `.failed.*`; `addons.backup.noComponent` | `-backupAddons` | writes `WTF/Backups/<zip>` | fixture presses it | `ui-home` |
| Restore Add-ons (`wow.addons.restore`) | `home.addons.restore*`, `.confirm.*`, `.restore.action`, `.done.*`, `.failed.*`, `.none.*` | `-restoreAddons` → `-confirmAddonRestoreNamed:` → `-performAddonRestoreNamed:` | replaces `Interface/AddOns` | fixture presses it | `ui-home` |
| Toggle Permissions (`wow.permissions`) | `home.permissions` | `-openPermissions` | opens the app's own Settings page | fixture presses it | — |
| Key / Controller Button Configuration (`wow.voice`) | `home.voice.keys` | `-manageVoice` | — | fixture opens the page | `ui-voice-page` |
| Test Voice & Dictation (`wow.voice.test`) | `home.voice.test` | `-testVoice` → `AKVoiceTestViewController` | — | fixture opens it and the voice suite drives the page | `voice-test` |
| Controller Touchpad Configuration (`wow.touchpad`) | `home.touchpad.configuration` | `-configureTouchpad` | — | fixture opens the page | `ui-touchpad-page` |
| Device profile (`wow.performance.deviceProfile`) | `home.performance.deviceProfile`, `home.profile.*` | `-chooseDeviceProfile` | defaults `WolkaraForeverDeviceProfile`, derived `…RenderProfile`, `…BackingScale` | fixture walks automatic, preview and back | `ui-device-profile` |
| Render profile (`wow.performance.renderProfile`) | `home.performance.renderProfile`, `home.render.*` | `-chooseRenderProfile` → `-applyRenderQuality:` | the render scale the launcher passes to the guest | fixture chooses each and the over-recommendation confirmation | `ui-render-profile` |
| Battery Saver Mode (`wow.performance.batterySaverMode`) + Battery Saver Options (`wow.performance.batterySaver`) | `home.performance.batterySaverMode`, `home.performance.batterySaverOptions`, `home.batterySaver.*`, `batterySaver.selected` | `-batterySaverModeChanged:`, `-openBatterySaverOptions` → `AKBatterySaverOptionsViewController` (`-limitChosen:`, `-afkChosen:`) | `…BatterySaverEnabledV1`, `…FrameLimitV1`, `…AFKMinutesV1`, and the three launch snapshot copies; off installs no presentation hook | `test_battery_saver.sh`, the fixture's switch-and-page block | `ui-battery-saver` |
| Gamepad UI (`wow.performance.gamepad`) | `home.performance.gamepad`, `home.gamepad.*` | `-gamepadChanged:` | `WolkaraForeverGamepadUI` in defaults; `GamePadEnable` in `WTF/Config.wtf`, re-written in `-beginStartup`; the client's own GamePad camera settings are untouched | fixture asserts the stored choice, one assignment, and the client's settings byte-identical | `ui-home` |
| Backup WoW UI Configuration (`wow.performance.backup`) | `home.performance.backup`, `home.backup.*` | `-backupUI` | `WTF/Backups/<zip>` | fixture presses it | `ui-home` |
| Restore WoW UI Configuration (`wow.performance.restore`) | `home.performance.restore`, `home.restore.*` | `-restoreUI` → `-restoreBackupNamed:` | `WTF` and `Interface` | fixture walks the flow | `ui-home` |
| Reset to Default Wow UI Configuration (`wow.performance.reset`) | `home.performance.reset`, `home.reset.*` | `-resetGraphics` → `-performGraphicsReset:` | removes only `gx*`/`graphics*` CVars, after a backup | `test_forever_ui.sh`, fixture confirms the reset | `ui-home` |
| Open Settings Folder (`wow.performance.settingsFolder`) | `home.performance.settingsFolder`, `home.settingsFolder.unavailable.*` | `-openSettingsFolder` | opens `WTF` | fixture presses it | `ui-home` |
| Interface Mode (`wow.launcher.interfaceMode`) | `home.launcher.interfaceMode.*` | `-chooseInterfaceMode` → `-applyInterfaceModeNamed:` | defaults `WolkaraForeverInterfaceModeV1` | fixture chooses each value | `ui-interface-mode` |
| Create Controller Layout (`wow.launcher.layoutCreate`) | `home.launcher.layout.create*`, `.template.*`, `.save*` | `-createInterfaceSetup` → `-saveInterfaceSetup` | saved layouts | fixture creates one | `ui-layout-create` |
| Edit Controller Layout (`wow.launcher.interfaceSetup`) | `home.launcher.interfaceSetup.*` | `-chooseInterfaceSetup` | layout in use | fixture opens it | `ui-layout-editor` |
| Restore Controller Layout (`wow.launcher.layoutRestore`) | `home.launcher.layout.restore*`, `.restoreFile`, `.delete`, `.importFailed.*`, `.importDone.*` | `-restoreInterfaceSetup`, `-importInterfaceSetup`, `-applyInterfaceSetupFromURL:`, `-deleteInterfaceSetup` | saved layouts, imported JSON | fixture restores | `ui-home` |
| Backup Controller Layout (`wow.launcher.layoutBackup`) | `home.launcher.layout.backup`, `.backupFailed.*` | `-backupInterfaceSetup` | share sheet | fixture presses it | `ui-home` |
| Primary button (`wow.primary`) | `home.action.*` | `-primaryAction` | the install/update/repair/launch state machine | every fixture phase assertion | `ui-home`, `wow-starting`, `wow-running`, `wow-startup-failed`, `wow-downloading` |
| Status, detail, progress, version (`wow.status`, `wow.detail`, `wow.progress`, `wow.version`) | `home.status.*`, `home.phase.*`, `home.download.remaining`, `home.version.*` | `-render` | installation state | same | as above |
| Diagnostics and logs (`wow.diagnostics`) | `home.diagnostics` | `-diagnostics` | — | fixture asserts it appears only after a failure | `wow-startup-failed` |

## Settings sheet

Built by `-settingsSheet`; each row is a `UIAlertAction`.

| Action | Label key(s) | Handler | Reads / writes | Test |
| --- | --- | --- | --- | --- |
| Verify and repair game files | `home.settings.repair` | `-repairInstallation` | `WoWRepairRequested.<product>` | fixture asserts the row set and order |
| Diagnostics and logs | `home.settings.diagnostics` | `-diagnostics` | — | fixture runs the block |
| Arm / Disarm network health for next launch | `home.settings.networkHealthOn/Off`, `.title`, `.message` | inline handler | `WolkaraForever.NetworkHealth.NextLaunch` | `test_network_health.sh` |
| Turn on / off input diagnostics | `home.settings.inputDiagnosticsOn/Off` | inline handler | `WolkaraForeverInputDiagnostics` | fixture's controller block |
| About and open-source licenses | `home.settings.about` | `-about` | bundle documents | fixture opens the page |
| Technical details | `home.settings.technical`, `home.settings.details.title` | inline handler | `_startupFailure`, `_error`, `_installation.error` | fixture asserts it is absent without a failure |

## Pages the launcher pushes

| Page | Built in | Test | Picture |
| --- | --- | --- | --- |
| About | `-about` (`home.about.title`, `about.intro`, `about.document.*`, `about.documentMissing`) | fixture asserts the four documents and a missing one | `ui-about` |
| Key / Controller Button Configuration | `wolkaraforever/Voice/VoiceViewController.m` (`voice.*`) | `test_voice.sh`, fixture | `ui-voice-page` |
| Test Voice | `VoiceTestViewController.m` (`voice.test.*`, `voice.state.*`) | `test_voice.sh`, fixture | `wow-voice-test-de` |
| Controller Touchpad Configuration | `Voice/ControllerTouchpadViewController.m` (`touchpad.*`) | `test_controller_input.sh`, `test_voice.sh` | `ui-touchpad-page` |
| Add-On Manager | `wolkaraforever/WoW/AddonManager.m` (`addons.*`) | `test_addon_archive.sh`, `test_curseforge.sh`, `test_addon_hub_live.sh` | `ui-addons-myaddons`, `addon-hub-discover`, `addon-hub-browse` |
| Diagnostics | `platform/launcher/App/DiagnosticsViewController.m` with rows from `wolkaraforever/Shell/main.m` (`diag.*`) | `test_external_jit_diagnostics.sh` | none — the page is not drawn by the launcher fixture |

## In-game surfaces

Drawn into the game's own window by the adapters, so the launcher fixture cannot capture them.

| Surface | Built in | Strings | Test |
| --- | --- | --- | --- |
| Toolbar (keyboard, trackpad, gamepad, gear, house, handle) | `wolkaraforever/Touch/TouchControls.m` | `touch.keyboard.*`, `touch.trackpad.*`, `touch.gamepad.*`, `touch.settings`, `touch.leave.*`, `touch.toolbar.*` | `test_touch_controls_ui.sh` |
| Touch controls overlay | `wolkaraforever/Touch/TouchGamepad.m` | `touch.settings.*` | `test_touch_gamepad_ui.sh` |
| Performance overlay | `wolkaraforever/Touch/AKPerformanceOverlay.m` | `overlay.*` | `test_touch_gamepad_ui.sh` |
| Keyboard accessory row and saved-password key | `Touch/TouchControls.m`, `Touch/KeyboardDictationEvents.h` | `touch.key.*`, `login.savedPassword.*` | `test_touch_controls_ui.sh` |
| AFK dim layer | `Touch/BatterySaverIdle.m` | — (a view, no text) | `test_battery_saver_idle_app.m` |

## Not captured, and why

- **Battle.net Login sheet.** Its rows are asserted by text in the fixture, but the sheet is only
  offered on the Forever edition with a ready installation, and a picture would put the words of an
  experimental authentication path in the user guide without the risk notice around it. The reference
  page describes it and points at the risk text in the app.
- **Toggle Permissions.** It opens another app's (the system's) page; there is nothing of ours to
  photograph.
- **In-game surfaces.** They exist only while a game is running. `wolkaraforever/tools/pilot.sh view`
  is how one is captured from a real session.

## Known gaps in the shipped UI

Recorded here so nobody documents them as features:

- `wolkaraforever/Voice/VoiceViewController.m` never shows `voice.takeButton` ("Keep the game from
  seeing it"); the key exists in the tables only.
- The Settings-sheet touchpad keys (`home.settings.touchpadPointerOn/Off`, `…touchpadSpeed*`) are
  unused; the touchpad controls live on their own page.
- `addons.action.check` is unused; installed rows pair **Not checked yet** with **Update**.
- The library screen and the Diagnostics page chrome are hard-coded English
  (`platform/launcher/App/LibraryViewController.m`, `DiagnosticsViewController.m`). They are the
  engine's screens, not this layer's; the rows this layer contributes to Diagnostics are localized.
