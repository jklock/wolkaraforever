# Supported-device contract — iPhone and iPad

> **Current as of 2026-11-05 · branch `liveupdates-11042026`.**

iPhone and iPad are peers. Neither is a fallback for the other, and an iPhone is not a
"compact presentation of the iPad page" — it is a supported device with its own layout
decisions, and the iPad's two-column page is a layout choice that must **survive** the arrival
of the phone, not be traded away for one.

This page is the contract. It says what the source supports, what has been measured on
physical hardware, and where the two differ. Anything not marked *measured* below is
**source support only** and must not be described anywhere as validated.

## 1. Supported devices

| Form factor | Family | Devices named in source | Physically measured |
| --- | --- | --- | --- |
| iPad | `TKDeviceFamilyPad` | iPad Pro 12.9-inch (5th generation, M1, `iPad13,9`); iPad Pro 13-inch (M5, `iPad17,4`); other iPad records in `DeviceProfile.m` | iPad Pro 12.9-inch (5th generation), iPadOS 27.0.1 — see `COMPATIBILITY.md` |
| iPhone | `TKDeviceFamilyPhone` | iPhone 16 Pro, 16 Pro Max, 17 Pro, 17 Pro Max, 18 Pro, 18 Pro Max, iPhone Duo | **None.** Every phone record is `measured: NO` |
| Unknown | `TKDeviceFamilyUnknown` | resolved to `+[TKDeviceProfile fallbackProfile]` | not applicable |

An unlisted device is not refused. It resolves to the fallback profile: Performance render
scale, no Quality offered, and it says so on the page. That is a deliberate conservative
answer, not a support statement.

## 2. Operating-system and execution-mode conditions

| Item | Contract |
| --- | --- |
| Minimum OS | Whatever the built SDK's deployment target is; the product is built and tested against current iOS/iPadOS only |
| Developer service | The supported integrated path. iPad is measured; iPhone is measured on iOS 27.0 in the restored `docs/IPHONE.md` record and is **source-supported** on current iPadOS/iOS |
| Local signing | Engineering path only. Never a consumer promise, on either form factor |
| External JIT | `TolkaraDiagnostics` only, via an unsigned generic `.ipa`. Never a consumer promise |
| App surface | `UIDeviceFamily` 1 and 2 (`TARGETED_DEVICE_FAMILY = "1,2"`) |
| Orientation | Portrait and landscape on both form factors. The launcher is a single scrolling column; the game is presented in the live window |

The original executable is never modified in any of these modes. Nothing in this contract
changes that.

## 3. Display and window geometry

| Item | iPad | iPhone |
| --- | --- | --- |
| Page structure | One vertical column of cards; **two cards side by side** when `bounds.width >= 700` and the text size is not an accessibility size | One vertical column of cards at every width |
| Two-column threshold | 700 points, measured from the scroll view's own bounds — never from `horizontalSizeClass`, which stays *regular* in a narrow iPad form sheet and drew a row wider than the list on 2026-10-22 | never applies |
| Fixed viewport | None. No fixed iPad point size is used for layout | None |
| Horizontal overflow | Forbidden. `scroll.contentSize.width <= scroll.bounds.size.width + 1`, and every card's frame lies inside the scroll view | same |
| Vertical scrolling | Allowed on iPhone; an iPad at a two-column width must fit the whole page without scrolling | allowed |
| Safe areas | Controls respect `view.safeAreaLayoutGuide`; the scroll view is pinned to it on all four edges | same, and the notch/Dynamic Island and the home indicator are what make it load-bearing |
| Render scale | Per `DeviceProfile` record; Quality only where measured | Current window size; 2× is a readability default, not a frame-rate claim |
| Backing scale | Derived from the chosen quality on that record | Derived from the live window, so fold and rotation changes are picked up |

The render scale and the window geometry are separate: `DeviceProfile` decides the backing
scale, the AppKit adapter reads the live window for the guest display. Neither writes the
game's own graphics settings.

## 4. Dynamic Type

| Item | Contract |
| --- | --- |
| Largest supported size | The largest accessibility category the OS offers must remain reachable: every control on the home page, every Add-ons row, every popup |
| Column collapse | An accessibility text size collapses the two-column card grid to one column, because two columns at that size clip |
| Popup bounds | Every popup is constrained to **≤ 85 % of the presenting screen** in both dimensions, with even margins and a reachable Cancel action |
| Localization | The German labels are longer than the English ones; the largest-size check runs in German because that is the failing case |

## 5. Input

| Path | iPad | iPhone |
| --- | --- | --- |
| Touch | Supported. On-screen gamepad, toolbar, trackpad | Supported |
| Keyboard | Hardware keyboard via GameController; the draft/typing path | Supported where a keyboard is attached |
| Controller | Physical controller routing and inspection; a mapped element's system gesture is released only for that element | same |
| Pointer | iPadOS pointer and Magic Keyboard trackpad; pointer presentation is installed by the runtime | Pointer where the OS reports one |
| Dictation | Hold/Toggle on a mapped button; the microphone is never opened until the switch is on and a button is mapped | same |

### Normal-play input budget

This is a correctness rule, not a performance preference. During ordinary play the controller
inspector must produce **no router reports, no main-queue blocks and no log writes** for input
the user has not mapped. Concretely:

- No interest when voice is off or no mapping is armed.
- Only the mapped exact element, or the mapped family, when dictation is armed.
- All learnable **button** elements only while the mapping learner is explicitly armed.
- Continuous axes, synthesised stick-direction buttons and touch-pad movement are never
  normal-play input and are never forwarded merely for inspection.
- An interested continuous source is coalesced to at most one pending report per display
  interval, retaining only its latest value. A button press/release stays lossless and ordered.

The 2026-11-04 device log is the reason: 12,658 duplicated controller-inspector event lines in
one five-minute run, each of them entering the main queue and being written to the log twice.

## 6. Performance profile policy

| Item | Contract |
| --- | --- |
| Who decides | `DeviceProfile` decides the render quality and backing scale; the user may override, and an override is labelled as a preview everywhere it appears |
| Measured devices | Quality is offered only on a record with `measured: YES`; the default is never Quality |
| Unmeasured devices | Balanced at most, and the page says the device is unrecognised |
| Background pacing | Background/inactive is capped at 5 fps by `Bridge/BackgroundPacing`; iPadOS still owns the app's execution lifetime |
| Automatic graphics changes | None. The launcher never changes the game's graphics settings by itself; the reset row is an explicit, confirmed, backed-up action |

## 7. Launcher and Add-ons popup geometry

Every popup in the launcher, Add-ons, voice and preferences goes through one presentation rule:

- Constrained to at most 85 % of the presenting screen in each dimension.
- Even margins on all four sides.
- Content scrolls when it does not fit.
- A reachable Cancel action at the largest supported Dynamic Type with the longest localized
  label.

`UIAlertController`'s implicit iPad sizing is not relied on; a form sheet is *regular* however
narrow it is, which is the assumption that produced the overflowing table header fixed on
2026-10-22.

## 8. Source support versus physical evidence

| Statement | Level |
| --- | --- |
| "The launcher draws a one-column page on iPhone" | source + fixture |
| "iPhone support is complete" | **not** claimed anywhere |
| "The launcher works on this iPad build" | device script, one build, one iPadOS, one mode |
| "The game runs on this iPhone" | recorded only for the 2026-10-02 session in the restored history; not a current claim |
| "Pointer p95 is within 2 ms of baseline" | device measurement only; see the pointer sweep protocol |

A source or fixture result never becomes a device result, and a device result on one form
factor never becomes a claim about the other.

## 9. The test matrix

The two simulators are required; the physical iPad is nice to have. A result was measured
on one of these or it is a source-only result:

| # | Device | Kind | Required? | What it is evidence for |
| --- | --- | --- | --- | --- |
| 1 | iPhone Duo | simulator | yes | The phone layout and the compact pages, against stand-ins |
| 2 | iPad Pro 13-inch (M5) | simulator | yes | The iPad layout, popups and the UIKit adapters, against stand-ins |
| 3 | iPad Pro 12.9-inch (5th generation) | the physical iPad | no | Developer service, physical Metal, real input, the installed build |

A release is measured on both simulators; a physical run is recorded when it happens and
is never a precondition. That ordering is deliberate: the simulators are the only devices
a change can be measured on every time, so they carry the requirement, and hardware is
where the *physical* claims are made — which is a different, narrower thing than passing.

The physical iPad is reached only through `wolkaraforever/tools/`; raw `devicectl` game
operations are not part of the matrix and never produce evidence. No other iPad, no iPhone
hardware, and no fourth simulator is in it, and a result from one is not evidence for any
of the three.

`wolkaraforever/tools/simulators.sh` is the matrix in code: the simulator suites and both
platform wrappers resolve their device through it, and it refuses a device that is not on
this list instead of substituting the nearest one. Adding a device changes this contract,
because a wider matrix is a wider promise about what *tested* means.

## 10. What would make this contract wrong

Change one of these and the contract must be re-measured, not re-worded:

- The two-column threshold, the card insets (14/16) or the row spacing (8).
- `DeviceProfile`'s conservative fallback, or which records are `measured`.
- The input-interest rules in §5.
- The 85 % popup bound.
- The Add-ons manifest format (a migration changes what a package is).
