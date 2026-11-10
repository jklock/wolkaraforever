# UI review: baseline 2026-11-08

## Classification

ui-contract-amendment — initial immutable baseline and enforcement release.

## Scope

Protects the existing WolkaraForever launcher/control UI without changing its product layout.
It adds policy, fixture capture comparison, baseline images, CODEOWNERS paths, and release gates.

## Existing states

The launcher fixture records the thirteen states listed in
`development/architecture/LAUNCHER_UI_BASELINE.md` on iPhone Duo and iPad Pro 13-inch (M5).
The physical iPad check is recorded in the release validation evidence before `v1.0.1` is tagged.

## End-user action

None. This release changes contributor controls and test evidence, not default application UI.

## Risks and boundary

Pixel baselines are intentionally sensitive. Legitimate visual changes require the separate
maintainer amendment process in `UI_POLICY.md`; feature PRs cannot update existing images.
