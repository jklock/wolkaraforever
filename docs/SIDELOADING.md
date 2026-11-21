# Install the unsigned External JIT app

> Verified: 2026-11-21 · Source: `8375cbb`

This page is for the unsigned `.ipa`: `wolkaraforever-unsigned.ipa`, the app a sideloading tool
signs with your own Apple ID. It is a convenience published for an existing release, or a package
you build yourself. Building the app from source and using the Developer service is the supported
route and is described in [Install WolkaraForever](INSTALLATION.md); this route is the one to take
when you cannot or do not want to run Xcode.

The package contains only WolkaraForever's own code: no game, no game assets, no signing
certificate, no provisioning profile, and no signing team.

## What this build can and cannot do

| | Unsigned External JIT app | Source build with Developer service |
| --- | --- | --- |
| Start an installed game | Yes, with a JIT enabler at every launch | Yes |
| Developer service (one-time Mac enrollment, no signing) | **No** — not included in this build | Yes |
| Local signing (page containers you build on a Mac) | Yes, if you build the containers yourself | Yes |
| Log in to Battle.net | Yes — the package carries the builder's public root certificates | Yes |
| Add-ons, touch controls, controller, dictation, Battery Saver, interface recovery | Yes | Yes |

The app is called **Tolkara** on your Home Screen. Its bundle identifier is whatever the package was
built with (`TOLKARA_BUNDLE_ID`), which is why a package you did not build yourself may sit beside
another copy rather than replace it.

## Where a package comes from

1. **A published release.** The maintainer can build and publish the package for an existing tag
   with the manual **Experimental IPA** workflow. It is built exactly as a source build is, verified
   before it is published, and named `wolkaraforever-unsigned.ipa`.
2. **Yourself.** `wolkaraforever/tools/package_altstore_ipa.sh` builds the same package from your own
   tree, verifies it, and writes `build/ipa/wolkaraforever-unsigned.ipa`.
   [Build and run WolkaraForever](BUILDING.md) has the details and the check that proves a package
   is what it claims.

Before you install one you did not build, verify it:

```sh
wolkaraforever/tools/verify_ipa.sh wolkaraforever-unsigned.ipa
```

It refuses anything that is not one app, built for External JIT, without a provisioning profile, an
app extension, a signing team — or without the public root certificates that make login possible.

## Install it

The package is unsigned on purpose: your sideloading tool signs it with **your** Apple ID, which is
what makes it runnable on your device. Every tool has its own screens; these are the steps they all
share.

1. Install a sideloading tool on the device. The release notes name **SideStore** and
   **LiveContainer** and give a link line for each, for example
   `sidestore://install?url=…/wolkaraforever-unsigned.ipa`; **AltStore** works the same way.
2. Install the package with that tool and let it sign the app with your Apple ID.
3. Trust the developer certificate on the device if iPadOS asks: **Settings → General → VPN &
   Device Management**.
4. Open **Tolkara**.

A free Apple ID's signature lasts seven days and must be refreshed by the same tool; a paid Apple
Developer membership lasts a year. Refreshing never deletes the app's data.

## Start a game

1. Open **Tolkara**. It opens the WolkaraForever home page — the page [Use WolkaraForever](USING_WOLKARAFOREVER.md) walks through and [What every control does](UI_REFERENCE.md) pictures.
2. Choose the edition, the region and the game language.
3. Tap **Install** and let the launcher download the game. It keeps it current afterwards; you do
   not copy a game in yourself, and the launcher never modifies the game's own executable.
4. When the page reports that it is ready, tap **Play**.

This build preselects **External JIT** and remembers that choice, so it does not ask how the game
should start. The Developer service is the source build's route; see
[Install WolkaraForever](INSTALLATION.md).

External JIT needs a JIT enabler **at every launch**. Your sideloading tool can provide one, or a
separate enabler such as **StikDebug** can attach as the app opens. The enabler prepares the memory,
the app asks it to detach, and only then does any game code run. Opened without JIT, the app shows
**JIT Not Enabled** — "Tolkara was opened without JIT. Enable JIT for it with the tool you sideloaded
it with (such as SideStore) or a JIT enabler such as StikDebug, then open it again" — instead of
starting the application.

Once the game is running, everything in [Use WolkaraForever](USING_WOLKARAFOREVER.md) and
[What every control does](UI_REFERENCE.md) applies unchanged.

## When it does not work

| What you see | What it means |
| --- | --- |
| The app says External JIT is unavailable | You are running a `Tolkara` (source) build, not this package. The two are different apps. |
| The app opens but the game does not start, and the log mentions an attached debugger | The JIT enabler is still attached. Close the app, start the enabler for this launch, and open the app again. |
| The app says a page container is missing | That build was made with **Local signing** preselected. Build the container on a Mac with `TOLKARA_MODE=local-signing`, or install the package that preselects External JIT. |
| Login is refused with `BLZ51900003` | The package has no public root certificates, or the game's own `WTF/Config.wtf` has no usable region and language. [Use WolkaraForever on iPhone](IPHONE.md#login-is-refused-blz51900003) has the check, and `verify_ipa.sh` refuses a package that lacks the roots. |
| It stopped opening after a few days | The signature expired. Refresh it with the sideloading tool that installed it. |
| Everything else | [Send us a log](SENDING_LOGS.md). The launcher's log is in the app's own Documents folder. |

Do not uninstall the app to fix a configuration problem: that deletes the game data it holds.
