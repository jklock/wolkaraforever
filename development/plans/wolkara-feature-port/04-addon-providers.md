# Phase 4 — Native Add-on Hub, providers and large packages

## Outcome

The default add-on experience is the native Add-on Hub described in
`features/addon-hub/PLAN.md`. CurseForge browser, Core API and Files import are
acquisition routes. All feed the same validated install transaction and one
first-class installed catalog.

## Existing safe pipeline

`WoW/AddonManager.m` drives UI and package actions; `AddonStore.*` owns managed
records; `AddonArchive.swift` validates archives; `UpdateLock.*` excludes game
updates; `CurseForgeClient.*` uses device-local credentials.  Preserve this path.

## Acquisition design

Add `WoW/AddonBrowser.{h,m}` using `WKWebView` and `WKDownload`, plus a provider
boundary shared by the existing CurseForge API client. The browser starts at the
Forever-filtered CurseForge search page and reports only a completed temporary
archive plus provenance to the common installer. It never replaces native My
Add-ons, Discover or Browse UI.

- Browser is the no-key acquisition route; API-key selection is explicit. Normal site login,
  cookies and challenge pages remain inside WebKit. No page scraping, custom
  authentication, credential copying or challenge bypass.
- Download-only HTTPS/redirect validation for CurseForge and ForgeCDN,
  MIME/body checks, 128 MiB byte limit, cancellation and unique temporary file.
- Store the final approved URL/domain and digest with the managed package record.
- Use the same archive extraction, traversal/symlink protection, staging,
  transactional replace, update lock, recovery and unmanaged-folder protection
  as API downloads.
- Provider-specific failures explain whether a player must use Files import or
  the API provider instead.

## What, why and how

The Add-ons page opens native **My Add-ons** by default, with native Discover and
Browse where catalog metadata is available. It exposes **Browse CurseForge**,
**Use API key**, and existing **Files import** as acquisition actions. The
browser's navigation is owned by WebKit; only a clicked archive download crosses
into the provider. Define a `TKAddonProvider` handoff (`completed temporary
archive`, `cancel`, `provenance record`), enforce trusted HTTPS hosts on every
download redirect, reject HTML/error bodies, then hand the file to the existing
archive/store transaction. Network work occurs outside `UpdateLock`; activation
remains inside it.

## Large TOC support

Add a bounded metadata-prefix reader to `AddonStore` and shared discovery in
`AddonManager`.  Read enough bytes to discover metadata but never truncate or
rewrite the installed file.  Build fixtures with two large valid TOCs, malformed
encoding, oversized prefix and ordinary modules.

## Serialization decision

First add a deterministic concurrent-install fixture.  If it demonstrates that
two managed mutations can overlap despite `UpdateLock`, introduce a serial
per-installation mutation coordinator above the existing transaction.  Do not
serialise network fetches unnecessarily; serialise only activation/state changes.

## Tests and proof

Extend `test_addon_archive.sh`, `test_wow_launcher.sh`, and add browser-delegate
fixtures for redirect/cancel/error/oversize/HTML/ZIP cases. Test native Add-on
Hub default, API-key alternate selection, project-identity retention and provider
provenance. Device proof uses a harmless add-on without an API key, then verifies
API-key mode separately; it records only archive digest, provider and transaction
result.
