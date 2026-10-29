<p align="center">
  <img src="docs/assets/wolkaraforever-logo.png" width="360" alt="WolkaraForever">
</p>

# WolkaraForever

> **Current as of 2026-10-29 · source revision `4934e20`**

**World of Warcraft Forever on iPad, running locally through Tolkara.**

WolkaraForever is a focused product layer for WoW Forever. It downloads, verifies, updates,
and starts the client on the iPad, then supplies the launcher, touch and controller interface,
voice input, add-on tooling, UI recovery, and diagnostics around it. It is not streamed from a
Mac. You provide the iPad, Apple development account, eligible WoW account, and game data;
this repository includes none of them.

## Credit and lineage

WolkaraForever builds directly on [Wolkara by fJavierLasso](https://github.com/fJavierLasso/wolkara),
which established the WoW-first launcher, on-device CDN lifecycle, and mobile-input direction.
It also retains [Tolkara](https://github.com/tolkara/tolkara), by Vasilii Kharitonov and the
Tolkara contributors, as its runtime, macOS API translation, and authorization foundation.

The current project is deliberately a layer rather than a private engine fork:

```text
platform/                 Tolkara, vendored byte-identical to upstream
        + patches/        narrow maintained changes to platform files
        + overlay.map     explicit mapping of WolkaraForever sources
        + wolkaraforever/ the product layer
        = build/platform/ generated build tree
```

The upstream history, MIT licence, and third-party notices are retained. See
[NOTICE.md](NOTICE.md) for source and reference attributions.

## What WolkaraForever provides

| Area | Current behavior |
| --- | --- |
| **Forever lifecycle** | Select Forever, a Blizzard CDN region, and English, Spanish, or German; download, resume, verify, repair, update, and start the selected client. Required updates finish before Play is available. |
| **Data integrity** | Reuses verified unchanged game data and stages updates so a partial replacement does not become a playable-looking broken installation. The original executable remains verified data, never a patched or re-signed repository artifact. |
| **Add-ons** | Browse installed packages, import a validated archive, open the add-on directory, and manage only packages the app recorded. CurseForge browsing/download uses an approved Core API key stored in the device Keychain. |
| **UI protection** | Create verified backups of `WTF` and `Interface`, restore through staging and a recovery journal, reset only graphics/display CVars, and write only `GamePadEnable` for the game's native gamepad UI switch. |
| **Input** | Use a toolbar, touch trackpad, in-game keyboard/draft entry, configurable on-screen gamepad, physical keyboard/controller input, and controller inspection. |
| **Voice** | Map a keyboard key or controller control to on-device dictation with Hold or Toggle behavior, Test Voice, permission routing, expected words, and focused-field insertion. |
| **Performance** | Show frame rate/frame time, GPU information, thermal state, memory, battery, and Low Power Mode. Background-aware pacing caps the Metal loop at 5 fps while inactive/backgrounded and restores normal pacing on foregrounding; iPadOS still controls background execution. |
| **Diagnostics** | Keep a redacted app log and expose Technical details, device-safe pilot commands, self-tests, and exact-SHA validation records. |

Read [Using WolkaraForever](docs/USING_WOLKARAFOREVER.md) for the operational guide and
[What WolkaraForever adds](development/technical/FEATURES.md) for the owning code and tests.

## Install from source

WolkaraForever is a source install, not an App Store, TestFlight, or public-IPA product. The
supported integrated route needs:

- an Apple-silicon Mac with current Xcode, Xcode command-line tools, XcodeGen, and Python 3;
- a paid Apple Developer membership with the required capabilities;
- an unlocked iPad in Developer Mode that trusts the Mac; and
- approximately 70 GB free for a Forever installation.

```sh
git clone https://github.com/jklock/wolkaraforever.git
cd wolkaraforever
cp local.env.example local.env
wolkaraforever/tools/install_prerequisites.sh --check
wolkaraforever/tools/device_variables.sh --write
wolkaraforever/tools/preflight.sh
wolkaraforever/tools/install.sh
```

Keep `TOLKARA_BUNDLE_ID` and `TOLKARA_KEYCHAIN_GROUP` stable in the private `local.env` file
so an update replaces the app without erasing its data or enrollment. The installer refuses to
replace a running game; use `--replace-running` only when you want it to request a clean stop.
`--force-kill` can interrupt a game-file write.

Full signing, first-launch, and recovery instructions are in
[Install WolkaraForever](docs/INSTALLATION.md).

## How Tolkara runs the client

Tolkara maps the unchanged arm64 macOS executable into a guest address space, applies the same
rebases and bindings dyld would, initializes carried libraries in dependency order, registers
the image with the Objective-C runtime, then enters the original `main`. File bytes stay
unchanged; loading state exists only in memory.

Imports resolve, in order, to a small loader-owned surface, symbols in the loaded image, a
translation library, or the corresponding iPadOS framework. The loader provides the functions
needed to describe its own image and memory behavior—such as mapping/protection, cache flush,
JIT write protection, dynamic-symbol lookup, bundle/executable paths, TLS bootstrap, dyld stub
binding, and selected synchronization/signal handling. Imports that no supported provider can
satisfy fail for a targeted build; generic builds use bounded diagnostic stubs only where
build-time analysis could not classify an import.

The translation layer adapts macOS APIs to iPadOS where the operating systems differ:

- **AppKit** becomes UIKit-backed application, window, event, pointer, keyboard, text, cursor,
  image, menu, alert, screen, and nib behavior.
- **Metal** uses the iPad GPU. Shader libraries are validated and rewrapped around unchanged AIR
  bitcode for the iPad's compiler; unsupported shader input stops with a diagnostic rather than
  silently substituting graphics work.
- **Audio, display, keyboard-layout, Security, and related APIs** are bridged to the appropriate
  iPadOS frameworks or narrowly implemented where required.

More detail is in [Architecture](development/architecture/ARCHITECTURE.md).

## Executable-memory modes

iPadOS normally requires executable pages to be code-signed. Tolkara supports three distinct
modes; the user chooses the one that applies. The integrated WolkaraForever route is Developer
service.

| Mode | Mechanism | Boundary |
| --- | --- | --- |
| **Developer service** | The app's tunnel reaches the iPad developer service to prepare a bounded memory region, verifies it, and confirms debugger detachment before guest bytes are copied or run. | The tunnel carries one private route; pairing material stays in the device-only Keychain. No game code is signed. |
| **Local signing** | A locally built page container holds the final code pages and is signed with the user's own identity. The runtime verifies the container's size, header, load commands, and byte relationship to the executable before mapping pages. | The container is derived locally and remains ignored build/device output. No debugger is involved. |
| **External JIT** | The unsigned generic Diagnostics build is signed by the user's sideloading tool; a JIT enabler prepares executable memory at launch. | Entry is refused while a debugger remains attached or the arena is not executable. This is an engineering route, not a general consumer install. |

No mode patches, re-signs, or redistributes the original executable. For protocol and page-container
detail, see [Local authorization](development/architecture/LOCAL_AUTHORIZATION.md).

## What has been tested—and what has not

The repository separates source, simulator, and physical-device evidence. A passing test does
not become a device claim.

```sh
wolkaraforever/tools/check_layers.sh          # platform identity, patches, overlay, boundaries
wolkaraforever/tools/check_docs.sh            # Markdown links, images, anchors
wolkaraforever/tools/test_emulation.sh        # platform and layer regression suites
wolkaraforever/tools/test_translation_sim.sh  # UIKit-backed adapter tests
wolkaraforever/tools/test_wow_launcher.sh     # downloader, updater, verification
wolkaraforever/tools/test_forever_ui.sh       # backup, restore, CVars, gamepad, locale
wolkaraforever/tools/validate.sh --full       # clean-tree, exact-SHA validation record
```

Physical results are meaningful only when they name the source revision, device, iPadOS, client
build, and execution mode. [Compatibility](COMPATIBILITY.md) states that boundary and points to
dated validation records; it is not a universal compatibility promise.

## Safety policy

WolkaraForever is a compatibility layer, not a tool for modifying or automating a game. It does
not accept or provide:

- binary patches, re-signing, redistribution, or repository storage of game code/assets;
- reading or changing a running game's memory beyond loading and image verification;
- bots, trainers, macros, or other gameplay automation; or
- anti-cheat, licence, account, or integrity-check workarounds.

The project does not hide the iPad, operating system, process state, or debugger status from the
client. Before guest entry, temporary debugger involvement used for memory preparation must be
gone; nothing attaches afterwards. Use your own account and comply with the game's licence and
service terms. Blizzard does not support or endorse this project, and successful execution is
not a guarantee of account safety.

## Development and maintenance

The public user guide is under [docs/](docs/README.md). Engineering material is under
[development/](development/README.md):

- [Project map](development/architecture/PROJECT_MAP.md) — modules, scripts, and product deltas.
- [Repository workflow](development/guides/REPOSITORY_WORKFLOW.md) — branch protection, reviews,
  required checks, exact-SHA evidence, releases, and upstream ingests.
- [Tooling](development/guides/TOOLING.md) and [Testing](development/testing/TESTING.md) — command
  reference and what each test proves.
- [Contributing](development/guides/CONTRIBUTING.md) — code and data boundaries.

`platform/` must remain byte-identical to Tolkara upstream. Product changes belong in
`wolkaraforever/` through a layer file, patch, and/or `overlay.map` entry. Use the repository
skill at [`.codex/skills/wolkaraforever-maintenance/`](.codex/skills/wolkaraforever-maintenance/)
for Codex work in this checkout.

## Legal

WolkaraForever, Wolkara, and Tolkara source lineage is released under the [MIT License](LICENSE).
No game files or Apple operating-system components are included. Reference implementations and
third-party licence text are listed in [NOTICE.md](NOTICE.md).

WolkaraForever is independent and is not affiliated with, sponsored by, or endorsed by Apple or
Blizzard Entertainment. macOS, iPadOS, iPad, Metal, and Xcode are trademarks of Apple. World of
Warcraft and Blizzard are trademarks of Blizzard Entertainment. Other names belong to their
respective owners and are used only to describe compatibility.
