# Validation: b8cebe7

- Commit: `b8cebe726893d55fc4cfb8997a5e365cbade8588` (branch `app-updates`)
- Recorded: 2026-10-30 02:04:02Z
- Working tree: clean
- Host: macOS 26.7.1 (arm64)
- Xcode: Xcode 27.1
- Device: iPad Pro (12.9-inch) (5th generation), 27.0.1

## Results

| Step | Result |
| --- | --- |
| layer gate (check_layers.sh) | PASS |
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
| the app builds for the device | PASS |
| platform emulation suite | PASS (1 known platform failure(s)) |
| translation adapters (simulator) | PASS |
| install and launch on the iPad | PASS |
| the app's own log, from the launch above | PASS |
| the device matrix, so far as a script can go | PASS |

## What each step printed

### layer gate (check_layers.sh) - PASS

```
Command: wolkaraforever/tools/check_layers.sh
PASS platform/ is byte-identical to upstream/main (00a8501, 1e8d13f1fe089fa32cd84a6b46fe3692e288aeac)
PASS no WolkaraForever strings under platform/
PASS 42 patch(es) apply cleanly
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
PASS check_localization: 504 keys
check_layers: OK
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
21:08:54.855 [wow] a check was asked for
21:08:54.859 [wow] checking wowf eu/deDE install=0 launch=0
21:08:54.919 [wow] checked: state=3 error=none
21:08:56.062 [language] the user chose en
21:08:56.144 [language] home: drawing the page in en (English)
21:08:56.150 [language] home: drawing the page in de (Deutsch)
21:08:56.905 [wow] a check was asked for
21:08:56.906 [wow] checking wowf eu/enUS install=0 launch=0
21:08:56.949 [wow] checked: state=3 error=none
21:08:57.311 [language] home: drawing the page in en (English)
21:08:58.934 [wow] a check was asked for
21:08:58.937 [wow] checking wowf eu/enUS install=0 launch=0
21:08:58.971 [wow] checked: state=3 error=none
21:09:01.468 [wow] a check was asked for
21:09:01.472 [wow] checking wowf us/enUS install=0 launch=0
21:09:01.513 [wow] checked: state=3 error=none
21:09:04.017 [wow] a check was asked for
21:09:04.020 [wow] checking wowf eu/enUS install=0 launch=0
21:09:04.054 [wow] checked: state=3 error=none
21:09:05.228 [wow] a check was asked for
21:09:05.230 [wow] checking wowf eu/enUS install=0 launch=0
21:09:05.265 [wow] checked: state=3 error=none
WoW UIKit PASS: automatic check/update, offline retry, edition race, background cancellation, verified launch, inline preparation/failure/session end, no duplicate launches and bundled licenses; home page headings, rows, order, identifiers, labels, enabled states and Mac-Ever URL; backup, confirmed reset, gamepad config, folder picker and restore flow; device profile (automatic, preview and the way back), render profile with the quality a device was measured at, no game-file write from either; the app language as a setting of its own (config ownership and migration, the row, immediate German and immediate English, no raw keys, the one-time German game-language offer through the validated locale writer, and German at the largest text size); and every control on the home page pressed - the edition sheet, download preferences and its Region sub-sheet, the app language row, all three add-on rows, the add-on folder browser, the permissions row, both voice pages, all nine Performance rows and both switches, the primary button, the Diagnostics button, and both navigation items.
org.tolkara.tests.wow-launcher: 64248
screenshots: /Users/klock/Library/Developer/CoreSimulator/Devices/<identifier>/data/Containers/Data/Application/<identifier>/Documents
```

### input, voice and config rules (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_voice.sh
21:09:31.251 [voice] AKVoiceEnabled set
21:09:31.252 [voice] AKVoiceTakeButtonFromGame set
21:09:31.575 [voice] test screen armed on Not set
21:09:32.086 [config] restored 3 choice(s) from wolkaraforever-config.json
21:09:32.110 [config] could not keep a recovery copy (“wolkaraforever-config.json” couldn’t be copied because you don’t have permission to access “Documents”.); the file is unchanged
21:09:32.119 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
21:09:32.121 [config] recovered 1 choice(s) from the previous copy
21:09:32.122 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
21:09:32.123 [config] the previous copy has already been tried once this launch
21:09:32.126 [config] 1 setting(s) were refused: AKVoiceMode (out of range)
21:09:32.126 [config] restored 1 choice(s) from wolkaraforever-config.json
21:09:32.128 [config] could not write wolkaraforever-config.json.writing (You don’t have permission to save the file “wolkaraforever-config.json.writing” in the folder “Documents”.)
21:09:32.130 [config] restored 0 choice(s) from wolkaraforever-config.json
21:09:32.139 [config] wolkaraforever-config.json was not used: it is 3145728 bytes, and a config file is not
21:09:32.139 [config] the previous copy has already been tried once this launch
21:09:32.141 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
21:09:32.141 [config] the previous copy has already been tried once this launch
21:09:32.142 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
21:09:32.143 [config] the previous copy has already been tried once this launch
21:09:32.145 [config] restored 0 choice(s) from wolkaraforever-config.json
21:09:32.147 [test] a write failure is being provoked now
21:09:32.148 [config] could not write wolkaraforever-config.json.writing (The file “wolkaraforever-config.json.writing” doesn’t exist.)
21:09:32.159 [config] restored 0 choice(s) from wolkaraforever-config.json
VOICE PASS: 303 checks
VOICE PASS: 303 checks
```

### app language resolution, tables and formatting - PASS

```
Command: wolkaraforever/tools/test_localization.sh
apply: applied 0021-appkit-runloop-mode-count.patch
apply: applied 0023-appkit-backing-scale.patch
apply: applied 0024-appkit-event-pump-cost.patch
apply: applied 0025-release-performance-build.patch
apply: applied 0026-metal-frame-diagnosis.patch
apply: applied 0027-iokit-trace-fast-path.patch
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
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
localization PASS: 58 checks (resolution, stored values, tables, fallback, formatting, plurals, change notice)
```

### on-screen controls and the game text field (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_touch_controls_ui.sh --self-test
[ak] input suspended (draftFirstResponder=1)
[ak] input suspended (draftFirstResponder=1)
[ak] input suspended (draftFirstResponder=1)
2026-10-29 21:09:56.222 TouchControlsFixture[66848:41051854] CoreText note: Client requested name ".SFCompact", it will get TimesNewRomanPSMT rather than the intended font. All system UI font access should be through proper APIs such as CTFontCreateUIFontForLanguage() or +[UIFont systemFontOfSize:].
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=44
[ak] system keyboard hidden draftFirstResponder=0
[ak] system keyboard hidden draftFirstResponder=0
[ak] the layer's own keyboard is up (iPadOS has no software keyboard to give)
[ak] the layer's keyboard asked for dictation
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=44
[ak] system keyboard hidden draftFirstResponder=0
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=342
[ak] system keyboard hidden draftFirstResponder=0
2026-10-29 21:09:56.597 TouchControlsFixture[66848:41051854] native: the announced text target answers dictation and reaches the guest
2026-10-29 21:09:56.597 TouchControlsFixture[66848:41051854] native: the toolbar carries Leave the game
[ak] keyboard event type=10
[ak] the user's keys: 1 taken (the game will not see those)
[ak] key usage=4 is the user's; the game does not see it
2026-10-29 21:09:56.678 TouchControlsFixture[66848:41051854] native: usage 0x04 is the user's; the guest's view never heard of it
[ak] keyboard event type=10
[ak] the user's keys: 0 taken (the game will not see those)
[ak] keyboard event type=10
[ak] keyboard event type=10
2026-10-29 21:09:57.783 TouchControlsFixture[66848:41051854] TOUCH_UI_SELF_TEST_PASS: whole-field replacement, empty clearing, duplicate suppression, draft editing, dictation, cancellation and fixed toolbar
org.tolkara.tests.touch-controls: 66848
```

### the on-screen gamepad (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_touch_gamepad_ui.sh --self-test
apply: applied 0026-metal-frame-diagnosis.patch
apply: applied 0027-iokit-trace-fast-path.patch
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
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
build/touch-gamepad-fixture/TouchGamepad.app: replacing existing signature
2026-10-29 21:10:08.484 TouchGamepadFixture[67629:41054142] [TouchGamepad] Connection failed: Fixture (1)
TOUCH_HAPTICS_PASS: independent stick edges, held/jitter suppression, inward rearm, cancellation and disabled feedback.
TOUCH_GAMEPAD_LIFECYCLE_PASS: physical priority, own/snapshot filtering, keyboard/focus cancellation, late replies, failure, retry and teardown.
org.tolkara.tests.touch-gamepad: 67629
```

### local service retry (patch 0006) - PASS

```
Command: wolkaraforever/tools/test_local_service_retry.sh
apply: applied 0025-release-performance-build.patch
apply: applied 0026-metal-frame-diagnosis.patch
apply: applied 0027-iokit-trace-fast-path.patch
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
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
PASS: local service recovery, sequential retries, terminal proof failure, deadlines, cancellation and stale callbacks
PASS: initial connection reset permits retry; reset after SYN/ACK remains terminal; no native readiness
PASS: 5 blocked states, each with its own sentence; unknown states are not classified; a missing, overlong or non-string device identifier blocks before a route starts
PASS: no enrollment ends in a bounded notEnrolled refusal, no readiness, no retry, no packets and no second attach
```

### developer-service handoff (synthetic peer) - PASS

```
Command: wolkaraforever/tools/test_authorization_handoff.sh
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
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
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
CURSEFORGE PASS: 27 checks, no network or credentials
```

### real ZIP extraction (Swift and pinned ZIPFoundation) - PASS

```
Command: wolkaraforever/tools/test_addon_archive.sh
apply: applied 0023-appkit-backing-scale.patch
apply: applied 0024-appkit-event-pump-cost.patch
apply: applied 0025-release-performance-build.patch
apply: applied 0026-metal-frame-diagnosis.patch
apply: applied 0027-iokit-trace-fast-path.patch
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
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
ADDON IMPORT PASS: real ZIP -> Objective-C bridge -> store -> duplicate/disable/restore/remove
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
apply: applied 0036-forever-release-profile.patch
apply: applied 0037-gate-recurring-diagnostics.patch
apply: applied 0038-native-memory-fast-path.patch
apply: applied 0039-bypass-inactive-runtime-guards.patch
apply: applied 0040-test-profile-forever-folder.patch
apply: applied 0041-launch-progress-links-the-app-language.patch
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
WoW manifest tests PASS (synthetic fixtures).
WoW client tests PASS: verified staging, cache repair, patch invalidation, malformed metadata and failed transport.
WoW installation PASS: missing, current, locale mismatch, outdated, ambiguous/missing metadata, changed bytes, path bounds; no writes.
2026-10-29 21:11:56.649 test_wow_update[70878:41063411] [wow-update] Rechecking CASC data.001 after a metadata change.
WoW updater PASS: unchanged data reuse, archive ranges, cancel before activation, durable resume, atomic activation, settings/addon preservation, superseded build and malformed input.
2026-10-29 21:11:58.415 test_wow_verification[70885:41063474] [wow-update] Rechecking CASC data.001 after a metadata change.
2026-10-29 21:11:58.433 test_wow_verification[70885:41063474] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-10-29 21:11:58.444 test_wow_verification[70885:41063474] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-10-29 21:11:58.446 test_wow_verification[70885:41063474] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-10-29 21:11:58.449 test_wow_verification[70885:41063474] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-10-29 21:11:58.451 test_wow_verification[70885:41063474] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-10-29 21:11:58.722 test_wow_verification[70885:41063474] [wow-update] Rechecking CASC data.000 after a metadata change.
Synthetic 16 MiB: cold read=16781056 bytes (0.0375s), warm read=0 bytes (0.0004s).
WoW verification PASS: cold payload reads=100; warm payload reads=0; clone rebinding, full keys/extents, repair, changed/deleted/truncated/symlink data, malformed records, metadata-only recovery, append corruption, 64 MiB checkpoint/resume.
DEVICE_PROFILE_PASS: 174 checks: every model resolves to its own record, an unknown device falls back to Performance, Quality is only offered where it was measured, an override is honoured and a stale one falls back to the running device, the stored names round-trip, and the settings written before this table still mean what they meant.
```

### config, gamepad and UI backup/restore - PASS

```
Command: wolkaraforever/tools/test_forever_ui.sh
apply: applied 0023-appkit-backing-scale.patch
apply: applied 0024-appkit-event-pump-cost.patch
apply: applied 0025-release-performance-build.patch
apply: applied 0026-metal-frame-diagnosis.patch
apply: applied 0027-iokit-trace-fast-path.patch
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
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
FOREVER_CONFIG_PASS: graphics allowlist, byte preservation, CRLF, missing config, gamepad normalisation, CVar set/replace/idempotence, refusal of unreadable names and values, performance preset and its reset, and path boundary.
FOREVER_UI_ARCHIVE_PASS: 37 checks: creation, exclusions, naming, validity, restore, retention, traversal, duplicates, editions, digests, links, special files and journal recovery.
```

### the app builds for the device - PASS

```
Command: wolkaraforever/tools/install.sh --build-only
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
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (42 patch(es), 123 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)

== 2/2 build (the platform's own script)
   build only: not touching the device (xcrun devicectl device install …)
Installed with Developer service. Next: tools/enroll.sh (once), then copy your apps' files (see profiles/).
A mode already chosen in the app is kept; change it there with Execution mode…

== 2/2 done: built, and the device was left alone
   install it       wolkaraforever/tools/pilot.sh install
   the log          build/platform/logs/install-*.log
```

### platform emulation suite - PASS (1 known platform failure(s))

```
Command: bash build/platform/tools/test_emulation.sh
known platform failures in this run: 1
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
[ak] mouse capture requested=1 raw_devices=0
[ak] mouse capture requested=1 raw_devices=0
[ak] mouse capture requested=1 raw_devices=0
[ak] mouse capture requested=1 raw_devices=0
[ak] mouse capture requested=1 raw_devices=0
[ak] mouse capture requested=0 raw_devices=0
[ak] mouse capture requested=0 raw_devices=0
[ak] mouse capture requested=0 raw_devices=0
[ak] mouse event type=1 point=(10,70)
[ak] mouse event type=2 point=(10,70)
[ak] mouse event type=3 point=(10,70)
[ak] mouse event type=4 point=(10,70)
[ak] mouse event type=25 point=(10,70)
[ak] mouse event type=26 point=(10,70)
[ak] mouse event type=1 point=(10,70)
[ak] mouse event type=2 point=(10,70)
[ak] cursor visibility hidden=1 outside=1 game_hidden=0 no_image=0
display pass, frame rects, panels, tracking areas, layer placement, contents scale, window ordering, Quartz events, window numbers and modifier keys: PASS
```

### install and launch on the iPad - PASS

```
Command: wolkaraforever/tools/pilot.sh cycle
== did it crash?
  baseline: Tolkara-2026-10-22-203503.ips
  newest:   Tolkara-2026-10-22-203503.ips (607474s ago)
  no new crash report

== what the app last said
  [pilot] no guest session

== the app's own log
  21:18:25.873 [audio] microphone permission: granted
  21:18:25.904 [ui] home: first appearance, checking the game files
  21:18:25.904 [wow] a check was asked for
  21:18:25.905 [wow] checking wowf us/enUS install=0 launch=0
  21:18:25.910 [input] inspector: screen capture changed, captured=1
  21:18:25.910 [input] input: system.capture on
  21:18:25.985 [host] foreground: dictation=0 listening=0 learning=0 audio=SoloAmbient/AVAudioSessionModeDefault mic=0
  21:18:25.985 [audio] microphone permission: already granted, nothing to ask
  21:18:25.987 [audio] speech permission: already granted, nothing to ask
  21:18:25.990 [ui] home: back in front
  21:18:26.766 [audio] the playback hook is at 0x104e65cc8 and reachable by name
  21:18:27.010 [wow] checked: state=3 error=none

== state
  app running:    1
  guest log says: none (written 6702s ago)
```

### the app's own log, from the launch above - PASS

```
Command: wolkaraforever/tools/pilot.sh log 40
  21:18:25.866 [input] inspector: GCMouseDidConnectNotification
  21:18:25.866 [input] inspector: 0 controller(s) connected
  21:18:25.866 [input] inspector: keyboard=Generic Keyboard mouse=CoreDevice touchscreenGesture
  21:18:25.866 [input] inspector: keyboard keys=134 printScreen=PrintScreen
  21:18:25.866 [input] inspector: keyboard key names= | A | Application | B | Backslash | C | CapsLock | CloseBracket | Comma | D | DeleteForward | DeleteOrBackspace | DownArrow | E | Eight | End | Equa
  21:18:25.866 [input] inspector: watching controller, keyboard, screenshot and capture
  21:18:25.866 [input] inspector: GCKeyboardDidConnectNotification
  21:18:25.866 [input] inspector: 0 controller(s) connected
  21:18:25.866 [input] inspector: keyboard=Generic Keyboard mouse=CoreDevice touchscreenGesture
  21:18:25.866 [input] inspector: keyboard keys=134 printScreen=PrintScreen
  21:18:25.866 [input] inspector: keyboard key names= | A | Application | B | Backslash | C | CapsLock | CloseBracket | Comma | D | DeleteForward | DeleteOrBackspace | DownArrow | E | Eight | End | Equa
  21:18:25.866 [input] inspector: watching controller, keyboard, screenshot and capture
  21:18:25.873 [audio] microphone permission: granted
  21:18:25.904 [ui] home: first appearance, checking the game files
  21:18:25.904 [wow] a check was asked for
  21:18:25.905 [wow] checking wowf us/enUS install=0 launch=0
  21:18:25.910 [input] inspector: screen capture changed, captured=1
  21:18:25.910 [input] input: system.capture on
  21:18:25.985 [host] foreground: dictation=0 listening=0 learning=0 audio=SoloAmbient/AVAudioSessionModeDefault mic=0
  21:18:25.985 [audio] microphone permission: already granted, nothing to ask
  21:18:25.987 [audio] speech permission: already granted, nothing to ask
  21:18:25.990 [ui] home: back in front
  21:18:26.766 [audio] the playback hook is at 0x104e65cc8 and reachable by name
  21:18:27.010 [wow] checked: state=3 error=none
  this log holds the launch from this run (122 before it, 123 now)
```

### the device matrix, so far as a script can go - PASS

```
Command: wolkaraforever/tools/device_matrix.sh
                               the deferred part, and it is printed above. -120 dBFS is
                               digital silence, not a quiet room, so this needs a person
                               to speak and a look at whether anything else holds the input.

== deferred, and why
  a real transcript          needs someone to speak into the iPad, because only a voice makes
                             the recogniser produce words. What is covered without one is the
                             state the session is left in: the app's own `voice` self-test opens
                             a real session with the real recogniser and hands it back, and
                             `mic=0` above is the same claim after being put away.
  a controller button        a real pad, in a hand: `input` above drives the router with a
                             synthetic press, which proves the mapper, the modes and the
                             published key set. What it cannot prove is what iPadOS reports
                             for a particular pad's buttons, which needs the pad.
  a dictation target         a running guest: `selftest dictation-target` asks the game's
                             own text field whether it takes words and keys, and with no
                             guest it correctly reports 0/1 checks. Launching the game is
                             outside this work, so it is deferred here and not counted as a
                             pass - run it once a game is up.
  the game itself            a live session touches the client's own store; the CASC and
                             in-game checks stay in COMPATIBILITY.md and are done by hand.
  a real add-on import       the extractor is the Swift/ZIPFoundation path the fixture
                             stands in for; it is exercised by importing an archive here.

DEVICE MATRIX PASS: 23 checks
```

## Read this as

Every step that ran passed, on the commit named above.

A step marked NOT RUN is not evidence. Anything the audit asked for that is not
listed as PASS here has not been shown for this commit.
