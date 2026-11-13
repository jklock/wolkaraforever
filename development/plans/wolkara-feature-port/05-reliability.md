# Phase 5 — Reliability improvements

Each item is independently releasable after a reproduction.  Do not import a
source patch merely because its title is plausible.

## What, why and how

Reliability features fail closed: an unknown capacity answer, unverified trust
record, missing manifest, lifecycle ambiguity or inactive-rendering failure must
produce a recoverable state, not a guess or an unbounded retry.  Every repair is
idempotent and stays inside the existing update/authorization owner.  This is why
each item begins with a regression fixture and ships separately: a fix for startup
must not quietly change game-data recovery or developer authorization.

## Storage accounting

**Owner:** `WoW/Updater.m`, `WoW/tests/test_wow_update.m`.

Measure whether the current free-space gate excludes reclaimable capacity needed
for a safe install.  If so, use the documented important-usage capacity API,
retain conservative failure behavior when unavailable, and test low/free/
reclaimable/error cases.  Do not claim install success until actual write space
is verified.

The UI distinguishes immediately free space from potentially reclaimable space;
the latter permits an attempt but never represents a guaranteed successful write.

## Enrollment recovery after reinstall

**Owner:** `Bridge` authorization overlays, pairing-storage Swift tests and
`Shell/main.m` integration.

Read existing trust only after verifying its device identity/fingerprint.  Never
overwrite a valid unrelated enrollment, log pairing material, or relax normal
authorization checks.  Add stale, matching, mismatching and malformed-record
tests before adding a one-time recovery path.

Recovery records only outcome reason and verified reference; pairing material
never enters Documents, logs, fixtures or source control.

## Responsive native startup

**Owner:** narrow patch around `runtime/GuestWait.*`, `runtime/NativeGuest.*`,
launcher startup activity and an overlay test.

Reproduce rotation/resize/scene-state change while startup waits.  Pump only
the lifecycle work necessary to keep UIKit responsive; do not re-enter guest
events or alter guest timing. Add startup-sleep and fold/rotation fixtures on
both required simulators, then physical iPad launch evidence when available.

## Verification/recovery gaps

**Owner:** `WoW/CASC.*`, `Updater.m`, `WoWViewController.m`.

Turn source bootstrap-manifest and stale-artifact claims into fixtures against
the current recovery system.  Add only missing validation/repair branches,
preserving update-lock order and CDN metadata repair.

## Inactive Metal submission

**Owner:** `Bridge/BackgroundPacing.m`, relevant Metal overlay/patch, background
tests.

The current product caps background pacing.  First reproduce rejected/stalled
inactive GPU work.  If confirmed, pause drawable acquisition and command-buffer
submission while inactive, preserve pending caller-owned work, resume once on
foreground, and bound diagnostic error records.  Do not make a background-run
guarantee or change foreground pacing without measurement.
