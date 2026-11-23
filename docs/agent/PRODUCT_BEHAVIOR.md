# Product behavior

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: launcher source, localized strings, and focused suites

WolkaraForever lets a user choose a Forever region and game language; download, resume, verify, repair, and update game data; then start the unchanged executable through an available execution mode. The launcher also supports app localization, interface-mode selection, opt-in experimental Battle.net browser login (including one saved game password on the device), add-ons, UI recovery, keyboard/controller/touch input, dictation, Battery Saver Mode (one master switch over a frame limit and an AFK dim), measured device render profiles, an always-on battery-saving sound path, and diagnostics.

| Behavior | Human guide |
| --- | --- |
| Install, signing, first launch | [Installation](../INSTALLATION.md) |
| Build assembly, execution modes, run commands, packaging | [Build and run WolkaraForever](../BUILDING.md) |
| Game lifecycle, languages, experimental browser login, add-ons, recovery, controls, voice, Battery Saver Mode, the battery-saving sound path | [Using WolkaraForever](../USING_WOLKARAFOREVER.md) |
| Phone-specific interface and constraints | [iPhone](../IPHONE.md) |
| Supported boundary and issue reports | [Compatibility](../../COMPATIBILITY.md) |

The launcher records only managed add-ons for removal, stages updates and restores before replacement, and its optional network diagnostics record no addresses, ports, host names, payloads, credentials, or game data. An API key is device-local and optional; browser or Files acquisition remains available where appropriate.

A plain launch starts the game in the route the build carries: the `Tolkara` build uses Developer service, and the `TolkaraDiagnostics` package preselects External JIT. The route is stored on first use, and the shipped home page has no chooser and no library screen; the chooser and the library's **Execution Mode** button exist only on the development screens reached by a non-plain launch. `TOLKARA_MODE` and `--execution-mode=` are how a build and a development run choose the route.

## Refresh when

Refresh after any user-visible launcher, lifecycle, localization, input, add-on, recovery, diagnostics, or execution-mode change.
