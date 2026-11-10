# Common procedure

1. Fetch, check out the original PR, and create a normal integration commit: `git merge --no-ff origin/main -m "merge: integrate current main for PR #<number> validation"`. Push normally to the same contributor branch.
2. Record current head, files, conversations, direct-integration state, UI class, user behavior, user action, collisions, risks, and focused tests in the individual document and PR body.
3. Run focused tests, `git diff --check`, `check_layers.sh`, `check_docs.sh`, both matrix simulators, then the test iPad through Device Hub. UI work also needs its review record and screenshot evidence.
4. Resolve every conversation and issue-register entry, obtain review, squash merge, validate exact main with `validate.sh --full --device --ui-review <record>`, tag the exact SHA, publish the release, and merge its generated validation-record docs PR before the next release.

Never claim a simulator or source result as device evidence. Leave the test app on normal launcher home; stable remains untouched.
