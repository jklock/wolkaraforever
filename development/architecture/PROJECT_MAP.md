# WolkaraForever project map

> **Current as of 2026-10-30 · branch `main`.**

WolkaraForever is a WoW-focused product layer over Tolkara. Tolkara supplies the runtime,
translation adapters, authorization, and generic launcher foundation; WolkaraForever supplies
the branded launcher, Forever lifecycle, usable iPad input, user-data protection, performance
observability, and safe device workflows.

## Assembly model

```text
platform/                 pinned Tolkara tree; byte-identical to upstream
        + patches/        small maintained deltas against platform files
        + overlay.map     explicit source-to-prepared-tree mapping
        + wolkaraforever/ product modules
        = build/platform/ generated build tree
```

`wolkaraforever/tools/prepare.sh` creates `build/platform/`, applies every patch, copies every
overlay, and generates the project after the complete tree exists. `check_layers.sh` rejects
platform drift, a patch that no longer applies, an overlay collision/missing destination, or a
cross-module reach-in. Never edit `platform/` directly.

## Product modules

| Module | Responsibility | Key additions over Tolkara |
| --- | --- | --- |
| `Shell/` | Branded app shell and lifecycle | WolkaraForever branding, theme, icon, configuration recovery, redacted logging, execution-mode glue, app self-tests, the app's own language service and its `en`/`de` string tables. |
| `WoW/` | Forever client lifecycle | CDN metadata, install/update/verify/resume, CASC handling, edition/region/locale choices, safe update lock, launcher UI. |
| `WoW/` add-ons and UI | User-owned game files | Validated archive import, managed package state, device-Keychain CurseForge credentials, browse/download, UI backup/restore, graphics-only reset, locale and `GamePadEnable` writes. |
| `Touch/` | iPad game interaction | In-game toolbar, trackpad, keyboard/draft path, on-screen gamepad, layout editor, haptics, performance overlay. |
| `Input/`, `Controller/`, `Voice/` | User-triggered input | Physical-controller inspection/routing, learned button/key triggers, Hold/Toggle dictation, speech lifecycle, Test Voice, permission flow, focused-field insertion. |
| `Bridge/` | Product hooks into the platform | Background frame pacing, local-service retry, and product-owned integration hooks. |
| `CoreAudio/` | Audio adapter support | Product test coverage for the host playback lease. |
| `patches/` | Narrow upstream changes | Input/voice hooks, audio session ownership, performance timing/HUD/backing-scale work, prepare pipeline, release profile, and safety gates. |

The full behavioral inventory and owning tests are in
[What WolkaraForever adds](../technical/FEATURES.md).

## User-visible enhancements

- A Forever-first launcher that downloads, resumes, verifies, updates, and starts a selected
  client without shipping game data.
- Separate region and language choices; for a ready Forever install, language changes text and
  audio locale together without changing the login portal.
- A separate app language (English, German, or the iPad's preference) for everything
  WolkaraForever draws, applied without a relaunch, with English as the fallback and a one-time
  offer to put the *game* into German; see
  [localization](../guides/LOCALIZATION.md).
- Add-on import and management that only deletes packages it recorded; CurseForge access with a
  device-local Core API key.
- Verified UI archive/restore with staging, journal recovery, digest checks, traversal defence,
  backup retention, graphics-only reset, and one-setting gamepad enablement.
- Toolbar, touch trackpad, keyboard and draft entry, configurable on-screen gamepad, physical
  controller routing and inspection, and opt-in voice dictation with Hold/Toggle controls.
- Performance HUD and renderer timing work that observes frame, GPU, thermal, memory, battery,
  and Low Power Mode without changing game graphics automatically.
- Background-aware Metal pacing: background/inactive state is capped at 5 fps and foreground
  returns to display-rate pacing; iPadOS still owns the app's execution lifetime.
- Device-safe installation and pilot scripts that avoid replacing or killing a client while it
  may be writing its data store.

## Script map

| Purpose | Commands |
| --- | --- |
| Prepare and inspect the layer | `prepare.sh`, `check_layers.sh`, `overlay_map.sh`, `update_tolkara.sh --check` |
| Local setup | `install_prerequisites.sh --check`, `device_variables.sh --write`, `preflight.sh`, `generate.sh` |
| Build and device lifecycle | `install.sh`, `launch.sh`, `pilot.sh`, `running_app.sh`, `device_log.sh` |
| Game data lifecycle | `push_game.sh`, `remove_game.sh`; use only when the app is safe to touch |
| Source and simulator verification | `test_emulation.sh`, `test_translation_sim.sh`, focused `test_*.sh`, `run.sh sim` |
| Device evidence | `device_matrix.sh`, `capture_gameplay_log.sh`, `validate.sh --device` |
| Documentation and release | `check_docs.sh`, `package_ipa.sh`, `make_wolkaraforever_icon.py` |

See [Tooling](../guides/TOOLING.md) for arguments and operational safeguards, and
[Testing](../testing/TESTING.md) for what each check proves.

## Evidence boundaries

Source tests prove code paths and data safety. Simulator tests prove the project’s UIKit-backed
fixtures. Device scripts prove only the recorded installed build and script-observable result.
Human actions—speech, controller use, login, gameplay quality—require a person and a report
bound to device, iPadOS, client build, execution mode, and source SHA. Preserve that distinction
in reviews, documentation, and release notes.
