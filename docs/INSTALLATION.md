# Install WolkaraForever

> **Current as of 2026-11-05 · branch `liveupdates-11042026`.**

WolkaraForever is installed from source. It is not an App Store, TestFlight, or public-IPA
release. The supported integrated route uses the device's Developer service, on an iPad or
an iPhone. The behaviour contract for both form factors is
[the supported-device contract](../development/architecture/DEVICE_CONTRACT.md), and the iPhone
page is [iPhone support](IPHONE.md).

## Requirements

- Apple-silicon Mac with current Xcode and command-line tools, XcodeGen, and Python 3.
- A paid Apple Developer membership. The required tunnel and memory capabilities are not
  available to a Personal Team.
- An unlocked device in Developer Mode that trusts the Mac and has sufficient free storage:
an  iPad or an iPhone. A Forever installation needs roughly 70 GB, which in practice means an
iPad.
- Your own eligible WoW account. This repository contains no game files or account access.

## Configure the local build

```sh
git clone https://github.com/jklock/wolkaraforever.git
cd wolkaraforever
cp local.env.example local.env
wolkaraforever/tools/install_prerequisites.sh --check
wolkaraforever/tools/device_variables.sh --write
```

Set the values requested in the ignored `local.env` file:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID
TOLKARA_BUNDLE_ID=your.unique.bundle.id
TOLKARA_KEYCHAIN_GROUP=your.unique.bundle.id.authorization
DEVICE=YOUR_CONNECTED_DEVICE
```

Keep the bundle ID and Keychain group stable. They allow later builds to replace the app
without erasing its data or enrollment. Never commit or share `local.env`.

## Install on the device

Keep the device unlocked and connected, then run:

```sh
wolkaraforever/tools/preflight.sh
wolkaraforever/tools/install.sh
```

The installer prepares the project, builds and signs it, installs the app, performs
Developer-service enrollment when needed, verifies the installed bundle, and returns the
app to its launcher. Approve any pairing or tunnel prompt.

The same commands install on an iPhone. `wolkaraforever/tools/device_variables.sh --write`
reads `DEVICE` from whichever device is attached, so a build that was aimed at an iPad does not
silently overwrite the app on a phone or the other way round.

The installer refuses to replace an active game session. Quit the game first, or explicitly
request a clean stop:

```sh
wolkaraforever/tools/install.sh --replace-running
```

`--force-kill` can interrupt a game-file write; use it only when you accept that risk.

## Repair signing in Xcode

If Xcode reports a signing error, generate the project and open it:

```sh
wolkaraforever/tools/generate.sh
open build/platform/Tolkara.xcodeproj
```

Select **Tolkara** and **LocalAuthorizationTunnel**, choose your team under
**Signing & Capabilities**, and let Xcode repair provisioning. Preserve the actual values in
`local.env`; generated project changes are not a durable configuration surface.

## First launch

1. Open **WolkaraForever**.
2. Choose **Forever**, then check the region and the language. The region starts as the one
   this device is set to, and it must match the region of the account you sign in with: the
   launcher writes it into the client's own settings at install and never rewrites them, so
   the wrong region leaves sign-in at **Connecting**. The region/locale row on the home
   screen changes it before you install.
3. Select **Install**, then keep the app open while it downloads and verifies the client.
4. Select **Play**. Allow the private tunnel if asked and keep the app foregrounded while
   memory preparation completes; it can take several minutes.
5. Sign in with your own account.

WolkaraForever has two language settings and they are independent: **Game language** changes the
text and audio the client downloads, and **App language** changes the launcher's own labels
(English, German, or System Default). Both live in the Game Edition card on the home screen, and
neither requires reinstalling the app. See [App language](USING_WOLKARAFOREVER.md#app-language).

Continue with [Using WolkaraForever](USING_WOLKARAFOREVER.md).

## Troubleshooting

| Problem | Action |
| --- | --- |
| Mac cannot see the device | Unlock and reconnect it, accept **Trust**, confirm Developer Mode, then rerun `device_variables.sh --write`. |
| App will not install | Run `preflight.sh` and inspect the exact Xcode signing error for both app targets. |
| Enrollment or tunnel fails | Keep the device connected and unlocked, then rerun `install.sh`. |
| Play is unavailable | Let download or verification finish; use **Settings → Technical details** for the reason. |
| Startup appears stalled | Keep the app foregrounded for several minutes. If it fails, reopen the app rather than deleting it. |

For support, provide the exact Technical details message and a redacted log—never credentials,
pairing records, provisioning data, or a device identifier.
