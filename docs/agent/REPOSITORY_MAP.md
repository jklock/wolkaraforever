# Repository map

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: tracked-file catalog

| Path | Role |
| --- | --- |
| `platform/` | Immutable, byte-identical Tolkara vendor tree (git subtree of `upstream/main`). Never edit directly. |
| `wolkaraforever/` | Product layer: overlay sources, patches, tools and tests. |
| `addons/` | Bundled WoW add-on source (`WolkaraRoue`). |
| `profiles/` | Product-owned profile data, plus one helper script in `wow-forever/`. |
| `docs/` | Standalone human documentation and approved public images. |
| `docs/agent/` | Agent-only current documentation and catalog. |
| `build/`, `logs/` | Ignored generated output. |

## Engine (`platform/`, vendored)

| Path | Contents |
| --- | --- |
| `runtime/` | Mach-O loading, guest memory, native execution (`SignedImage`, `DebuggerArena`), carried libraries, runtime stubs, interpreter diagnostics. |
| `translation/` | macOS API adapters: AppKit input and windowing, Metal, audio, Security. |
| `authorization/` | Developer service: pairing, transport, tunnel extension, memory-preparation protocol. |
| `launcher/` | The app: library, diagnostics and execution-mode controllers. |
| `management/` | Tolkara Management, the Mac setup app. |
| `profiles/`, `support/` | The application-profile format and shared support code. |
| `tests/`, `testguest/` | The engine's own suites and the synthetic guest fixture. |
| `tools/` | The engine's build, run, install, packaging and probe scripts. |
| `docs/`, `AGENTS.md` | The engine's own guides. They describe upstream Tolkara, not this fork's workflows. |

## Layer (`wolkaraforever/`)

Paths named in the Contents column are paths in the prepared tree (`build/platform/`), not at the
repository root.

| Path | Contents |
| --- | --- |
| `Shell/` | Entry point, execution mode, logging, localization tables, self-tests, app icon. |
| `WoW/` | Forever lifecycle: launcher page, CASC and updater, add-on manager and store, UI backup and restore, device profiles, experimental browser login. |
| `Touch/` | On-screen controls, the in-game overlay, interface mode and layout storage; its sources are also the `translation/AppKit/` adapter overlays. |
| `Input/`, `Controller/`, `Voice/` | Input routing, controller pointer and inspection, dictation and its audio-session coordinator. |
| `Bridge/` | Battery Saver policy, presentation pacing, display rate, local-service retry and the enrolment reference, overlaid into `authorization/App/`, `translation/Metal/` and `translation/AppKit/`. |
| `CoreAudio/` | `AKAudioModel`, the game's sound without iOS's audio device layer, overlaid into `translation/AKSupport/` and `launcher/WoW/`. |
| `Chat/` | The chat composer, overlaid into `translation/AppKit/`. |
| `NetworkHealth/` | The opt-in anonymous TCP health counter, overlaid into `runtime/`. |
| `AppKit/` | Its test only; the AppKit adapter sources live in `Touch/` and `Chat/`. |
| `Addons/` | The packaged add-on artifact the launcher installs. |
| `patches/` | The maintained patches against the pinned engine — the only way `platform/` behaviour changes. |
| `overlay.map` | Generated mapping from each layer file to the engine path it replaces; `check_layers.sh` proves it is current. |
| `tools/` | The layer's scripts: prepare, the gates, wrappers that run the engine's own scripts on the prepared tree, fixtures, packaging, and the documentation generators. |
| `tools/tests/` | Unit suites for the layer's scripts. Feature suites sit beside the tools as `test_*.sh`. |

## Assembly

`prepare.sh` exports `platform/` as committed into `build/platform/`, applies `patches/`, copies the
overlay named in `overlay.map`, then runs the engine's project generator. `check_layers.sh` proves
that boundary — the tree is byte-identical to upstream, every patch applies, every layer file is
carried by the overlay — and does not prove runtime behaviour.

## Refresh when

Refresh after a top-level layout, module ownership, overlay, patch, or generated-output change.
