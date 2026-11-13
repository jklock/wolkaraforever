# Touch Controller plan

## Outcome

Touch Controller gains an opt-in Simple layout, independent shoulders, optional
L3/R3 double-tap, and direct-camera restart reliability without introducing
game-command automation.

## Why

The reviewed source has useful interaction ideas but couples some to its own
gamepad/action model. WolkaraForever must preserve its virtual-controller input
boundary and existing Full layout.

## Acceptance

Existing installs migrate to Full. Simple, L3/R3 and ability zones are off by
default. Every virtual press is released on cancellation, background, resize and
disconnect. Touch fixtures and live flows on both simulators prove each gesture;
Device Hub is additional evidence for physical claims.

## Completion gate

Layout migration is reversible: invalid/newer settings fall back to Full and
feature disable restores the existing layout without deleting saved positions.
All labels, gesture hints and errors are localized and accessible. Run gamepad,
touch-controls and translation suites on both permitted simulators, including
portrait/landscape, Dynamic Type and lifecycle coverage. On Duo, exercise the
current mobile `InterfaceMode`/`LayoutStore` behavior rather than iPad defaults.
Device Hub may additionally prove Full, Simple, shoulders, L3/R3, drag threshold,
cancellation and foreground return. Record both simulator/source-SHA outcomes
and physical status in PR Proof; update the touch guide and COMPATIBILITY only
with observed results.
