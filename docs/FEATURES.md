# What WolkaraForever adds

WolkaraForever is the World of Warcraft product layer over the vendored [Tolkara](https://github.com/tolkara/tolkara) engine. Tolkara loads an unchanged macOS application on iPadOS and translates the APIs it needs. WolkaraForever supplies the WoW-specific experience: obtaining and protecting a client, making input usable, and making the result observable without reading or modifying game memory.

This is the current feature map. It names the behavior, why it exists, the safety boundary, and the source or test that defines it. Dated device observations stay in [COMPATIBILITY.md](../COMPATIBILITY.md).

## Product shell and game lifecycle

The branded launcher is the normal entry point. It keeps state in the app container and disables actions that conflict with an update, active session, or absent installation.

| Capability | Behavior and reason | Boundary and proof |
| --- | --- | --- |
| Edition, region, language | Selects a supported WoW edition, Blizzard CDN region, and English or Spanish locale. Changing language in an installed Forever client updates only `textLocale` and `audioLocale`; it does not change the login portal. Region and locale are separate because they solve different user problems. | `WoW/WoWViewController.m`, `ForeverUI.m`; `test_forever_ui.sh`. |
| Install, repair, update | Fetches CDN metadata, stages verified files, reuses verified unchanged content, and blocks Play until a required update completes. | A partial game-tree replacement is worse than a failed update. `Client.m`, `Manifest.m`, `Updater.m`, `CASC.m`; `test_wow_launcher.sh`. |
| Play and leave | Starts the selected client through the chosen execution mode. The in-game toolbar's Leave control returns to the normal launcher state after guest exit. | The app must not leave a user trapped on an unusable guest screen. `Shell/`, `Touch/`; launcher and touch simulator fixtures. |
| Logging and diagnostics | Stores a redacted app log in the app container; device tools retrieve it without touching game files or manipulating an active session. | Reports need evidence without credentials, pairing data, teams, or device identifiers. `Shell/WolkaraForeverLog.*`, `pilot.sh log`, `device_log.sh`. |

See [the launcher reference](WOW_LAUNCHER.md) for the update state machine and [the user guide](USING_WOLKARAFOREVER.md) for visible controls.

## Add-ons and the user's UI

These features operate on files in the game's working directory. They never inspect game memory or alter the game's executable.

| Capability | Behavior and reason | Boundary and proof |
| --- | --- | --- |
| Archive import | Imports one add-on ZIP after validating entry paths, CRCs, limits, duplicate folders, and cleanup on failure. | An archive cannot escape the destination or leave a half-installed package. `AddonArchive.swift`, `AddonManager.m`; `test_addon_archive.sh`. |
| Managed add-ons | Lists packages and can disable, restore, pin, unpin, or remove packages the manager installed. | The manager tracks its own files and never removes an untracked user folder. `AddonStore.*`, `AddonManager.*`; `test_wow_launcher.sh`. |
| CurseForge | Searches metadata and downloads a chosen file with the user's Core API key. | The device-only key is not logged or committed; malformed responses and downloads do not become installed add-ons. `CurseForgeClient.*`, `AddonCredentialStore.*`; `test_curseforge.sh`. |
| UI backup and restore | Creates a verified ZIP of `WTF` except `Backups` plus `Interface`; restores through staging and a recovery journal. | Backups are named, digested, edition-bound, traversal-safe, and retained. A failed restore has a recovery path. `ForeverUIArchive.swift`; `test_forever_ui.sh`. |
| Graphics reset and preset | Removes only an explicit graphics/display CVar allowlist, or writes the documented performance preset. | Account, portal, locale, sound, bindings, gamepad, and unknown settings survive. `ForeverUI.m`; `test_forever_ui.sh`. |
| Gamepad UI | Normalizes exactly one `SET GamePadEnable` line. | It changes the game's native switch only; no bindings, controller profile, or touch layout is rewritten. `ForeverUI.m`; `test_forever_ui.sh`. |

See [the user guide](USING_WOLKARAFOREVER.md#performance-ui-manager). The [add-on plan](ADDON_MANAGER_PLAN.md) is historical design context; code and tests above define current behavior.

## Input, controls, and voice

Input travels through the layer's UIKit-facing code. This is user-initiated input, not a bot, macro system, or game-memory integration.

| Capability | Behavior and reason | Boundary and proof |
| --- | --- | --- |
| Touch toolbar and trackpad | Provides pointer, keyboard, gamepad, settings, and Leave controls; maps touch gestures to host input. | iPad has no native macOS pointer model, but the toolbar remains usable while the guest renders. `Touch/TouchControls.*`; `test_touch_controls_ui.sh`. |
| On-screen gamepad | Appears automatically without a physical controller; its layout, size, opacity, grid, rings, and haptics are configurable. | A usable default should not prevent per-device adjustment. `TouchGamepad.*`, `TouchGamepadLayout.*`, `TouchHaptics.*`; `test_touch_gamepad_ui.sh`. |
| Physical controller | Routes standard and extended GameController elements and includes an inspector for what a connected pad actually sends. | iPadOS reserves some buttons; the inspector prevents a false promise that every hardware control can be mapped. `Controller/`, `Input/`; [controller input](CONTROLLER_INPUT.md). |
| Dictation | Opens iPad speech recognition only after the user enables and triggers it; finalized text uses the same insertion path as typed text and targets the focused game field. | Recognition stays on device and never uses a cloud transcription service. `Voice/`, `Input/`; `test_voice.sh`. |
| Trigger ownership | Learns a key/controller element, supports Hold and Toggle, suppresses repeated presses, and can leave a controller button visible to the game. | Input cannot be assumed exclusive; the UI warns about collision risk until game mapping is measured. `Input/Trigger.*`, `InputRouter.*`; [input triggers](INPUT_TRIGGERS.md). |
| Test Voice and permissions | Verifies mapping and recognition before a game starts, and links to the system permission page. | A configured microphone is not proof that speech reaches the app. `VoiceTestViewController.*`; [voice](VOICE.md). |

The device scope for voice and controller behavior is deliberately bounded in [COMPATIBILITY.md](../COMPATIBILITY.md). Simulator tests validate routing and lifecycle, not a particular microphone, controller, or game screen.

## Performance and observability

| Capability | Behavior and reason | Boundary and proof |
| --- | --- | --- |
| Performance HUD | Shows renderer-sourced FPS/frame time, GPU information, thermal state, memory, battery, and low-power state; users can move and expand it. | It reads host metrics only and never changes graphics because a threshold was observed. `Touch/AKPerformanceOverlay.*`; `test_wow_launcher_ui.sh`. |
| Renderer timing | Attributes frames at the presentation boundary only when the marker proves a guest frame. | A display link is a scheduling signal, not proof of a submitted game frame. patches `0018`, `0019`, `0035`; [performance lanes](PERFORMANCE_LANES.md). |
| Backing scale and budget | Supplies backing scale and offers a measured performance preset. | It makes no universal frame-rate claim without matching device/build/scene evidence. patches `0023`–`0025`; [performance and thermal](PERFORMANCE_THERMAL.md). |
| Measurement tools | `perf_sweep.py` samples controlled variants; `capture_gameplay_log.sh` labels baseline/candidate evidence. | They refuse unsafe session state and write ignored artifacts under `logs/`. [tools reference](TOOLING.md). |

## Layer and safety architecture

`platform/` is the byte-identical Tolkara vendor tree. WolkaraForever code lives in `wolkaraforever/`; patches and `overlay.map` apply it to ignored `build/platform/`. That separation makes product changes and engine updates auditable.

- Never edit `platform/` for a WolkaraForever change. Add a layer file, overlay entry, or patch against the current pin.
- Run `wolkaraforever/tools/check_layers.sh` before trusting a build. It proves assembly and upstream identity, not runtime or device behavior.
- Use layer install, launch, game-copy, log, and pilot tools for device work. They inspect live state, preserve a session where possible, and establish a baseline.
- The original application executable is hash-verified data. It is never patched, re-signed, inspected after loading, or shipped in this repository.

Read [architecture](ARCHITECTURE.md), [maintaining the layer](MAINTAINING.md), [testing](TESTING.md), and [the tools reference](TOOLING.md) before changing code or running a device workflow.
