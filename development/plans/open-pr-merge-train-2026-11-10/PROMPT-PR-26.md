# Execute PR #26 — Duo refinement package (v1.0.10)

Execute PR-26.md exactly. This is a **current-main reconstruction**, not a merge of the
historical PR tree.

1. Fetch and re-query origin/main and PR #26. The reviewed anchors are main 3705e92d, old
   base 550755f, and head 806e3e0; if main advanced, use its fetched tip.
2. In a new worktree, check out scarrdi94-ui:iphone-duo-layout and normally merge origin/main.
   Do not rebase, reset, force-push, replace PR #26, bulk-copy old files, or use
   checkout --theirs.
3. Restore current-main behavior first. Inventory every historical changed file, then accept,
   rebuild, or reject it under the plan. Preserve v1.0.2–v1.0.9, especially v1.0.8's dormant
   mobile foundation and v1.0.9's Launcher Manager/package-install contract.
4. Port only mode-gated Duo refinements. AKInterfaceModeIsMobile() is the sole gate: missing,
   malformed, or ipados remains exact Standard/iPadOS behavior. Never infer mode from
   hardware, gamepad preferences, or another defaults reader.
5. Treat the add-on as a reviewed versioned upgrade: source → deterministic ZIP/manifest →
   production verifier → explicit Add-On Manager install. No auto-install/update or launcher
   redesign.
6. Prove touch ownership, hit regions, cancellation/release, mode round trips, localization,
   add-on migration/package integrity, and unchanged iPadOS baselines on both matrix
   simulators. Use a physical iPad only for a claim it can exercise.
7. Run every final check in PR-26.md on the final SHA. Keep generated validation output local,
   clear it after the decision, and never commit/link it.
8. Merge only when current main is preserved and every gate passes. Tag v1.0.10 from that
   final main SHA. Release notes are product-facing additions/updates only and credit
   contributors whose work shipped.

Stop for a maintainer decision if the original fork cannot be updated, a desired feature would
alter Standard/iPadOS behavior or explicit installation, needs prohibited runtime/gameplay work,
or lacks a testable current-main acceptance contract.
