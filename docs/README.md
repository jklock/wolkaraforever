# WolkaraForever user guide

> **Current as of 2026-11-05 · branch `liveupdates-11042026`.**

These guides are for using WolkaraForever. They describe the supported source install and
the features exposed by the current app; engineering notes and historical records are kept
outside this folder.

1. [Install WolkaraForever](INSTALLATION.md) on an iPad or an iPhone.
2. [Use WolkaraForever](USING_WOLKARAFOREVER.md) to install Forever, configure controls
   and voice, manage add-ons, and protect or recover the UI.
3. [iPhone support](IPHONE.md), for what has actually been measured on a phone.

The behaviour both form factors are held to is
[the supported-device contract](../development/architecture/DEVICE_CONTRACT.md).

If something fails, capture the exact **Settings → Technical details** message and a
redacted log. Do not include account credentials, signing material, pairing records, or
device identifiers. Do not delete the app as a first troubleshooting step because that
removes its downloaded game data and enrollment state.

## How much a statement here proves

Every result in this project is at one of four levels. A result never moves up
without a new run at the higher level, and the level is named wherever a result
is recorded.

| Level | What it proves | What it cannot prove |
| --- | --- | --- |
| **Source** | The code and the focused tests that build and run on a Mac with no device and no game. | Anything about a device, Metal, the developer service, or World of Warcraft. |
| **Simulator** | WolkaraForever's own screens and adapters ran in the iOS Simulator. | A physical device's Metal, packet tunnel, memory preparation, or authorization. |
| **Device script** | A WolkaraForever tool drove this build on a named device and recorded what came back. | Anything the script did not exercise, and anything the game itself does. |
| **Human full-game** | A person installed, launched and played the real game on the device. | Compatibility with a different device, OS version, or client build, or with the other form factor. |

Only the last level supports a statement about how World of Warcraft behaves.
[Compatibility](../COMPATIBILITY.md) names the level of each current result.
Development, architecture, tools, and validation records live in
[development/](../development/README.md).
