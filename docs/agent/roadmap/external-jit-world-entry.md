# External JIT world entry

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: current External JIT diagnostics source review

External JIT remains a diagnostics route. The `TolkaraDiagnostics` build starts a guest through it
(the launcher handles Local signing and External JIT before the Developer-service branch), so any
future world-entry work must retain the debugger-detachment checks, avoid game-code changes, and
provide source, simulator, and explicitly scoped device evidence.
