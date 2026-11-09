# PR review log — 2026-11-08

This log records code-level review before integration, not a claim that device validation has
occurred. Re-check SHA, PR conversations, and branch mergeability immediately before every merge.

## #27 — retry downloads

Retain as the selected retry implementation. It may retry only explicitly transient transport
failures using 1, 2, 4, and 8 second delays. Tests must prove cancellation and terminal sibling
failure wake retry waits; metadata repair, verification, activation, and Play eligibility remain
unchanged. Security/TLS, integrity, malformed response, range, and storage errors fail at once.
No UI change or end-user action is introduced.

## #28 — speed and ETA

Add status text only through existing `wow.detail`; no card/grid/control movement, recoloring, or
navigation change. Add deterministic throughput/ETA tests and `wow-downloading.png` on both
matrices. Existing images remain byte-identical. End user sees progress information during a
download; no action is required.

## #23 — mobile foundation

Its four commits/64 files originate from old `1e50c7a`; normal merge from current main is
mandatory. Preserve CDN, retry, status, policy, and baseline work while resolving. French is an
additional selector/table state, not a replacement or moved selector. Expand fixture packaging
and localization checks from `en/de` to `en/de/fr`, preserve safe text entry without the optional
mobile add-on, and keep platform-facing code patch/overlay-only. End user may select French;
existing English/German UI remains unchanged.

## #26 — Duo package

One commit, 51 files, 4,877 insertions/274 deletions, real parent `64ed9cf`; it conflicts with
current main despite GitHub base metadata. Resolve only on #26's original branch after #23.
Retain the Duo overlay/add-on capability, not upstream-style replacement layout. Standard is the
saved default; Duo is an explicit saved user setting. Add Duo-only golden states and retain every
Standard image. End user must deliberately enable Duo; no existing UI default changes.
