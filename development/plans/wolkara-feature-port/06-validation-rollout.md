# Phase 6 — Validation, migration and rollout

## Per-PR baseline

1. Start on current `main` in one worktree and record `git status`.
2. Add the focused regression before the behavior change whenever practical.
3. Run the owning focused command, then `wolkaraforever/tools/check_layers.sh`.
4. Run `wolkaraforever/tools/check_docs.sh` whenever user/developer behavior or
   a command changes.
5. Do not run broad/device validation as a substitute for a failing focused test.

## What “done” means

Compilation is not completion. Source tests prove data rules; **both required
simulators** prove UIKit integration and first-class Duo parity; Device Hub,
when available, supports only actual physical controller, keyboard, microphone
and launcher claims. A simulator cannot prove physical controller timing, and a
device screenshot cannot prove malformed archive rejection. Preserve
device/mode/config with every performance result and compare p50/p95/p99 under
matching conditions. Generated reports, captures and screenshots remain local
and are cleared before handoff; summarize their result without attaching/linking
them in the PR.

## Required test matrix

| Feature | Required dual-simulator checks | Optional physical evidence |
| --- | --- | --- |
| Controller path | voice/router and Controller Manager fixtures | mapped claimed/unclaimed press timing on iPad Pro 12.9-inch (5th generation) |
| Composer/keyboard/voice | `test_voice.sh`, `test_touch_controls_ui.sh --self-test`, translation simulation | Device Hub open/edit/send/cancel/language sequence |
| Touch Controller 2 | touch gamepad/direct-camera suites, translation simulation | Device Hub gesture and controller coexistence |
| Add-ons | archive + launcher suites, loopback provider fixture | safe user-owned install/update/readback |
| Reliability | owning updater/authorization/runtime suite | coordinated install/startup evidence only where user-visible |

Name the simulator: **iPhone Duo** or **iPad Pro 13-inch (M5)**.  Device claims
name the physical **iPad Pro 12.9-inch (5th generation)** and exact source SHA.

## Migration rules

- New settings are versioned under `WolkaraForeverConfig`; malformed values fall
  back safely and are surfaced in diagnostics without printing sensitive text.
- Existing voice mappings remain unclaimed and retain their delivery mode.
- Existing gamepad layouts migrate to Full; Simple starts from product defaults.
- Existing managed add-ons retain API-provider records. Browser records include
  final URL and digest; Files/unmanaged records remain visible/managed with an
  explicit unavailable-update state until linked. No record exposes WebKit
  credentials.
- Composer is feature-flagged initially, preserving classic direct dictation.

## Rollout gates

1. Simulator feature proof.
2. Record physical Device Hub status; when run, return the app to normal home
   screen and running. Do not block release for an unavailable physical run or
   describe it as passed without one.
3. Small opt-in release with diagnostics counters but no transcript/audio capture.
4. Review measured p95/p99 controller-to-Composer and failure/restore outcomes.
5. Make defaults only after reproducible evidence; retain a one-release rollback
   path for Composer and controller claim behavior.

## Documentation deliverables

Update `development/technical/FEATURES.md`, relevant user guides, configuration
reference, changelog and `COMPATIBILITY.md` only with observed behavior.  Record
device evidence through the project validation workflow; do not copy source
repository claims.
