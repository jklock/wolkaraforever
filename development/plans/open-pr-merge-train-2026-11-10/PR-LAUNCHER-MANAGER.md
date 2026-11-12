# Launcher Manager UI-contract amendment — v1.0.9

Create a new maintainer-authored PR, separate from #23/#26. It is the sole authorized launcher-contract amendment in this train.

Add wow.box.launcherManager in the former wide-grid spacer beside UI Manager and after UI Manager in one-column layout. Add wow.launcher.interfaceMode with iPadOS default and iOS on Duo only. Persist the selection; mode changes never install, disable, remove, or update packages.

Keep the existing recommendation row identifier. Its title is Install Recommended Add-ons (Mac-Ever) for iPadOS and Install Recommended Add-ons (WolkaraRoue) for Duo. Tap opens Add-On Manager, never silent install. Mac-Ever filters CurseForge project 1733200 and retains the existing explicit API-key/install flow. WolkaraRoue shows bundled ZIP version/hash and an explicit transactional local Install action; malformed/unexpected archives fail closed.

Update UI policy, baseline spec, device contract, English/German/French strings, review record, fixture assertions, inventory, and approved screenshots. Test default, selector, missing key, local success/failure, no removal on switch, largest German type, both simulators, test iPad, exact-main release. Rollback: v1.0.8.

## Execution record (2026-11-12)

Delivered on branch `launcher-manager-v1.0.9`; the review is
`development/reviews/ui/UI-LAUNCHER-MANAGER-2026-11-12.md`.

What landed:

- `wow.box.launcherManager` replaces the wide-grid spacer; `wow.launcher.interfaceMode` offers
  exactly `iPadOS` and `iOS on Duo`, persisted to `WolkaraForeverInterfaceModeV1`, and a mode
  change touches no package. The recommendation row keeps `wow.addons.macEver`, changes its
  title with the mode, and opens the Add-On Manager (Mac-Ever filtered to 1733200; the bundled
  WolkaraRoue package with release, SHA-256 and an explicit Install).
- `TKAddonPackage.bundled(in:error:)` locates and verifies the shipped pair, and `verify` now
  checks the manifest's release against the archive's own TOC. `TKAddonStore`'s transactional
  import/update is the local Install path.
- `TKWoWAddonManagerViewController` gains the additive `recommendation:` initializer and the
  `bundledPackageProvider` seam the fixture uses without the Swift verifier linked.
- EN/DE/FR strings, `check_localization.py`'s same-in-both list, the UI policy, baseline spec,
  device contract, feature inventory, user guide, changelog and the review record.
- Four new baseline states on both matrix simulators (`wow-launcher-ipados.png`,
  `wow-launcher-duo.png`, `wow-addons-recommended-macever.png`,
  `wow-addons-recommended-wolkararoue.png`) plus the re-recorded images the sixth card changes.

Evidence, measured:

- `test_wow_launcher_ui.sh` passes on iPhone Duo and iPad Pro 13-inch (M5);
  `check_ui_policy.sh` passes twice in a row after recording.
- `test_addon_package.sh` and `test_addon_archive.sh` pass, including the bundled install and
  every wrong package refused.
- `test_localization.sh` (65 checks), `test_curseforge.sh` (52 checks),
  `test_wow_launcher.sh`, `test_mobile_addon.sh`, `check_layers.sh` and `check_docs.sh` pass.
- Physical iPad: installed and relaunched to home; a screenshot shows the six-card page with
  `Interface Mode: iPadOS`; `pilot.sh selftest addons-page` passes 27/27 including the two new
  recommendation checks. A live game session blocked the final exact-SHA reinstall; the
  installed content is the committed tree, and the session was left alone.

Not done in this record: the squash merge, the exact-main `validate.sh` run, the `v1.0.9` tag
and the release publication. Those follow review, per the repository workflow.
