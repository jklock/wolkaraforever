# iPhone support

> **Current as of 2026-11-05 · branch `liveupdates-11042026`.**
>
> iPhone and iPad are both supported. This page says what has been measured on a physical
> iPhone and what has not. The layout and behaviour contract for both form factors is
> [the supported-device contract](../development/architecture/DEVICE_CONTRACT.md).

## What is measured, and what is not

One physical iPhone has been exercised on this project: an **iPhone 16 Pro Max on iOS 27.0**,
in **Developer service** mode. On 2026-10-02 that session logged in to World of Warcraft
Forever 1.60.1 (build 70170), entered the world, and played for about two hours without a
reported problem, at 60 FPS, 50 % render scale and graphics quality 2. A Bluetooth keyboard
and AssistiveTouch were used for that first session; the app's own iOS keyboard and
touchscreen-trackpad controls were confirmed working in Forever on the same device afterwards.
Classic Era 1.15.9 (build 70003) reached its cinematic and login screen.

That is a record of one session on one device, and it is the whole of the physical iPhone
evidence. It is **not** a claim that:

- any other iPhone model or iOS version works;
- Local signing or External JIT works on an iPhone (neither was tested there);
- the iPhone presentation has been checked at every Dynamic Type size or in every locale by a
  person, beyond the launcher checks listed below;
- the game's own text field, add-ons, or UI backup/restore were exercised on that phone.

Every phone record in `wolkaraforever/WoW/DeviceProfile.m` is marked `measured: NO` for that
reason: the session above proves the product ran, not that a particular render target was
benchmarked.

## Install

The build, signing and install steps are the same as for an iPad. Follow the prerequisites,
Developer Mode and signing steps in [BUILDING.md](../development/guides/BUILDING.md), then use
the project's own tools rather than raw device commands.

From the repository root, create `local.env` from `local.env.example` once and set your own
`DEVELOPMENT_TEAM`, a unique `TOLKARA_BUNDLE_ID`, and `DEVICE`. Keep that file private; it is
ignored by Git. For iPhone, the measured execution mode is Developer service:

```sh
TOLKARA_MODE=developer-service NATIVE_GUEST_SHIMS=GENERIC wolkaraforever/tools/install.sh
```

`install.sh` prepares the tree, builds and signs the app and its helper, then installs it over
the same bundle ID (which keeps the app's data). `wolkaraforever/tools/device_variables.sh
--write` fills `DEVICE` from the attached phone so the tooling targets the device you meant
rather than whichever one is first attached.

For a file-level installation the app exposes its Documents folder through `UIFileSharing`
so a game can be copied to it with `wolkaraforever/tools/push_game.sh --source
"/Applications/World of Warcraft"`. Do not use raw `devicectl` file operations: the project
scripts check for active writes and preserve the game store.

To launch, read logs, or check state, use `wolkaraforever/tools/launch.sh`,
`wolkaraforever/tools/device_log.sh` and `wolkaraforever/tools/preflight.sh`. Never uninstall
the app or force-stop a running client.

## What the phone page looks like

The launcher is a single scrolling column on iPhone at every width and in both orientations,
inside the safe area, with no fixed iPad viewport and no horizontal overflow. The iPad keeps
its two-column card grid whenever the page is at least 700 points wide and the text size is
not an accessibility size.

| Behaviour | iPad | iPhone |
| --- | --- | --- |
| Card grid | two columns at ≥ 700 pt | one column, always |
| Scrolling | the whole page fits at two-column width | vertical scrolling is expected |
| Home page | mark beside the status panel | mark above the status panel |
| Add-ons | full column set, compact fallback when narrow | compact rows |
| Popups | ≤ 85 % of the screen, even margins | same |

At the largest accessibility text size the iPad collapses to one column too, because two
columns clip. German is the failing case for width, so that is the language the oversized
check runs in.

## Starting with mobile data

The first reported cellular-only launch on 2026-10-04 failed to connect to the on-device
developer service even though the route was running, with Wi-Fi enabled but not connected.
Cellular-only startup is still an unresolved requirement and remains experimental.

The recovery sequence in the runtime is:

1. Keep mobile data enabled while checking or installing updates and pressing Play.
2. If the local connection fails, the route is kept and retried for up to two minutes. When
   the waiting message appears, turn mobile data off in Control Centre and return to the app
   without closing it.
3. Keep the app in front while it prepares memory. Turn mobile data back on afterwards for the
   game's own connection, and restore it if preparation times out or fails.

The app never changes cellular settings itself. Only a TCP reset or timeout **before the first
connection** is retried; pairing or proof failures, later disconnects, memory preparation and
an uncertain detach are never retried by this mechanism.

This is a candidate workaround informed by StikDebug's and SideStore's published network
sequences, not a confirmed fix. Normal startup with mobile data continuously enabled remains
the goal.

## Copying a game to the phone

Open the app once with the phone connected; Finder > your iPhone > Files and Files > On My
iPhone then list the app's Documents folder. Creating an unrelated folder with the same name
does not register the app for file sharing. Installing over the same bundle ID preserves its
data.

Use `wolkaraforever/tools/push_game.sh --source "/Applications/World of Warcraft"` to copy
your own Mac installation. The script copies the game unchanged. It does not copy account
preferences, saved credentials or add-ons.

Before the first launch, set the region and language consistently: `portal`, `textLocale` and
`audioLocale` must agree with the region you chose and the languages you installed, or the
tested client shows its unsupported region selector. Those are local game settings, not
defaults in this project's source, and this project does not write them for you.

For Forever, take those values from a working Forever `WTF/Config.wtf` after a successful
manual login on the Mac. Do not carry over another edition's `portal` value just because the
account region matches.

## System certificates

Keep the default `TOLKARA_SYSTEM_ROOTS=YES` in a private build on your own Mac. It packages
public system root certificates for the macOS Security adapter; it does not export personal
keychain contents or private keys, and iOS still applies its own trust policy. The published
redistributable build deliberately sets it to `NO` so the artifact contains no system roots —
copying that choice into a private build leaves the adapter without the resource, which is
what happened to the first iPhone build.

## Mouse, controller and keyboard

The initial Forever session used a Bluetooth keyboard and **Settings > Accessibility > Touch >
AssistiveTouch**; both editions required AssistiveTouch for the tested physical mouse. In
Forever a left click did not activate the tested controls, while pressing the mouse wheel
(middle click, not scrolling) did, which then allowed controller support to be enabled.

This project's own input path is different and is what current builds use: the on-screen
gamepad, the toolbar trackpad, the hardware keyboard via GameController, and physical
controller routing and inspection. Their synthetic and fixture tests pass, and the keyboard
and trackpad controls were confirmed in Forever on that physical iPhone. Input on other
phones and in other applications remains unverified.

## Validation and remaining limits

- The app and its helper declare device families `[1, 2]` and support both landscape
  directions on iPhone while preserving the iPad's four orientations.
- A signed build installed on the physical iPhone; Developer service authenticated the tunnel
  and prepared executable memory. Classic Era ran every initializer and reached its cinematic
  and login screen; preparation took approximately 53–55 seconds in the recorded attempts.
- Forever 1.60.1 (70170) login, world entry and about two hours of gameplay were confirmed on
  2026-10-02, including a cold launch after a reboot with no Mac connected.
- Other iPhone models, other iOS versions and iPad regressions on hardware are unverified.
  The two-hour report covers one Forever session, not every game area.
- The deployment target is not a tested-device support claim.

## For contributors

Commit source, documentation and synthetic tests only. Keep generated Xcode projects,
`local.env`, build products, raw device logs, game configurations, application files, signing
material and pairing records out of a pull request. A model name, OS version and game build are
enough context for a compatibility report; device names and identifiers are not needed and must
not be committed.
