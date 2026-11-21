# Install WolkaraForever

> Verified: 2026-11-21 · Source: `8375cbb`

Install WolkaraForever from source on an iPad or iPhone. This guide uses the supported Developer-service route; [Build and run WolkaraForever](BUILDING.md) covers the other execution modes and the build itself.

## Requirements

- Apple-silicon Mac with current Xcode, Xcode command-line tools, XcodeGen, and Python 3. An Intel
  Mac runs the same commands but `install_prerequisites.sh --check` warns that the documented path
  and the device builds are arm64.
- Paid Apple Developer membership.
- Unlocked iPad or iPhone in Developer Mode that trusts your Mac.
- About 70 GB free for the Forever game data and its updates (the launcher also keeps a 1 GB reserve).
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

The app starts the game through **Developer service**, the route this guide sets up; the unsigned package in [Install the unsigned External JIT app](SIDELOADING.md) uses **External JIT** instead. The route is part of the build (it comes from `TOLKARA_MODE` in `local.env`, which `local.env.example` already sets to `developer-service`) and is remembered once used, so the home page does not ask. [Build and run WolkaraForever](BUILDING.md) explains what each mode needs.

## Update or recover

Run `install.sh` again with the same private configuration to update the app. Do not delete the app as a first recovery step: it removes downloaded game data. If signing fails, correct `DEVELOPMENT_TEAM` in `local.env` (or the account in Xcode’s Settings → Accounts), then rerun preflight.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| Prerequisite check fails | Install the named Mac tool, then run the check again. |
| Device is missing | Unlock it, reconnect it, confirm trust and Developer Mode, then rerun `device_variables.sh --write`. |
| Install refuses replacement | Stop the game from the app before retrying. |

Read [Compatibility](../COMPATIBILITY.md) for support limits.
