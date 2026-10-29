# Install WolkaraForever

WolkaraForever is installed from source with Xcode. The supported route uses an
Apple-silicon Mac, your paid Apple Developer membership, and your own iPad. It is not
an App Store, TestFlight, or public IPA install.

## Before you begin

You need:

- An Apple-silicon Mac with current Xcode, Xcode command-line tools, XcodeGen, and
  Python 3.
- A paid Apple Developer membership. The app's tunnel needs Network Extension,
  increased-memory-limit, and extended-address-space capabilities; a Personal Team
  cannot provide them.
- An iPad with Developer Mode enabled, unlocked, trusted by the Mac, and with enough
  space for the game. A Forever installation needs roughly 70 GB.
- Your own eligible WoW account. No game files are included in this repository.

## 1. Get the source and configure your identity

```sh
git clone https://github.com/jklock/wolkaraforever.git
cd wolkaraforever
cp local.env.example local.env
wolkaraforever/tools/install_prerequisites.sh --check
wolkaraforever/tools/device_variables.sh --write
```

Open `local.env` and set these values:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID
TOLKARA_BUNDLE_ID=your.unique.bundle.id
TOLKARA_KEYCHAIN_GROUP=your.unique.bundle.id.authorization
DEVICE=YOUR_CONNECTED_IPAD
```

Keep the bundle ID and Keychain group stable. They are what allow a later build to
replace the app without removing its game data or enrollment. `local.env` is private;
never commit or share it.

## 2. Check the iPad, then install

Keep the iPad unlocked and connected. Before the first install, run:

```sh
wolkaraforever/tools/preflight.sh
wolkaraforever/tools/install.sh
```

`install.sh` prepares the project, builds and signs the app, installs it, performs the
Developer-service enrollment when required, verifies the bundle on the iPad, and returns
the app to its normal home screen. Approve the pairing or tunnel prompt on the iPad if
iPadOS asks.

The script refuses to replace an active game session. Quit WoW first. If the app is
still running and you explicitly want the script to request a clean stop, use:

```sh
wolkaraforever/tools/install.sh --replace-running
```

Do not use `--force-kill` unless you accept the risk of interrupting a game-file write.

### If Xcode reports signing errors

Run this once to generate the project:

```sh
wolkaraforever/tools/generate.sh
open build/platform/Tolkara.xcodeproj
```

In Xcode, select the **Tolkara** and **LocalAuthorizationTunnel** targets, choose your
team in **Signing & Capabilities**, then let Xcode repair provisioning. Keep the
configuration in `local.env`; regenerating the project replaces manual project edits.

## 3. Install Forever and play

1. Open **WolkaraForever** on the iPad.
2. Choose **Forever**, your download region, and language.
3. Tap **Install** and keep the app in the foreground until it finishes verifying.
4. Tap **Play**. Allow the private tunnel if asked, then keep the app foregrounded while
   memory preparation completes. The first launch can take several minutes.
5. Sign in with your own account.

After the game is ready, read [Using WolkaraForever](USING_WOLKARAFOREVER.md) for
add-ons, controls, voice input, UI backups, and recovery.

## If something goes wrong

| Problem | What to do |
| --- | --- |
| The Mac cannot see the iPad | Unlock it, reconnect it, tap **Trust**, confirm Developer Mode, then rerun `device_variables.sh --write`. |
| The app will not install | Rerun `preflight.sh`; then check the exact Xcode signing error for both app targets. |
| Enrollment or the tunnel does not complete | Keep the iPad unlocked and connected, then rerun `install.sh`. |
| Play is unavailable | Let any update or verification complete. Use **Settings → Technical details** for the reason. |
| Preparation appears stalled | Keep the app foregrounded for several minutes. If it fails, reopen the app; do not delete it first. |

For a problem report, include the exact Technical details message and a redacted log. Never
include credentials, pairing records, or a device identifier.
