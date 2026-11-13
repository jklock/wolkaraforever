# Execute: Add-on Hub

Implement `PLAN.md` and every task in `TASKS.md` on one feature branch/worktree.
Extend the current `AddonManager`, `AddonStore`, `AddonPackage` and bundled
`WolkaraRoue` recommendation; do not replace their established managed-package
behavior. Ship normalized records, native My Add-ons/Discover/Browse, provider-blind
management, API/browser/Files/unmanaged migration, in-app browser handoff,
update resolver, rollback and completion gate. Never scrape CurseForge, copy
WebKit credentials, open external Safari, or create a second archive installer.

Emit bounded `addon-hub` log events for record migration, source identity/link,
browser handoff/download verdict, archive transaction, update state/queue,
per-row outcome, cancellation, rollback and recovery. Log only package digest,
provider kind and non-sensitive identifiers; never URLs with tokens, WebKit
cookies, API key, archive contents or user paths. Add fixture assertions for
every visible toolbar/row/detail action and mixed-provider update ordering.

Create the required additive UI-review record before visible UI code; preserve
the launcher contract. Run `test_addon_archive.sh`, `test_wow_launcher.sh` and
`test_wow_launcher_ui.sh` on iPhone Duo and iPad Pro 13-inch (M5), then
`check_layers.sh` and `check_docs.sh`. Perform live simulator QA on both: native
My Add-ons default, search/sort/filter, Refresh, group, API install, browser
handoff install, Files import, unmanaged discovery, Link project, Update,
Update all, failure/cancel/relaunch and backup/restore. Capture screenshots of
each native tab and a browser-handoff return; keep them local and summarize their
result and log evidence in the PR.

Open one PR for this feature. Include exact SHA, simulator test/live-QA proof,
local-QA screenshot observations, structured logs, privacy/credential-boundary
proof, migration and rollback evidence, English/German/French localization, and
known physical-iPad status. Clear generated validation artifacts before handoff.
It is not ready until the complete mixed-provider script and every completion
gate pass.
