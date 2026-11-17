# Product behavior

> Verified: 2026-11-16 · Source: `9680e63` · Proof: launcher source, localized strings, and focused suites

WolkaraForever lets a user choose a Forever region and game language; download, resume, verify, repair, and update game data; then start the unchanged executable through an available execution mode. The launcher also supports app localization, interface-mode selection, add-ons, UI recovery, keyboard/controller/touch input, dictation, battery settings (a frame limit and an AFK saver), and diagnostics.

| Behavior | Human guide |
| --- | --- |
| Install, signing, first launch | [Installation](../INSTALLATION.md) |
| Build assembly, execution modes, run commands, packaging | [Build and run WolkaraForever](../BUILDING.md) |
| Game lifecycle, languages, add-ons, recovery, controls, voice, battery (frame limit, AFK saver) | [Using WolkaraForever](../USING_WOLKARAFOREVER.md) |
| Phone-specific interface and constraints | [iPhone](../IPHONE.md) |
| Supported boundary and issue reports | [Compatibility](../../COMPATIBILITY.md) |

The launcher records only managed add-ons for removal, stages updates and restores before replacement, and keeps diagnostics redacted. An API key is device-local and optional; browser or Files acquisition remains available where appropriate.

The first start of a game with no execution mode chosen opens the mode chooser and cannot be skipped; the choice is stored and can be changed afterwards from the **Execution Mode** button on the library screen. A build can preselect the mode with `TOLKARA_MODE`.

## Refresh when

Refresh after any user-visible launcher, lifecycle, localization, input, add-on, recovery, diagnostics, or execution-mode change.
