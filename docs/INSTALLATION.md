# Install WolkaraForever

> **Current as of 2026-10-29 · branch `main`.**

WolkaraForever is installed from source. It is not an App Store, TestFlight, or public-IPA
release. The supported integrated route uses the iPad Developer service.

## Requirements

- Apple-silicon Mac with current Xcode and command-line tools, XcodeGen, and Python 3.
- A paid Apple Developer membership. The required tunnel and memory capabilities are not
  available to a Personal Team.
- An unlocked iPad in Developer Mode that trusts the Mac and has sufficient free storage.
  A Forever installation needs roughly 70 GB.
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
DEVICE=YOUR_CONNECTED_IPAD
```

Keep the bundle ID and Keychain group stable. They allow later builds to replace the app
without erasing its data or enrollment. Never commit or share `local.env`.

## Install on the iPad

Keep the iPad unlocked and connected, then run:

```sh
wolkaraforever/tools/preflight.sh
wolkaraforever/tools/install.sh
```

The installer prepares the project, builds and signs it, installs the app, performs
Developer-service enrollment when needed, verifies the installed bundle, and returns the
app to its launcher. Approve any iPadOS pairing or tunnel prompt.

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
2. Choose **Forever**, a region, and a language.
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
| Mac cannot see the iPad | Unlock and reconnect it, accept **Trust**, confirm Developer Mode, then rerun `device_variables.sh --write`. |
| App will not install | Run `preflight.sh` and inspect the exact Xcode signing error for both app targets. |
| Enrollment or tunnel fails | Keep the iPad connected and unlocked, then rerun `install.sh`. |
| Play is unavailable | Let download or verification finish; use **Settings → Technical details** for the reason. |
| Startup appears stalled | Keep the app foregrounded for several minutes. If it fails, reopen the app rather than deleting it. |

For support, provide the exact Technical details message and a redacted log—never credentials,
pairing records, provisioning data, or a device identifier.
