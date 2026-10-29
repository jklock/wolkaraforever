<p align="center">
  <img src="docs/assets/wolkaraforever-logo.png" width="320" alt="WolkaraForever">
</p>

<h1 align="center">WolkaraForever</h1>

<p align="center"><strong>World of Warcraft Forever on iPad, built on <a href="https://github.com/tolkara/tolkara">Tolkara</a>.</strong></p>

WolkaraForever installs a WoW client on an iPad and plays it there. The game downloads
from Blizzard's CDN, runs locally through Tolkara's compatibility layer, and takes touch,
controller and dictation input. Nothing is streamed from a Mac.

It is an experimental source release: you build it with Xcode and your own Apple developer
account. There is no IPA, App Store or TestFlight build.

## Credits

It continues [Wolkara](https://github.com/fJavierLasso/wolkara) by Javier Lasso, where the
WoW launcher, updater and input layer began, on
[Tolkara](https://github.com/tolkara/tolkara) by Vasilii Kharitonov and contributors, which
supplies the engine. MIT licence; the original copyright lines are kept in
[LICENSE](LICENSE) and every other source is credited in [NOTICE.md](NOTICE.md).

Two upstreams, kept apart on purpose: `upstream` is Tolkara, vendored byte-identical into
`platform/`; `fJavierLasso` is the original Wolkara, ported feature by feature. See
[Maintaining](docs/MAINTAINING.md#two-upstreams).

## What you need

- An Apple silicon Mac with Xcode, XcodeGen (`brew install xcodegen`) and Python 3.
- A **paid** Apple developer account. The app and its tunnel need Network Extension,
  increased memory limit and extended address space; free Personal Team signing cannot
  provide them.
- An iPad with Developer Mode on, trusted by the Mac, and room for the game (~70 GB).
- Your own WoW account. Game files come from Blizzard; none are included here.

## Build and install

```bash
git clone https://github.com/jklock/wolkaraforever.git
cd wolkaraforever
cp local.env.example local.env    # DEVELOPMENT_TEAM, TOLKARA_BUNDLE_ID, TOLKARA_KEYCHAIN_GROUP, DEVICE
wolkaraforever/tools/install.sh   # prepare, build, sign, install, enroll, relaunch
```

`--build-only` stops after the build. To use Xcode instead: run
`wolkaraforever/tools/generate.sh`, open `build/platform/Tolkara.xcodeproj`, run the
**Tolkara** scheme — the app on the device is called **WolkaraForever** — then enroll once
with `cd build/platform && tools/enroll.sh`.

A checked walkthrough is in [From zero to playing](docs/FROM_ZERO.md).

## Play

Choose an edition, region and language, press **Install**, and keep the app in front while
it downloads. At **Ready to play**, press **Play**, allow the local tunnel if iPadOS asks,
wait out memory preparation (minutes, every launch), and log in.

- **Updates** run in the app, on open and before Play: resumable, checksum-verified, and
  they keep your settings and add-ons.
- **Add-ons**: import a ZIP from Files or browse CurseForge. The manager can disable,
  restore, pin and remove what it installed, and never deletes a folder it did not create.
- **Input**: on-screen keyboard with dictation, a trackpad with two-finger scrolling, an
  on-screen controller, physical controllers, and any button or key mapped to dictation.
- **Leave game** closes the app from the in-game toolbar after a countdown, so a screen
  with no quit is not a dead end. Play works again on the next launch.

## Execution modes

You choose how the executable reaches memory. All three leave the original file untouched.

| Mode | Memory prepared by | What is signed |
| --- | --- | --- |
| **Developer service** (default) | the iPad's developer service over the app's tunnel; the debugger detaches before any application code runs | only our code |
| **External JIT** | a JIT enabler you already run, such as StikDebug; the runtime asks it to detach and refuses entry while anything is attached | only our code; your tool signs the app |
| **Local signing** | a page container built from the app's final code pages and signed with your own identity | the container only |

Details: [build and execution modes](docs/BUILDING.md).

## Status

Login, gameplay, touch controls, controllers, dictation, updates, add-ons and backup/restore
work on the development iPad Pro M5 (iPadOS 27). 60 FPS at graphics quality 4 is a gameplay
report, not a benchmark. Other devices and editions need testing: dated results are in
[COMPATIBILITY.md](COMPATIBILITY.md), per-feature proof in
[What WolkaraForever adds](docs/FEATURES.md).

Limits: developer-workflow setup; minutes of memory preparation per launch, in the
foreground; a network connection to install and update; voice chat's helper process is not
supported.

## What happens to the game

- The executable is imported as data, verified by SHA-256, and mapped into memory. It is
  never edited, re-signed or bundled. The loader applies the rebases and binds dyld would.
- The loader answers a short fixed list of calls — `mmap`, `mprotect`, `memset`, `dlsym`,
  `dyld_stub_binder` and a dozen like them — because they concern how the image was loaded.
  The list is in [`platform/runtime/NativeGuest.m`](platform/runtime/NativeGuest.m).
- Everything else resolves to the real iPadOS framework, to an adapter in
  [`platform/translation`](platform/translation), or to a library the app carries. An
  import nothing provides becomes a logging stub; in a build made for one application it
  stops the launch instead.
- Nothing hides the environment: no concealed debuggers, processes, device model or OS.

## Testing

```bash
wolkaraforever/tools/test_emulation.sh   # layer gate, platform suite, every layer suite
```

Device suites and self-tests: [TESTING.md](docs/TESTING.md). Tool reference:
[TOOLING.md](docs/TOOLING.md). Read [CONTRIBUTING.md](CONTRIBUTING.md) before a pull
request.

## Policy

Not accepted here: reading or changing an application's memory beyond loading it —
trainers, overlays, bots, input automation; anti-cheat, licence or integrity workarounds;
shipping third-party game code, assets or OS components. This governs the application, not
this project: testing and automating our own code is expected.

Not affiliated with or endorsed by Apple or Blizzard. You are responsible for your own
right to run the game and for complying with its licence.

## Links

[Documentation](docs/README.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Launcher and updater](docs/WOW_LAUNCHER.md) · [Touch input](docs/TOUCH_INPUT.md) ·
[Voice](docs/VOICE.md) · [Controller](docs/CONTROLLER_INPUT.md) ·
[Device workflow](docs/DEVICE_WORKFLOW.md) · [Maintaining](docs/MAINTAINING.md) ·
[Testing](docs/TESTING.md) · [Tools](docs/TOOLING.md)

Source: [jklock/wolkaraforever](https://github.com/jklock/wolkaraforever) · continues
[fJavierLasso/wolkara](https://github.com/fJavierLasso/wolkara) by Javier Lasso · engine
[Tolkara](https://github.com/tolkara/tolkara) · [tolkara.org](https://tolkara.org)
