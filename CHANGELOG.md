# Changelog

> Verified: 2026-11-13 · Source: `3c33543`

## Unreleased

- Documentation now separates standalone user guidance from the agent-only operational catalog.
- **My Add-ons no longer sits on "Updating…".** "Never asked" is its own state, **Not checked yet**, with a **Check** action that runs the check; *Checking…* appears only while a request is genuinely in flight, and a sweep with no key clears its own in-flight marks and says why. Opening **My Add-ons**, and **Refresh**, still ask the provider about every linked package.
- **Update All settles.** The batch used to advance before each archive write committed and re-asked the packages it had just reported, so every row returned to **Not checked yet**. It now finishes on the archive transaction, keeps the settled answer, and ends with every row up to date.
- **Installed rows carry their CurseForge thumbnail.** The project's artwork is kept with the package's provider identity, and the whole page is filled in one provider query rather than one request per row; a package with no recorded identity keeps the neutral placeholder.
- **A first run without a provider key has a door.** Browse and Discover each offer **Set up access**, which opens the key sheet; with a key the Sort and Filter rows open the sheets they name.
- **Backup Add-ons and Restore Add-ons**: the whole add-on folder as one ZIP under `WTF/Backups/`, restorable transactionally, and neither row reaches the network.
- **The four Controller Layout decisions are four rows**: create, edit, restore and back up, the last through the system share sheet.
- **A controller claim survives a config transfer**: `AKControllerClaims` is in the config export/import allowlist and in the schema.
- **The in-app add-on browser no longer opens during a transition**, which removes UIKit's unbalanced begin/end appearance transitions.
- A disabled Voice page stays readable while its controls remain off.

## v1.0.16

- Added a native Add-on Hub.
- Added explicit dictation-language controls.
- Added touch-controller and bounded controller-command improvements.
- Added review-then-send Chat Composer behavior.
- Improved enrollment, stale-log, and reliability handling.

## Earlier releases

Earlier releases established the Forever launcher, interface modes, localization, add-on handling, UI recovery, voice, diagnostics, and source-built installation. Use the current guides for supported behavior rather than historical release notes.
