# Architecture

> Verified: 2026-11-13 · Source: `3c33543` · Proof: cataloged source and overlay map

Tolkara provides the Mach-O loader, guest-memory arena, macOS-to-iPadOS translation libraries, and authorization mechanisms. WolkaraForever layers the branded shell, Forever installation lifecycle, add-on management, touch and controller UX, voice, localization, diagnostics, and safe device tooling over it.

The prepared build is `platform/ + patches + overlay.map + wolkaraforever/ -> build/platform/`. The original game executable is imported as verified data and remains unmodified.

| Product area | Primary owner |
| --- | --- |
| Launcher and lifecycle | `wolkaraforever/WoW/`, `Shell/` |
| Input and mobile UI | `Touch/`, `Input/`, `Controller/`, `Voice/` |
| Game add-on | `Addons/`, `addons/WolkaraRoue/` |
| Platform integration | `Bridge/`, `CoreAudio/`, maintained patches |
| Runtime and translation | immutable `platform/runtime/`, `translation/`, `authorization/` |

For user-facing behavior, consult [product behavior](PRODUCT_BEHAVIOR.md). For exact file responsibilities, consult the [catalog](FILE_CATALOG.md).

## Refresh when

Refresh after changes to an overlay boundary, execution mode, product subsystem, patch, or source ownership.
