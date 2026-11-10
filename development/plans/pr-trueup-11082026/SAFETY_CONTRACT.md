# Safety contract

## Non-negotiable boundaries

1. `platform/` remains a byte-identical vendor tree. Product work is an overlay or maintained
   patch under `wolkaraforever/`; no direct platform edit enters any PR.
2. Every retained PR keeps its original branch and original GitHub PR. Integrate current main by
   a normal merge commit; never rebase, reset, force-push, or create a replacement PR.
3. Do not merge the next PR until exact-main validation, tag, and evidence for the preceding
   release are complete.
4. Existing WolkaraForever app UI is immutable in feature releases. New capability is opt-in,
   defaults to the present Standard UI, and receives a new named state/baseline. World of
   Warcraft in-game UI is outside this UI policy.
5. CDN/download/startup invariants fail closed: valid CDN metadata, verification, activation,
   and Play eligibility cannot be loosened by retry or presentation work. TLS/security,
   integrity, malformed response, range, and storage errors do not retry.
6. Device results use only project tools. A visible app UI claim is separately demonstrated in
   Device Hub on the physical matrix iPad and leaves the app on launcher home, running.

## Test layers

`check_layers.sh` proves vendor/overlay assembly. Focused client/launcher tests prove the changed
path. UI fixture tests prove matrix simulator contracts and golden states. `validate.sh --full`
adds platform and translation suites. `--device` adds the controlled install/pilot/device matrix.
Neither a simulator nor a source test is substituted for the required Device Hub interaction.

## Release stop conditions

Stop the sequence and repair on the same original branch when a merge conflict, test failure,
baseline drift, missing review record, unresolved conversation, missing device evidence, or
post-merge validation failure occurs. Do not progress by waiving the condition or by changing an
old golden file in a feature PR.
