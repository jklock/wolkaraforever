# Issue 67 — External-JIT world-entry diagnosis

## Goal

Identify the iPhone 16 Pro Max termination after **Enter World** in the source-built,
free-Apple-ID, External-JIT lane. Do not claim a runtime fix until a reproduction has
shown the same failure class or stable world entry.

## Implementation

- Record opt-in, app-owned External-JIT checkpoints in `Documents/`: route selection,
  native startup hand-off, application foreground/background changes, memory warnings,
  and the last native outcome. Preserve the prior launch's record until a new external-JIT
  launch starts.
- Extend the sideload verification command to classify the persisted record together with
  `native-guest.log`: missing JIT, attached debugger, unavailable arena, host lifecycle
  interruption, memory warning, native return, or unexplained interruption.
- Keep the checkpoint data to host events and runtime markers. It must not inspect game memory,
  collect account data, or automate the game.
- Obtain a fresh report with source SHA, sideloader and signing tier, JIT enabler, device,
  OS, game build, and both diagnostic files. Implement a minimal fix only when that report
  identifies a defect in this repository.

## Verification

- Unit-test checkpoint creation, prior-record preservation, and classification outcomes.
- Run package and execution-mode tests plus the required simulator matrix.
- Re-run the original physical External-JIT scenario after an evidence-backed change; record
  the source SHA and full environment before closing #67.

