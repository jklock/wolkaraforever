# Execute: Reliability closure

Implement `PLAN.md` and every task in `TASKS.md` on one feature branch/worktree.
Close every listed candidate as fixed, covered, or not reproducible after its
defined evidence attempt. Do not combine updater, authorization, runtime and
Metal changes in one PR. Do not edit `platform/` except through an approved,
minimal numbered layer patch when a confirmed fix needs a hook.

Emit bounded feature-specific log events for each reproduced condition and its
recovery verdict. Do not log credentials, pairing records, device IDs, game paths
or data. Add a regression assertion for every fixed path and state every
covered/not-reproducible candidate in the PR Proof section; do not create or
commit generated validation-inventory artifacts.

Run each owning focused suite on iPhone Duo and iPad Pro 13-inch (M5) where it
has a UI/lifecycle effect, plus `test_translation_sim.sh` for Metal/AppKit work,
`check_layers.sh` for layer changes, and `check_docs.sh`. Perform live simulator
QA and local screenshots for startup/rotation, update recovery, enrollment
messaging or inactive/foreground rendering whenever that candidate changes
visible UI. Create the required additive UI-review record first and preserve the
launcher contract.

Open one PR per confirmed reliability feature; if candidates land independently,
open separate PRs and state the closure classification in each PR Proof section.
Every PR includes exact SHA, test/simulator results, local-QA observations where
applicable, structured logs, rollback and data-preservation proof. Clear
generated validation artifacts before handoff. The final closure PR is ready
only when no candidate remains unclassified.
