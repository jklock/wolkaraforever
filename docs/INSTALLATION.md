# Install WolkaraForever

> Verified: 2026-11-13 · Source: `3c33543`

Install WolkaraForever from source on an iPad or iPhone. This guide uses the supported Developer-service route.

## Requirements

- Apple-silicon Mac with current Xcode, Xcode command-line tools, XcodeGen, and Python 3.
- Paid Apple Developer membership.
- Unlocked iPad or iPhone in Developer Mode that trusts your Mac.
- At least 70 GB free for a Forever installation.
- Your own eligible game account and game data.

## Configure the build

1. Clone the repository and create your private configuration.

   ```sh
   git clone https://github.com/jklock/wolkaraforever.git
   cd wolkaraforever
   cp local.env.example local.env
   ```

2. Keep the bundle ID and Keychain group stable in `local.env` so updates keep the app’s data and enrollment.
3. Check prerequisites, select the connected device, and run preflight.

   ```sh
   wolkaraforever/tools/install_prerequisites.sh --check
   wolkaraforever/tools/device_variables.sh --write
   wolkaraforever/tools/preflight.sh
   ```

## Install and start

Run:

```sh
wolkaraforever/tools/install.sh
```

The installer builds, signs, installs, and launches the app through project safety checks. It refuses to replace a running game unless you request that action. Do not use raw device-file commands to install or copy game data.

On first launch, choose Forever, a region, and a game language. Download the required data and select **Play** only after the launcher reports that it is ready.

## Update or recover

Run `install.sh` again with the same private configuration to update the app. Do not delete the app as a first recovery step: it removes downloaded game data. If signing fails, correct the selected identity in Xcode, then rerun preflight.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| Prerequisite check fails | Install the named Mac tool, then run the check again. |
| Device is missing | Unlock it, reconnect it, confirm trust and Developer Mode, then rerun `device_variables.sh --write`. |
| Install refuses replacement | Stop the game from the app before retrying. |

Read [Compatibility](../COMPATIBILITY.md) for support limits.
