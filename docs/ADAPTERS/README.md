# Adapters: how these documents work

Every hand-written adapter in `platform/translation/` is documented here, per file,
in source order. The rule is: **no statement is left unexplained**. Boilerplate that
carries no decision (imports, `@end`, brace-only lines, `return self;` from an
initializer that already validated its arguments) is listed in a compact table rather
than given a paragraph, so that every line appears exactly once and every line that
*does* something is explained next to what it does.

Conventions used throughout:

- **Line ranges** refer to the file as vendored in `platform/` (upstream), because
  that is the stable text. The fork's own changes to each file are listed at the end
  of its document as patch deltas, by patch number, with the reason and the measured
  effect where one exists. `wolkaraforever/patches/` is authoritative for the delta.
- **"Guest"** is the unmodified macOS program. **"Host"** is the Tolkara app process.
- **"Apple's"** describes what the macOS class or function does, cited only where the
  adapter's behaviour is a deliberate imitation of it.
- A method that exists purely so a selector resolves (a no-op an application calls
  once at start-up) is marked **(no-op)** and still says why the no-op is correct
  rather than merely absent.

## Index

| Document | Covers |
| --- | --- |
| [AppKit.md](AppKit.md) | `translation/AppKit/` — application, event loop, windows, views, screens, input, images, nibs |
| [AppKitExtras.md](AppKitExtras.md) | `AppKit.h`, `NibArchive.m`, `TouchControls.m`, `TouchTrackpad.c` |
| [Support.md](Support.md) | `AKSupport/` and the rest: logging, stubs, alerts, menus, monitors, drawing |
| [Metal.md](Metal.md) | `translation/Metal/` — device, presentation, shader libraries, storage, tracing |
| [Textures.md](Textures.md) | `translation/Metal/` — BC texture substitution, block decoding, render diagnostics |
| [Audio.md](Audio.md) | `translation/AudioToolbox/`, `translation/AudioUnit/`, `translation/CoreAudio/` |
| [Core.md](Core.md) | `translation/CoreGraphics/`, `translation/CoreServices/`, `translation/Carbon/`, `translation/IOKit/` |
| [Security.md](Security.md) | `translation/Security/` — keychain, legacy CDSA crypto, session |
| [GameController.md](GameController.md) | `translation/GameController/` |
| [Performance.md](Performance.md) | The per-frame path assembled from the above: what the layer costs per frame, and what is proven about it |
