# Execution procedure

Perform this once for the policy PR and once for each retained feature PR, in release order
`trueup`, `#27`, `#28`, `#23`, `#26`.

## Integrate current main without rewriting

```sh
git fetch origin --prune
gh pr checkout <number> --repo jklock/wolkaraforever
git merge --no-ff origin/main -m "merge: integrate current main for PR validation"
git status --short --branch
git push origin HEAD
```

Resolve every conflict on the original branch. Record `Already up to date` when applicable. Run
`git diff --check`, `check_layers.sh`, `check_docs.sh`, focused tests, then:

```sh
wolkaraforever/tools/validate.sh --full --device --ui-review <review-record>
```

Run iPhone Duo and iPad Pro 13-inch (M5) screenshots; install with project tools on the physical
iPad Pro 12.9-inch (5th generation); exercise visible behaviour with Device Hub; capture evidence;
and return to launcher home with the app running. Update the same PR body with head SHA, review,
end-user action, commands/results, evidence boundary, and risks. Obtain maintainer review and
resolve all conversations.

## Exact-main release

```sh
gh pr merge <number> --repo jklock/wolkaraforever --squash --admin
git fetch origin main
git worktree add --detach ../wolkaraforever-postmerge-<number> origin/main
cd ../wolkaraforever-postmerge-<number>
wolkaraforever/tools/validate.sh --full --device --ui-review <review-record>
git tag -a v<version> -m "release: <summary>"
git push origin v<version>
```

Commit the generated validation record after the tag; it must name the tagged SHA. No release
work starts until the prior tag has its passing exact-main evidence.
