# Security and policy

> Verified: 2026-11-13 · Source: `3c33543` · Proof: repository policy and security scope

Never commit game data, signing material, provisioning profiles, credentials, pairing records, device identifiers, logs, captures, or generated validation reports. The original executable is never patched or re-signed. Do not add gameplay automation, anti-cheat or license workarounds, post-entry debugger attachment, or application-memory inspection beyond loading and verification.

Developer service, Local signing, and External JIT have separate executable-memory boundaries. Review an execution-mode change against its owning source, tests, and [Security](../../SECURITY.md).

## Refresh when

Refresh after a security boundary, data-retention rule, execution mode, device protocol, or reporting route changes.
