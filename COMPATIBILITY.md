# Compatibility

> **Current source review: 2026-10-28 · revision `fbd69f8`**

Compatibility is specific to an iPad model, iPadOS version, WoW build, execution mode,
account state, and the exact source revision. This page deliberately does not turn a past
result into a broad support promise.

## Current product boundary

WolkaraForever currently presents the Forever install and launcher flow. The source includes
download/update verification, add-on management, touch and controller input, voice
configuration, UI backup/restore, graphics-only reset, the gamepad setting, performance
overlay, and background-aware frame pacing. Their presence in source is not the same as a
physical pass on every iPad.

The supported integrated installation path is the iPad Developer service. The repository
also contains engineering paths for Local signing and External JIT; neither should be read as
a general consumer-install promise.

## Evidence currently available

| Area | Evidence | Scope |
| --- | --- | --- |
| Layer integrity and documentation links | Repository checks | Source structure and documentation only; not an on-device result. |
| Forever configuration operations | Focused source tests | Backup/restore, graphics reset, gamepad setting, locale writes, and path safety. |
| Earlier device work | Historical records | Dated results, with their device/build/revision boundaries retained in `development/validation/`. |

No statement here certifies that `fbd69f8` has been physically exercised on a particular
device after this documentation review. Treat a device result as valid only when it names the
device, iPadOS version, client build, execution mode, and source revision.

## Before you rely on it

- Use your own eligible account and game files.
- Install through the [current installation guide](docs/INSTALLATION.md), not an older release
  instruction.
- Test sign-in, graphics, controls, voice, add-ons, and the recovery flow yourself for the
  iPad and game build you intend to use.
- Keep a UI backup before changing game settings or add-ons.

Historical engineering and device evidence is preserved under
[development/validation/](development/validation/), where it remains explicitly dated rather
than being presented as current compatibility.
