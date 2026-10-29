---
name: wolkaraforever-maintenance
description: Maintain WolkaraForever safely when changing its layer, Forever features, device workflows, documentation, or release evidence.
---

# WolkaraForever maintenance

Use this skill for work in this repository that changes WolkaraForever behavior, layer
assembly, device operations, validation, contributor workflow, or user/developer
documentation. Do not use it for ordinary questions unrelated to this repository.

Read [the project map](../../../development/architecture/PROJECT_MAP.md) and
[repository workflow](../../../development/guides/REPOSITORY_WORKFLOW.md) before a
cross-cutting change. For specific behavior, route to `development/technical/` and the owning
test named in `development/testing/TESTING.md`.

## Non-negotiable boundaries

- `platform/` is a byte-identical Tolkara vendor tree. Make product changes through
  `wolkaraforever/patches/` and `wolkaraforever/overlay.map`; never hand-edit `platform/`.
- Use `wolkaraforever/tools/` for WolkaraForever install, launch, stop, game-copy, log, and
  device operations. Do not bypass their live-session checks with raw device operations.
- Never commit application files, captures, credentials, signing data, device identifiers,
  pairing records, `build/`, or `logs/`.
- Separate source/simulator checks from physical-device proof. Bind physical claims and
  validation records to the exact SHA, installed build, device, iPadOS, client build, and
  execution mode.

## Required workflow

1. Inspect the layer map, owning module, current worktree, and existing focused test.
2. Keep the change on a single-purpose branch/worktree. Do not mix upstream ingests with
   feature work.
3. Implement through the owning module and patch/overlay boundary. Add focused coverage for a
   changed behavior.
4. Run `check_layers.sh` for layer-facing changes, `check_docs.sh` for documentation, and the
   focused suite. Use `test_emulation.sh` for cross-cutting runtime work.
5. Before a release or a claim of device behavior, commit the candidate and run clean-tree
   `validate.sh`; use `--device` only with coordinated device authority.
6. Report commands, outcomes, exact evidence scope, and remaining gaps. Do not convert a
   passing source or simulator result into a device claim.

For the complete contributor and GitHub policy, follow
[REPOSITORY_WORKFLOW.md](../../../development/guides/REPOSITORY_WORKFLOW.md).
