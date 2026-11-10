# Validation: bd0ed91

- Commit: `bd0ed91a8a40b7fd8db10f44f18a31f2bd4bc7b3` (branch `HEAD`)
- Recorded: 2026-11-10 14:29:15Z
- Working tree: clean
- Host: macOS 26.7.1 (arm64)
- Xcode: Xcode 27.2

## Results

| Step | Result |
| --- | --- |
| layer gate (check_layers.sh) | PASS |
| immutable launcher UI policy and matrix baselines | PASS |
| validation distinguishes known failures from incomplete suites | PASS |
| install does the right thing per execution mode | PASS |
| pilot.sh fails closed and keeps its own session | PASS |
| launcher pages (simulator fixture) | PASS |
| input, voice and config rules (simulator fixture) | PASS |
| app language resolution, tables and formatting | PASS |
| on-screen controls and the game text field (simulator fixture) | PASS |
| the on-screen gamepad (simulator fixture) | PASS |
| local service retry (patch 0006) | PASS |
| developer-service handoff (synthetic peer) | PASS |
| CurseForge response and request contracts | PASS |
| real ZIP extraction (Swift and pinned ZIPFoundation) | PASS |
| the app icon's assets and catalog | PASS |
| game file verification and repair (CASC) | PASS |
| config, gamepad and UI backup/restore | PASS |
| signed device app build | NOT RUN (DEVELOPMENT_TEAM unset) |
| platform emulation suite | PASS |
| translation adapters (simulator) | PASS |
| device run (--device) | NOT RUN |

## What each step printed

### layer gate (check_layers.sh) - PASS

```
Command: wolkaraforever/tools/check_layers.sh
PASS platform/ is byte-identical to upstream/main (00a8501, 1e8d13f1fe089fa32cd84a6b46fe3692e288aeac)
PASS no WolkaraForever strings under platform/
PASS 48 patch(es) apply cleanly
PASS every layer file is carried by the overlay
PASS every overlayed file exists in the layer
PASS wolkaraforever/overlay.map is what wolkaraforever/tools/overlay_map.sh generates
PASS prepare.sh accepts the overlay against the pinned platform
PASS every replacement is a change of ours
PASS no cross-module reach-in from WoW into Touch
PASS no cross-module reach-in from Touch into WoW
PASS the root carries no platform path
PASS every layer file is tracked, so the overlay map sees all of them
PASS the audio session has one owner
PASS no patch and no prepared platform file mutates the audio session
PASS no game other than WoW Forever is named outside platform/ (upstream's mirror)
PASS check_localization: 541 keys
check_layers: OK
```

### immutable launcher UI policy and matrix baselines - PASS

```
Command: wolkaraforever/tools/check_ui_policy.sh --review UI-BASELINE-11082026.md
08:32:24.779 [wow] checked: state=3 error=none
08:32:25.942 [language] the user chose en
08:32:25.943 [language] home: drawing the page in en (English)
08:32:25.945 [language] home: drawing the page in de (Deutsch)
08:32:26.640 [wow] a check was asked for
08:32:26.642 [wow] checking wowf eu/enUS install=0 launch=0
08:32:26.672 [wow] checked: state=3 error=none
08:32:27.044 [language] home: drawing the page in en (English)
08:32:28.662 [wow] a check was asked for
08:32:28.664 [wow] checking wowf eu/enUS install=0 launch=0
08:32:28.691 [wow] checked: state=3 error=none
08:32:31.188 [wow] a check was asked for
08:32:31.190 [wow] checking wowf us/enUS install=0 launch=0
08:32:31.219 [wow] checked: state=3 error=none
08:32:33.723 [wow] a check was asked for
08:32:33.725 [wow] checking wowf eu/enUS install=0 launch=0
08:32:33.753 [wow] checked: state=3 error=none
08:32:34.934 [wow] a check was asked for
08:32:34.936 [wow] checking wowf eu/enUS install=0 launch=0
08:32:34.969 [wow] checked: state=3 error=none
WoW UIKit PASS: automatic check/update, offline retry, edition race, background cancellation, verified launch, inline preparation/failure/session end, no duplicate launches and bundled licenses; home page headings, rows, order, identifiers, labels, enabled states and Mac-Ever URL; backup, confirmed reset, gamepad config, folder picker and restore flow; device profile (automatic, preview and the way back), render profile with the quality a device was measured at, no game-file write from either; the app language as a setting of its own (config ownership and migration, the row, immediate German and immediate English, no raw keys, the one-time German game-language offer through the validated locale writer, and German at the largest text size); and every control on the home page pressed - the edition sheet, download preferences and its Region sub-sheet, the app language row, all three add-on rows, the add-on folder browser, the permissions row, both voice pages, all nine Performance rows and both switches, the primary button, the Diagnostics button, and both navigation items.
org.tolkara.tests.wow-launcher: 99487
UI baseline comparison passed
screenshots: /Users/klock/Library/Developer/CoreSimulator/Devices/<identifier>/data/Containers/Data/Application/<identifier>/Documents
UI policy: PASS
```

### validation distinguishes known failures from incomplete suites - PASS

```
Command: wolkaraforever/tools/tests/test_validate.sh
VALIDATION CLASSIFIER PASS: 6 checks
```

### install does the right thing per execution mode - PASS

```
Command: wolkaraforever/tools/tests/test_after_install.sh
AFTER-INSTALL PASS: 15 checks
```

### pilot.sh fails closed and keeps its own session - PASS

```
Command: wolkaraforever/tools/tests/test_pilot.sh
PILOT PASS: 54 checks
```

### launcher pages (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_wow_launcher_ui.sh
08:37:34.439 [wow] checked: state=3 error=none
08:37:35.607 [language] the user chose en
08:37:35.608 [language] home: drawing the page in en (English)
08:37:35.611 [language] home: drawing the page in de (Deutsch)
08:37:36.295 [wow] a check was asked for
08:37:36.297 [wow] checking wowf eu/enUS install=0 launch=0
08:37:36.339 [wow] checked: state=3 error=none
08:37:36.698 [language] home: drawing the page in en (English)
08:37:38.319 [wow] a check was asked for
08:37:38.321 [wow] checking wowf eu/enUS install=0 launch=0
08:37:38.349 [wow] checked: state=3 error=none
08:37:40.837 [wow] a check was asked for
08:37:40.839 [wow] checking wowf us/enUS install=0 launch=0
08:37:40.867 [wow] checked: state=3 error=none
08:37:43.356 [wow] a check was asked for
08:37:43.358 [wow] checking wowf eu/enUS install=0 launch=0
08:37:43.386 [wow] checked: state=3 error=none
08:37:44.567 [wow] a check was asked for
08:37:44.569 [wow] checking wowf eu/enUS install=0 launch=0
08:37:44.603 [wow] checked: state=3 error=none
WoW UIKit PASS: automatic check/update, offline retry, edition race, background cancellation, verified launch, inline preparation/failure/session end, no duplicate launches and bundled licenses; home page headings, rows, order, identifiers, labels, enabled states and Mac-Ever URL; backup, confirmed reset, gamepad config, folder picker and restore flow; device profile (automatic, preview and the way back), render profile with the quality a device was measured at, no game-file write from either; the app language as a setting of its own (config ownership and migration, the row, immediate German and immediate English, no raw keys, the one-time German game-language offer through the validated locale writer, and German at the largest text size); and every control on the home page pressed - the edition sheet, download preferences and its Region sub-sheet, the app language row, all three add-on rows, the add-on folder browser, the permissions row, both voice pages, all nine Performance rows and both switches, the primary button, the Diagnostics button, and both navigation items.
org.tolkara.tests.wow-launcher: 6600
ok wow-home-de.png: only 5060 RGBA byte(s) of rounding within tolerance
UI baseline comparison passed
screenshots: /Users/klock/Library/Developer/CoreSimulator/Devices/<identifier>/data/Containers/Data/Application/<identifier>/Documents
```

### input, voice and config rules (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_voice.sh
08:38:14.641 [voice] AKVoiceEnabled set
08:38:14.642 [voice] AKVoiceTakeButtonFromGame set
08:38:14.958 [voice] test screen armed on Not set
08:38:15.473 [config] restored 3 choice(s) from wolkaraforever-config.json
08:38:15.488 [config] could not keep a recovery copy (“wolkaraforever-config.json” couldn’t be copied because you don’t have permission to access “Documents”.); the file is unchanged
08:38:15.493 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
08:38:15.494 [config] recovered 1 choice(s) from the previous copy
08:38:15.496 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
08:38:15.496 [config] the previous copy has already been tried once this launch
08:38:15.498 [config] 1 setting(s) were refused: AKVoiceMode (out of range)
08:38:15.498 [config] restored 1 choice(s) from wolkaraforever-config.json
08:38:15.501 [config] could not write wolkaraforever-config.json.writing (You don’t have permission to save the file “wolkaraforever-config.json.writing” in the folder “Documents”.)
08:38:15.502 [config] restored 0 choice(s) from wolkaraforever-config.json
08:38:15.505 [config] wolkaraforever-config.json was not used: it is 3145728 bytes, and a config file is not
08:38:15.506 [config] the previous copy has already been tried once this launch
08:38:15.507 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
08:38:15.507 [config] the previous copy has already been tried once this launch
08:38:15.508 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
08:38:15.508 [config] the previous copy has already been tried once this launch
08:38:15.510 [config] restored 0 choice(s) from wolkaraforever-config.json
08:38:15.512 [test] a write failure is being provoked now
08:38:15.513 [config] could not write wolkaraforever-config.json.writing (The file “wolkaraforever-config.json.writing” couldn’t be saved in the folder “Documents”.)
08:38:15.532 [config] restored 0 choice(s) from wolkaraforever-config.json
VOICE PASS: 341 checks
VOICE PASS: 341 checks
```

### app language resolution, tables and formatting - PASS

```
Command: wolkaraforever/tools/test_localization.sh
apply: applied 0028-apply-guest-backing-scale-to-window.patch
apply: applied 0029-report-selected-guest-mode.patch
apply: applied 0030-test-guest-scale-contract.patch
apply: applied 0031-cache-guest-display-mode.patch
apply: applied 0032-avoid-shader-cache-hit-copy.patch
apply: applied 0033-install-metal-diagnostics-only-when-requested.patch
apply: applied 0034-metal-anomaly-timeline.patch
apply: applied 0035-hud-frame-path-without-diagnostic-logging.patch
apply: applied 0036-forever-release-profile.patch
apply: applied 0037-gate-recurring-diagnostics.patch
apply: applied 0038-native-memory-fast-path.patch
apply: applied 0039-bypass-inactive-runtime-guards.patch
apply: applied 0040-test-profile-forever-folder.patch
apply: applied 0041-launch-progress-links-the-app-language.patch
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: /Volumes/Storage/Projects/wolkaraforever-postmerge-42/build/platform now carries the layer (48 patch(es), 153 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
localization PASS: 58 checks (resolution, stored values, tables, fallback, formatting, plurals, change notice)
```

### on-screen controls and the game text field (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_touch_controls_ui.sh --self-test
[ak] input suspended (draftFirstResponder=1)
[ak] input suspended (draftFirstResponder=1)
2026-11-10 08:38:44.382 TouchControlsFixture[10621:10623533] CoreText note: Client requested name ".SFCompact", it will get TimesNewRomanPSMT rather than the intended font. All system UI font access should be through proper APIs such as CTFontCreateUIFontForLanguage() or +[UIFont systemFontOfSize:].
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=44
[ak] system keyboard hidden draftFirstResponder=0
[ak] system keyboard hidden draftFirstResponder=0
[ak] the layer's own keyboard is up (iPadOS has no software keyboard to give)
[ak] the layer's keyboard asked for dictation
[ak] system keyboard shown draftFirstResponder=1 markedText=0 height=335
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=44
[ak] system keyboard hidden draftFirstResponder=0
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=342
[ak] system keyboard hidden draftFirstResponder=0
2026-11-10 08:38:44.829 TouchControlsFixture[10621:10623533] native: the announced text target answers dictation and reaches the guest
2026-11-10 08:38:44.830 TouchControlsFixture[10621:10623533] native: the toolbar carries Leave the game
[ak] keyboard event type=10
[ak] the user's keys: 1 taken (the game will not see those)
[ak] key usage=4 is the user's; the game does not see it
2026-11-10 08:38:44.892 TouchControlsFixture[10621:10623533] native: usage 0x04 is the user's; the guest's view never heard of it
[ak] keyboard event type=10
[ak] the user's keys: 0 taken (the game will not see those)
[ak] keyboard event type=10
[ak] keyboard event type=10
2026-11-10 08:38:45.996 TouchControlsFixture[10621:10623533] TOUCH_UI_SELF_TEST_PASS: whole-field replacement, empty clearing, duplicate suppression, draft editing, dictation, cancellation and fixed toolbar
org.tolkara.tests.touch-controls: 10621
```

### the on-screen gamepad (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_touch_gamepad_ui.sh --self-test
apply: applied 0034-metal-anomaly-timeline.patch
apply: applied 0035-hud-frame-path-without-diagnostic-logging.patch
apply: applied 0036-forever-release-profile.patch
apply: applied 0037-gate-recurring-diagnostics.patch
apply: applied 0038-native-memory-fast-path.patch
apply: applied 0039-bypass-inactive-runtime-guards.patch
apply: applied 0040-test-profile-forever-folder.patch
apply: applied 0041-launch-progress-links-the-app-language.patch
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: /Volumes/Storage/Projects/wolkaraforever-postmerge-42/build/platform now carries the layer (48 patch(es), 153 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
test_touch_gamepad_ui: iPad Pro 13-inch (M5) (16GB) (<identifier>)
build/touch-gamepad-fixture/TouchGamepad.app: replacing existing signature
2026-11-10 08:38:59.536 TouchGamepadFixture[11719:10626084] [TouchGamepad] Connection failed: Fixture (1)
TOUCH_TRACKING_PUMP_PASS: deferred UI and tracking timers progress; closed-panel pump remains nonblocking.
TOUCH_HAPTICS_PASS: independent stick edges, held/jitter suppression, inward rearm, cancellation and disabled feedback.
TOUCH_GAMEPAD_LIFECYCLE_PASS: physical connection closes settings and editing; physical priority, own/snapshot filtering, keyboard/focus cancellation, late replies, failure, retry and teardown.
org.tolkara.tests.touch-gamepad: 11719
```

### local service retry (patch 0006) - PASS

```
Command: wolkaraforever/tools/test_local_service_retry.sh
apply: applied 0031-cache-guest-display-mode.patch
apply: applied 0032-avoid-shader-cache-hit-copy.patch
apply: applied 0033-install-metal-diagnostics-only-when-requested.patch
apply: applied 0034-metal-anomaly-timeline.patch
apply: applied 0035-hud-frame-path-without-diagnostic-logging.patch
apply: applied 0036-forever-release-profile.patch
apply: applied 0037-gate-recurring-diagnostics.patch
apply: applied 0038-native-memory-fast-path.patch
apply: applied 0039-bypass-inactive-runtime-guards.patch
apply: applied 0040-test-profile-forever-folder.patch
apply: applied 0041-launch-progress-links-the-app-language.patch
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: /Volumes/Storage/Projects/wolkaraforever-postmerge-42/build/platform now carries the layer (48 patch(es), 153 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
PASS: local service recovery, sequential retries, terminal proof failure, deadlines, cancellation and stale callbacks
PASS: initial connection reset permits retry; reset after SYN/ACK remains terminal; no native readiness
PASS: 5 blocked states, each with its own sentence; unknown states are not classified; a missing, overlong or non-string device identifier blocks before a route starts
PASS: no enrollment ends in a bounded notEnrolled refusal, no readiness, no retry, no packets and no second attach
```

### developer-service handoff (synthetic peer) - PASS

```
Command: wolkaraforever/tools/test_authorization_handoff.sh
apply: applied 0037-gate-recurring-diagnostics.patch
apply: applied 0038-native-memory-fast-path.patch
apply: applied 0039-bypass-inactive-runtime-guards.patch
apply: applied 0040-test-profile-forever-folder.patch
apply: applied 0041-launch-progress-links-the-app-language.patch
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: /Volumes/Storage/Projects/wolkaraforever-postmerge-42/build/platform now carries the layer (48 patch(es), 153 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
Developer session: proof failure, pre-completion cancellation, TLS failure, startup deadline and late-result cleanup passed
Synthetic managed TLS/CDTunnel/TCP/RSP integration (no real attachment)
PASS Debug over managed tunnel: valid, expectedResult=true
PASS Debug over managed tunnel: wrong-challenge, expectedResult=true
PASS Debug over managed tunnel: missing-detach-reply, expectedResult=true
Synthetic managed TLS/CDTunnel/TCP/RSP integration (no real attachment)
PASS Arena service over managed tunnel: valid, expectedResult=true
PASS Arena service over managed tunnel: wrong-challenge, expectedResult=true
PASS Arena service over managed tunnel: missing-detach-reply, expectedResult=true
PASS Arena service over managed tunnel: service-expiry, expectedResult=true
```

### CurseForge response and request contracts - PASS

```
Command: wolkaraforever/tools/test_curseforge.sh
CURSEFORGE PASS: 52 checks, no network or credentials
```

### real ZIP extraction (Swift and pinned ZIPFoundation) - PASS

```
Command: wolkaraforever/tools/test_addon_archive.sh
apply: applied 0029-report-selected-guest-mode.patch
apply: applied 0030-test-guest-scale-contract.patch
apply: applied 0031-cache-guest-display-mode.patch
apply: applied 0032-avoid-shader-cache-hit-copy.patch
apply: applied 0033-install-metal-diagnostics-only-when-requested.patch
apply: applied 0034-metal-anomaly-timeline.patch
apply: applied 0035-hud-frame-path-without-diagnostic-logging.patch
apply: applied 0036-forever-release-profile.patch
apply: applied 0037-gate-recurring-diagnostics.patch
apply: applied 0038-native-memory-fast-path.patch
apply: applied 0039-bypass-inactive-runtime-guards.patch
apply: applied 0040-test-profile-forever-folder.patch
apply: applied 0041-launch-progress-links-the-app-language.patch
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: /Volumes/Storage/Projects/wolkaraforever-postmerge-42/build/platform now carries the layer (48 patch(es), 153 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
ADDON IMPORT PASS: real ZIP -> Objective-C bridge -> store -> provider identity, migration, transactional update, rollback, unmanaged folders
ADDON ARCHIVE PASS: 58 checks, production Swift and pinned ZIPFoundation
```

### the app icon's assets and catalog - PASS

```
Command: wolkaraforever/tools/test_icon_assets.sh
ok   WolkaraForever-default.png is 1024x1024
ok   WolkaraForever-default.png has no alpha channel
ok   WolkaraForever-dark.png is 1024x1024
ok   WolkaraForever-dark.png has no alpha channel
ok   WolkaraForever-tinted.png is 1024x1024
ok   WolkaraForever-tinted.png has no alpha channel
ok   the catalog names the three appearances and nothing else
ok   the catalog names WolkaraForever-dark.png, which is present
ok   the catalog names WolkaraForever-default.png, which is present
ok   the catalog names WolkaraForever-tinted.png, which is present
ok   there are exactly three PNGs in the set
ok   all three entries are the 1024x1024 universal asset
ok   dark and tinted are declared as appearances rather than separate idiom entries
ok   all three entries are universal

ICON PASS: 14 checks
```

### game file verification and repair (CASC) - PASS

```
Command: wolkaraforever/tools/test_wow_launcher.sh
WoW storage: missing=67000000000 loose=0 reserve=1073741824 available=68073741824 source=important-usage
WoW storage: missing=67000000000 loose=1 reserve=1073741824 available=68073741824 source=important-usage
WoW storage: missing=48 loose=16 reserve=1073741824 available=32223120533 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=32222502037 source=important-usage
2026-11-10 08:41:40.011 test_wow_update[17110:10639716] [wow-update] Rechecking CASC data.001 after a metadata change.
WoW storage: missing=0 loose=16 reserve=1073741824 available=32221871253 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=32221854869 source=important-usage
WoW storage: missing=59 loose=16 reserve=1073741824 available=32221846677 source=important-usage
WoW storage: missing=48 loose=16 reserve=1073741824 available=32221232277 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=32220621973 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=32220617877 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=32220601493 source=important-usage
WoW storage: missing=160 loose=16 reserve=1073741824 available=32220609685 source=important-usage
WoW updater PASS: unchanged data reuse, archive ranges, cancel before activation, durable resume, atomic activation, settings/addon preservation, superseded build and malformed input.
2026-11-10 08:41:42.049 test_wow_verification[17138:10639831] [wow-update] Rechecking CASC data.001 after a metadata change.
2026-11-10 08:41:42.071 test_wow_verification[17138:10639831] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-10 08:41:42.083 test_wow_verification[17138:10639831] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-10 08:41:42.085 test_wow_verification[17138:10639831] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-10 08:41:42.090 test_wow_verification[17138:10639831] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-10 08:41:42.091 test_wow_verification[17138:10639831] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-10 08:41:42.400 test_wow_verification[17138:10639831] [wow-update] Rechecking CASC data.000 after a metadata change.
Synthetic 16 MiB: cold read=16781056 bytes (0.0438s), warm read=0 bytes (0.0004s).
Synthetic 100k warm keys: formatted 0.9169s, binary 0.0232s; payload reads=0.
WoW verification PASS: cold payload reads=100; warm payload reads=0; clone rebinding, full keys/extents, repair, changed/deleted/truncated/symlink data, malformed records, metadata-only recovery, append corruption, 64 MiB checkpoint/resume.
DEVICE_PROFILE_PASS: 408 checks: every model resolves to its own record, an unknown device falls back to Performance, Quality is only offered where it was measured, an override is honoured and a stale one falls back to the running device, the stored names round-trip, and the settings written before this table still mean what they meant.
```

### config, gamepad and UI backup/restore - PASS

```
Command: wolkaraforever/tools/test_forever_ui.sh
apply: applied 0029-report-selected-guest-mode.patch
apply: applied 0030-test-guest-scale-contract.patch
apply: applied 0031-cache-guest-display-mode.patch
apply: applied 0032-avoid-shader-cache-hit-copy.patch
apply: applied 0033-install-metal-diagnostics-only-when-requested.patch
apply: applied 0034-metal-anomaly-timeline.patch
apply: applied 0035-hud-frame-path-without-diagnostic-logging.patch
apply: applied 0036-forever-release-profile.patch
apply: applied 0037-gate-recurring-diagnostics.patch
apply: applied 0038-native-memory-fast-path.patch
apply: applied 0039-bypass-inactive-runtime-guards.patch
apply: applied 0040-test-profile-forever-folder.patch
apply: applied 0041-launch-progress-links-the-app-language.patch
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: /Volumes/Storage/Projects/wolkaraforever-postmerge-42/build/platform now carries the layer (48 patch(es), 153 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
FOREVER_CONFIG_PASS: graphics allowlist, byte preservation, CRLF, missing config, gamepad normalisation, CVar set/replace/idempotence, refusal of unreadable names and values, performance preset and its reset, and path boundary.
FOREVER_UI_ARCHIVE_PASS: 37 checks: creation, exclusions, naming, validity, restore, retention, traversal, duplicates, editions, digests, links, special files and journal recovery.
```

### signed device app build - NOT RUN (DEVELOPMENT_TEAM unset)

```
Not run: local.env has no DEVELOPMENT_TEAM. This source/simulator validation does not claim a signed device build.
```

### platform emulation suite - PASS

```
Command: bash build/platform/tools/test_emulation.sh
known platform failures in this run: 0
[ak] bitmap 1x1 bits=8 samples=4 alpha=1 planar=0 format=0 stride=0 pixelBits=40 space=NSDeviceRGBColorSpace
[ak] bitmap 1x1 bits=8 samples=3 alpha=0 planar=0 format=0 stride=3 pixelBits=32 space=NSDeviceRGBColorSpace
colours, graphics contexts per thread, padded RGB bitmaps and NSRectFill: PASS
quartz events: location, timestamp, flags, typed fields, keyboard events and null events: PASS
software text keys, composed Unicode, text-client ABI, commands and replacement ranges: PASS
local event monitors: order, masks, consumption, removal during dispatch: PASS
synthetic invalid padding: status=-2147415994 bytes=0 cipher=32
synthetic invalid padding: status=-2147415994 bytes=0 cipher=32
synthetic invalid padding: status=-2147415994 bytes=0 cipher=32
legacy crypto: ABI and PBKDF2/AES match native macOS CSSM; malformed inputs rejected
PASS: the caller's security session has graphics access
PASS: display gamma tables are kept per program and read back; the physical display is left alone
Packaged 151 public system certificates matching native SSL policy
[security] native-trusted public roots matched=151 candidates=151
system roots: typed enumeration, native trust filtering, query isolation and rejection pass
Steam Cloud: final flush keeps main-thread callbacks responsive PASS
Steam Cloud: bounded protobuf, malformed input, first pull, zipped downloads, backups, uploads, remote changes, conflicts, a remote change during upload and symlink rejection PASS
PLATFORM_EMULATION_COMPLETE
```

### translation adapters (simulator) - PASS

```
Command: wolkaraforever/tools/test_translation_sim.sh
known platform failures in this run: 0
[ak] window content size -> 852x393 @1.00x
[ak] cursor presentation=native iPad pointer
[ak] toolbar: leave game control on the toolbar (house; asks the guest to terminate)
[ak] cursor visibility hidden=1 outside=1 game_hidden=0 no_image=0
[ak] window content size -> 956x440 @1.00x
[ak] cursor presentation=native iPad pointer
[ak] toolbar: leave game control on the toolbar (house; asks the guest to terminate)
[ak] cursor visibility hidden=1 outside=1 game_hidden=0 no_image=0
[ak] window content size -> 678x466 @1.00x
[ak] cursor presentation=native iPad pointer
[ak] toolbar: leave game control on the toolbar (house; asks the guest to terminate)
[ak] cursor visibility hidden=1 outside=1 game_hidden=0 no_image=0
[ak] window content size -> 951x669 @1.00x
[ak] cursor presentation=native iPad pointer
[ak] toolbar: leave game control on the toolbar (house; asks the guest to terminate)
[ak] cursor visibility hidden=1 outside=1 game_hidden=0 no_image=0
[ak] window content size -> 669x951 @1.00x
display pass, frame rects, panels, tracking areas, layer placement, contents scale, window ordering, Quartz events, window numbers and modifier keys: PASS
```

### device run (--device) - NOT RUN

```
Not run: pass --device with an iPad connected.
```

## Read this as

Every step that ran passed, on the commit named above.

A step marked NOT RUN is not evidence. Anything the audit asked for that is not
listed as PASS here has not been shown for this commit.

