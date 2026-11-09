# Continuation prompt

You are executing the WolkaraForever PR true-up sequence. Start from current `origin/main`; do
not rely on historic SHAs without rechecking them. Read `README.md`, `SAFETY_CONTRACT.md`,
`OPEN_PR_AUDIT.md`, `EXECUTION.md`, `DOCS_AND_EVIDENCE.md`, `development/architecture/UI_POLICY.md`,
and `development/architecture/LAUNCHER_UI_BASELINE.md`.

Complete `PR-trueup-11082026` first, then release #27 as v1.0.2, #28 as v1.0.3, #23 as v1.0.4,
and #26 as v1.0.5. Close #35 without merge using the documented rejection. Keep every original
PR and normal branch history: fetch, checkout its PR branch, merge `origin/main` with a normal
merge commit, resolve there, push normally, then squash merge only after review. Never rebase,
reset, force-push, replace a PR, or edit `platform/` directly.

For every release: inspect the exact diff against current main; document code effect, UI effect,
and end-user action in `PR-<number>.md`; run focused tests, layer/docs gates, full validation
with `--ui-review`, both simulator matrices, controlled physical-iPad install, Device Hub
exercise, and exact-main validation; tag only the validated squash SHA. Stop and fix a failure
before advancing. UI is additive-only: Standard remains default; old screenshots/identifiers
never change; all optional changes are user-controlled and documented.
