# Security and policy

> Verified: 2026-11-13 · Source: `3c33543` · Proof: repository policy and security scope

Never commit game data, signing material, provisioning profiles, credentials, pairing records, device identifiers, logs, captures, or generated validation reports. The original executable is never patched or re-signed. Do not add gameplay automation, anti-cheat or license workarounds, post-entry debugger attachment, or application-memory inspection beyond loading and verification.

Developer service, Local signing, and External JIT have separate executable-memory boundaries. Review an execution-mode change against its owning source, tests, and [Security](../../SECURITY.md).

## Browser sign-in data

Opt-in browser sign-in (off by default) uses a dedicated in-memory WebKit data store
for the Battle.net session; it is never written to disk and ends with the process.
Do not read, log, export or copy its cookie values. Passwords stay in the official
website's form; there is no injected script, native autofill bridge or password storage.

The launch ticket is held in process memory only until the game starts. It is then
consumed once: written to the `net.battle` launch preferences the game reads, and the
in-memory copy dropped. Those preferences (`WEB_TOKEN`, `REGION`, `LOCALE`,
`GAME_ACCOUNT`, `ACCOUNT_TS`) are removed as soon as the game has taken `WEB_TOKEN`,
when the game returns, after ten minutes, and on every process start. The
`WEB_TOKEN` cipher is the game's fixed wire format, not a security boundary; the
protection is that the ticket never sits in storage. Never log tickets,
credential-bearing callbacks or navigation error descriptions. Synthetic tests use
isolated domains and fabricated tickets. Do not read desktop credentials, modify the
game or weaken account authentication to make sign-in work.


## Refresh when

Refresh after a security boundary, data-retention rule, execution mode, device protocol, or reporting route changes.
