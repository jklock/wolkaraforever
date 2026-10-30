# Professional repository-management plan

## Status

> **Applied on 2026-10-30 for `main`; repository-owned templates and Dependabot configuration
> are on branch `prostatus` pending review.**

The active `Protect main` ruleset requires a pull request, one approval, code-owner review,
resolved conversations, linear history, and blocks force-pushes and branch deletion. The
repository owner has the selected normal bypass. Repository metadata, Wiki, Discussions, Issues,
Projects, automatic head-branch deletion, vulnerability alerts, Dependabot security updates,
secret scanning, push protection, private vulnerability reporting, and read-only default Actions
permissions are enabled. The remaining visual social-preview upload and first Wiki page need the
GitHub web UI because GitHub exposes neither through the repository REST API.

## Goal

Keep `main` continuously buildable and reviewable without making normal work burdensome for a
small team. This plan records the configuration target and applied status. Re-verify the GitHub
settings after an ownership or team change.

## Target operating model

- `main` is the one release-ready integration branch. It contains reviewed, passing work only.
- Contributors work in short-lived `feature/`, `fix/`, `docs/`, or `chore/` branches and merge
  through pull requests.
- The repository owner has the selected normal bypass. Contributors without repository ownership
  cannot bypass safeguards; every bypass remains subject to PR evidence and audit history.
- Checks are proportional: all PRs run the two fast repository checks; source changes carry the
  focused test named by `development/guides/REPOSITORY_WORKFLOW.md`; device validation is
  required only when the claim depends on a physical device.

## Phase 1 — baseline settings

1. Set the repository description, topics, website/docs link, and social preview. Keep the
   README as the primary technical entry point.
2. Keep Issues, Discussions, Projects, Wiki, and the issue tracker enabled. Enable a public
   security policy and private vulnerability reporting.
3. Enable secret scanning, push protection, Dependabot alerts, Dependabot security updates, and
   dependency graph. Review alerts promptly; do not blindly merge automated updates.
4. Enable **Automatically delete head branches** after merged PRs.
5. Keep squash merge enabled and make it the normal contributor path. Keep merge commits enabled
   only for deliberate integration/upstream-ingest PRs; rebase merge is optional.
6. Maintain a visible release policy: ordinary commits do not publish artifacts; annotated
   `v*` tags are created only from an exact, validated `main` SHA and trigger the existing manual
   experimental IPA workflow when explicitly dispatched.

## Phase 2 — `main` ruleset

Create one active ruleset targeting the default branch `main`.

| Rule | Setting | Why / low-friction exception |
| --- | --- | --- |
| Pull request required | Yes; require **one** approval | Gives the new contributor a real review boundary. The repository owner has the selected normal bypass. |
| Dismiss stale approval | Yes | A reviewed diff must remain the merged diff. |
| Require conversation resolution | Yes | Prevents acknowledged issues from being silently merged. |
| Require branch up to date | No by default | Avoids needless rebases for low-risk docs work. Enable temporarily during a release cut or a sensitive upstream ingest. |
| Required checks | None from hosted CI | The **Verify** workflow was deleted on 2026-10-29: its macOS job never acquired a runner and failed after fifteen minutes on every push, so the check was about GitHub's capacity rather than about the change. `check_docs.sh` and `check_layers.sh` are run locally and their results recorded in the PR. Add focused tests to PR evidence; promote a check back into hosted CI only when it can complete on a runner the free tier provides. |
| Block force pushes | Yes | Protects the integration history. |
| Block branch deletion | Yes | `main` must always exist. |
| Require linear history | Yes | Keeps review/revert history readable. |
| Require signed commits | No initially | Revisit after every contributor has a stable signing setup; do not create avoidable onboarding failures. |
| CODEOWNERS review | Yes | `.github/CODEOWNERS` names the current owner and is enforced for its protected paths. Update it before an ownership change. |

Do not require a merge queue, deployment approval, mandatory status checks for unavailable macOS
hardware, or a second approval while the project has one active maintainer. Those controls can
be added when team size or release frequency makes them useful.

## Phase 3 — workflow and permissions

1. Set Actions default workflow permissions to **Read repository contents**. The release workflow
   already declares its narrowly needed `contents: write`; do not grant broad default write access.
2. Require approval for first-time contributors' workflows and review workflow changes as
   security-sensitive. Restrict Actions to GitHub-maintained actions or explicitly pinned,
   reviewed third-party actions.
3. Create a `release` environment only if a release needs approval. Put release credentials there;
   never place them in repository variables or committed files.
4. Store non-secret configuration in Actions variables; store values only in repository or
   environment secrets. Secret values cannot be recovered after creation, so document ownership,
   rotation contact, and purpose outside the secret itself.
5. Keep the manual IPA workflow manual. A tag alone must not silently publish a new binary.

## Phase 4 — contributor experience

1. Keep `.github/CODEOWNERS` aligned with the owner and accepted contributor identities. Limit
   ownership to paths they genuinely maintain.
2. Add GitHub issue forms for bug reports, device compatibility reports, feature requests, and
   security-sensitive reports. Device reports must collect app SHA, device model, iPadOS, game
   build, execution mode, expected/actual result, and logs redacted of credentials.
3. Keep the PR template's behavior, verification, device evidence, and risk sections mandatory
   in practice. Add labels: `bug`, `feature`, `docs`, `iPhone`, `iPad`, `localization`,
   `performance`, `security`, `upstream`, `needs-device`, and `good first issue`.
4. Use milestones for releases and Projects only for cross-PR initiatives (iPhone support,
   localization, performance). Avoid duplicating every GitHub issue in another tracker.
5. Add `CONTRIBUTING.md`, `SECURITY.md`, support boundaries, and the Wiki navigation described
   in `development/wiki/GITHUB_WIKI_PLAN.md` if any are not already present or current.

## Phase 5 — release and incident discipline

1. Before a release, merge the final PR, run `validate.sh --full` on the resulting exact SHA,
   then run coordinated `validate.sh --device` only when physical claims are part of the release.
2. Create an annotated `vX.Y.Z` tag at that SHA. Generate release notes from merged PRs, including
   compatibility and unresolved limits; never imply device/gameplay proof that was not collected.
3. If `main` regresses, revert the smallest offending merged PR immediately. Fix-forward only
   when the repair is understood and can be validated faster than a revert.
4. Record security incidents privately, rotate affected credentials, and publish only the
   user-facing disclosure/release information appropriate to the incident.

## Administration sequence

1. Reconfirm owner and contributor GitHub handles before changing the ruleset or CODEOWNERS.
2. Re-verify Phase 1 settings and the Phase 2 ruleset through repository Settings.
3. Run `wolkaraforever/tools/check_docs.sh` and `wolkaraforever/tools/check_layers.sh` on the
   candidate branch and put both results in the PR: there is no hosted CI to do it.
4. Keep `@jklock` current in CODEOWNERS, then re-verify CODEOWNERS enforcement after every owner change.
5. Keep labels/templates/security configuration current and publish the initial Wiki structure.
6. Open a test PR from the contributor account to prove review, checks, merge, and branch cleanup
   work as intended. Record the result in the repository workflow guide.
