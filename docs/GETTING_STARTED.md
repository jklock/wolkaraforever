# Build and run

The short route. For the checkpointed version with troubleshooting, see
[From zero to playing](FROM_ZERO.md).

## Requirements

- Apple silicon Mac, Xcode for your iPad's iPadOS version, XcodeGen, Python 3.
- A **paid** Apple developer account. The app and its tunnel need Network Extension,
  increased memory limit and extended address space; free Personal Team signing cannot
  provide them.
- An iPad with Developer Mode on, trusted by the Mac. Tested on an iPad Pro M5, iPadOS 27.
- Room for the game: the tested Forever install is about 70 GB.
- Your own WoW account.

`wolkaraforever/tools/install_prerequisites.sh` checks and installs the Mac pieces.

## 1. Clone and configure

```bash
git clone https://github.com/jklock/wolkaraforever.git
cd wolkaraforever
brew install xcodegen
cp local.env.example local.env
```

`platform/` already holds the current Tolkara engine; do not clone it separately. With the
iPad connected, `wolkaraforever/tools/device_variables.sh --write` fills `DEVICE`.

Fill in `local.env`:

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID
TOLKARA_BUNDLE_ID=local.wolkaraforever.yourname
TOLKARA_KEYCHAIN_GROUP=local.wolkaraforever.yourname.authorization
DEVICE=YOUR_DEVICE_UDID
TOLKARA_MODE=developer-service
NATIVE_GUEST_SHIMS=GENERIC
GUEST_EXE=
```

Keep these local; never commit them. `wolkaraforever/tools/preflight.sh` checks the Mac,
device and app before you build.

## 2. Build and install

Either:

```bash
wolkaraforever/tools/install.sh
```

which prepares, builds, signs, installs, enrolls and relaunches — or by hand:

```bash
wolkaraforever/tools/generate.sh
open build/platform/Tolkara.xcodeproj
```

Pick the **Tolkara** scheme and your iPad, then Run. The app on the device is called
**WolkaraForever**. Do not run `LocalAuthorizationTunnel` or `StorageProbe` as the
application.

Automatic signing must succeed for both `Tolkara` and `LocalAuthorizationTunnel`. Keep
**Debug executable** and **Metal API Validation** off — the generated scheme already does.
Store personal settings in `local.env`; regenerating replaces project edits.

## 3. Enroll once

```bash
build/platform/tools/enroll.sh
```

Keep the device unlocked, and approve the pairing prompt. The command must end with
**Verified enrollment imported**. It stores this installation's authorization in the
device-only Keychain; changing the bundle ID or Keychain group means enrolling again.

## 4. Install a game and play

Choose the edition, region and language, press **Install**, keep the app in front, then
**Play** once it is ready. Allow the local tunnel if iPadOS asks — it reaches the device's
developer service for memory preparation, it does not stream the game.

Already have the game on your Mac? Copy it instead:

```bash
wolkaraforever/tools/push_game.sh --source "/Applications/World of Warcraft"
```

See [DEVICE_WORKFLOW.md](DEVICE_WORKFLOW.md).

## Updating

- **The app**: close the game, pull, regenerate, Run again with the same bundle ID, team
  and Keychain group. Game data survives.
- **The game**: inside the app, on open and before Play.
- **The engine**: [MAINTAINING.md](MAINTAINING.md#updating-tolkara-the-engine).

If something fails, record Settings → Technical details and a redacted log. Do not delete
the app or its data as a first step. A build success or a simulator pass does not prove the
game runs on another device.
