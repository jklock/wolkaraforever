# Build and run WolkaraForever

> Verified: 2026-11-16 · Source: `9680e63`

This guide covers the mechanisms behind a WolkaraForever build: how the tree is assembled, the
three ways the runtime can execute an application, and the commands that build, install, run,
and package the app. Read [Install WolkaraForever](INSTALLATION.md) first if you only want the
supported install path.

Every command below runs from the repository root. The engine is vendored at `platform/` and is
never edited by hand; `wolkaraforever/tools/` is the layer that prepares and drives it.

## How a build is assembled

`wolkaraforever/tools/prepare.sh` produces `build/platform/`:

1. `git archive HEAD:platform` exports the vendored engine as committed, so `platform/` stays
   byte-identical to upstream.
2. `wolkaraforever/tools/apply.sh` applies `wolkaraforever/patches/*.patch` and then copies the
   layer's files into the paths the engine's own build expects (`wolkaraforever/overlay.map`).
3. The engine's project generator runs **after** the overlay, so layer files that arrive with
   the overlay are compiled rather than silently resolved to nil at runtime.

`build/platform/` is ignored output and can be deleted at any time. Because the layer half comes
from the working tree, `prepare.sh` says so out loud when the tree is dirty; `validate.sh` refuses
to produce evidence on a dirty tree.

A command sequence, therefore, is always "prepare, then run the engine's own script on the
prepared tree". The wrappers in `wolkaraforever/tools/` do exactly that, which is why the engine
scripts under `build/platform/tools/` are never called directly for a normal build.

## Execution modes

The runtime can start an application's code in one of three ways. The mode is a device-side
choice stored by the app; a build can preselect it with `TOLKARA_MODE` in `local.env`, and a
development launch can override it for one run with `--execution-mode=`.

| Mode | What it needs | Where the code executes |
| --- | --- | --- |
| Developer service | Developer Mode, plus a one-time enrollment from a Mac so the iPad's own developer service prepares memory | The developer service's arena; the service detaches before any application code runs |
| Local signing | A page container derived from the application's code pages, signed with your own developer identity on a Mac, copied to the app's `Documents/LocalSigning/` | A signed page container (`SignedImage`) |
| External JIT | A JIT enabler that attaches at launch, prepares memory, and detaches again | The `DebuggerArena`; the runtime refuses guest entry while anything is still attached |

Which build offers which mode:

| Build | Developer service | Local signing | External JIT |
| --- | --- | --- | --- |
| `Tolkara` (the app `install.sh` builds) | Yes | Yes | Shown as unavailable: not included in this build |
| `TolkaraDiagnostics` (the unsigned `.ipa`) | Shown as unavailable | Yes | Yes |

The app asks the first time you start a game: starting with no mode chosen opens the chooser and
the game starts once you choose, so the first choice cannot be skipped. Change it later with the
**Execution Mode** button on the library screen. In a build made with `TOLKARA_MODE` set, that
preselection becomes the stored choice on first use.

Each mode's own setup, and what to do when it is not ready, is in
[Install WolkaraForever](INSTALLATION.md) and in
[Use WolkaraForever](USING_WOLKARAFOREVER.md). Two limits are worth knowing before choosing:

- Local signing needs a container that matches the executable. A container built from the
  on-disk code is valid only for an application that does not rewrite its own code at launch;
  where it does, the container must come from a capture of the final code pages
  (`TOLKARA_CAPTURE`), which the tooling cannot produce for every application. A container that
  does not match stops the launch before more application code runs, and
  `Documents/native-guest.log` says why (`[signed-image] FATAL …`).
- External JIT needs the enabler at every launch and refuses guest entry while any debugger
  remains attached. It is a diagnostics route, not the supported integrated one.

## Build and install the app

```sh
cp local.env.example local.env     # once: DEVELOPMENT_TEAM, TOLKARA_BUNDLE_ID
wolkaraforever/tools/install.sh
```

`install.sh` runs five steps and stops on the first failure:

0. **Guard** — refuses to install while the app or the game is running. Replacing the app
   underneath a live client corrupted its update index once; `--replace-running` stops it
   cleanly first, and `--force-kill` is the explicit escalation that is never implied.
1. **Prepare** — `wolkaraforever/tools/prepare.sh`.
2. **Build** — the engine's own `install.sh` on the prepared tree, which builds and signs our
   code only, then installs it. `--build-only` stops here and never touches the device, so a
   compile error costs nothing; with no iPad attached it builds for the generic iOS destination.
3. **After the install** — decided by `TOLKARA_MODE`
   (`wolkaraforever/tools/after_install.sh`): Developer service enrolls the developer service;
   Local signing checks that the page container for this build's executable is on the device;
   External JIT does nothing, because its enabler acts at launch. With no mode chosen, nothing
   is enrolled yet.
4. **Verify** — the device is asked to list the bundle.
5. **Return to the launcher** — the app is relaunched plainly, so an install never leaves a
   development status screen up.

A private device build may use this Mac's public trust roots. `install.sh` refuses
`TOLKARA_SYSTEM_ROOTS=NO`; that switch belongs to the redistributable unsigned `.ipa`.

Installing replaces the app under the same bundle ID and keeps its data, so updating is the same
command again with the same `local.env`.

## Run it

```sh
wolkaraforever/tools/launch.sh              # the launcher, so its own checks run
wolkaraforever/tools/launch.sh --restart    # stop a running session cleanly first
wolkaraforever/tools/pilot.sh state         # what the device is doing right now
wolkaraforever/tools/pilot.sh cycle         # state, install, launch, wait, view
wolkaraforever/tools/device_log.sh          # Documents/native-guest.log
```

`launch.sh` refuses to launch while the app is already running rather than replacing the process,
and it records the newest client error file before launching so the run can be judged afterwards.
`--restart` stops the session with SIGTERM first so the client can close its own stores.

`pilot.sh` is the scripted version of the same loop and is deliberately willing to refuse:
`state`, `stop`, `install`, `launch`, `game`, `wait`, `view`, `crash`, `log`, `leave`, `return`,
`restore`, `selftest`, `cycle`. Every command that launches records baselines first, so "did it
fail?" is answered by comparison — a new file in `Documents/World of Warcraft/_forever_/Errors/`
or a new crash report means the launch failed.

## Run in the simulator

```sh
wolkaraforever/tools/run.sh sim                       # loader diagnostics
SIMULATOR=iphone wolkaraforever/tools/run.sh sim
TOLKARA_MODE=local-signing wolkaraforever/tools/run.sh sim
wolkaraforever/tools/run.sh device                    # the same loop on the iPad
```

`run.sh` prepares the tree and runs the engine's own run script, which builds the
`TolkaraDiagnostics` scheme, installs it, launches it, and captures console and crash logs.
Simulator runs resolve the device through `wolkaraforever/tools/simulators.sh`, so only the two
matrix simulators are accepted; `SIMULATOR=` cannot widen the matrix.

The engine's run script accepts an empty, `developer-service`, or `local-signing` `TOLKARA_MODE`.
External JIT is never passed to it: that route needs an enabler, not a simulator.

## Build in Xcode

```sh
wolkaraforever/tools/open_xcode.sh          # prepare, generate, open build/platform/Tolkara.xcodeproj
wolkaraforever/tools/generate.sh            # generate only
```

The project is generated disposable output — `generate.sh` rewrites it, so keep personal settings
in `local.env`. An Xcode build of the `Tolkara` scheme carries the generic compatibility libraries
(the same as `NATIVE_GUEST_SHIMS=GENERIC`), and its scheme starts the app without Xcode's
debugger, which must not stay attached to a game.

## Build the unsigned External JIT IPA

```sh
wolkaraforever/tools/package_altstore_ipa.sh            # verify, then build/ipa/Tolkara-unsigned.ipa
wolkaraforever/tools/package_ipa.sh [output.ipa]        # the engine's own packaging script
wolkaraforever/tools/verify_ipa.sh <ipa> [report]       # check one before it is sideloaded
```

The `.ipa` is `TolkaraDiagnostics`, built generic (one adapter per translated framework, no
particular application), unsigned, and with External JIT preselected. Only our own code goes in:
no application code, no signing team, no provisioning profile, and no root certificates copied
from this Mac (`TOLKARA_SYSTEM_ROOTS=NO`). Your sideloading tool — or a JIT enabler it installs —
signs the app with your own Apple ID and provides the memory that External JIT needs.

`package_altstore_ipa.sh` refuses a dirty source tree and verifies the result before reporting
success. A `v*` tag publishes the same artifact as `Tolkara-unsigned.ipa`. The bare
`package_ipa.sh` writes into the prepared tree, which the next `prepare.sh` deletes; pass an
output path under `build/ipa/` if you want to keep the result.

## Test devices

| Device | Kind | Requirement |
| --- | --- | --- |
| iPhone Duo | simulator | required for every change |
| iPad Pro 13-inch (M5) | simulator | required for every change |
| iPad Pro 12.9-inch (5th generation) | physical iPad | welcome, recorded, never a release blocker |

`wolkaraforever/tools/setup_simulators.sh --apply` creates at most those two simulators and never
deletes one. Do not create a simulator, and do not substitute a nearby device: a suite that cannot
find its matrix device fails and says so. A simulator result is not evidence about physical Metal,
authorization, or performance; say which device ran when you report a result.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `prepare.sh` says the tree is dirty | Expected while developing; commit before producing evidence. |
| `install.sh` refuses to replace the app | Something is running. Stop it from the app, or use `--replace-running`. |
| The build fails and nothing reached the iPad | Rerun with `--build-only` and read `build/platform/logs/install-*.log`. |
| Developer service is "not ready" | The enrollment is missing: run `wolkaraforever/tools/install.sh` again with `TOLKARA_MODE=developer-service`, which enrolls for you. |
| The app says a page container is missing | Build with `TOLKARA_MODE=local-signing`, or copy the container for this executable's SHA-256 into `Documents/LocalSigning/`. |
| The app says External JIT is unavailable | That is the `Tolkara` build. External JIT is offered by the unsigned `TolkaraDiagnostics` `.ipa`. |
| A `devicectl` call hangs | Lock the iPad, unlock it, confirm trust and Developer Mode, then rerun `wolkaraforever/tools/preflight.sh`. |

Read [Compatibility](../COMPATIBILITY.md) for the support boundary, and
[Security](../SECURITY.md) to report a vulnerability.
