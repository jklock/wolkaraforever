# Repository workflow and GitHub settings

> **Current as of 2026-10-30 · branch `main`.**

This is the durable contributor workflow for WolkaraForever. It protects the pinned upstream
engine and evidence that must remain tied to the exact build that ran.

## GitHub settings to configure

Apply these rules to `main` in GitHub. GitHub branch protection cannot be committed to this
repository; this page is the authoritative configuration record.

- Require a pull request before merging, with at least one approval.
- Dismiss stale approvals when new commits are pushed; require conversation resolution and
  the branch to be current with `main`.
- No hosted CI. The verification is `wolkaraforever/tools/check_docs.sh` and
  `wolkaraforever/tools/check_layers.sh`, run locally before the PR is opened, with the results
  and the exact source SHA written into the PR. The **Verify** workflow was deleted on
  2026-10-29: its macOS job never acquired a runner — the run said *"The job was not acquired by
  Runner of type hosted even after multiple attempts"* and failed after fifteen minutes on every
  push — so the red cross was about GitHub's capacity, not about the change, and reviewers learned
  to ignore it. A check that cannot run is worse than one a person runs and reports. If hosted CI
  comes back it has to be able to finish: a runner image the free tier actually provides, or only
  the checks that run on Linux.
- Require linear history; allow squash merges for ordinary PRs. Reserve merge commits for
  intentional integration branches.
- Block force-pushes and branch deletion. The repository owner has the intentionally selected
  normal bypass; every bypassed merge must still carry the PR's verification and risk record.
- Enforce `.github/CODEOWNERS` for protected paths.
- Enable GitHub secret scanning, push protection, Dependabot alerts, and private
  vulnerability reporting.

## Branch and pull-request rules

1. Branch from current `main`, naming it `feature/...`, `fix/...`, `docs/...`, or `chore/...`.
2. Keep one behavior or concern per branch. Use a separate worktree for unrelated work.
3. Do not commit generated `build/` or `logs/` output, game data, credentials, signing
   material, provisioning profiles, pairing records, device identifiers, or captures.
4. Write small, imperative commits that can be reviewed independently. Do not mix upstream
   ingestion, product behavior, documentation-only work, and formatting cleanup.
5. Rebase onto current `main`, resolve conflicts deliberately, and run the relevant checks
   again before requesting review.
6. The PR description must name the behavior changed, safety boundary, commands run and
   results, device coverage, and explicit remaining gaps. The template provides the format.

## Required verification

| Change | Minimum verification |
| --- | --- |
| Any layer, patch, overlay, or `platform/`-adjacent change | `wolkaraforever/tools/check_layers.sh` plus focused tests |
| User or developer documentation | `wolkaraforever/tools/check_docs.sh` and `git diff --check` |
| WoW launcher, add-on, or Forever UI behavior | Owning `test_wow_launcher.sh`, `test_addon_archive.sh`, `test_curseforge.sh`, or `test_forever_ui.sh` |
| Touch, controller, or voice behavior | Owning simulator test plus physical confirmation when the claim concerns hardware behavior |
| Runtime, authorization, translation, or cross-cutting behavior | `test_emulation.sh`; add `test_translation_sim.sh` when UIKit adapters changed |
| Release candidate | Clean-tree `validate.sh --full`; add `--device` only for a coordinated device run |

A passing layer gate proves assembly and upstream identity. It does not prove the app launched,
the renderer works, or hardware input works. Simulator, source, and physical-device evidence
must be reported separately.

## Exact-SHA evidence and releases

Run `wolkaraforever/tools/validate.sh` on a clean candidate after code is committed. It writes
a scrubbed record under `development/validation/` and refuses to represent an uncommitted
working tree as a commit. Never hand-edit generated validation records. A later device result
does not validate an earlier SHA.

For a release, tag the single tested SHA. Build, package, test, and publish from that SHA only.
Inspect the failing CI job before changing another lane or retagging. The External JIT IPA
workflow is manual and is never an automatic side effect of tagging.

## Upstream updates

`platform/` is a byte-identical Tolkara vendor tree. Never edit it by hand. Use:

```sh
wolkaraforever/tools/update_tolkara.sh --check
wolkaraforever/tools/update_tolkara.sh --test
```

Keep the upstream ingest in its own PR. Review patch application, overlay collisions, layer
checks, and affected suites before merging. Product work belongs in `wolkaraforever/` as an
overlay file or explicitly maintained patch.

## Device and security boundary

Use `wolkaraforever/tools/` for install, launch, stop, log, game-copy, and device checks. The
scripts refuse unsafe live-session operations and preserve baselines; do not replace them with
raw device file operations. Never uninstall an app or force-stop a live game without explicit
user authorization.

The original executable remains unchanged verified data. Do not add game automation, runtime
memory inspection beyond loading/verification, anti-cheat/licence/integrity workarounds, or
committed application data. See [Contributing](CONTRIBUTING.md) and the
[project map](../architecture/PROJECT_MAP.md).
