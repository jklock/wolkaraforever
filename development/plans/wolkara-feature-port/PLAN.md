# End-to-end implementation plan

This is the build plan, not a source-port checklist.  It converts useful source
ideas into product-owned changes that preserve the layer boundary: no edits in
`platform/`; every platform-facing change is an explicit `wolkaraforever/patches/`
patch or overlay entry.

## Delivery map

| Phase | Feature | Depends on | Primary result |
| --- | --- | --- | --- |
| 1 | [Realtime controller path](01-controller-realtime-path.md) | none | A mapped press is bounded, measured and optionally claimed from the game. |
| 2 | [Chat Composer](02-chat-composer.md) | phase 1 event API | A controller, keyboard or microphone opens/reviews/sends one safe chat draft. |
| 3 | [Keyboard, speech and touch](03-keyboard-speech-touch.md) | phase 2 for chat controls | Composed text, language selection and improved native touch control. |
| 4 | [Add-on providers](04-addon-providers.md) | none | Native Add-on Hub is default; browser, API-key and Files acquisition share one safe install pipeline. |
| 5 | [Reliability](05-reliability.md) | none | Safer installs, enrollment recovery, responsive startup and bounded inactive rendering. |
| 6 | [Validation and rollout](06-validation-rollout.md) | every phase | Evidence, migration, staged release and rollback rules. |
| 7 | [Completion specification](07-completion-spec.md) | product decisions | Exact defaults, targets, schemas, PR cuts and manual scripts. |

Each phase is one or more small PRs.  Do not combine a product feature with an
upstream ingest, release work, unrelated UI cleanup, or a documentation sweep.

## Feature-complete contract

No feature is complete because its code compiles or its individual PRs merge.
It is complete only when every task in its feature directory has passed, its
saved-state migration and rollback have been exercised, localized/accessibility
UI is present, its owning simulator suites and live UI sequence pass on both
iPad Pro 13-inch (M5) and iPhone Duo, and its physical-device status is stated
without inference. Device Hub evidence is required before making a physical
interaction claim, but an unavailable physical run is not a release blocker.
Keep generated logs, screenshots, simulator output and validation reports
local-only; state exact SHA, commands, simulator/mode, outcomes and physical
status in the PR Proof section, then clear local reports with
`wolkaraforever/tools/clear_validation_reports.sh`. Update user-facing
documentation and `COMPATIBILITY.md` only with facts actually measured.

Every visible feature is an additive UI change unless a separately approved UI
contract amendment says otherwise. Before implementation, create the required
`development/reviews/ui/` record and run `check_ui_policy.sh` as applicable;
do not alter existing launcher cards, labels, placement, or golden baselines.

## Feature plans and tasks

Implement each feature from its own plan and task list:

| Feature | Plan | Tasks |
| --- | --- | --- |
| Physical controller input | [Plan](features/controller-input/PLAN.md) | [Tasks](features/controller-input/TASKS.md) · [Prompt](features/controller-input/PROMPT.md) |
| Chat Composer | [Plan](features/chat-composer/PLAN.md) | [Tasks](features/chat-composer/TASKS.md) · [Prompt](features/chat-composer/PROMPT.md) |
| Keyboard and dictation | [Plan](features/keyboard-dictation/PLAN.md) | [Tasks](features/keyboard-dictation/TASKS.md) · [Prompt](features/keyboard-dictation/PROMPT.md) |
| Touch Controller | [Plan](features/touch-controller/PLAN.md) | [Tasks](features/touch-controller/TASKS.md) · [Prompt](features/touch-controller/PROMPT.md) |
| Add-on Hub | [Plan](features/addon-hub/PLAN.md) | [Tasks](features/addon-hub/TASKS.md) · [Prompt](features/addon-hub/PROMPT.md) |
| Reliability | [Plan](features/reliability/PLAN.md) | [Tasks](features/reliability/TASKS.md) · [Prompt](features/reliability/PROMPT.md) |

## Required implementation order

1. Controller-input task 1 determines whether claim can ever ship; task 2 is
   required before Composer controller entry.
2. Chat Composer core precedes controller entry, Send/Cancel, destinations and
   speech-language work. Keyboard/dictation can run in parallel only through its
   committed-Unicode task; language UI waits for Composer core.
3. Add-on Hub record migration precedes every native UI/provider/update task.
4. Touch Controller is independent. It must extend the existing reviewed
   `WolkaraRoue`/`InterfaceMode`/`LayoutStore` mobile path where relevant, but
   cannot add commands, macros, game automation, or a source add-on port.
5. Reliability candidates run only with a specific reproducer and never block an
   otherwise complete feature unless they touch that feature's changed path.

An agent may not substitute a later task for an unmet prerequisite or mark a
feature complete with a deliberately skipped task. A product decision to defer a
task requires maintainer approval and an explicit updated plan.

## Cross-cutting decisions fixed by this plan

- **The native layer owns interaction.** No game-side command add-on, bots,
  input automation or guest-memory inspection.
- **A controller claim is explicit.** A player chooses whether a mapped control
  remains visible to the game.  Defaults preserve existing behavior.
- **A chat message is transactional.** The user sees the exact text before a
  send; one request cannot result in more than one game insert, Return or Escape.
- **Provider choice does not weaken file safety.** Every add-on, regardless of
  source, uses the existing staged archive/lock/recovery path.
- **Measurements are feature-specific.** Existing pointer-display-link timing
  is not evidence for controller-to-chat latency.

## Execution handoff

Follow the feature task list for the branch, plus the shared
[implementation standards](IMPLEMENTATION_STANDARDS.md): named current files,
prohibited shortcuts, required commands, stop conditions, and acceptance proof.

## Existing code that is deliberately retained

- `wolkaraforever/Voice/Dictation.*`: on-device-only recognition, audio-session
  restoration, final-result delivery and failure handling.
- `wolkaraforever/Touch/TouchControls.*`: native keyboard, fallback keyboard,
  draft editor and guest event delegate.
- `wolkaraforever/Input/{InputRouter,InputInterest,Trigger}.*` and
  `wolkaraforever/Controller/ControllerInspector.*`: canonical input identity,
  persisted mappings, diagnostics and system-gesture management.
- `wolkaraforever/WoW/{AddonArchive,AddonStore,AddonManager,UpdateLock}.*`:
  validated extraction, managed records, mutual exclusion and recovery.
- `wolkaraforever/tools/prepare.sh`, `overlay.map`, `check_layers.sh`: the
  sole assembly route for product changes.

## Source ideas deliberately transformed

The source reviewed-chat controller, language switching, channel destinations,
Simple controller, L3/R3, browser acquisition, large TOCs, reclaimable storage,
startup lifecycle work and inactive Metal handling are inputs to the phases.
They are never cherry-picked.  Source device claims and source tests become
test hypotheses, not acceptance evidence.
