# Testing

Every claim this project makes has a script behind it, and the script's own output is
what counts. This page is how to run the suites, what each one proves, and what only a
person or a device can prove.

> **Paths.** From the repository root, layer scripts are `wolkaraforever/tools/...`. A bare
> `tools/...` in an older document means `wolkaraforever/tools/...`. The platform's own
> suites are run for you against the prepared tree at `build/platform/`.

## The one command

```bash
wolkaraforever/tools/test_emulation.sh
```

This is the regression suite. In order:

1. `prepare.sh` exports `platform/` and applies the layer.
2. `check_layers.sh` runs first - if the split itself is out of shape, everything after it
   would prove nothing.
3. The platform's own suite runs against the prepared tree, so it covers the runtime and
   the adapters *as we ship them*, including every patch the layer carries.
4. Every layer suite `wolkaraforever/tools/test_*.sh` runs, except the UI fixtures (they
   need a simulator) and the umbrella itself.

Compiler warnings are errors (`-Wall -Wextra -Werror`), and the native suites run under
ASan and UBSan where configured. A failing layer suite fails the run.

## Choose the smallest command that can prove the change

Run the narrowest row first. A broader row is useful only after the focused behavior
passes; it does not turn simulator evidence into a device result.

| Changed area | First command | Then, if the change crosses a boundary | What the result means |
| --- | --- | --- | --- |
| `WoW/ForeverUI.*` or archive code | `test_forever_ui.sh` | `test_wow_launcher_ui.sh` for a visible row | Config and archive rules / launcher presentation in a simulator. |
| Updater, manifest, CASC, or install state | `test_wow_launcher.sh` | `test_wow_launcher_ui.sh` | Synthetic CDN, staging, repair, and launcher state; no real CDN account or game run. |
| Add-on archive or manager | `test_addon_archive.sh` or `test_curseforge.sh` | `test_wow_launcher.sh` | ZIP/provider contract and managed-files lifecycle. |
| Voice or mapped input | `test_voice.sh` | `test_wow_launcher_ui.sh`; device self-test if appropriate | Routing, permissions handling, and session lifecycle; not proof that a person was heard. |
| Toolbar, trackpad, or touch gamepad | `test_touch_controls_ui.sh --self-test` or `test_touch_gamepad_ui.sh --self-test` | `test_translation_sim.sh` | UIKit event/layout behavior in a simulator. |
| Patch, overlay, runtime, or adapter code | `check_layers.sh` plus the affected suite | `test_emulation.sh`; `test_translation_sim.sh` for UIKit adapters | Prepared-tree assembly and host regression coverage. |
| Device script | matching `wolkaraforever/tools/tests/test_*.sh` | `preflight.sh`, then the requested safe device operation | Script logic first; a real-device result only after the real operation. |

All commands in this table are `wolkaraforever/tools/<command>` from the repository
root. The full names are intentional: they distinguish product-layer tools from
Tolkara's tools inside `platform/` or `build/platform/`.

## What is covered

| Suite | What it proves |
| --- | --- |
| Platform suite (`test_emulation.sh`) | Memory semantics, malformed Mach-O input, fixups, packaging, the pairing/tunnel/debug protocols against independent peers, the page-container contract, the signer, a macOS end-to-end container load, shader containers, keyboard/text input, and crypto parity with macOS. |
| Adapter simulator suite (`test_translation_sim.sh`) | The UIKit-backed adapters: touch controls, gamepad, haptics and fonts, exercised in the simulator with the layer overlaid. |
| Launcher (`test_wow_launcher.sh`) | The WoW launcher's suites: editions, download, verification, resume, updates. |
| Launcher UI (`test_wow_launcher_ui.sh`) | Our own synthetic launcher fixture - no game files, accounts or network. Set `SIMULATOR`. |
| Touch controls UI (`test_touch_controls_ui.sh`) | The toolbar, trackpad and layout fixture. |
| Gamepad UI (`test_touch_gamepad_ui.sh`) | The on-screen controller fixture. |
| Voice (`test_voice.sh`) | Input, dictation and configuration rules, as a tiny app in the simulator. |
| Forever UI (`test_forever_ui.sh`) | The `Config.wtf` rules and the Forever UI archive (backup/reset/restore). |
| Add-on archive (`test_addon_archive.sh`) | The production Swift extractor and the app's pinned ZIPFoundation. |
| CurseForge (`test_curseforge.sh`) | The CurseForge client against its expected request/response shapes. |
| Icon assets (`test_icon_assets.sh`) | The generated app icon: 1024 square, opaque, non-empty, and a catalog that names exactly the files present. |
| Local-service retry (`test_local_service_retry.sh`) | The retry engine and packet-service probe. |

### Tests of the tools themselves

`wolkaraforever/tools/tests/` tests the guardrails around device work without changing a
device: `test_after_install.sh`, `test_device_variables.sh`,
`test_install_prerequisites.sh`, `test_pilot.sh`, `test_preflight.sh`,
`test_push_game.sh`, `test_running_app.sh`, `test_validate.sh`, and
`test_xcrun_device_timeout.sh`. `make_addon_archives.py` produces intentionally valid
and invalid add-on archives used by the production extraction tests. Run a tool test
when changing its script; do not substitute it for an install, copy, or launch result.

The UI fixtures build and open *our* input fixtures, never an imported application.

## The device matrix

```bash
wolkaraforever/tools/device_matrix.sh
```

This is the part of the physical-iPad matrix a Mac can drive on its own:

1. the device can be inspected at all;
2. a fresh install, and a user's file surviving it;
3. a config file the user edited being imported;
4. a malformed config file being refused, kept, and survived;
5. the notices the installed app carries;
6. being put away and brought back with nothing left listening or recording;
7. the app's own self-tests on the installed build;
8. no new crash report and no new game error file.

Some checks need a person - speaking into the iPad, pressing a pad button - and are
listed as deferred at the end of the script rather than pretended. Record device results
in [COMPATIBILITY.md](../COMPATIBILITY.md).

## The app's own self-tests

The app runs checks on itself when launched with `--selftest=<name>`. `pilot.sh selftest
<name>` runs one and reads the verdict.

| Name | What it checks |
| --- | --- |
| `input` | Drives the real input router, settings store and published key set with synthetic presses. |
| `voice` | Opens a real dictation session with the real recogniser (on-device only) and checks the session is handed back. |
| `dictation-target` | Asks the object registered as the game's text input whether it takes words and keys. |

They assert session state and wiring; they do not prove the microphone delivered audio or
that a person spoke. That is why a real voice or a real pad still needs a person.

## Recording evidence

```bash
wolkaraforever/tools/validate.sh            # fast suites, write a record
wolkaraforever/tools/validate.sh --full     # add the slow platform suites
wolkaraforever/tools/validate.sh --device   # also install and pilot on the iPad
```

`validate.sh` writes one file per commit under `development/validation/`, naming the
commit, whether the tree was clean, the host and Xcode, every command with its exit
status, and the tail of what it printed. It refuses a dirty tree unless you pass
`--allow-dirty`, and scrubs device identifiers from the output so the record can be
committed. A run that names a commit it did not build is worse than no evidence; that is
what this script exists to prevent.

When the platform's suite fails only on failures the platform itself owns, the list in
[`known_platform_failures.txt`](../wolkaraforever/tools/known_platform_failures.txt) names
them. Anything not on that list fails the run, and the known failures are still reported,
never hidden.

## Testing without a device

```bash
wolkaraforever/tools/test_emulation.sh     # sanitizer regression suite on the Mac
wolkaraforever/tools/run.sh sim            # loader diagnostics in the simulator
TOLKARA_MODE=local-signing wolkaraforever/tools/run.sh sim   # Local signing against the fixture
```

The simulator runs the `TolkaraDiagnostics` scheme against the synthetic test application
in `testguest/`. Simulator builds need no signing team. A simulator pass says nothing about
Metal behaviour or native execution on a real device.

## Adding a test

- Add a layer test as `wolkaraforever/tools/test_<area>.sh`; `test_emulation.sh` picks it
  up automatically unless its name ends in `ui.sh` (those are run directly, needing a
  simulator) or it is the umbrella itself.
- Add a unit test beside the code it covers, named `test_*.{c,m,swift,py}`.
- Cover memory bounds, malformed input, protocol failures and adapter behaviour you touch.
- Prefer a synthetic fixture over anything imported from an application. See the
  ground rules in [CONTRIBUTING.md](../CONTRIBUTING.md).

## What still needs a person

A script cannot press a pad button, speak into the microphone, or judge whether the game
plays well. Those results are recorded by date in [COMPATIBILITY.md](../COMPATIBILITY.md).
If something fails, include the exact message from Settings -> Technical details and a
redacted log - never account, pairing or device-identifier information.
