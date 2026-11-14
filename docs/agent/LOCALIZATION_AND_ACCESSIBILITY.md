# Localization and accessibility

> Verified: 2026-11-13 · Source: `3c33543` · Proof: Shell strings and localization checks

App language and game language are separate settings. Keep user-visible strings, accessibility labels, alerts, menus, status text, and screenshots consistent with supported locales. Use sentence-case headings and descriptive alt text; do not encode meaning only in color or an image.

Run `wolkaraforever/tools/check_localization.py` and the relevant simulator test when localization changes. Update [Using WolkaraForever](../USING_WOLKARAFOREVER.md) when a user-visible language choice changes.

## Refresh when

Refresh after locale, string ownership, accessibility, screenshot, or localization-check changes.
