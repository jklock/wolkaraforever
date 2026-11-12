# Slashplayed adoption audit

> **Snapshot:** `paulstraw/slashplayed` `7acb2e1618a5` (2026-11-12). This is an
> adoption plan, not permission to copy source. Each work package begins from
> WolkaraForever's current behavior and may use only independently implemented
> code or code whose licence and notices have been verified.

Reference: [Slashplayed at the audited commit](https://github.com/paulstraw/slashplayed/tree/7acb2e1618a50a8c47608cf6943f6e3b3c6fccc3).

## Finding

Slashplayed is not a usable upstream for WolkaraForever. Its product is a separately
implemented launcher with a different runtime, signing model, device set, and support
contract. It does, however, expose five worthwhile product and engineering directions:

1. a single scrubbed diagnostics export;
2. setup that diagnoses and explains prerequisites in one place;
3. reliable, inexpensive hosted checks for code that can be checked on Linux;
4. a model- and build-specific compatibility ledger; and
5. a deliberate feasibility programme for additional game editions, form factors and
   host operating systems.

The table below is the decision register. `Adopt` means an independently implemented
WolkaraForever change is warranted. `Research` means no product claim or implementation
commit may start before the stated spike proves the premise. `Reject` means do not port
the approach.

| ID | Source idea | Decision | Why |
| --- | --- | --- | --- |
| A1 | One-click scrubbed diagnostic ZIP | Adopt | Our redacted device log, pilot output and validation records are useful but require several manual commands. A bounded export is better support intake. |
| A2 | Repeatable setup assistant | Adopt | `preflight.sh` has the checks, but its terminal output is not a persisted, user-facing checklist with repair actions. |
| A3 | PR CodeQL and Linux-safe CI | Adopt | The repository has no hosted CI because its former macOS lane could not acquire a runner. Static checks and CodeQL do not need a macOS runner. |
| A4 | Device/capability matrix with explicit “untested” wording | Adopt | Our fixed simulator matrix and exact-SHA records are stronger evidence, but a generated compatibility view would make the current device/build/execution-mode limits easier to understand. |
| A5 | Storage, first-start and update estimates | Adopt | The launcher already knows manifest sizes, download progress and selected locale. It should expose estimates and their uncertainty before an install. |
| R1 | On-demand game-data streaming | Research | This may reduce initial storage and time, but must preserve our verified archive, resume, atomic activation and no-live-write guarantees. |
| R2 | Incremental executable/update delivery | Research | A small build update is attractive, but every new build needs current CDN metadata, hash verification, compatibility classification and a safe rollback path. |
| R3 | More WoW editions | Research / product decision | The product currently protects a Forever-specific data contract. A new edition needs an explicit profile, legal/product decision, isolated store, fixture set and device evidence. |
| R4 | Vision Pro support | Research / product decision | It is a distinct UI, input, display and pairing target; iPhone/iPad compatibility does not establish it. |
| R5 | Windows/Linux companion | Research / product decision | It could broaden setup access, but creates a new signing, pairing, credential-storage and support surface. |
| X1 | Replace Tolkara with `spguest` | Reject | Tolkara already provides a broader tested loader and is the protected vendored engine. Slashplayed’s loader is explicitly modelled on Tolkara. |
| X2 | Device-side Apple-ID renewal / public anisette dependency | Reject | It expands credential and third-party trust exposure, conflicts with the paid-team capability contract, and is unsuitable without a separate security decision. |
| X3 | Depend on LocalDevVPN or another external JIT helper | Reject | WolkaraForever already has bounded Developer-service, Local-signing and External-JIT modes. An additional helper weakens the execution and support contract without demonstrated benefit. |

## Execution order

1. **A1 Support bundle** — isolated product-layer change; no runtime or signing changes.
2. **A3 Static CI** — isolated workflow change; keep all device and simulator gates local.
3. **A2 Setup status** — reuse existing preflight facts; do not give UI authority to alter a device.
4. **A4 Compatibility presentation** — generate from source-controlled validation records, never from
   self-reported capability claims.
5. **A5 Estimates** — add before starting R1/R2; it improves clarity even if streaming is rejected.
6. **R1/R2 feasibility** — separate spikes, no user-facing promise and no mutation of `platform/`.
7. **R3–R5** only after an explicit maintainer decision on product scope.

Do not combine these tracks. In particular, A1–A5 must not be blocked by another
edition, Vision Pro, Windows/Linux, signing or loader work.

## Non-negotiable guardrails

- `platform/` remains byte-identical to Tolkara; product changes are overlays or maintained
  patches only.
- Original game executables remain hash-verified data: never patch, re-sign or inspect them
  beyond the existing loading and verification boundary.
- Never add game input automation, memory inspection, integrity workarounds or a debugger
  attached after guest entry.
- No credentials, signing keys, provisioning profiles, pairing records, device identifiers or
  unsanitized logs enter a bundle, a repository, an issue or a support export.
- A simulator pass is not device evidence. The required simulator matrix stays iPhone Duo and
  iPad Pro 13-inch (M5); live launcher, input and game claims require the physical iPad flow
  stated in `AGENTS.md`.
- Any copied third-party source needs its exact licence text and copyright notice. Slashplayed
  itself is not a licence source for Tolkara-derived material.

## Acceptance bar for every adoption

Each implementation PR must identify the decision ID, owner files, data it reads/writes,
failure behavior, focused test, required simulator result, device evidence (when applicable),
documentation change and explicit rollback story. `check_layers.sh` is mandatory for every
layer-facing change; the candidate release retains exact-SHA validation.

See [evidence and work packages](EVIDENCE.md) for the detailed comparison and acceptance
criteria.
