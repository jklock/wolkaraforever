# Security and policy

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: repository policy and security scope

Never commit game data, signing material, provisioning profiles, credentials, pairing records, device identifiers, logs, captures, or generated validation reports. The original executable is never patched or re-signed. Do not add gameplay automation, anti-cheat or license workarounds, post-entry debugger attachment, or application-memory inspection beyond loading and verification.

Developer service, Local signing, and External JIT have separate executable-memory boundaries. Review an execution-mode change against its owning source, tests, and [Security](../../SECURITY.md).

## Experimental browser sign-in

The opt-in Forever browser-login path is off by default. It uses a dedicated nonpersistent WebKit store; never read, log, export, or persist its cookies, credentials, callbacks, or tickets. No script injection, native password bridge, desktop credential access, executable modification, or authentication weakening is permitted.

A valid result stays in process memory until the immediate Forever start, then is handed to the game once through its required launch preferences. Clear those preferences after consumption, game return, timeout, disable, explicit clear, or process start. Tests must use fabricated tickets and isolated preference domains.

## Refresh when

Refresh after a security boundary, data-retention rule, execution mode, device protocol, or reporting route changes.
