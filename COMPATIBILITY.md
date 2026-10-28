# Compatibility

Applications that people have actually run with Tolkara. Add a row through a
pull request; say what you tested, on what hardware, with which execution mode
(Developer service, Local signing or External JIT), and what did not work.
| Application | Version | Device / OS | Execution mode | Works | Known problems | Profile |
| --- | --- | --- | --- | --- | --- | --- |
| World of Warcraft Forever (Classic beta, macOS arm64 client) | 1.60.1 | iPad Pro M5, iPadOS 27 | Local signing | Login and gameplay (2026-09-27), with no debugger, helper or tunnel and no memory preparation. At startup the client's own unpacked code matched the signed page container byte for byte, and all 13,280 initializers ran into the original `main`. | Developer service is not the tested route on this iPad. Same capture limitation as the other client. | [`wow-forever`](profiles/wow-forever) |
| World of Warcraft Forever (release, macOS arm64 client) | 1.60.1.70634 | iPad Pro 12.9-inch 5th generation (M1, `Dadpad`), iPadOS 27.0.1 | Developer service | Reaches the login screen on 2026-10-27 from a store pushed off the Mac (see below): all 13,305 initializers ran into the original `main`, the launcher's own check reports `Ready to play` against the published build, and the launch produced no assertion file and no crash report. The beta's settings and add-ons were carried across, with `portal` set to `US`. | The store was verified by the launcher (metadata and executable) and by the client's own boot, not block by block; Local signing for this build was not exercised. | [`wow-forever`](profiles/wow-forever) |

## The beta became the release (2026-10-27)

The client this layer started with was the Classic Beta — product `wow_classic_beta`,
folder `_classic_beta_`. The release is a different product: `wowf` in `_forever_`, with
its own entry in `.build.info`. A copy into the app only adds and overwrites, so moving
between them is a delete followed by a push, and the delete needs the device.

Measured on `Dadpad`, over the paired network:

- **What was there**: `Documents/World of Warcraft` held 3,227 files, **73.17 GB**,
  being the beta's edition folder and `Data/wow_classic_beta`, plus one file in the
  updater's snapshot beside it.
- **Removed** with `wolkaraforever/tools/remove_game.sh --all` in **33 s**: paths are
  removed deepest first through the app's own file-sharing service, because AFC's
  remove is not recursive. A fresh listing afterwards reported both paths gone.
- **Pushed** with `wolkaraforever/tools/push_game.sh --source "/Volumes/Storage/World of
  Warcraft"`: 64 GB at about **45 MB/s**, 15.94 GB of the shared store in the first six
  minutes.
- **Afterwards**: `Data/data` 99 files, 67.39 GB; `Data/indices` 1,505 files, 0.32 GB;
  `Data/wowf` 30 files; `_forever_` 54 files. `.build.info` is byte-identical to the
  Mac's (689 bytes, SHA-256 `661c170b…`), naming `wowf` `1.60.1.70634`.
- **The launcher's own check**, run on the device: `Ready to play`, `1.60.1.70634`.
  That check verifies the metadata and the executable's hash against the published
  build; it does not read every data block.
- **The client's own boot**: the login screen reads `Version 1.60.1 (70634) (Release
  arm64)` at 60 fps, with no file in `_forever_/Errors` and no new crash report.
- **User data carried across**: the beta's `WTF` (99 files) and `Interface` (736
  files, two add-ons) were copied into `_forever_` after the push. The one setting that
  could not travel unchanged is `portal`: the beta wrote `test`, the release writes the
  region, so it was set to `US` — the value the release client itself had written on the
  Mac. The account name on the login screen came from that restored `WTF`.

The beta's own copy of these files is out of the app and is not committed; it lives in
ignored build output, `build/device-backup/2026-10-27-beta/`.

## Measured performance, and what it did not show (2026-10-23)

On Dadpad (iPad Pro 12.9-inch, 5th generation, M1, iPadOS 27) with Developer
service, against the installed Forever client 1.60.1, launched with
`--local-game-startup --measure-native`. The evaluation and its evidence are in
[PERFORMANCE_LANES.md](docs/PERFORMANCE_LANES.md).

- **Frame pacing at the login screen**: 55 consecutive 5 s windows, 59.9-60.2 fps,
  longest gap 20.8 or 25.0 ms, and **no gap over 50 ms in any window**. Nothing in
  either tree sets a frame cap; the 25 ms gap (one frame one refresh late) occurs in
  most windows and is not yet attributed.
- **GPU attribution** (layer patch 0019): over 31 windows the GPU was busy for
  **7.3-25.9 ms of a 16.7 ms frame** and for **53% of wall time at rest**, rising to
  94% and then past the frame budget once (a 25.9 ms frame at 59.2 fps) as the
  client finished loading the screen. At rest the frame is not waiting on the GPU.
  The frame-timing log line carries `gpu_ms=` and `gpu_load=`; the HUD's expanded
  view reads the same two values into a `GPU:` row (the number is measured; the row
  itself was not read on screen, because expanding the HUD needs a tap).
- **Launch latency** (layer patches 0019-0020): developer-service memory preparation
  took **67.3 s** for the 99.5 MB image, measured as the preflight read-back running
  at 1.5-1.6 MB/s (sampled from the provider's own progress file once a second).
  Thirty-two reads in flight instead of four brought it to **62.5 s**, not the 8x the
  window suggests: the limit is the tunnel's deliberate one-segment-in-flight TCP,
  not the protocol above it.
- **`--selftest=forever-ui` PASS 17/17** and **`--selftest=forever-ui-clean` PASS
  2/2** on the installed build, with the new HUD row present; the overlay preference
  was returned to off afterwards.
- **In play**, the same build, in a questing zone at the user's settings, the HUD
  read **49.8 FPS (20.0 ms), GPU 7.8 ms of 20.0 ms (39% busy), thermal Nominal,
  Low Power Mode off, RAM 3826 MB with 12.5 GB headroom**. The GPU is doing the same
  8-10 ms it did at 60 fps on the login screen, so the in-world frame is **not
  GPU-bound and not thermal at that moment**: the client is producing 20 ms frames on
  the CPU side. See [PERFORMANCE_LANES.md](docs/PERFORMANCE_LANES.md).
- **Shader warm-up, measured in the same session**: 114 Metal libraries loaded
  during play, **96 of them inside one 20 s window at world entry** (dated against
  the audio engine's fixed-rate log counters). A burst, not the steady frame cost.
- **Open defect found while reviewing the logs**: CoreFoundation logged
  `invalid mode 'kCFRunLoopCommonModes' provided to CFRunLoopRunSpecific` at the
  moment the HUD was switched on. CoreFoundation prints that once per process, so
  how often the run loop is entered that way is not yet known, and a caller that
  loops on the immediate return would spin the main thread.

**Not measured**: a long in-world run (thermal drift), the per-library compile cost,
and the frequency of that run-loop error. The in-world frame rate above is a single
reading, not a benchmark.

## Login screen and cinematics at 60 fps under thermal pressure (2026-10-27)

Dadpad (iPad Pro 12.9-inch, 5th generation, M1, iPadOS 27), Developer service,
candidate with 34 layer patches including `0035-hud-frame-path-without-diagnostic-logging`,
launched normally with `wolkaraforever/tools/launch.sh --local-game-startup` - **no
`--measure-native`**, so none of the detailed frame-timing path was in use, and
`0034-metal-anomaly-timeline` was not in the build. The client was not logged into.

**What this section does not show, stated first because the numbers read stronger than
they are.** The login screen and a cinematic are the only two scenes reachable without a
login, and both are much lighter than the world. Nothing here measures the world, and
nothing here can show that `0035` helps: that patch removes the HUD's per-drawable
`AKFrameTiming` object, synchronised aggregate and 5 s log write from the frame path, and
on the login screen the frame has about 16 ms of unused budget (GPU 53% busy, CPU idle in
submission), so removing per-frame work cannot move a number that is already pinned to
vsync. Its benefit is only observable in a CPU-bound frame - which is the in-world case
below, measured on 2026-10-23 **before** this patch existed, at 49.8 fps. The candidate's
headline change is therefore **unproven for the case it targets**. The cinematic is weaker
still: it runs at GPU 1.5 ms of 16.7 ms (9% busy), a video-decode path, so holding 60 fps
there says nothing about game load.

The load gap is visible in our own two measurements: in the world the GPU was busy for
7.8 ms of a **20.0 ms** frame (39%), while the login screen has it busy for 8.9 ms of a
**16.7 ms** frame (53%). The world spends longer per frame while asking the GPU for less,
so the extra time is on the CPU - which is exactly the axis the login screen cannot load.

- **Login screen, thermal Nominal (Cool)**: four samples 4 s apart read `60.2`, `60.0`,
  `60.0`, `60.0` FPS, latest gap 16.7 ms, GPU 8.1-10.8 ms of 16.7 ms (53-54% busy),
  drawable wait 0.0 ms, Low Power Mode off.
- **Cinematic, thermal Serious (Throttling active)**: ten samples over roughly two
  minutes read `60.0`, `60.5`, `60.0`, `60.0`, `60.0`, `60.0`, `60.0`, `60.5`, `60.0`,
  `60.0` FPS, gap 8.3-16.7 ms, **GPU 1.5 ms of 16.7 ms (9% busy)**. This is a video path
  with the GPU nearly idle, so the result is that video playback holds 60 fps at Serious
  thermal - not a load test, and not evidence about a heavy scene.
- **Back at the login screen, still thermal Serious**: six further samples read `60.0`,
  `60.0`, `60.0`, `60.0`, `60.2` FPS with the GPU back to 5.7-11.0 ms (53% busy). This
  shows the login screen alone holds 60 at Serious thermal. It does **not** explain the
  49.8 fps in-world figure and is not offered as an explanation for it: the world is
  CPU-bound, the login screen is not, so thermal behaviour in one says nothing definitive
  about the other.
- **No new error file and no new crash report** across the whole run: newest error file
  `2026-10-15_20.46.04_Error_4394.txt`, newest crash report `Tolkara-2026-10-22-203503.ips`,
  both predating the run. Audio `errors=0 silence_flags=0` throughout.
- **Independent check from the runtime's own log**: frame 600 -> frame 1800 presented in
  20.003 s = `60.0 fps` (average gap 16.67 ms), matching the HUD.

- **CPU attribution** (instrumented run of the *same installed binary*, launched with
  `--local-game-startup --measure-native`; no rebuild): 25 consecutive 5 s windows at
  the login screen, **thermal Serious throughout**, read `59.90-60.10 fps` (mean
  `60.01`), `gap_avg_ms` `16.65-16.70`, `max_gap_ms` `20.8-25.0`, `gpu_ms` `5.9-11.3`
  with `gpu_load` `0.52-0.54`, and `wait_ms` (drawable wait) `0.01`. The CPU submitted a
  frame in **`cpu_submit_avg_ms` `0.04-0.05`** and at worst **`cpu_submit_max_ms` `0.28`**,
  sampled once per frame (300 samples in every 5 s window), and **`wait_completed` and
  `wait_scheduled` were `0` in all 25 windows** - the main thread never blocked on the
  GPU. So at the login screen the frame is limited by vsync: the GPU has ~7.8 ms of the
  16.7 ms frame unused and the CPU is idle in the submission window. **The CPU is not the
  holdup here**, which is the opposite of the in-world case below (20.0 ms frames while
  the GPU stayed at 7.8 ms). `cpu_submit` measures acquire->commit only, not total guest
  CPU time, so it bounds the submission slice rather than accounting for every
  instruction.
- The instrumented run was then replaced with an ordinary `--local-game-startup` launch,
  so the device was left on a normal run with the HUD showing `60.0 FPS`.

**Limitations.** In a normal run the HUD is the only frame-rate instrument: `0035`
removed the per-frame timing writes, so the log records present timestamps for frames
1, 60, 600 and 1800 only and says nothing about the cinematic window. Samples are HUD
readings from screenshots, taken passively with
`wolkaraforever/tools/pilot.sh view` and `xcrun devicectl device capture screenshot`;
no input was sent to the game. One 20.8 ms gap appeared in a post-cinematic sample - the
known one-frame-one-refresh-late case, still unattributed - and no gap over 50 ms was
seen. **CPU was measured at the login screen only**: a cinematic needs a tap the
operator has to make, so there is no CPU figure for the cinematic window.

**Tool defect found and fixed in the same run.** `pilot.sh state` reported
`guest log says: none` while the client was on its login screen with a live game, because
`session_live` required a `startup_return=PASS` line and the runtime writes that only
when the guest *returns* (`platform/runtime/NativeGuest.m`). The guard was therefore
inverted: a game somebody was in read as "no session" (so `install` would have stopped it),
and a launcher visit within the hour after a session ended read as "live". It now looks for
a guest-start marker with no return after it, which also distinguishes the launcher alone
from a game in progress. The test fixture had encoded the same mistake, which is why the
suite passed over it. While fixing it, a second hole appeared: `copy from` failed twice with
`socket was closed unexpectedly` and left an empty log, and an empty log reads exactly like
"no session" - so the guard now refuses when the app is up and its log cannot be read,
rather than guessing, and `--force` does not override that either.

## Performance under thermal load, on the release build (2026-10-27)

First measurements against the released client (1.60.1.70634, `wowf`), on Dadpad with
Developer service, at the login screen — the only scene reachable without an account.
Full method, limits and the ordered plan are in
[PERFORMANCE_THERMAL.md](docs/PERFORMANCE_THERMAL.md); the tool that produces every row
is `wolkaraforever/tools/perf_sweep.py`.

| configuration | fps | GPU per frame | GPU busy | thermal |
|---|---|---|---|---|
| native (renderScale 1.0) | 60.02 | 9.3 ms | 53% | serious |
| client `renderScale 0.75` | 60.02 | 7.8-7.9 ms | 46% | nominal |
| client `renderScale 0.5` | 60.02 | 5.1 ms | 30% | nominal |
| the app's own "Performance" profile (backing scale 0.75) | 60.02 | **9.9 ms** | 57% | nominal |
| client `DynamicRenderScale` + `targetFPS 60` | 60.00 | 9.0 ms | 53% | nominal |
| `renderScale 2.0` (4× the pixels, GPU-bound) | **23.6** | 75-81 ms | — | — |

What those rows establish: the client's own `renderScale` is the lever that moves GPU
time and, within minutes, the thermal state (serious → nominal); the app's shipped
"Performance" profile does **not** reduce the scene's GPU work; the client's dynamic
scaler did nothing on this scene and paced worst; and 2× supersampling is not survivable,
let alone playable. The in-world frame was **not** measured today.

The in-world 16-20 ms drawable wait identifies a presentation-path problem but does not
by itself prove a 40/48 Hz panel rate: it can also be a drawable-queue or guest-pacing
delay. The app requests `CAFrameRateRangeMake(30, 60, 60)` — Apple's documented route to
30/60 priority for games — and logs the rate of its diagnostic display link
(`wolkaraforever/Bridge/DisplayRate.m`). On the login screen that link targets **16.68 ms
(60 Hz)** while Metal still records 20.8/25.0 ms outliers. This is not in-world proof;
the next valid evidence is an in-world Metal present trace.

## Voice dictation into the game (2026-10-21)

The user extensively validated voice dictation on Dadpad (iPad Pro 12.9-inch, 5th generation,
iPadOS 27) with Developer service and an Xbox Bluetooth pad mapped to Options as Hold to talk.
The **Test Voice** page delivered a transcript, and utterances were typed into the running game:
the recorded login-screen checks produced 21 characters each, sent Return by auto-submit,
dequeued 43 guest key events, returned the audio session to the game, produced no crash report,
and left the app running. The app's own `dictation-target` self-test also reported PASS 2/2.
The recorded evidence covers the exercised iPad/controller configuration; it is not a claim
about every controller model, game field, or device.

## Forever UI operations and the performance HUD (2026-10-22, commit `355b0d8`)

On Dadpad (iPad Pro 12.9-inch, 5th generation, iPadOS 27) with Developer service,
against the installed Forever client 1.60.1 (70450):

- `--selftest=forever-ui` PASS 16/16 on the real `_classic_beta_` tree. It made a
  verified UI backup (`WoW-UI-2026-10-22T03-41-37Z.zip` in `WTF/Backups`), reset
  graphics with every other Config.wtf line byte-identical afterwards, restored
  that backup to a byte-identical Config.wtf, wrote exactly one
  `SET GamePadEnable "1"` line without changing any other line, and restored the
  backup again so the user's files were left as found.
- The optional performance HUD showed live presentation metrics in the client:
  `Frame Rate: 60.2 FPS (12.5 ms)`, with the expansion and position the
  preference store held. `--selftest=forever-ui-clean` then returned the overlay
  preference to its default off state.
- The home page rendered the Add-On Manager, Voice & Input Manager and Performance & UI
  Manager rows in the documented order.

Not verified on the device: the gamepad setting across a full client launch
(the setting was written and read back, and the client launched with the
restored file, but the enable-then-launch sequence was not performed), and the
Files picker presentation (its destination is asserted in the simulator
fixture). Developer-service enrollment failed at the trusted USB handshake on
this iPad; the pre-existing enrollment in the game-bearing bundle still allowed
the client to launch. See `development/validation/355b0d8.md`.

## Latest WolkaraForever gameplay report (2026-10-07)

The developer reports **60 FPS at graphics quality 4 on an iPad Pro M5**
in WoW Forever. Render scale, exact client build and a repeatable benchmark were
not supplied for this latest report; do not infer them from the older quality-2
session below. This confirms reported gameplay performance, not the fresh-download
flow or the latest update-recovery fix. Those require separate device tests.

## iPad validation (2026-10-01)

The [WoW launcher branch](docs/WOW_LAUNCHER.md) was compiled for iOS on 2026-10-03.
The user tested the themed home screen on this iPad and requested automatic
installation of detected patches. This revision implements native CDN updates,
verified data reuse, resumable staging and atomic activation. Synthetic tests
and isolated Mac-copy transactions pass: Forever 1.60.1.70205 selected
1,215,567 standard macOS objects (67,079,188,425 encoded bytes), fetched
248,252,461 missing asset bytes and verified all 143 loose files. The Mac source
installation was unchanged. The user subsequently completed the patch download
on the physical iPad. Readback confirmed version 1.60.1.70205 and an executable
identical to the Mac original (SHA-256). Startup stopped before guest entry:
the loader incorrectly required a DONE marker after the complete rebase stream.
This revision accepts a stream ending at its declared length, retains operand
and target bounds checks, and validates all 241,069 rebases and 3,549 binds of
the readback executable without running it. **Device startup and gameplay after
this fix still need manual confirmation.** Fresh installation is covered only by synthetic
fixtures. AltStore PAL execution remains unproven. These launcher checks do not
extend the gameplay results recorded below.

The 2026-10-07 updater optimization persists verification receipts so ordinary
patches can reuse unchanged CASC segments without rereading all their payload.
The first update without receipts still checks existing content; Settings →
**Verify and repair game files** always forces a complete check. Synthetic
patch/resume/corruption tests, the simulator repair flow and the signed device
build pass. A 16 MiB synthetic warm planning pass reads zero payload bytes;
speed on the physical iPad's full installation remains unmeasured. The first
device trial reported repeated **CASC data changed during the update** while
resuming 70235 → 70245. A follow-up revalidates only a changed segment's trusted
objects before allowing metadata-only recovery; checksum failures still block
activation. Synthetic metadata-change/resume and 64 MiB checkpoint tests pass;
a subsequent physical retry reached `activate` and `complete` in Xcode after
rechecking `data.075`. The logged counters were 67,488,524,145 bytes read and
44,033,527 reused during that adoption/resume pass. This is an observed update
completion, not a warm-patch speed measurement or a post-update gameplay test.
See [persistent verification](docs/WOW_LAUNCHER.md#persistent-verification-2026-10-07).

On 2026-10-06, the follow-up adds an [automatic touch controller](docs/TOUCH_CONTROLLER_PROPOSAL.md)
with a custom UIKit layout, and fixes clipped descenders in the home status.
Real GameController input and connection lifecycle are covered by synthetic
simulator fixtures. This touch-controller revision has **not yet been tested
in WoW on the physical iPad** and does not extend the gameplay report below.

The subsequent WolkaraForever revision adds saved control opacity, separate rear/front
sizes, draggable groups/buttons and reset. Its original UIKit fixture verifies
preferences, bounds, all button/axis events and input suppression during editing;
the settings and editor were also inspected in the simulator. The app now has
its own name/icon and selects the build's startup route without a public picker.
The signed arm64 iOS build and strict signature check pass. The user subsequently
reported native keyboard/slider stalls while WoW and the controller continued
working; beginning the Control Center gesture released the UI. A follow-up fixes
UIKit starvation reproduced with a busy synthetic desktop-event queue and
publishes pending native UI changes after event processing. Regression tests,
manual simulator typing/slider drags and the signed device build pass. The
[UI-pump correction](docs/TOUCH_INPUT.md#native-ui-stalls-while-the-guest-continues-2026-10-06)
did **not** resolve the full device symptom: on 2026-10-07 the user reported
queued keyboard taps released by Control Center / Notification Center. The new
[visible draft editor and tracking-mode follow-up](docs/TOUCH_INPUT.md#visible-draft-and-tracking-mode-follow-up-2026-10-07)
remove per-key native document resets and service UIKit tracking work while the
keyboard/settings are open. Synthetic checks pass; resolution of the device
stall and frame-rate impact remain unverified. The toolbar now stays top center
regardless of keyboard/controller state, with a further optical pointer offset.
The draft's **Replace** action now selects all and replaces the focused field
instead of appending; an empty draft clears it. Reading the field's prior text
is still unsupported. Synthetic replacement/clearing and key-order tests pass;
WoW's handling of Select All on the iPad needs user validation.

On 2026-10-07, the user reported a first-launch failure after installing from
Xcode, followed by a successful launch from the icon. The failed device log
records completed memory preparation and confirmed helper detachment, followed
by an `isLowPower` Objective-C exception on the native iOS Metal device during
initialization. Xcode's launch record enabled `MTL_DEBUG_LAYER=1`; the shared
scheme now disables Metal API Validation to match an ordinary icon launch.
A synthetic Metal-property probe passes in the simulator with validation both
on and off, so it does not reproduce the device failure. The user subsequently
reported that it now works after this correction (2026-10-07).

The subsequent haptics change adds optional haptic feedback for controller and
toolbar buttons, plus one cue per stick-edge crossing with independent radial
hysteresis. Synthetic tests check pulse requests and unchanged controller input;
the physical feel and strength still need testing on the iPad.

Results updated on 2026-10-02 with the Forever gameplay report below.

Experimental support was tested on an iPad Pro M5 / iPadOS 27 with
Developer service. The generic arm64 build installed successfully. Trusted USB
enrollment and the local authenticated tunnel/capability probe passed. The user
confirmed a cold launch after reboot with the iPad disconnected from the Mac.
Network access (Wi-Fi is fine) is required to download and update the game; a
disconnected Mac does not affect a launch.

The user confirmed that Forever starts and works through
the screens described below. Both required AssistiveTouch for the tested mouse
setup. These are manual device observations; the extent of input and gameplay
validation is recorded separately for each client.

### World of Warcraft Forever 1.60.1 (build 70170)

On 2026-10-02 the user confirmed successful login, world entry and about two
hours of gameplay without problems on an iPad Pro M5 / iPadOS 27, using
Developer service. The reported frame rate was 60 FPS at 50% render scale and
graphics quality 2. This is a manual report from the tested session, not a
benchmark across all areas or activities.

The initial setup used a Bluetooth keyboard and AssistiveTouch. The keyboard
was needed to enter account details. With AssistiveTouch
enabled, clicking the mouse wheel (middle button, not scrolling) selected the
controls used to enable controller support; left mouse click did not. The
controller could then navigate the menus. The separate
[touch-input implementation](docs/TOUCH_INPUT.md) now provides an on-screen keyboard
and trackpad with two-finger scrolling. Its synthetic and simulator checks
pass, and on 2026-10-02 the user confirmed the new controls working correctly
in Forever on the same iPad Pro M5 / iPadOS 27. Other-device input testing
remains pending. The two-hour gameplay/performance report above predates
these controls.

The working setup uses the beta's own `portal "test"` setting and the default
`TOLKARA_SYSTEM_ROOTS=YES` for the private build. Earlier attempts rejected
login with `BLZ51900003`. Matching the portal alone did not resolve it; the
initial build also lacked `CompatibilityRootCertificates.plist`. Login and
gameplay were confirmed after rebuilding with that public certificate
resource. The existing certificate-adapter tests passed with ASan/UBSan on
the Mac using all 158 packaged candidates.

Build 70170 was copied over 70124 with current Data files verified by path and
size, and the copied client bundle and metadata verified by SHA-256 readback.
Game files and iPad settings were preserved during the subsequent Tolkara
app update. The original game executable was not modified.

### Palworld 1.0.8

The first native attempt prepared 351,895,552 bytes of executable memory in
209.602 seconds, then stopped before initializers at legacy rebase operation
1,000,001. The loader now bounds rebase work by the loaded image's pointer
capacity instead of a fixed million. A data-only Mac check of the unchanged
executable and its six carried libraries passed: the executable has 1,598,313
rebases and 14,217 binds.

With that fix installed, the next attempt prepared memory in 210.030 seconds,
completed all 5,741 initializers and entered the original main, then stopped.
The log includes unavailable libraries/stubbed imports and an unimplemented
`NSAppleEventManager` call, and ends with Unreal's crash reporter failing to
spawn (`EPERM`). The reporter failure does not identify the preceding fault.
No out-of-memory error was recorded in that runtime log; peak memory and the
original crash cause remain unknown. No game window or gameplay was validated.

## Runtime diagnostics

### Add-on manager (2026-10-14)

The native add-on manager was signed with the configured development identity
and installed on Dadpad (iPad13,9); the current build launches and stays
running. The installed app contains the ZIPFoundation 0.9.20 archive
validator, device-only CurseForge credential storage, a live CurseForge
browse surface (search, sort, category filter, pagination) and
managed-package controls. This is build/launch proof only: interactive Files
import, an approved personal CurseForge key and WoW's AddOns menu have not yet
been exercised on the device, so no package or game compatibility result is
claimed here.

As of 2026-10-16 the parts of that which a fixture can hold are covered by
`wolkaraforever/WoW/tests/test_wow_launcher_app.m`: TOC parsing, store import (including
importing the same add-on twice, which used to delete the installed copy), a
missing TOC, a file the TOC does not list, pin, disable, remove, and the
credentials contract. The device-side list above is unchanged - a fixture is not
a device, and what it covers is the manager's own logic, not WoW reading the
result.

The game launch itself exposed a runtime gap. The guest's `NSFont` class
reference bound to UIFoundation's private `NSFont`, whose selectors are not
AppKit's, so `+[NSFont messageFontOfSize:]` raised during the login UI and the
process ended with no crash report (the guest log's last lines record the
exception). The AppKit adapter now implements `NSFont` as `AKFont` and aliases
the AppKit symbol names in its `ldflags`, as it already did for `NSColor`; the
shipped shim exports the class and a simulator check drives its class methods.
The rebuilt app was reinstalled and relaunched on Dadpad, and with the container
repaired the client now starts: `Client.log` records `Client Initialize` at
18:23:33 and reaches the login screen (`Switching to screen="AccountLogin"`,
with the intro movie at 18:23:40), then a clean `Glues Shutdown` at 18:40:14 when
the user closed it, with no crash report and no CPU-resource diagnostic for the
session. Logging in and gameplay past the login screen are not yet verified on
the device.

The same afternoon the client refused to start at all, showing its own "World of
Warcraft" alert and then exiting cleanly (the launcher ended the session, so it
looked like a crash). Its `Tact.log` recorded the reason: "Corruption detected in
KMT file. (invalid sorted hash) ... Failed to initialize dynamic container.
Error(11): needs repair". Every `.idx` (KMT) file under `Data/data` had been
rewritten at 15:34 and a `05tempfile.idx` was left behind, so an update had been
interrupted by the app's termination, leaving one half-written index generation
and no earlier generation to fall back on. Restoring the complete index set from
the intact Mac copy (98 files covering all 16 buckets and their earlier
generations) plus one valid newest-generation index per bucket let the client
bind the container, run all 13,302 initializers, enter main, play its intro
cinematic with video and audio, and reach the login screen on Dadpad. The launcher's update path still needs
to be checked for this failure mode: an interrupted index write must leave the
container bootable, and older index generations must be kept (or restored) so the
client can roll back.

The launcher now repairs that state instead of leaving it to a manual copy of the
index set. The client's own interrupted index commit leaves a truncated
generation as a bucket's newest, and TACT then refuses to bind that mapping table,
so the next launch aborts with the client's own alert. Before the guest runs,
`runNativeGame:` rewrites each bucket's newest generation from the newest
generation that validates and carries rows, using the same validity checks the
CASC store applies when it opens, and removes the client's leftover
`<bucket>tempfile.idx` (`TKWoWCASCRepairIndexGenerations`, `wolkaraforever/WoW/CASC.m`).
Verified on Dadpad by planting the exact damage and launching three times in a
row: each launch from a planted truncated generation (buckets `0b` and `0c`) logged
the rewrite and reached the client's intro cinematic with no TACT error and no
NeedsRepair, and a fourth relaunch after killing a running session needed no
repair at all.

The Metal adapter no longer references a `BCTextures.m` fallback. That file never
existed in the repository, and clean shim builds failed to link on the dangling
`AKInstallBCTextureFallback` symbol (see
`build/black-screen-triage/upstream-gpu-identity-test.log`) while cached shims
kept the app building, so the add-on commit removed the reference. Whether the
guest needs BC-texture handling behind the Mac-style GPU identity the adapter
reports remains an open compatibility question.

A device report said the Add-on Manager's search field raises no keyboard. The
field does take focus: the fixture now pushes the manager into a window exactly
as the launcher does and confirms the search field is hit-testable and becomes
first responder. A plain text field behaves the same in the headless simulator,
which presents no software keyboard at all, so that probe cannot separate app
from environment. Nothing in the app suppresses text input: the launcher has a
single key window when the manager is open, the AppKit adapter installs no
responder or event swizzles, and the manager is unreachable after a guest
session. An attached hardware keyboard is the remaining explanation, as iPadOS
keeps the on-screen keyboard hidden until the keyboard key or Command-K is
pressed; this is not independently confirmed on the device.

On 2026-09-26, `--sparse-memory-probe` passed on the iPad Pro M5 / iPadOS 27.
Tolkara's own assembly used 112 GiB of software address ranges and completed
18,600 scalar, SIMD, addressing and atomic fault/resume operations, using
96 KiB of backing pages.

An entry records what one person observed. It is not a promise that the
application will keep working, and it says nothing about whether its publisher
permits it: read "Online games and account risk" in the [README](README.md).
