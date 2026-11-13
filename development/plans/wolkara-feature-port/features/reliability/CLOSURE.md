# Reliability closure

Source SHA for every record: `b801a8b6e29f4935bc4eb63a564e21e698dd3cb7`.
Five candidates were carried in [PLAN.md](PLAN.md) and [TASKS.md](TASKS.md). Each is
closed here as **fixed**, **covered** by a named current test, or **not reproducible**
after the evidence attempt written beside it. There is no open item and no deferral.

The two simulators are the requirement, and every result below names the one that ran.
No physical iPad was used for this closure: no candidate needed a physical run to be
classified, and none is claimed.

## 1. Reclaimable storage accounting - covered

- **Symptom (source claim):** a free-space gate that counts only raw free blocks can
  refuse a large install that iOS would have made room for by reclaiming caches.
- **Owner:** `wolkaraforever/WoW/Updater.m`; test `wolkaraforever/WoW/tests/test_wow_update.m`.
- **Boundary that would fail:** `-[TKWoWUpdater checkStorageAtPath:missingBytes:looseBytes:error:]`.
- **Affected user data:** none. A refusal is the failure mode; no file is written.
- **Rollback:** not applicable - nothing changed.

The current gate already answers the question the source raised. It asks
`NSURLVolumeAvailableCapacityForImportantUsageKey` first, takes the raw filesystem size
whenever that number is unavailable *or* smaller (a silent zero must not hide blocks the
filesystem can already use), keeps a 1 GiB reserve, and refuses with the measured figure
when the answer is unusable rather than guessing. `TestStorage` in `test_wow_update.m`
asserts the reclaimable case (115 GB important vs 30 GB raw free), the low case with the
reported numbers in the message, a silent zero, an unavailable important-usage service, an
unavailable filesystem size (including that the message is not "Not enough storage"), a
negative value, `NSNull`, the exact boundary, and both overflow directions.

Measured: `wolkaraforever/tools/test_wow_launcher.sh` (Mac, ASan/UBSan) -
`WoW updater PASS: unchanged data reuse, archive ranges, cancel before activation, durable
resume, atomic activation, settings/addon preservation, superseded build and malformed
input.` The storage cases are `assert`s inside that binary.

## 2. Enrollment reference after a reinstall - fixed

- **Symptom:** for the current product, "not enrolled" is decided from one fact: the
  marker `TKEnrolledDeviceIdentifier` that the launcher reads in
  `-[AKHostSceneDelegate preflightBlockedState]`. That marker lives in the app container
  (`UserDefaults`); the trust record it points at lives in the device Keychain. Reinstalling
  the app deletes the container and keeps the Keychain, so a device that is still verifiably
  enrolled is refused, and only a new enrollment import puts the marker back.
- **Steps that reproduce it:** install the app, enrol, delete the app, install the same
  build again. Measured on both matrix simulators by
  `wolkaraforever/tools/test_enrollment_reference_sim.sh`, which does exactly this with
  `simctl uninstall` / `install` around the probe.
- **Boundary that failed:** the launch never reaches a route because
  `WKAuthorizationPreflightState(nil)` is `notEnrolled`; that function and its "a missing
  device identifier must block before any route starts" assertion are covered by
  `wolkaraforever/Bridge/tests/test_authorization_blocked_state.m`, and the other half -
  that the record is still there and nothing else restores the marker - is now asserted in
  the probe (`marker absent and record present before recovery`).
- **Owner:** authorization bridge; new
  `wolkaraforever/Bridge/EnrollmentReference.swift`, overlaid to
  `authorization/Storage/EnrollmentReference.swift`, called once per launch from
  `wolkaraforever/Shell/main.m`.
- **Affected user data:** the trust pin is read and never written; the only write to
  user-visible state is the marker, and only after the record it names verifies.
- **Rollback:** remove the overlay entry and the one call. The reference is an inert
  second Keychain item; nothing else reads it, so an app without the file behaves exactly
  as before. No data migration is needed because no existing record changes.

What it does, precisely:

- The reference is a second item under a fixed account in the same access group and a
  service of its own (`local.tolkara.pairing.enrollment.reference.v1`). It holds the
  record's device identifier and the record's public fingerprint - no keys, no pairing
  material - and it is looked up by that fixed account, so the user's keychain is never
  enumerated.
- A launch that still has its marker derives (or repairs) the reference from the record the
  marker names. That is what makes it survive a reinstall that happens afterwards.
- A launch without a marker restores it only when the reference parses, the record it names
  loads, and the fingerprint matches. A marker that exists is never replaced, a record that
  will not load is never overwritten, and a stale or mismatching reference restores nothing.
  A stale or malformed reference is removed (it can never be used); a mismatching one is
  left alone.
- One bounded line reaches the app's log, under the `enrollment` tag, with a closed
  vocabulary: `event=reference outcome=nothing|current|recorded|recovered|refused
  reason=...`. No identifier, fingerprint, key or path can travel in it, and a test asserts
  the vocabulary and the absence of any material.

Measured:

| Check | Device | Result |
| --- | --- | --- |
| `test_authorization_handoff.sh` (adds the decision table) | Mac, ASan | PASS - `Enrolment reference PASS: matching, backfilled, repaired, recovered, stale, mismatching, malformed, oversized, invalid marker, unreadable record, never-replaced marker and the one-item store all behave as required` |
| `test_enrollment_reference_sim.sh` | iPad Pro 13-inch (M5) | PASS - 12 cases, reinstall included |
| `test_enrollment_reference_sim.sh` | iPhone Duo | PASS - 12 cases, reinstall included |
| `check_layers.sh` | Mac | PASS - 61 patches, 185 overlaid files, 583 localization keys |

The simulator run's own lines (both devices identical in shape):

```
PASS write: reference derived from the verified record, pin untouched
PASS recover: marker absent and record present before recovery; recovered from it; pin unchanged
PASS marker: the recovered marker is read back by a later process
PASS malformed: malformed reference refused and removed, no marker restored
PASS stale: stale reference refused and removed, no marker restored
PASS mismatch: mismatching reference refused; pin and marker unchanged
PASS invalid-marker: unusable marker refused and left untouched
PASS clean: fixture record, reference and marker removed
```

## 3. Responsive native startup - not reproducible

- **Symptom (source claim):** a rotation, resize or fold while startup "sleeps" leaves the
  scene unserviced.
- **Owner:** `runtime/GuestWait.c`, `runtime/NativeGuest.m`, launcher startup.
- **Boundary that would fail:** the one main-thread wait the runtime owns,
  `gw_wait`, and the launcher's pre-guest waits.
- **Affected user data:** none.
- **Rollback:** not applicable - nothing changed.

Attempt and what it measured:

1. **No sleep exists on the path.** The launcher's pre-guest waits are all main-queue work:
   the route wait and provider reply in `-[TKLocalAuthorization startAndProbeLocalRoute:]`,
   the cloud prepare on a worker queue, the container hash on a worker queue. There is no
   `sleep`, `usleep` or blocking semaphore in `Shell/main.m`, `WoW/WoWViewController.m`,
   `Bridge/` or the startup portion of `runtime/`. The startup activity view draws from its
   own queue, through its own `CATransaction`, precisely because the final block is the
   guest's own execution.
2. **The runtime's one main-thread wait already keeps the scene serviced, and only there -
   covered by the runtime's own suite.** `tools/test_emulation.sh` already runs
   `tests/test_guest_wait.c` (chunks the completion wait at 10 ms, pumps once per chunk,
   and passes worker threads, explicit deadlines, other operations, a missing pending
   function and native errors through unchanged with their own errno) and
   `tests/test_guest_wait_runloop.c` (a **real** kernel job wait that can only finish by
   running main-run-loop work during a shader pause, with an alarm so a regression fails
   rather than hangs). `wolkaraforever/tools/test_emulation.sh` (Mac, ASan/UBSan): PASS.
3. **A live startup completes.** `TOLKARA_MODE=local-signing wolkaraforever/tools/run.sh sim`
   reaches the guest on both simulators (iPad Pro 13-inch (M5) and iPhone Duo both print
   `[host] native first initializer returned` after
   `signed-image container=~/Documents/LocalSigning/page-container.dylib`), with the app's
   own lifecycle notifications delivered before and after it.

What was **not** attempted, stated rather than implied: a rotation or fold *while the guest
holds the main thread*. The simulator has no fold, the UI fixture's pages are
landscape-only by design (changing that would move every reviewed baseline), and the
remaining window is the guest's own event loop - re-entering guest events to service it is
what the plan and the runtime's contract forbid. So the claimed defect is not reproducible
here: the layer adds no sleep of its own, and the pump it relies on is already asserted
against a real kernel wait. No claim is made that a scene change during a guest-held startup
is impossible.

## 4. Verification and recovery gaps - covered

- **Symptom (source claim):** a missing bootstrap manifest or a stale artifact is not
  detected or repaired before launch.
- **Owner:** `wolkaraforever/WoW/Installation.m`, `CASC.m`, `Updater.m`, `WoWViewController.m`.
- **Boundary that would fail:** `TKWoWInspectInstallation`,
  `TKWoWCASCRepairIndexGenerations`, the verification receipts.
- **Affected user data:** the installation; every branch below is fail-closed or repairs in
  place, and the tests assert the user's settings and executable are untouched.
- **Rollback:** not applicable - nothing changed.

Current behaviour, each with its assertion:

| Case | Behaviour | Asserted by |
| --- | --- | --- |
| No installation | `TKWoWInstallationMissing` | `test_wow_installation.m` |
| Missing `.build.info` | `TKWoWInstallationNeedsRepair`, nothing written | `test_wow_installation.m` |
| Oversized or ambiguous metadata | `NeedsRepair` with the reason, never a guess | `test_wow_installation.m` |
| Legacy metadata without `CDN Hosts`/`CDN Servers` | `metadataNeedsRepair`, repaired by the updater's `writeBuildInfo` | `test_wow_installation.m` |
| Executable bytes changed | `NeedsRepair`, file left as it is | `test_wow_installation.m` |
| Truncated CASC index generations | repaired before the guest runs (`TKWoWCASCRepairIndexGenerations` in `runNativeGame:`) | `test_wow_verification.m` (`repair` in its verdict) |
| Stale verification receipt | cold payload re-read; changed, deleted, truncated, symlinked and appended data never reuse a receipt | `test_wow_verification.m` |

Measured: `test_wow_launcher.sh` (Mac, ASan/UBSan) -
`WoW installation PASS: missing, current, locale mismatch, outdated, ambiguous/missing
metadata, changed bytes, path bounds; no writes.` and
`WoW verification PASS: cold payload reads=100; warm payload reads=0; clone rebinding, full
keys/extents, repair, changed/deleted/truncated/symlink data, malformed records,
metadata-only recovery, append corruption, 64 MiB checkpoint/resume.`

## 5. Inactive Metal submission - not reproducible

- **Symptom (source claim):** while the app is inactive, GPU work is rejected or stalls, so
  drawable acquisition and command-buffer submission should be paused.
- **Owner:** `wolkaraforever/Bridge/BackgroundPacing.m` (overlaid into the Metal adapter).
- **Boundary that would fail:** `-[CAMetalLayer nextDrawable]`, which the guest's renderer
  goes through and which the adapter already wraps.
- **Affected user data:** none.
- **Rollback:** not applicable - nothing changed.

Attempt: `wolkaraforever/tools/test_background_pacing_sim.sh` builds
`wolkaraforever/Shell/tests/test_background_pacing.m` with our own
`translation/Metal/BackgroundPacing.m` and runs it in the simulator. The fixture takes a
real `CAMetalLayer` on the simulator's Metal device, installs the hook twice (a second
install must not wrap the method again), measures acquisition while active, posts the same
`UIApplicationWillResignActiveNotification` the app receives, measures again, posts
`UIApplicationDidBecomeActiveNotification` and measures the first frame and the resumed
rate. It counts nil drawables instead of assuming they are frames.

| | iPad Pro 13-inch (M5) | iPhone Duo |
| --- | --- | --- |
| Active | 120.2 acquisitions/s, slowest 13.9 ms, 0 nil | 120.7/s, slowest 10.4 ms, 0 nil |
| Inactive | 5.4/s, slowest 202.4 ms, 0 nil | 5.5/s, slowest 202.1 ms, 0 nil |
| First frame after foregrounding | 9.1 ms | 9.1 ms |
| Resumed | 120.0/s, slowest 9.1 ms, 0 nil | 119.9/s, slowest 9.7 ms, 0 nil |

No acquisition was refused, none stalled beyond its own 200 ms interval, and the resume
cost is one 5 ms wake slice rather than the background interval. With that measured, pausing
drawable acquisition and submission would remove frames the current cap already paces
safely, so no change was made.

Stated rather than implied: this measures the pacing contract on an off-screen layer in a
spawned process, not a guest session with the game rendering in the background, and not a
physical device. It is the same entry point and the same notifications, and it is the
evidence this environment can produce; it does not prove that no guest can ever see a
rejected drawable.

## Gates

| Gate | Result |
| --- | --- |
| `check_layers.sh` | PASS |
| `check_docs.sh` | PASS |
| `test_wow_launcher.sh` (Mac, ASan/UBSan) | PASS |
| `test_emulation.sh` (platform suite, then every layer suite) | PASS - exit 0; 186 pass lines, including `real kernel job wait remains responsive to main-run-loop work during shader pause` and `shader-pause wait pump, delayed pending state, native wake/error and finite-timeout preservation` |
| `test_authorization_handoff.sh` (Mac, ASan) | PASS |
| `test_translation_sim.sh` - iPad Pro 13-inch (M5) | PASS |
| `test_translation_sim.sh` - iPhone Duo | PASS |
| `test_enrollment_reference_sim.sh` - both simulators | PASS |
| `test_background_pacing_sim.sh` - both simulators | PASS |

Baselines: none re-recorded. No launcher page, label, placement or screenshot changed, so
there is no UI-review amendment for this work and `wow-*`/`voice-*`/`addons-*` baselines are
untouched.

Generated output (build logs, reports, probe reports) stays in ignored
`build/`; nothing from a run is committed.
