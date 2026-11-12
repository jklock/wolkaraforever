# UI review: launcher contract amendment for v1.0.10

## Classification

`ui-contract-amendment`. It changes one protected launcher contract that v1.0.9 set
(`UI-LAUNCHER-MANAGER-2026-11-12.md`) and adds one row to the same card. Nothing else on the
home page moves, and no in-game control contract changes.

This record supersedes two claims in the v1.0.9 record, which remain true of v1.0.9: the
interface selector no longer offers "exactly two choices", and the recommendation row no longer
reads `Install Recommended Add-ons (Mac-Ever)` on iPadOS.

## Exact SHA

`00f7de7` on `pr26-duo-refinement`, merged as the v1.0.10 squash commit.

## Changed states

1. **Interface mode** (`wow.launcher.interfaceMode`) offers four choices instead of two:
   `Automatic`, `iPadOS`, `iOS`, `iOS on Duo`. Automatic is labelled with what it resolves to on
   this device (`Automatic (iPadOS)` / `Automatic (iOS)` / `Automatic (iOS on Duo)`). The
   checkmark marks the stored choice, never the resolution, so an automatic choice stays
   automatic when the same settings are used on another device. The row's title still reads
   `Interface Mode: %@` with the interface in force.
2. **Controller layout** (`wow.launcher.interfaceSetup`) is new, directly under the mode row in
   the same card. It opens a sheet with the three built-in arrangements, any arrangement the
   person saved, `Save This Layout…`, `Reserve an Area…`, `Delete a Saved Layout…`, and one row
   per placed control naming the element it sends (`A → A`).
3. **Recommendation** (`wow.addons.macEver`, identifier unchanged) reads
   `Install Recommended Add-ons (WolkaraRoue)` in every interface and opens the bundled,
   verified package page. It still installs nothing by itself.

## End-user action

Mode: Launcher Manager → Interface Mode → a choice. Layout: Launcher Manager → Controller
Layout → a template, a saved layout, a control, or a drawn area. Neither touches a game file,
an add-on, or a package installation.

## Screenshots

Baselines re-recorded on both matrix devices for the states that show the card:
`wow-home.png`, `wow-home-large-text.png`, `wow-home-de.png`, `wow-home-de-large-text.png`,
`wow-starting.png`, `wow-running.png`, `wow-startup-failed.png`, `wow-downloading.png`,
`wow-launcher-ipados.png`, `wow-launcher-duo.png`. `wow-addons-recommended-macever.png` is
retired with the recommendation it depicted; `wow-addons-recommended-wolkararoue.png` is
unchanged.

The sheets the two rows open are not captured, as with every other sheet on this page.

## Tests

`wolkaraforever/tools/test_wow_launcher_ui.sh` (fixture assertions plus RGBA baseline
comparison) on iPhone Duo and iPad Pro 13-inch (M5): passed.
`wolkaraforever/tools/check_ui_policy.sh --review development/reviews/ui/UI-CONTRACT-2026-11-12.md`:
passed. `wolkaraforever/tools/test_wow_launcher.sh`: passed.

## Risks

- **No physical iPad evidence.** The visible launcher claim here is exercised on the two matrix
  simulators only; the iPad Pro 12.9-inch (5th generation) was not available for this change.
  Stated plainly rather than implied.
- **The card is taller.** Two rows fit the existing cell on both matrix devices; a third would
  need a layout decision, which is why the mapping list lives inside the sheet rather than on
  the card.
- **A saved arrangement can reserve up to 16 areas.** A person can reserve most of the screen and
  then wonder why the sticks do not respond; the areas are theirs to clear, and the sheet says
  where they come from.
