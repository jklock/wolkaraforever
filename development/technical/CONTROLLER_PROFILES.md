# Game controller profiles, and why the game sees a button we mapped

Research note, 2026-10-23. Written because a controller button mapped for dictation
also reaches World of Warcraft, and the question was what can be done about it. Every
claim below is marked **measured** (on Dadpad, from a log or an API read) or
**documented** (Apple's own headers, quoted).

Nothing here changes the game. It is the shape of the problem, the API surface, and
the options for working around it with this pad or any other.

## What we measured

| Fact | Evidence |
| --- | --- |
| The pad presents to iPadOS as **vendor "Xbox Bluetooth Gamepad", category "Xbox One"** | `inspector: trigger Options (hold to talk) began from xbox.bluetooth.gamepad.xbox.one/controller.button.options` — the id is `slug(vendorName).slug(productCategory)` (`ControllerInspector.m`, `AKControllerIdentity`) |
| The mapped trigger is the pad's **Options** button | same line: `controller.button.options` |
| Our app's own GameController session reports **0 controllers** while the pad is on and the app is in the foreground | `inspector: 0 controller(s) connected`, `wolkaraforever.log`, 22:29:59; the home page was on screen at 06:47 the next morning with no further inspector lines. Needs one press to resolve — see "What is still missing" |
| Taking the pad's button from the game is **not** implemented for controller elements | `InputElement`/`AKVoiceSettings.ownedKeyUsages` covers `keyboard.key.<usage>` only; `VoiceViewController` says so in as many words |
| The guest and the layer share one process and one GameController | `platform/translation/GameController/GameController.m` header: the stub is *experimental and opt-in*; `NATIVE_GUEST_SHIMS=GENERIC` does not include it, and `translation/AppKit` links the **real** framework for `GCMouse` |

The last row is the whole problem. There are two consumers of the same objects in one
process: our inspector, and the guest. Anything the framework reports, it reports to
both.

## The profile model

**Documented** (`GCController.h`, `GCPhysicalInputProfile.h`, and the profile
subclasses in the same framework):

- A `GCController` is a device. It exposes up to four *profiles*:
  `extendedGamepad`, `microGamepad`, `gamepad` (deprecated since iOS 10),
  `motion`, plus `physicalInputProfile` — which, as the header says, *"is equivalent
  to the controller's microGamepad, or extendedGamepad instance"*.
- Since iOS 17 a controller also has `input`, a `GCControllerLiveInput`; its
  `unmappedInput` is the same input **"without any system-level control remapping
  applied"**.
- `GCExtendedGamepad` is the profile an Xbox-style pad gets. Its documented shape:
  two shoulders, two triggers, four face buttons in a diamond, a D-pad, two
  thumbsticks with optional clicks, **optional Home and Options buttons**, and a
  Menu button.
- Subclasses add vendor extras: `GCXboxGamepad` (paddles, Share),
  `GCDualShockGamepad`, `GCDualSenseGamepad`. `GCDirectionalGamepad` is the
  Siri-Remote-style profile (`GCDirectionalGamepad.h`); `GCRacingWheel` is its own
  device.

So his pad — an Xbox One category device — is an **extended** profile, most likely a
`GCXboxGamepad`, which is why Share is even visible to us (`currentControllerDeclaresShare`).

## The element inventory and the names we use

**Documented**: the framework names every element with a `GCInput…` constant. The
ones an extended profile can carry, and the id our layer derives for each
(`AKInputElementForControllerButton` on the profile's own dictionary key):

| Constant | Profile key | Our element id | Notes |
| --- | --- | --- | --- |
| `GCInputButtonA/B/X/Y` | `Button A` … | `controller.button.a` … | face buttons |
| `GCInputButtonMenu` | `Button Menu` | `controller.button.menu` | primary menu; iPadOS uses it |
| `GCInputButtonOptions` | `Button Options` | `controller.button.options` | **secondary menu — the button in use** |
| `GCInputButtonHome` | `Button Home` | `controller.button.home` | optional; iPadOS system action |
| `GCInputButtonShare` | `Button Share` | `controller.button.share` | Xbox; iPadOS spends it on screenshots |
| `GCInputLeftShoulder`/`RightShoulder` | `Left Shoulder` … | `controller.button.left.shoulder` … | |
| `GCInputLeftTrigger`/`RightTrigger` | `Left Trigger` … | `controller.button.left.trigger` … | analog |
| `GCInputLeftThumbstickButton`/`Right…` | `Left Thumbstick Button` … | `controller.button.left.thumbstick.button` … | stick clicks |
| `GCInputXboxPaddleOne…Four` | `Paddle 1` … | `controller.button.paddle1` … | only if the hardware sends them |
| `GCInputLeftThumbstick`/`RightThumbstick` | `Left Thumbstick` … | `controller.axis.left.thumbstick` | axes |
| `GCInputDirectionPad` | `Direction Pad` | `dpad.dpad.*` | directions, not the pad |
| `GCInputDualShockTouchpadButton`, `…One`, `…Two` | `Touchpad Button`, `Touchpad 1/2` | — | DualShock/DualSense only |
| `GCInputBackLeftButton`/`BackRightButton`, `GCInputGripButton`, `GCInputLeftSideButton`/`RightSideButton` | — | — | newer iOS form factors |
| `GCInputPedalAccelerator/Brake/Clutch`, `GCInputSteeringWheel`, `GCInputShifter` | — | — | racing wheel |
| `GCInputStylusPrimaryButton`/`SecondaryButton`/`Tip` | — | — | stylus |

The paddles are the interesting row: a pad that sends them gives us four buttons a
game written in 2004 cannot have bound, and they are not system-reserved.

## What iPadOS keeps for itself

**Documented** (`GCControllerElement.h`, and it uses this exact example): the Options
button *"can be bound to take a screenshot with a long press. This occurs outside of
the control of the app. If a user presses the Options button, the system gesture
recognizer will run by default. If a long press is detected, input will not be
forwarded to your app … If a long press is not detected, input will be forwarded to
your app, with a delay."*

An app can set `preferredSystemGestureState = GCSystemGestureStateDisabled` on an
element to ask for *"system gesture recognizers will not run at all. Input is passed
directly to the app."* That is what our inspector does for a mapped element, and for
everything while the user is choosing one.

That is the limit of it, though: it governs **iPadOS's** recognisers, not another
consumer in the same process.

Related, and worth knowing before choosing a button:

- **Home** has its own settings API since iPadOS 27
  (`GCControllerHomeButtonSettingsManager`): the system action *"can be deferred to
  the app"* when the app sets
  `physicalInputProfile.buttons[GCInputButtonHome].preferredSystemGestureState` to
  `GCSystemGestureStateDisabled` (the header's words). In-app action, not a way to
  hide it from a second consumer.
- **Share** is spent on the screenshot gesture before any app is offered it; the
  inspector's notes call the screenshot notification the only route to it.
- **Menu/Options** are what a guest UI written for a desktop would never have bound,
  but on iPadOS they are also the two buttons the system wants.
- `GCEventViewController` and, since iOS 18, `GCEventInteraction` govern whether
  controller input *also arrives as UIKit events* in this app (`receivesEventsInView`,
  default `NO` = "exclusively through the Game Controller framework"). They route
  input within one app; they cannot hide an element from it.

## Remapping: what it can and cannot buy us

**Documented** (`GCPhysicalInputProfile.h`, "Remapping input elements"): iPadOS
supports per-user, per-app controller customisation, and the framework reflects it:

- `elements` / `buttons` are keyed by the **alias**; `localizedName` follows the
  remap while `unmappedLocalizedName` and `GCControllerLiveInput.unmappedInput` do not.
- `mappedElementAlias(forPhysicalInputName:)`, `mappedPhysicalInputNames(forElementAlias:)`,
  `hasRemappedElements`, and `GCControllerUserCustomizationsDidChange` — *"a
  notification that posts when the user customizes the button mappings or other
  settings of a controller"*.

That last sentence is the key to the user's own idea. A remap is applied **inside the
framework**, which means it applies to every consumer in the process at once: remap a
button and both our inspector **and** the guest see the remapped element. Two
consequences:

1. Remapping cannot hide a press from the guest. It can only change *which logical
   button* the press becomes — and therefore which of the game's bindings it triggers.
2. It is still the most useful lever, because the game's reaction follows the
   binding. If Options is remapped onto a button the game does nothing with, the game
   stops reacting to it. That is exactly "if I remapped the key this would be a non
   issue" — true, as long as the target is a button the game ignores.

Our layer reads the profile's keys, so our element ids follow the alias too. An
existing mapping is remembered per controller model, so a remap can silently move a
saved mapping onto a different physical button — worth knowing before remapping.

## The options, ranked

| Option | What it fixes | What it costs | Evidence |
| --- | --- | --- | --- |
| **A keyboard key as the trigger** | Completely: our shim suppresses the key before the guest sees it (`AKTouchOwnedKeyUsagesDidChange`) | Needs a keyboard, or a pad button that iPadOS presents as a key (it does not) | `INPUT_TRIGGERS.md`, `test_touch_controls_ui.sh --self-test` |
| **A pad button the game does not use** | Completely, with no code: the game simply does not react | Requires knowing which buttons those are on *this* pad — the inventory below | This note, once the press is captured |
| **System remap** (Settings → General → Game Controllers, per app) | Moves the trigger onto such a button, or moves Options off the game's binding | The guest follows the remap, so it can move the problem rather than end it; saved mappings follow aliases | `GCPhysicalInputProfile.h` |
| **Change the game's own binding** | Stops the game reacting | The game's UI has to offer it; a controller element may not be listed | not measured — the game was not touched |
| **Build the guest's GameController stub** (`TOLKARA_EXPERIMENTAL_ADAPTERS=GameController`) | The guest sees no controllers at all | The game loses **all** pad input, not one button | `translation/GameController/GameController.m` |
| **Interpose on the guest's handlers** | One element, reliably | Touches the game's own input path — ruled out by the user, and written up here only so the decision is recorded | considered, not done |

Two things follow. First, the *hard* guarantee only exists for keyboard keys today,
because that is the one path where our own shim sits between the input and the guest.
Second, for a pad the honest product answer is "use a button the game ignores", and
the data needed to name one is the pad's element list plus its paddles.

## What is still missing, and how to get it

The inventory of **this** pad — which elements it actually exposes, whether it sends
`Paddle 1…4`, whether it declares Share, and what its profile class is — is not in any
log we have: the app was running with `0 controller(s) connected` at the last recorded
launch, and a pad connected while the app is suspended produces nothing in our log.

One press with the app in the foreground is enough. The inspector logs a full
inventory on connect (`inspector: …`), which will give:

- `vendorName`, `productCategory`, transport and the profile classes present;
- every button key in `physicalInputProfile.buttons` (which is the list of ids above,
  filtered to the ones this hardware sends);
- whether `buttonShare` and `paddleButton1…4` exist;
- the current `preferredSystemGestureState` of each reserved button.

With that, "a button the game does not use" can be named rather than guessed.
