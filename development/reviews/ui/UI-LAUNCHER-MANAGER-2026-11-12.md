# UI review: Launcher Manager (v1.0.9)

## Classification

ui-contract-amendment - the sixth protected card, the interface-mode selector, and the
recommendation row's amended title and destination. It is the sole authorized launcher-contract
amendment in the 2026-11-10 train and follows v1.0.8 (#23).

## Scope

The release adds `wow.box.launcherManager` in the cell that was the grid's empty spacer beside
UI Manager, and after UI Manager in the one-column layout. The card holds one setting,
`wow.launcher.interfaceMode`, with exactly two choices - `iPadOS` and `iOS on Duo` - persisted
to `WolkaraForeverInterfaceModeV1`. Choosing a mode writes that key and nothing else: it never
installs, disables, removes or updates an add-on.

The Add-On Manager card's recommendation row keeps its identifier, `wow.addons.macEver`. Its
title is `Install Recommended Add-ons (Mac-Ever)` on iPadOS and
`Install Recommended Add-ons (WolkaraRoue)` on iOS on Duo, and it opens the Add-On Manager
instead of a browser page. It never installs silently.

On iPadOS the page it opens is Browse, filtered to CurseForge project 1733200, with the
existing explicit Core API key and Install flow. On iOS on Duo the page opens on Installed with
the bundled WolkaraRoue package, its release and SHA-256, and its own explicit Install action.
The package is located and verified against its manifest before it is offered; the archive's
own TOC release is checked against the manifest's, so a manifest edited to name another release
is refused rather than believed.

Every other card keeps its position, width, inset, row order and default behaviour. The
two-column row is `FillEqually`, so the sixth card takes exactly the width the spacer had; in
one column it is full width like the others.

## Changed states

Four named states are added to the baseline inventory, on both matrix devices:

- `wow-launcher-ipados.png` - the ready page with `Interface Mode: iPadOS` and
  `Install Recommended Add-ons (Mac-Ever)`.
- `wow-launcher-duo.png` - the same page after choosing `iOS on Duo`, with
  `Interface Mode: iOS on Duo` and `Install Recommended Add-ons (WolkaraRoue)`.
- `wow-addons-recommended-macever.png` - the Add-On Manager the Mac-Ever recommendation opens,
  on Browse, in the missing-key state.
- `wow-addons-recommended-wolkararoue.png` - the Add-On Manager the WolkaraRoue recommendation
  opens, showing `Version 0.9.1 · SHA-256 0123...` and Install.

The four pre-existing home-page images (`wow-home.png`, `wow-home-large-text.png`,
`wow-home-de.png`, `wow-home-de-large-text.png`) and every image whose page sits behind a
presented sheet changed, because the sixth card is visible behind them. All were re-recorded in
the dedicated amendment run. The selector's action sheet is not itself a baseline: its
translucent backdrop is not deterministic to the five-per-channel tolerance, so its exact two
choices and persistence are asserted as values by `test_wow_launcher_app.m` instead.

## End-user action

One new setting, and one row that now navigates instead of opening a browser. A person who never
opens the Launcher Manager sees the same page as v1.0.8 except for the sixth card; the
recommendation row still names Mac-Ever and still requires an explicit Install in the Add-On
Manager. Choosing `iOS on Duo` changes the recommendation to the bundled package and changes
nothing installed. No default installation, removal or update happens without a tap.

## Evidence

Simulators, both required matrix devices:

- iPhone Duo: `WoW UIKit PASS`, `UI baseline comparison passed`.
- iPad Pro 13-inch (M5): `WoW UIKit PASS`, `UI baseline comparison passed`.
- `wolkaraforever/tools/check_ui_policy.sh` was run twice after recording and passed both
  times on both devices, so the new images are stable, not a lucky capture.

The fixture asserts, as values: the six-card grid and its exact cell order; the new heading and
row; the selector's action titles `✓ iPadOS` / `iOS on Duo` / `Cancel` and then `iPadOS` /
`✓ iOS on Duo` / `Cancel`; the persisted key; the recommendation title in both modes; that the
game's `Interface/AddOns` folder is byte-for-byte the same before and after a mode switch; that
the Mac-Ever page is `TKAddonRecommendationMacEver` filtered to 1733200; that the WolkaraRoue
page is `TKAddonRecommendationWolkaraRoue`; that a verified package renders its release and hash
with an enabled Install; and that an unverified package hides Install and leaves the installed
tree untouched.

Mac-native suites:

- `wolkaraforever/tools/test_addon_package.sh` - the committed package verifies; the locator
  accepts it and refuses all nine wrong packages for their own reasons; the wrong-version
  package is refused by the TOC check ("release 0.9.1, not 9.9.9").
- `wolkaraforever/tools/test_addon_archive.sh` - 59 checks, including the bundled package
  installing through the store, updating in place on a second Install, and refusing a tampered
  archive without replacing anything.

Physical iPad (iPad Pro 12.9-inch, 5th generation; iPadOS 27.2; Developer service), installed
with `wolkaraforever/tools/install.sh` from the working tree that became `d9d49ce`:

- The install reached step 5/5 and relaunched the plain launcher. Its own log reads
  `home: the launcher is up (mode=developer-service source=saved)`, the first appearance check
  ran and finished (`checked: state=3 error=none`), and there is no new error file or crash
  report.
- A device screenshot after that launch shows the six-card page with **LAUNCHER MANAGER** and
  `Interface Mode: iPadOS` beside UI Manager, and the Add-On Manager card's
  `Install Recommended Add-ons (Mac-Ever)` row. That is the iPadOS default on the installed
  build.
- `wolkaraforever/tools/pilot.sh selftest addons-page` reports
  `addons-page PASS 27/27 checks`, which now includes: the Duo recommendation opens the
  bundled-package page; the app's own bundle carries a verified WolkaraRoue package; the page
  knows its release and a 64-character SHA-256; the row shows that release with an enabled
  Install; opening the page installed nothing; and the iPadOS recommendation is the Mac-Ever
  page filtered to CurseForge project 1733200.
- The app was put back on its normal home screen afterwards, and `pilot.sh view` shows it
  running there (`home: back in front`, `checked: state=3 error=none`).

What the device did not show: the selector sheet's own tap, and a final reinstall from the
committed SHA. A live game session was running when the final exact-SHA reinstall was
attempted, and the reviewed install guard correctly refused to replace the app underneath it;
the installed build's content is the committed tree (`d9d49ce` differs from it only by that
commit), and the live session was left alone rather than stopped a third time. The simulator
matrix carries the required evidence; the device result above is recorded as the narrower,
physical thing it is.

Localization: `wolkaraforever/tools/check_localization.py` passes with 563 keys; `iPadOS` and
`iOS on Duo` are on the documented same-in-both list, and the bundled version/hash line is
`Version %@ · SHA-256 %@` in all three tables.

## Risks and boundary

- **A mode is not an install.** The selector writes one `NSUserDefaults` key. The fixture
  compares the game's `Interface/AddOns` directory before and after both switches; no store
  method is called on that path.
- **The bundled package is data in the app.** It is verified before it is offered and again by
  the store's transactional import; a package that is missing, tampered, truncated, foreign or
  of another release is refused with its own message, and nothing is extracted.
- **Mac-Ever needs the user's own key.** The recommendation opens the existing Browse page; it
  does not embed a download URL or a key, and opening it is not an installation. The
  missing-key state is the recorded baseline.
- **Baseline sensitivity.** The images are compared per channel with a tolerance of five. The
  four new states are page states, not translucent sheets, because the sheet's backdrop varied
  by more than the tolerance between identical runs; the two policy runs above reproduce the
  committed images.
- **The physical iPad is nice to have.** A device result is recorded below when it ran, and is
  never presented as a simulator result or vice versa.
