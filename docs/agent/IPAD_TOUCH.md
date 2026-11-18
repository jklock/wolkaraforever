# iPad touch (the TouchPlay interface)

> Verified: 2026-11-18 · Source: `upstream/ipad-touch` · Proof: `check_layers.sh`, `test_touch_controls_ui.sh`, `test_touch_gamepad_ui.sh`, `test_wow_launcher_ui.sh`, `test_addon_package.sh`, `test_addon_archive.sh`, `test_touchplay_addon.sh`

**iPad touch** (`ipadtouch`) is the fifth stored interface mode: an iPad played with the bundled
TouchPlay add-on, whose buttons are keys. Everything below is gated on `AKInterfaceModeIsTouchPlay()`
(YES only for the stored value `ipadtouch`) or on an object only that mode makes; in iPadOS, iOS,
iOS on Duo and Automatic the product is unchanged. The human guide is
[Play by touch on iPad](../IPAD_TOUCH.md).

## Where the code is

| Layer path | What it is |
| --- | --- |
| `wolkaraforever/Touch/InterfaceMode.{h,m}` | `ipadtouch`, `AKInterfaceModeIsTouchPlay()`, the two-crash fallback to iPadOS (the session functions do nothing in any other mode) |
| `wolkaraforever/Touch/TouchContract.{h,m}` | reads TouchPlay's saved button list (`TPC1;...`, the contract); compiled into the app (`launcher/WoW`, class names `AKApp...`) and the adapter |
| `wolkaraforever/Touch/TouchAreas.{h,m}` | the buttons' fingers: tap on lift, hold, press keys, chords in any modifier order, aiming, the world key, the press glow, the toolbar dock |
| `wolkaraforever/Touch/TouchWorldSignal.{h,m}` | the add-on's secure-input pulses: 1 in the world, 2 left, 3 a window open |
| `wolkaraforever/Touch/TouchGamepad.{h,m}` | the walk stick (`initWalkStickWithHostView:below:`), its own overlay beside jklock's touch controller |
| `wolkaraforever/Touch/TouchTextBridge.{h,m}` | the secure field over the game's password box (typed by hand, never stored, no AutoFill) |
| `wolkaraforever/Touch/TouchControls.{h,m}` | the iPad touch toolbar, the signal wiring, release on resign, the chat chips and Send |
| `addons/TouchPlay`, `wolkaraforever/Addons/TouchPlay-*.{zip,json}` | the add-on's sources and its packaged, hash-bound release |
| `wolkaraforever/tools/tests/touchplay`, `wolkaraforever/tools/touchplay` | the add-on's own LuaJIT tests and its art tool (`make-art.py`, SVG sources) |

## Patches

All in `translation/AppKit/AppKit.m` (0065 also states its rule in `tests/test_appkit_views.m`).

| Patch | What it does |
| --- | --- |
| 0065 `host-ipad-touch-has-the-direct-touch-gestures` | the host's direct-touch gate (0055) is YES for `ipadtouch` as for `ios`; every other value unchanged |
| 0066 `touchplay-buttons-take-their-fingers` | a finger on a TouchPlay button is the button's; keys with modifiers through the host |
| 0067 `touchplay-world-touch` | second tap right click, hold sends the world key, turn drag, 20 pt edge zone, aiming |
| 0068 `touchplay-pinch-skips-the-walk-stick` | the camera pinch never takes the walk stick's thumb |
| 0069 `touchplay-world-touch-only-in-the-world` | 0067's rules only while the areas are live (in the world) |
| 0070 `touchplay-leaving-the-app-lets-go-of-the-world` | the host's world gesture is let go when the app resigns |
| 0071 `touchplay-chord-modifiers-last-the-games-frame` | a chord's modifiers stay down for the game's frame; NSApplication's queue asks the host only while it holds one |
| 0072 `touchplay-pinch-skips-the-walk-stick-with-a-window-open` | the same with a game window open |
| 0073 `touchplay-two-fingers-are-a-pinch` | two fingers that come together are a pinch even on the walk stick |

## Where jklock's features meet iPad touch

| jklock feature | In iPad touch | Rule |
| --- | --- | --- |
| Touch Controller 2 (overlay, layouts, direct camera) | not made | iPad touch makes no controller overlay or virtual gamepad; the walk stick is its own `AKTouchGamepad` instance. The Controller Layout rows keep their wording and act on the other modes' layout. |
| Direct touch (0055) | yes, extended | 0065 opens it to `ipadtouch`; 0066-0073 add the buttons and world rules on top, only with the areas iPad touch makes |
| Chat Composer (review then send) | not in force | `composerInReviewMode` is NO in iPad touch; every other mode follows the stored delivery mode |
| Toolbar | its own placement | top-centre band, four buttons (no controller toggle or gear); every other mode keeps its toolbar |
| Trackpad switch | its own key | `WolkaraForeverIPadTouchTrackpadEnabled`; the shared `TKTouchTrackpadEnabled` is untouched |
| Add-On Manager recommendation | TouchPlay | `TKAddonRecommendationTouchPlay`, the same bundled-package flow as WolkaraRoue's; the Launcher Manager row `wow.launcher.touchPlay` is in the card only in this mode |
| Controller touchpad as mouse, dictation, controller ingress | unchanged | jklock's, in every mode |

## Tests

- `test_touch_controls_ui.sh`: the contract reader (1000 checks), the areas (502), the text bridge
  (97) and the world signal (54) as bare simulator processes, the two-images check, the contract
  wiring check, and the controls fixture in all four stored modes (iPadOS, iOS and iOS on Duo run the
  suite they always ran).
- `test_touch_gamepad_ui.sh`: the interface-mode and crash-fallback fixtures and the 21 walk-stick
  cases, in all four stored modes, plus `test_crash_guard_wiring.sh`.
- `test_wow_launcher_ui.sh`: the mode sheet (iPad only), the fallback notice, the TouchPlay row and
  its page.
- `test_addon_package.sh`, `test_addon_archive.sh`: the TouchPlay package verifies, refuses its nine
  wrong copies and installs through the store.
- `test_touchplay_addon.sh`: the add-on's Lua compiles, its `.toc` is complete, its 34 test files pass.

## Refresh when

Refresh after a patch here is added or renumbered, after a jklock feature meets an iPad touch one, or
after TouchPlay's contract, package or tests change.
