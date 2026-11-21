# Repository status

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: Git history and `git status --short`

WolkaraForever is a source-built iPad and iPhone launcher layer for WoW Forever over the immutable Tolkara vendor tree. The newest release tag is `v1.0.21`; `main` carries unreleased work beyond it, listed under **Unreleased** in [Changelog](../../CHANGELOG.md).

## Execution modes

- Developer service is the supported integrated route, and the mode `local.env.example` preselects. It is offered by the `Tolkara` build only.
- Local signing builds a local page container with the user's signing identity. It is offered by every build.
- External JIT is a diagnostics route offered by the `TolkaraDiagnostics` build (the unsigned `.ipa`). It requires an external JIT enabler and refuses guest entry while a debugger remains attached.

The project does not distribute game files, patch or re-sign game code, automate gameplay, inspect game memory beyond loading and verification, or claim universal device compatibility. User setup is documented in [Install WolkaraForever](../INSTALLATION.md).

## Refresh when

Refresh after a release, execution-mode change, repository-policy change, or change to the supported product boundary.
