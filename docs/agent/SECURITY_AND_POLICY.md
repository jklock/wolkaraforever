# Security and policy

> Verified: 2026-11-13 · Source: `3c33543` · Proof: repository policy and security scope

Never commit game data, signing material, provisioning profiles, credentials, pairing records, device identifiers, logs, captures, or generated validation reports. The original executable is never patched or re-signed. Do not add gameplay automation, anti-cheat or license workarounds, post-entry debugger attachment, or application-memory inspection beyond loading and verification.

Developer service, Local signing, and External JIT have separate executable-memory boundaries. Review an execution-mode change against its owning source, tests, and [Security](../../SECURITY.md).

## Browser sign-in data

Opt-in browser sign-in uses a dedicated persistent WebKit data store
for Battle.net sessions. Do not read, log, export or copy its cookie values. Sign-out
clears that store and the launch handoff. Passwords stay in the official website's
form; there is no injected script, native autofill bridge or password storage.

The macOS launch handoff stores an encrypted short-lived ticket inside the app's
sandbox. Its protocol cipher is compatibility encoding, not a device-security
boundary. Clear the handoff on process start and cancellation; reject and clear
expired tickets when checking launch readiness. Never log tickets, credential-bearing
callbacks or navigation error descriptions. Synthetic
tests use isolated domains and fabricated tickets. Do not read desktop credentials,
modify the game or weaken account authentication to make sign-in work.

## Refresh when

Refresh after a security boundary, data-retention rule, execution mode, device protocol, or reporting route changes.
