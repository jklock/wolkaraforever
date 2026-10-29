# Implementation prompt: German app localization

> **Implemented on 2026-10-29** (`1bf95d0`, recorded in
> [the device check](../validation/56ddc87-german-app-localization.md)). This file is kept as the
> prompt the work was written against, not as outstanding work: what was built, what is
> deliberately not translated and how a string is added are in
> [the localization guide](../guides/LOCALIZATION.md).

## Objective

Make German (`de`) a complete, accessible application language for WolkaraForever, while
retaining the already-implemented German **game** locale (`deDE`) path. A German-speaking
person must be able to choose German in the launcher, restart the app, and use every
WolkaraForever-owned screen in German. The selected game language and app language are
separate preferences, but the first German app-language selection should offer to align the
game language to German rather than silently changing it.

## Existing behavior to preserve

- The game-language picker supports `enUS`, `esES`, and `deDE`.
- `deDE` is shown as **German**, persists as `WoWLocale`, writes both `textLocale` and
  `audioLocale`, and causes a current build with non-matching `.build.info` locale tags to
  update before Play is enabled.
- Region does not change the game's login portal when a language changes.
- English remains the fallback when a localization resource, locale identifier, or translated
  string is missing. Never show a raw localization key.
- The original game executable, game data, credentials, device identifiers, and `platform/`
  remain outside the change. Keep all product changes in `wolkaraforever/` and preserve the
  layer gate.

## Required implementation

1. **Localization foundation**
   - Add an app-language setting with `en`, `de`, and `system` choices. `system` resolves
     from the iPad preferred-language list, using German only for a German language preference;
     otherwise it resolves to English.
   - Keep the resolved application locale in one small localization service. It must be usable
     by Objective-C and Swift product code, be safe before UI construction, and notify visible
     screens when the setting changes.
   - Add `en.lproj` and `de.lproj` product-owned string resources. Use stable, namespaced keys
     and plural-aware formatting where counts are shown. Do not localize user data, filenames,
     WoW CVar names, Blizzard product identifiers, log event keys, command-line flags, or
     diagnostics intended for support.
   - Audit every user-visible string in `Shell/`, `WoW/`, `Touch/`, `Input/`, `Controller/`,
     `Voice/`, and the app self-test UI. This includes alerts, buttons, menus, accessibility
     labels/hints, empty/error states, progress phases, permission explanations, About, and
     Settings. The app must not become half-German.

2. **Language settings UX**
   - Add **App language** to the Game Edition area specified in
     `development/uichanges/LAUNCHER_REORGANIZATION_PLAN.md`. It displays the current resolved
     language and opens English, German, and System Default choices.
   - Changing app language applies immediately to the launcher without restarting the app.
     Preserve the current screen when possible; a controlled rebuild of the root controller is
     acceptable when needed to avoid mixed-language navigation bars or stale action sheets.
   - Selecting German app language presents a one-time, localized choice: **Also change game
     language to German** or **Keep game language unchanged**. The action must use the existing
     validated locale writer and existing update gate. Do not begin a download without the
     user choosing the first option.
   - Include a short, translated explanation that app language affects WolkaraForever labels,
     while game language controls downloaded game text/audio.

3. **German content quality**
   - Use natural German suitable for iPad UI, consistent formal address, concise labels, and
     typographically correct punctuation. Retain meaningful English product names such as
     WolkaraForever, World of Warcraft, CurseForge, Mac-Ever, iPadOS, and GitHub.
   - Have a fluent German reviewer check the entire `de` table in context. Do not use machine
     translation as final copy without review.
   - Support Dynamic Type, RTL-neutral layout constraints, text expansion, VoiceOver, and long
     German compound nouns. No fixed-width English-only controls or clipped action-sheet items.

4. **Tests and proof**
   - Add focused unit tests for system-locale resolution, persisted setting migration, fallback,
     the German/game-language confirmation path, and text formatting.
   - Extend the UIKit fixture to run key launcher flows in English and German, asserting no raw
     keys, correct German titles/actions, accessibility values, and an immediate language change.
   - Run `wolkaraforever/tools/check_layers.sh`, the owning launcher/UI tests,
     `wolkaraforever/tools/test_translation_sim.sh` if adapters are affected, and
     `wolkaraforever/tools/check_docs.sh`.
   - Build and install through `wolkaraforever/tools/install.sh`. On an iPad, confirm the German
     launcher can select and preserve German app language, choose German game language, and
     enters the existing selected-language update state. Record source SHA, device, iPadOS,
     execution mode, and what a person observed. Do not call this gameplay proof.

5. **Documentation and release hygiene**
   - Update the user guide, installation guide, feature inventory, architecture/project map,
     contributor instructions, and Wiki pages to explain the two independent language settings.
   - Add translator contribution instructions and a key/string review checklist. Ensure
     `check_docs.sh` covers links to the new pages.
   - Do not claim German app support in README or release notes until the German fixture and the
     physical launcher check have passed on the exact released SHA.

## Acceptance criteria

- Every WolkaraForever-owned user-facing screen is English or German as selected; no mixed
  default English text remains except intentional names/technical values.
- German game language remains a verified `deDE` download/configuration path and does not alter
  portal or unrelated WoW settings.
- The app stays usable at the largest Dynamic Type size on supported iPads and the planned
  iPhones.
- A clean branch passes its focused suites, documentation gate, layer gate, and the recorded
  physical launcher check before merge.
