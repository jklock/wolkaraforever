# App completion plan

Status: active. Updated 2026-10-29.

## Scope and success boundary

This plan closes source, simulator, documentation, and non-game device gaps in
WolkaraForever. External JIT and full-game launch, login, performance, and
gameplay validation are explicitly out of scope: they require testing the full
game, which is not available for this work.

Success is a clean, exact-SHA candidate with all applicable source and simulator
checks passing, current documentation, and any available device checks recorded
at their actual evidence level. It is not a claim that the full game works.

## Workstreams

### 1. Make the evidence truthful

1. Remove or update every document that calls `fbd69f8` the current revision.
   Do not replace it with a new static SHA unless it is a dated validation
   record; general documentation must describe the current branch without
   becoming stale after the next commit.
2. Reconcile the conflicting Developer-service statements: some guides say
   relaunch and reboot work, while the architecture record says the production
   preparation service and launch UI are not fully connected and cold recovery
   is unproven.
3. Keep a four-level evidence label in user and engineering documentation:
   source, simulator, device-script, and human full-game. Do not promote a
   result between levels.

**Checks:** `wolkaraforever/tools/check_docs.sh`, `git diff --check`.

### 2. Complete and harden the supported Developer-service path

1. Trace the existing enrollment, protected pairing store, discovery, tunnel,
   preparation manager, and launcher handoff. Identify the concrete missing
   production configuration and UI-to-session handoff before changing code.
2. Implement only the missing handoff/configuration through a maintained patch
   or `wolkaraforever/` overlay; never edit `platform/`.
3. Preserve explicit failure states for missing enrollment, untrusted peer,
   unavailable developer image, insufficient arena, and incomplete detach.
   Never fall back to unsigned guest entry or weaken authentication.
4. Add focused synthetic tests for successful handoff and every blocked state.

**Checks:** owning authorization tests, `wolkaraforever/tools/check_layers.sh`,
`wolkaraforever/tools/test_emulation.sh`.

### 3. Finish app-owned behavior coverage

1. Run and repair the owning suites for launcher/install/update/repair,
   backup/restore, add-ons, locale, touch, on-screen gamepad, controller
   routing, voice, and local-service retry.
2. Add a fixture for each uncovered error or recovery path found while tracing
   the Developer-service handoff. Fixtures must not use imported game files or
   automate gameplay.
3. Keep experimental adapters and launch flags hidden/off by default until a
   separate device-validation effort exists. Do not label them supported.
4. Keep voice history and transcript post-processing out of this completion
   scope. They need a separate retention/privacy and product decision.

**Checks:** `test_wow_launcher.sh`, `test_forever_ui.sh`,
`test_touch_controls_ui.sh`, `test_touch_gamepad_ui.sh`, `test_voice.sh`,
`test_local_service_retry.sh`, and `test_translation_sim.sh` when adapters
change.

### 4. Non-game device acceptance, if device authority is available

1. Start read-only with `preflight.sh --require-app` and `pilot.sh state`.
2. Use the guarded WolkaraForever installer only. Do not replace a running
   installation without explicit authority, and never use raw device file
   commands.
3. Run the Mac-drivable checks: fresh-install preservation, config
   import/refusal, notices, background/foreground, app self-tests, and
   crash/error-file inspection.
4. Exercise only WolkaraForever's own fixture screens for touch, controller,
   and voice wiring. Record them as device-script or human fixture evidence,
   not full-game evidence.
5. Leave the iPad on the normal home screen with WolkaraForever running.

**Checks:** `wolkaraforever/tools/device_matrix.sh`, `pilot.sh selftest input`,
`pilot.sh selftest voice`, `pilot.sh selftest dictation-target`.

### 5. Candidate and release boundary

1. Keep each workstream on a short-lived, single-purpose branch/worktree:
   documentation, Developer-service implementation, test coverage, and device
   evidence are separate pull requests.
2. Rebase each candidate on `main`; run its narrow tests first, then required
   layer and documentation gates.
3. Commit before writing validation evidence. Run
   `wolkaraforever/tools/validate.sh --full` on a clean tree. Add `--device`
   only for the authorized non-game device sequence.
4. Update `COMPATIBILITY.md` with the exact candidate SHA and only the checks
   that actually ran. State full-game testing, JIT, and performance as not run.
5. Do not tag or call this a general release until a future, separately
   authorized full-game acceptance effort completes.

## Completion checklist

- [ ] General documentation no longer claims an obsolete source SHA.
- [ ] Developer-service implementation and failure paths are source-tested.
- [ ] All app-owned source and simulator suites pass on the candidate SHA.
- [ ] Layer and documentation gates pass.
- [ ] Clean validation record exists for the candidate SHA.
- [ ] Non-game device results, if run, name the device, iPadOS, mode, and SHA.
- [ ] Compatibility documentation makes no JIT or full-game claim.
