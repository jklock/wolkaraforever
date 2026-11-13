# Reliability plan

## Outcome

Fix only reproduced failures in storage recovery, enrollment recovery, manifest
verification, startup responsiveness, or inactive Metal work. Each is a separate
feature/PR with its own failing fixture and rollback.

## Why

The source has ideas in these areas, but they cross updater, authorization,
runtime and graphics ownership. Combining them would make failures impossible to
attribute and risk user game data or execution-mode behavior.

## Acceptance

Every change starts with a current reproducer, is idempotent and fail-closed,
preserves user data, and has an owning focused suite. Every visible lifecycle
change runs on both required simulators; physical evidence may support, but never
be inferred from, a physical startup/rendering claim.

## Completion gate

This feature closes only after every candidate is classified: reproduced and
fixed, proven covered by a named current test, or not reproducible after its
specified simulator/physical evidence attempt. There is no blanket
"reliability complete" and no open-ended deferral category. Each shipped fix
has migration/rollback behavior, a focused regression, relevant simulator
coverage on both simulators, recorded physical status when it changes
startup/rendering, exact-SHA PR Proof, and a documentation/COMPATIBILITY update
where users can observe it. Generated evidence stays local and is cleared before
handoff.
