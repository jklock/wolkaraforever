# Validation: b3d39bd

- Commit: `b3d39bdcc04520578d563eb1e5710ef396715e59` (branch `main`)
- Recorded: 2026-11-11 22:14:08Z
- Working tree: clean
- Host: macOS 26.7.1 (arm64)
- Xcode: Xcode 27.2
- Device: iPad Pro (12.9-inch) (5th generation), 27.2

## Results

| Step | Result |
| --- | --- |
| layer gate (check_layers.sh) | PASS |
| immutable launcher UI policy and matrix baselines | FAIL (exit 1) |
| validation distinguishes known failures from incomplete suites | PASS |
| install does the right thing per execution mode | PASS |
| pilot.sh fails closed and keeps its own session | PASS |
| launcher pages (simulator fixture) | FAIL (exit 1) |
| input, voice and config rules (simulator fixture) | PASS |
| app language resolution, tables and formatting | PASS |
| on-screen controls and the game text field (simulator fixture) | PASS |
| the on-screen gamepad (simulator fixture) | FAIL (exit 1) |
| local service retry (patch 0006) | PASS |
| developer-service handoff (synthetic peer) | PASS |
| CurseForge response and request contracts | PASS |
| real ZIP extraction (Swift and pinned ZIPFoundation) | PASS |
| the app icon's assets and catalog | PASS |
| game file verification and repair (CASC) | PASS |
| config, gamepad and UI backup/restore | PASS |
| the signed app builds for the device | PASS |
| platform emulation suite | PASS |
| translation adapters (simulator) | PASS |
| install and launch on the iPad | PASS |
| the app's own log, from the launch above | PASS |
| the device matrix, so far as a script can go | FAIL (exit 1) |

## What each step printed

### layer gate (check_layers.sh) - PASS

```
Command: wolkaraforever/tools/check_layers.sh
PASS platform/ is byte-identical to upstream/main (00a8501, 1e8d13f1fe089fa32cd84a6b46fe3692e288aeac)
PASS no WolkaraForever strings under platform/
PASS 53 patch(es) apply cleanly
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
PASS check_localization: 542 keys
check_layers: OK
```

### immutable launcher UI policy and matrix baselines - FAIL (exit 1)

```
Command: wolkaraforever/tools/check_ui_policy.sh
16:14:57.706 [wow] update progress: snapshot 0/0
16:14:57.706 [wow] update progress: download 50/100
16:14:57.707 [wow] update progress: complete 1/1
16:14:57.709 [wow] verification bytes read=0 reused=0
16:14:57.714 [wow] checked: state=3 error=none
16:14:57.985 [wow] a check was asked for
16:14:57.989 [wow] checking wowf eu/enUS install=0 launch=0
16:14:58.019 [wow] checked: state=0 error=Synthetic offline response
16:14:58.291 [wow] a check was asked for
16:14:58.293 [wow] checking wowf eu/enUS install=0 launch=0
16:14:58.325 [wow] checked: state=3 error=none
16:14:58.599 [wow] checking wowf eu/enUS install=0 launch=1
16:14:59.112 [wow] checked: state=3 error=none
16:14:59.303 [wow] a check was asked for
16:14:59.304 [wow] checking wowf eu/enUS install=1 launch=0
16:14:59.332 [wow] update progress: snapshot 0/0
16:14:59.332 [wow] update progress: download 50/100
16:14:59.456 [wow] check paused: phase=download progress=50/100
16:14:59.463 [voice] dictation: the app went to the background (state=0, listening=0)
16:14:59.843 [wow] update progress: complete 1/1
16:14:59.850 [wow] verification bytes read=0 reused=0
16:15:00.064 [ui] home: back in front
16:15:00.065 [ui] home: back in front
Assertion failed: (UIApplication.sharedApplication.idleTimerDisabled), function -[TKWoWFixtureDelegate resumeUpdate], file test_wow_launcher_app.m, line 981.
org.tolkara.tests.wow-launcher: 71296
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

### launcher pages (simulator fixture) - FAIL (exit 1)

```
Command: wolkaraforever/tools/test_wow_launcher_ui.sh
16:22:25.196 [wow] update progress: snapshot 0/0
16:22:25.196 [wow] update progress: download 50/100
16:22:25.197 [wow] update progress: complete 1/1
16:22:25.199 [wow] verification bytes read=0 reused=0
16:22:25.205 [wow] checked: state=3 error=none
16:22:25.467 [wow] a check was asked for
16:22:25.468 [wow] checking wowf eu/enUS install=0 launch=0
16:22:25.500 [wow] checked: state=0 error=Synthetic offline response
16:22:25.769 [wow] a check was asked for
16:22:25.771 [wow] checking wowf eu/enUS install=0 launch=0
16:22:25.804 [wow] checked: state=3 error=none
16:22:26.074 [wow] checking wowf eu/enUS install=0 launch=1
16:22:26.583 [wow] checked: state=3 error=none
16:22:26.779 [wow] a check was asked for
16:22:26.781 [wow] checking wowf eu/enUS install=1 launch=0
16:22:26.813 [wow] update progress: snapshot 0/0
16:22:26.813 [wow] update progress: download 50/100
16:22:26.936 [wow] check paused: phase=download progress=50/100
16:22:26.940 [voice] dictation: the app went to the background (state=0, listening=0)
16:22:27.323 [wow] update progress: complete 1/1
16:22:27.325 [wow] verification bytes read=0 reused=0
16:22:27.540 [ui] home: back in front
16:22:27.541 [ui] home: back in front
Assertion failed: (UIApplication.sharedApplication.idleTimerDisabled), function -[TKWoWFixtureDelegate resumeUpdate], file test_wow_launcher_app.m, line 981.
org.tolkara.tests.wow-launcher: 76008
```

### input, voice and config rules (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_voice.sh
16:25:57.722 [voice] AKVoiceTakeButtonFromGame set
16:25:58.040 [voice] test screen armed on Not set
16:25:58.552 [config] restored 3 choice(s) from wolkaraforever-config.json
16:25:58.566 [config] could not keep a recovery copy (“wolkaraforever-config.json” couldn’t be copied because you don’t have permission to access “Documents”.); the file is unchanged
16:25:58.571 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
16:25:58.572 [config] recovered 1 choice(s) from the previous copy
16:25:58.574 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
16:25:58.574 [config] the previous copy has already been tried once this launch
16:25:58.576 [config] 1 setting(s) were refused: AKVoiceMode (out of range)
16:25:58.576 [config] restored 1 choice(s) from wolkaraforever-config.json
16:25:58.578 [config] could not write wolkaraforever-config.json.writing (You don’t have permission to save the file “wolkaraforever-config.json.writing” in the folder “Documents”.)
16:25:58.580 [config] restored 0 choice(s) from wolkaraforever-config.json
16:25:58.583 [config] wolkaraforever-config.json was not used: it is 3145728 bytes, and a config file is not
16:25:58.583 [config] the previous copy has already been tried once this launch
16:25:58.584 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
16:25:58.584 [config] the previous copy has already been tried once this launch
16:25:58.585 [config] wolkaraforever-config.json was not used: it is not readable: The data couldn’t be read because it isn’t in the correct format.
16:25:58.585 [config] the previous copy has already been tried once this launch
16:25:58.587 [config] restored 0 choice(s) from wolkaraforever-config.json
16:25:58.589 [test] a write failure is being provoked now
16:25:58.590 [config] could not write wolkaraforever-config.json.writing (The file “wolkaraforever-config.json.writing” couldn’t be saved in the folder “Documents”.)
16:25:58.592 [config] restored 0 choice(s) from wolkaraforever-config.json
VOICE PASS: 341 checks
org.tolkara.tests.voice: 78556
VOICE PASS: 341 checks
```

### app language resolution, tables and formatting - PASS

```
Command: wolkaraforever/tools/test_localization.sh
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
apply: applied 0050-external-jit-clear-enabler-arena.patch
apply: applied 0051-external-jit-unprepared-high-region.patch
apply: applied 0052-external-jit-arena-executable.patch
apply: applied 0053-external-jit-in-every-build.patch
apply: applied 0054-appkit-content-view-fills-content-area.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (53 patch(es), 159 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
localization PASS: 58 checks (resolution, stored values, tables, fallback, formatting, plurals, change notice)
```

### on-screen controls and the game text field (simulator fixture) - PASS

```
Command: wolkaraforever/tools/test_touch_controls_ui.sh --self-test
[ak] input suspended (draftFirstResponder=1)
[ak] input suspended (draftFirstResponder=1)
2026-11-11 16:26:28.845 TouchControlsFixture[80614:14288744] CoreText note: Client requested name ".SFCompact", it will get TimesNewRomanPSMT rather than the intended font. All system UI font access should be through proper APIs such as CTFontCreateUIFontForLanguage() or +[UIFont systemFontOfSize:].
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=44
[ak] system keyboard hidden draftFirstResponder=0
[ak] system keyboard hidden draftFirstResponder=0
[ak] the layer's own keyboard is up (iPadOS has no software keyboard to give)
[ak] the layer's keyboard asked for dictation
[ak] system keyboard shown draftFirstResponder=1 markedText=0 height=335
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=411
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=411
[ak] system keyboard shown draftFirstResponder=0 markedText=0 height=411
2026-11-11 16:26:29.311 TouchControlsFixture[80614:14288744] native: the announced text target answers dictation and reaches the guest
2026-11-11 16:26:29.311 TouchControlsFixture[80614:14288744] native: the toolbar carries Leave the game
[ak] keyboard event type=10
[ak] the user's keys: 1 taken (the game will not see those)
[ak] key usage=4 is the user's; the game does not see it
2026-11-11 16:26:29.385 TouchControlsFixture[80614:14288744] native: usage 0x04 is the user's; the guest's view never heard of it
[ak] keyboard event type=10
[ak] the user's keys: 0 taken (the game will not see those)
[ak] keyboard event type=10
[ak] keyboard event type=10
[ak] system keyboard hidden draftFirstResponder=0
2026-11-11 16:26:30.493 TouchControlsFixture[80614:14288744] TOUCH_UI_SELF_TEST_PASS: whole-field replacement, empty clearing, duplicate suppression, draft editing, dictation, cancellation and fixed toolbar
org.tolkara.tests.touch-controls: 80614
```

### the on-screen gamepad (simulator fixture) - FAIL (exit 1)

```
Command: wolkaraforever/tools/test_touch_gamepad_ui.sh --self-test
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
apply: applied 0050-external-jit-clear-enabler-arena.patch
apply: applied 0051-external-jit-unprepared-high-region.patch
apply: applied 0052-external-jit-arena-executable.patch
apply: applied 0053-external-jit-in-every-build.patch
apply: applied 0054-appkit-content-view-fills-content-area.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (53 patch(es), 159 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
test_touch_gamepad_ui: iPad Pro 13-inch (M5) (16GB) (<identifier>)
build/touch-gamepad-fixture/TouchGamepad.app: replacing existing signature
Assertion failed: (pad.connections==1 && !pad.visible), function TestLifecycle, file test_touch_gamepad_app.m, line 380.
TOUCH_TRACKING_PUMP_PASS: deferred UI and tracking timers progress; closed-panel pump remains nonblocking.
TOUCH_HAPTICS_PASS: independent stick edges, held/jitter suppression, inward rearm, cancellation and disabled feedback.
org.tolkara.tests.touch-gamepad: 81664
```

### local service retry (patch 0006) - PASS

```
Command: wolkaraforever/tools/test_local_service_retry.sh
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
apply: applied 0050-external-jit-clear-enabler-arena.patch
apply: applied 0051-external-jit-unprepared-high-region.patch
apply: applied 0052-external-jit-arena-executable.patch
apply: applied 0053-external-jit-in-every-build.patch
apply: applied 0054-appkit-content-view-fills-content-area.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (53 patch(es), 159 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
PASS: local service recovery, sequential retries, terminal proof failure, deadlines, cancellation and stale callbacks
PASS: initial connection reset permits retry; reset after SYN/ACK remains terminal; no native readiness
PASS: 5 blocked states, each with its own sentence; unknown states are not classified; a missing, overlong or non-string device identifier blocks before a route starts
PASS: no enrollment ends in a bounded notEnrolled refusal, no readiness, no retry, no packets and no second attach
```

### developer-service handoff (synthetic peer) - PASS

```
Command: wolkaraforever/tools/test_authorization_handoff.sh
apply: applied 0042-xcode-27-package-ipa-products.patch
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: applied 0050-external-jit-clear-enabler-arena.patch
apply: applied 0051-external-jit-unprepared-high-region.patch
apply: applied 0052-external-jit-arena-executable.patch
apply: applied 0053-external-jit-in-every-build.patch
apply: applied 0054-appkit-content-view-fills-content-area.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (53 patch(es), 159 file(s) overlaid)
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
apply: applied 0050-external-jit-clear-enabler-arena.patch
apply: applied 0051-external-jit-unprepared-high-region.patch
apply: applied 0052-external-jit-arena-executable.patch
apply: applied 0053-external-jit-in-every-build.patch
apply: applied 0054-appkit-content-view-fills-content-area.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (53 patch(es), 159 file(s) overlaid)
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
WoW storage: missing=48 loose=16 reserve=1073741824 available=15460524774 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=15459914470 source=important-usage
2026-11-11 16:29:12.196 test_wow_update[86309:14306458] [wow-update] Rechecking CASC data.001 after a metadata change.
WoW storage: missing=0 loose=16 reserve=1073741824 available=15459271398 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=15459263206 source=important-usage
WoW storage: missing=59 loose=16 reserve=1073741824 available=15459259110 source=important-usage
WoW storage: missing=48 loose=16 reserve=1073741824 available=15458517734 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=15457911526 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=15457637094 source=important-usage
WoW storage: missing=0 loose=16 reserve=1073741824 available=15457616614 source=important-usage
WoW storage: missing=160 loose=16 reserve=1073741824 available=15457620710 source=important-usage
WoW startup contract PASS: a retried and an exhausted download leave metadata, verification, activation and Play eligibility unchanged, and activation happens once for the completed build.
WoW updater PASS: unchanged data reuse, archive ranges, cancel before activation, durable resume, atomic activation, settings/addon preservation, superseded build and malformed input.
2026-11-11 16:29:14.182 test_wow_verification[86318:14306527] [wow-update] Rechecking CASC data.001 after a metadata change.
2026-11-11 16:29:14.203 test_wow_verification[86318:14306527] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-11 16:29:14.217 test_wow_verification[86318:14306527] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-11 16:29:14.219 test_wow_verification[86318:14306527] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-11 16:29:14.224 test_wow_verification[86318:14306527] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-11 16:29:14.225 test_wow_verification[86318:14306527] [wow-update] Rechecking CASC data.000 after a metadata change.
2026-11-11 16:29:14.567 test_wow_verification[86318:14306527] [wow-update] Rechecking CASC data.000 after a metadata change.
Synthetic 16 MiB: cold read=16781056 bytes (0.0599s), warm read=0 bytes (0.0004s).
Synthetic 100k warm keys: formatted 1.0770s, binary 0.0477s; payload reads=0.
WoW verification PASS: cold payload reads=100; warm payload reads=0; clone rebinding, full keys/extents, repair, changed/deleted/truncated/symlink data, malformed records, metadata-only recovery, append corruption, 64 MiB checkpoint/resume.
DEVICE_PROFILE_PASS: 408 checks: every model resolves to its own record, an unknown device falls back to Performance, Quality is only offered where it was measured, an override is honoured and a stale one falls back to the running device, the stored names round-trip, and the settings written before this table still mean what they meant.
DOWNLOAD_STATUS_PASS: 40 checks: the throughput window, the estimate, and the words both are written in - a steady transfer reads its own rate, a burst is averaged until it leaves the window, a restarted attempt is unknown rather than negative, the array is never written past its end, and an unknown, zero or day-long estimate is withheld in both languages.
```

### config, gamepad and UI backup/restore - PASS

```
Command: wolkaraforever/tools/test_forever_ui.sh
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
apply: applied 0050-external-jit-clear-enabler-arena.patch
apply: applied 0051-external-jit-unprepared-high-region.patch
apply: applied 0052-external-jit-arena-executable.patch
apply: applied 0053-external-jit-in-every-build.patch
apply: applied 0054-appkit-content-view-fills-content-area.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (53 patch(es), 159 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)
FOREVER_CONFIG_PASS: graphics allowlist, byte preservation, CRLF, missing config, gamepad normalisation, CVar set/replace/idempotence, refusal of unreadable names and values, performance preset and its reset, and path boundary.
FOREVER_UI_ARCHIVE_PASS: 37 checks: creation, exclusions, naming, validity, restore, retention, traversal, duplicates, editions, digests, links, special files and journal recovery.
```

### the signed app builds for the device - PASS

```
Command: wolkaraforever/tools/install.sh --build-only
apply: applied 0043-authorization-blocked-states.patch
apply: applied 0044-sign-guest-local-determinism.patch
apply: applied 0045-iphone-guest-display.patch
apply: applied 0046-initial-guest-scene-size.patch
apply: applied 0047-pump-native-control-tracking.patch
apply: applied 0048-require-private-roots-before-device-install.patch
apply: applied 0049-show-guest-alert-accessory-text.patch
apply: applied 0050-external-jit-clear-enabler-arena.patch
apply: applied 0051-external-jit-unprepared-high-region.patch
apply: applied 0052-external-jit-arena-executable.patch
apply: applied 0053-external-jit-in-every-build.patch
apply: applied 0054-appkit-content-view-fills-content-area.patch
apply: /Volumes/Storage/Projects/wolkaraforever/build/platform now carries the layer (53 patch(es), 159 file(s) overlaid)
prepare: build/platform ready (platform 00a8501)

== 2/2 build (the platform's own script)
Private trust store verified before device install.
   build only: not touching the device (xcrun devicectl device install …)
Installed with Developer service. Next: tools/enroll.sh (once), then copy your apps' files (see profiles/).
A mode already chosen in the app is kept; change it there with Execution mode…
   private trust store: present and valid

== 2/2 done: built, and the device was left alone
   install it       wolkaraforever/tools/pilot.sh install
   the log          build/platform/logs/install-*.log
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

### install and launch on the iPad - PASS

```
Command: wolkaraforever/tools/pilot.sh cycle
  21:45:16.894 [input] window: press with no key (type=1)
  2026-11-10 21:45:16.894 Tolkara[39119:3964042] [ak] window: press with no key (type=2)
  21:45:16.894 [input] window: press with no key (type=2)
  2026-11-10 21:45:16.894 Tolkara[39119:3964042] [ak] window: press with no key (type=1)
  21:45:16.894 [input] window: press with no key (type=1)
  21:45:17.877 [host] closing in 4
  21:45:17.880 [host] closing now: the user pressed Close WolkaraForever

== the app's own log
  16:36:46.810 [input] inspector: watching controller, keyboard, screenshot and capture
  16:36:46.817 [audio] microphone permission: granted
  16:36:46.853 [input] inspector: screen capture changed, captured=1
  16:36:46.858 [ui] home: first appearance, checking the game files
  16:36:46.858 [wow] a check was asked for
  16:36:46.860 [wow] checking wowf us/enUS install=0 launch=0
  16:36:46.933 [host] foreground: dictation=0 listening=0 learning=0 audio=SoloAmbient/AVAudioSessionModeDefault mic=0
  16:36:46.933 [audio] microphone permission: already granted, nothing to ask
  16:36:46.935 [audio] speech permission: already granted, nothing to ask
  16:36:46.940 [ui] home: back in front
  16:36:47.679 [audio] the playback hook is at 0x10440e048 and reachable by name
  16:36:47.985 [wow] checked: state=3 error=none

== state
  app running:    1
  guest log says: PASS (written 67996s ago)
```

### the app's own log, from the launch above - PASS

```
Command: wolkaraforever/tools/pilot.sh log 40
  16:36:46.795 [input] window: offered a key command for Print Screen (input=0x46)
  16:36:46.809 [input] inspector: GCMouseDidConnectNotification
  16:36:46.809 [input] inspector: 0 controller(s) connected
  16:36:46.809 [input] inspector: keyboard=Generic Keyboard mouse=CoreDevice touchscreenGesture
  16:36:46.810 [input] inspector: keyboard keys=134 printScreen=PrintScreen
  16:36:46.810 [input] inspector: keyboard key names= | A | Application | B | Backslash | C | CapsLock | CloseBracket | Comma | D | DeleteForward | DeleteOrBackspace | DownArrow | E | Eight | End | Equa
  16:36:46.810 [input] inspector: watching controller, keyboard, screenshot and capture
  16:36:46.810 [input] inspector: GCKeyboardDidConnectNotification
  16:36:46.810 [input] inspector: 0 controller(s) connected
  16:36:46.810 [input] inspector: keyboard=Generic Keyboard mouse=CoreDevice touchscreenGesture
  16:36:46.810 [input] inspector: keyboard keys=134 printScreen=PrintScreen
  16:36:46.810 [input] inspector: keyboard key names= | A | Application | B | Backslash | C | CapsLock | CloseBracket | Comma | D | DeleteForward | DeleteOrBackspace | DownArrow | E | Eight | End | Equa
  16:36:46.810 [input] inspector: watching controller, keyboard, screenshot and capture
  16:36:46.817 [audio] microphone permission: granted
  16:36:46.853 [input] inspector: screen capture changed, captured=1
  16:36:46.858 [ui] home: first appearance, checking the game files
  16:36:46.858 [wow] a check was asked for
  16:36:46.860 [wow] checking wowf us/enUS install=0 launch=0
  16:36:46.933 [host] foreground: dictation=0 listening=0 learning=0 audio=SoloAmbient/AVAudioSessionModeDefault mic=0
  16:36:46.933 [audio] microphone permission: already granted, nothing to ask
  16:36:46.935 [audio] speech permission: already granted, nothing to ask
  16:36:46.940 [ui] home: back in front
  16:36:47.679 [audio] the playback hook is at 0x10440e048 and reachable by name
  16:36:47.985 [wow] checked: state=3 error=none
  this log holds the launch from this run (79 before it, 80 now)
```

### the device matrix, so far as a script can go - FAIL (exit 1)

```
Command: wolkaraforever/tools/device_matrix.sh
                               to speak and a look at whether anything else holds the input.

== out of scope: these need a person, a pad, or a running game
  Every check above is automated, and none of them waits for someone to press, speak or
  watch. The things below cannot be automated on this device at all, so they are out of
  scope for this matrix rather than outstanding work:
  a spoken transcript        only a voice makes the recogniser produce words. What is
                             covered without one is the state the session is left in:
                             `voice` above opens a real session with the real recogniser
                             and hands it back, and `mic=0` after being put away is the
                             same claim.
  a controller button        a real pad, in a hand: `input` above drives the router with a
                             synthetic press, which proves the mapper, the modes and the
                             published key set. What it cannot prove is what iPadOS reports
                             for a particular pad's buttons, which needs the pad.
  a dictation target         a running guest: `selftest dictation-target` asks the game's
                             own text field whether it takes words and keys, and with no
                             guest it correctly reports 0/1 checks. That is a check to run
                             with the game up, outside this matrix.
  the game itself            a live session touches the client's own store; the CASC and
                             in-game checks stay in COMPATIBILITY.md and are done by hand.
  a real add-on import       the extractor is the Swift/ZIPFoundation path the fixture
                             stands in for; it is exercised by importing an archive here.

DEVICE MATRIX FAIL: 1 of 24 checks failed
```

## Read this as

**4 step(s) failed.** The failures are above, with what they printed.

A step marked NOT RUN is not evidence. Anything the audit asked for that is not
listed as PASS here has not been shown for this commit.
