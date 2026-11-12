# WolkaraForever launcher UI policy

## Purpose and scope

This policy protects the **WolkaraForever application UI**, not World of Warcraft's in-game
interface. It applies to these paths:

- `wolkaraforever/Shell/`
- `wolkaraforever/WoW/`
- `wolkaraforever/Voice/`
- `wolkaraforever/Touch/`
- `wolkaraforever/Controller/`

The launcher is additive-only. A feature may add an optional capability, setting, status state,
selector value, localized text, or documented golden state. It must not modify an existing
launcher/control element's placement, size, color, style, label, identifier, order, behaviour,
navigation, geometry, safe-area treatment, popup behaviour, or default state.

Changing an existing protected element requires a separate maintainer-authored UI-contract
amendment release. It is never folded into a feature PR. The amendment must update this policy,
the baseline specification, screenshots, fixture assertions, review record, and device evidence.

## Frozen contract

| Contract | Required value |
| --- | --- |
| Grid threshold | two columns only when the scroll view bounds are at least 700 points wide |
| iPhone | one column at every width |
| Card grid | six cards in three rows: Game Settings Manager, Add-On Manager, Dictation (V2T) Manager, Performance Manager, UI Manager, Launcher Manager |
| Overflow | horizontal overflow is forbidden |
| Card insets | 14/16 points |
| Row spacing | 8 points |
| Accessibility | largest Dynamic Type remains reachable; German proves long text |
| Popups | no more than 85% of presenting-screen width or height; even margins; reachable Cancel |
| Theme | `WKInk`, `WKGold`, `WKMuted`, `WKPanel`, `WKOnGold`, `WKPopupMaximumScreenFraction` |
| Accessibility IDs | all existing identifiers are immutable in feature PRs |

`DEVICE_CONTRACT.md` remains the measured geometry source. Re-measure a changed value; do not
weaken the prose to fit an implementation.

## Amendment record

The v1.0.9 Launcher Manager amendment is the sole authorized launcher-contract amendment in
the 2026-11-10 train. It changed two protected things and nothing else:

- The sixth card, `wow.box.launcherManager`, now occupies the cell that was the grid's empty
  spacer beside UI Manager. It is the same width in the two-column layout and follows UI
  Manager in the one-column layout, so every other card's geometry is unchanged.
- The recommendation row keeps its identifier, `wow.addons.macEver`. Its title is
  `Install Recommended Add-ons (Mac-Ever)` on iPadOS and
  `Install Recommended Add-ons (WolkaraRoue)` on iOS on Duo, and its action opens the Add-On
  Manager instead of a browser page. It never installs silently.

`wow.launcher.interfaceMode` offers exactly two choices, `iPadOS` and `iOS on Duo`; the
selection is persisted to `WolkaraForeverInterfaceModeV1`, and a mode change never installs,
disables, removes or updates a package. The states this produces are recorded in
`LAUNCHER_UI_BASELINE.md`; the review is
`development/reviews/ui/UI-LAUNCHER-MANAGER-2026-11-12.md`.

## Mandatory evidence

Every UI-affecting PR includes a review record under `development/reviews/ui/` stating its
classification (`none`, `additive`, or `ui-contract-amendment`), exact SHA, changed states,
end-user action, screenshots, tests, and risks. The release validation runs
`wolkaraforever/tools/check_ui_policy.sh --review <record>`.

The policy checker runs launcher screenshots against committed RGBA baselines on iPhone Duo and
iPad Pro 13-inch (M5). A visible launcher, touch, controller, or voice claim also requires
Device Hub exercise on the physical iPad Pro 12.9-inch (5th generation), ending on the normal
launcher home screen with WolkaraForever running.

Existing golden images may not change in an additive PR. New optional states add a named image
and an inventory entry. Recording requires the explicit approval phrase documented in
`LAUNCHER_UI_BASELINE.md`.
