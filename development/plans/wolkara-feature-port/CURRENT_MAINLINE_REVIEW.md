# Current-mainline review — 2026-11-12

Reviewed against `main` `438bf348ddd13ae7a10cc0ea50ccd1b0751e03b6` (2026-11-12),
including the v1.0.10 Duo product foundation and the subsequent External-JIT
diagnostics update. Earlier WolkaraForever PRs and issues are closed; no task in this
plan depends on reopening, merging, or citing them.

## Current foundations that feature work must preserve

| Current mainline capability | Feature plans that must extend it | Required guardrail |
| --- | --- | --- |
| `Touch/InterfaceMode`, `LayoutStore`, `TouchGamepadLayout` | controller input, chat, keyboard/dictation, touch controller | Duo uses Automatic/iOS-on-Duo behavior; iPad retains its approved layout. Never reset layouts or force an iPad mode on phone hardware. |
| `addons/WolkaraRoue` and package/install verification | touch controller, Add-on Hub | Preserve the reviewed non-automating companion. No command dispatch, macros, game automation, or source add-on import. |
| `WoW/AddonManager`, `AddonStore`, `AddonPackage`, bundled recommendation | Add-on Hub | Extend the one managed catalog. API, browser, Files and discovered packages use the same post-install state and actions. |
| Current Launcher/Add-ons routes and UI contract | every visible feature | Additive UI only. Preserve launcher cards, labels, placements and approved baselines unless a separately approved UI-contract amendment exists. |
| English, German and French app localization | every feature with copy | Add all three locales and VoiceOver coverage with the feature; do not regress existing strings. |

## Required execution matrix

Every visible feature PR runs its focused tests and live UI flow on both:

1. iPhone Duo simulator — Automatic/iOS-on-Duo behavior, one-column layout,
   safe areas, keyboard motion, Dynamic Type, rotation/lifecycle as applicable.
2. iPad Pro 13-inch (M5) simulator — current iPad interface and approved
   six-card/grid behavior remain unchanged.

Physical iPad Device Hub work is additional evidence. It is required to make a
physical interaction claim, but its absence does not block release after the
required simulator matrix passes. A PR states the physical status explicitly.

## Evidence and PR rule

Each feature opens its own PR after rebasing on then-current `origin/main` and
re-running the gap reproduction. PR Proof states the base/source SHA, both
simulator commands and outcomes, interface modes, local live-QA outcome,
structured-log assertions, migration/rollback coverage, localization/UI-policy
result, and physical status. Generated logs, screenshots, simulator reports and
validation inventories are local-only; do not commit, attach or link them, and
run `wolkaraforever/tools/clear_validation_reports.sh` before handoff.

## Plan audit result

The feature prompts, plans and tasks now use this current-mainline contract.
They do not prescribe stale replacement modules, stale two-locale work, committed
validation artifacts, or a physical-only completion gate. Any later mainline
change requires the implementation agent to repeat this review for its feature
before editing code.
