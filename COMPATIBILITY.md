# Compatibility and support boundary

> Verified: 2026-11-21 · Source: `8375cbb`

WolkaraForever is a source-built project for an iPad or iPhone that you own and configure with your own Apple Developer account. The supported integrated route requires Developer Mode, current Xcode tooling, and an execution path that can prepare executable memory.

## Supported boundary

The project supports the Forever lifecycle and features described in the current user guide. Its reviewed simulator layouts are iPhone Duo and iPad Pro 13-inch (M5).

## Not guaranteed

WolkaraForever does not promise universal device, iOS-version, controller, network, account, or game-client compatibility. It does not provide an App Store build, game distribution, gameplay automation, game-code modification, integrity bypasses, or account-safety guarantees.

**Battle.net Login (Experimental)** is an opt-in compatibility path, not a supported replacement for normal in-game login. Its browser session and one-use launch result are transient; it may stop working without notice. Use it at your own risk.

**Login and the system roots.** The game validates Battle.net's certificate against macOS's system root certificates, which every artifact this project's toolchain builds supplies. An app installed by another route, or built without them, cannot log in in any execution mode: the client answers `BLZ51900003` with the experimental login on and off. [Use WolkaraForever on iPhone](docs/IPHONE.md) says how to check a build.

## Report a problem

Start with [Install WolkaraForever](docs/INSTALLATION.md) and [Use WolkaraForever](docs/USING_WOLKARAFOREVER.md). When you report a problem, follow [Send us a log](docs/SENDING_LOGS.md) and include the exact Technical details message if one was shown. Do not include credentials, signing material, pairing records, account information, or device identifiers.
