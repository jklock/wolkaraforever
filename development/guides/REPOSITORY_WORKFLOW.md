# Repository workflow and GitHub settings

> **Current as of 2026-10-30 · branch `main`.**

This is the durable contributor workflow for WolkaraForever. It protects the pinned upstream
engine and evidence that must remain tied to the exact build that ran.

## GitHub settings to configure

Apply these rules to `main` in GitHub. GitHub branch protection cannot be committed to this
repository; this page is the authoritative configuration record.

- Require a pull request before merging, with one approval **from the code owner**.
  `.github/CODEOWNERS` names `@jklock` for every path and required code-owner review is on, so
  no pull request reaches `main` without the maintainer's approval. Dismiss stale approvals when
  new commits are pushed; require conversation resolution and the branch to be current with
  `main`.
- Enforced on the `main` ruleset since 2026-11-08: `required_approving_review_count` 1,
  `require_code_owner_review` on, `dismiss_stale_reviews_on_push` on,
  `required_review_thread_resolution` on, linear history, no force-push, no deletion.
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
- Block force-pushes and branch deletion for everyone, the owner included.
- The maintainer (`@jklock`) is the only bypass actor, with bypass mode **pull requests only**:
  the owner must still open a pull request — a direct push to `main` is refused for the owner
  too, measured 2026-11-08 — and merges it with the admin override
  (`gh pr merge <n> --squash --admin`, or the bypass option in the web UI), because GitHub does
  not let anyone approve their own pull request. Nobody else has a bypass; a collaborator's
  pull request stays unmergeable until the owner approves it, and every bypassed
  merge still carries the PR's verification and risk record.
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
5. Before review and again before merge, merge current `origin/main` into the original PR branch:

   ```sh
   git fetch origin --prune
   gh pr checkout <number> --repo jklock/wolkaraforever
   git merge --no-ff origin/main -m "merge: integrate current main for PR validation"
   git status --short --branch
   ```

   Resolve conflicts on that branch and push normally. Record "Already up to date" when no
   merge is required. Do **not** rebase, reset, force-push, rewrite branch history, or replace
   the original pull request. The merge commit is integration evidence; the final PR still
   squash-merges to `main`.
6. The PR description must name the behavior changed, safety boundary, commands run and
   results, device coverage, and explicit remaining gaps. The template provides the format.

## Required verification

Before any release verification, follow [Test execution protocol](TEST_EXECUTION_PROTOCOL.md).
Focused fixtures must be green on the required matrix before baseline or integration work begins.

| Change | Minimum verification |
| --- | --- |
| Any layer, patch, overlay, or `platform/`-adjacent change | `wolkaraforever/tools/check_layers.sh` plus focused tests |
| User or developer documentation | `wolkaraforever/tools/check_docs.sh` and `git diff --check` |
| WoW launcher, add-on, or Forever UI behavior | Owning suite plus `check_ui_policy.sh --review <record>`; existing baselines cannot change in an additive PR |
| Touch, controller, or voice behavior | Owning simulator test plus physical confirmation when the claim concerns hardware behavior |
| Runtime, authorization, translation, or cross-cutting behavior | `test_emulation.sh`; add `test_translation_sim.sh` when UIKit adapters changed |
| Release candidate | Clean-tree `validate.sh --full`; add `--device` only for a coordinated device run |

A passing layer gate proves assembly and upstream identity. It does not prove the app launched,
the renderer works, or hardware input works. Simulator, source, and physical-device evidence
must be reported separately.

A simulator result counts only if it ran on one of the two matrix simulators — **iPhone Duo** or
**iPad Pro 13-inch (M5)** — and a device result only if it ran on the **iPad Pro 12.9-inch
(5th generation)**. Those three are the whole test matrix; the tools refuse anything else. Name
the device in the report.

## Exact-SHA evidence and releases

Run `wolkaraforever/tools/validate.sh --full --device --ui-review <record>` on a clean candidate
after code is committed. It writes
a scrubbed record under `development/validation/` and refuses to represent an uncommitted
working tree as a commit. Never hand-edit generated validation records. A later device result
does not validate an earlier SHA.

For a release, squash merge only after the integrated branch review is approved and every
conversation is resolved:

```sh
gh pr merge <number> --repo jklock/wolkaraforever --squash --admin
git fetch origin main
git worktree add --detach ../wolkaraforever-postmerge-<number> origin/main
cd ../wolkaraforever-postmerge-<number>
wolkaraforever/tools/validate.sh --full --device --ui-review <record>
git tag -a v<version> -m "release: <summary>"
git push origin v<version>
```

The tag points to the exact tested squash-merge SHA. Commit the generated validation record
after tagging; it must name that SHA. No later release branch starts until exact-main validation
passes. Build, package, test, and publish from that SHA only.

Every published release credits the people who helped ship it. The release workflow resolves
each released commit's merged pull request and its closing issue references from GitHub, then
adds a **Contributors** section naming the PR author and each issue reporter. Keep the PR's
closing keywords and author intact; do not replace that generated section with a hand-written
summary. A person is credited once per PR or issue even when multiple release commits point to
the same work.

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
