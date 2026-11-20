# Use WolkaraForever on iPhone

> Verified: 2026-11-13 · Source: `3c33543`

WolkaraForever can run on an iPhone that meets the [installation requirements](INSTALLATION.md). Plan storage and controls before downloading a game.

## Choose the phone interface

1. Open **Launcher Manager**.
2. Choose **iOS on Duo**.
3. Return home and confirm that the compact interface is active.

You can later return to **iPadOS**. The choice changes the interface only.

## Plan storage, network, and controls

Keep enough free storage for the game and updates. Use a reliable network for the first download. If a download stops, reopen the launcher and resume or repair it instead of deleting the app. The phone interface supports touch controls and can use a compatible physical keyboard or controller.

## Login is refused (`BLZ51900003`)

The game checks Battle.net's certificate against macOS's system root certificates, which
WolkaraForever supplies from the build that produced the app. Every artifact this project's
toolchain builds carries them — a device install, a simulator run, and the unsigned External JIT
`.ipa` alike — and both the packaging and the verification scripts refuse one that does not. An
app built or signed by some other route, or from a fork that removed them, carries none, and the
client then refuses every login with this code, whether the experimental Battle.net login is on
or off.

The same code appears when the game's own `WTF/Config.wtf` has no usable region and language.
When the launcher installs the game itself it writes those settings; a copy pushed from a Mac
keeps the Mac's.

To check a build, read the app's log after one attempt: `Documents/native-guest.log` carries a
line `[security] native-trusted public roots matched=N candidates=M` when the client asks for the
system roots. No such line means the build has none.

## Troubleshoot safely

Use **Settings → Diagnostics and logs** for the exact error message and for the log itself:
[Send us a log](SENDING_LOGS.md) has the three steps. Do not delete the app to solve a
configuration problem. Read [Compatibility](../COMPATIBILITY.md) before relying on a
device-specific workflow.
