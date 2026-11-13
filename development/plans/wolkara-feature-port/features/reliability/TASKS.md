# Reliability tasks

## 1. Triage before code

For each candidate, write a one-page reproduction record: symptom, source SHA,
steps, failing test/log boundary, owner module, affected user data, and rollback.
If any field is unknown, stop after the record and request prioritization. Do not
write a catch-all reliability PR.

## 2. Storage, enrollment, manifest, or startup

Make one branch per reproduced item. Add the failing fixture first. Implement
only the narrow idempotent fail-closed recovery in its owner (`WoW` updater/store,
authorization bridge, manifest verifier, or launcher lifecycle). Do not combine
authorization, updater and runtime changes. Run the owner suite plus
`check_layers.sh`; record device evidence when user-visible startup behavior is
claimed.

## 3. Inactive Metal

Branch `fix/inactive-metal-submission` only after a reproducible failing case.
Keep foreground pacing unchanged, preserve caller-owned pending work, resume once
on foreground, bound error records, and make no background-execution promise.
Run focused background/Metal fixture, translation simulation, and coordinated
physical proof.

## 4. Close the reliability backlog

In the final closure PR Proof section, list every source candidate: reclaimable
storage, enrollment reference, bootstrap/manifest, startup scene servicing and
inactive Metal submission. For each, state the current reproducer/result and
classify it as fixed, covered, or not reproducible after the specified evidence
attempt. Run every owning focused suite, `check_layers.sh` for changed layer code
and `check_docs.sh` for changed documentation. Do not commit generated inventory,
logs or captures; clear them before handoff. Do not mark the feature complete
with an unclassified item.
