# Evidence and work packages

## Audit method

The reference was read at commit `7acb2e1618a5`, not inferred from marketing copy.
Repository metadata, its complete current tree, its commit history and recent workflow results
were inspected. The audit found no exact non-generic source blob shared with WolkaraForever and
no reference to WolkaraForever or its contributors. Its `spguest_tlv.S` is a near-verbatim
renaming of Tolkara `GuestTLSArm64.S`; Slashplayed documents that derivation. That fact is a
licensing boundary, not a candidate port.

| Reference evidence | What it demonstrates | WolkaraForever comparison |
| --- | --- | --- |
| `apps/companion/Sources/Diagnostics.swift` | ZIP staging, filename policy and deliberate identifier/token scrubbing. | `Shell/WolkaraForeverLog.*`, `pilot.sh` and `device_log.sh` already redact and retrieve logs, but do not create one user-shareable support artifact. |
| `apps/companion/Sources/Onboarding*.swift`, `SetupStatus.swift` | A repeatable prerequisite workflow that preserves failures for diagnostics. | `preflight.sh`, `device_variables.sh`, `install_prerequisites.sh` and `FROM_ZERO.md` have the facts but not a single persistent status model. |
| `.github/workflows/ci.yml`, `codeql.yml` | Recent PR/push checks include CodeQL on Linux. | `REPOSITORY_WORKFLOW.md` documents why the previous hosted macOS lane was removed; Linux static analysis can be evaluated separately. |
| `apps/companion/Sources/Device.swift`, `docs/guide.md` | Model gating, explicitly untested labels, capacity estimates and first-start/update explanations. | `COMPATIBILITY.md`, device scripts and exact-SHA records are rigorous but fragmented for an end user. |
| `apps/client/spcdn.*`, `docs/architecture.md` | Device-side program/data acquisition and small update flow. | `WoW/Updater.*` already has CDN selection, durable resume, hashes, atomic activation and cancellation; streaming would alter those invariants. |
| `apps/companion-rs`, `docs/setup-without-a-mac.md` | A Windows/Linux host experiment with self-managed Apple-ID provisioning. | No equivalent exists. It creates a credential, certificate, pairing and support perimeter outside the existing macOS/Xcode route. |
| `apps/client/spguest.*`, `spjit.m`, helper code | Custom loader and external helper flow. | Duplicates the problem already solved by Tolkara's runtime plus its three documented execution modes; no adoption value shown. |

## A1 — Support bundle

**Goal:** Export a small, redacted ZIP that a user can attach to an issue without manually
collecting device logs.

**Own:** product-layer diagnostics and `wolkaraforever/tools/`; do not change `platform/`.

**Design:** Create a staged directory containing only a versioned manifest, source SHA,
sanitized app log, safe pilot/preflight verdicts, selected edition/locale in non-identifying
form, and the existing validation record identifier if present. Scrub team IDs, UDIDs, serials,
hostnames, paths outside the app container, pairing material, credentials, API keys, tokens and
raw game files. Use an allow-list, byte/entry caps, a random staging name and an atomic ZIP
write. The UI must preview exactly what is included and warn that free-form user descriptions
can still contain personal data.

**Tests:** unit tests for every redaction class, archive traversal/symlink refusal, cap behavior,
failed staging cleanup, stable manifest schema and a fixture proving no known secret reaches the
ZIP. `check_docs.sh`; required simulator fixture for the UI. A physical Device Hub export and
inspection is required before claiming live support availability.

**Reject if:** an acceptable export cannot be defined without including device identifiers,
pairing records or game data.

## A2 — Setup status and repair routing

**Goal:** Turn existing read-only prerequisites into a durable status checklist.

**Design:** Define a versioned, redacted `PreflightResult` schema produced by the existing tools.
The launcher may display status and copy a repair command; only the user runs an action that
alters Xcode, signing, pairing, the device, data or a live session. Include source SHA, execution
mode, failure category and next safe action. Do not embed shell output blindly.

**Tests:** schema parsing, localization, unavailable-tool behavior, stale-result labeling, no
device identifiers in persisted results and both required simulator screenshots. A physical
preflight display may be documented only after Device Hub interaction ends on normal home.

## A3 — Linux-safe hosted checks

**Goal:** Restore value from hosted CI without repeating the unavailable macOS-runner failure.

**Design:** Start with a separate workflow for Markdown/link checks, Python syntax/unit tests,
shell syntax/static analysis where dependencies are available, action pin review, and CodeQL for
languages GitHub can analyse without building iOS targets. Pin actions to reviewed SHAs; use
read-only permissions by default; never run fork code under `pull_request_target`; make a skipped
required check impossible. Keep Xcode, simulator, device and exact-SHA validation local.

**Proof:** ten ordinary runs and one fork PR complete without manual intervention; then document
which check is required in the ruleset. A runner acquisition failure means the lane is removed or
made non-required, not ignored.

## A4 — Compatibility ledger

**Goal:** Present current evidence without converting it into a support promise.

**Design:** Add a source-controlled schema that records exact SHA, execution mode, game build,
device model, OS, date, test type and outcome. Generate the user-facing table from that schema and
label unknown combinations “not tested”; never auto-promote a simulator result to a device result.
Existing `COMPATIBILITY.md` records are migrated only after manual review.

**Proof:** generator determinism, malformed-record rejection, every generated entry links to its
evidence, and `check_docs.sh` verifies output.

## A5 — Install estimates

**Goal:** Before a user starts, show known download size, available-space requirement, estimated
time range and the conditions that make them uncertain.

**Design:** Derive values from signed/validated manifest metadata and observed transfer rate only;
never claim a precise duration from a stale measurement. Treat locale, existing verified bytes,
region, storage headroom and network state separately. Preserve the current cancellation and
atomic-activation behavior.

**Proof:** fixtures for zero/unknown speed, missing capacity, locale changes, resumed downloads,
network change and low-space refusal; two matrix simulator UI fixtures; device observation only
after a real install through the approved tools.

## R1 — Progressive data acquisition spike

**Question:** Can Forever be playable from a verified minimal file set while additional archives
arrive without corrupting the game store or violating the no-live-write guard?

**Exit criteria:** a disposable fixture store proves manifest completeness rules, all writes are
staged and atomic, offline/restart/cancel recover correctly, and `push_game.sh`/install tools can
detect the state. No real game profile or release UI is changed during the spike.

## R2 — Build-only update spike

**Question:** Can a newer compatible executable and metadata be staged independently of all data
while retaining verified rollback?

**Exit criteria:** signed CDN metadata, hash validation, compatibility classifier, old-build
fallback, no overwrite of a running/writing store, and a negative test for every malformed or
mixed-version state. This is not permission to patch or re-sign the executable.

## R3–R5 — Scope decisions

These require a maintainer decision before code is written.

- **R3 editions:** one new profile per edition, no shared mutable store by default, edition-specific
  CDN/build fixtures, input/UI review and live evidence.
- **R4 Vision Pro:** a separate target and accessibility/input contract, simulator strategy, headset
  pairing/install flow and physical headset evidence. Do not reuse iPad screenshots or claims.
- **R5 Windows/Linux companion:** threat model for certificates, Apple-ID tokens, key storage,
  device pairing and updates; reproducible packaging; support ownership; and independent security
  review. Free-team renewal and anisette services are explicitly out of scope.

## Explicit non-adoptions

Do not copy `spguest`, `spjit`, its helper, its signing/Apple-ID workflow, LocalDevVPN integration,
or any source from Slashplayed. They provide no demonstrated advantage over the protected Tolkara
architecture and would require separate licence review. Any future comparison with that source
must preserve the Tolkara copyright notice and MIT text for material derived from Tolkara.
