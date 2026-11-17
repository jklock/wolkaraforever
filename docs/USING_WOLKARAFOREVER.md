# Use WolkaraForever

> Verified: 2026-11-13 · Source: `3c33543`

Use the launcher to prepare Forever, configure the interface, and recover safely when a setting or add-on causes a problem.

![WolkaraForever home screen](screenshots/launcher-home.jpg)

## Set up and update your game

1. On the home screen, select Forever, your region, and the game language.
2. Start the download. The launcher can resume, verify, repair, and update recorded game data.
3. Wait for the ready state before selecting **Play**.

Changing game language can require additional files. App language and game language are separate settings.

## Change app language or interface

Open **Settings** to choose an app language. Open **Launcher Manager** to choose **iPadOS** or **iOS on Duo**. Interface selection changes the arrangement only; it does not change game data or add-ons.

## Manage add-ons

Open **Add-On Manager** to view recorded packages, install the bundled WolkaraRoue package, import a validated archive, or browse a supported provider. An optional provider key stays in the device Keychain. The app removes only add-ons it recorded as managed.

A provider tab without a key shows one **Set up access** row; opening it asks for the key and then loads the tab. When a key is saved, use the **⚙️** button in the Add-on Manager’s top bar to **Change CurseForge key…** or **Remove key**; removal is confirmed and leaves the key only deleted from this device's Keychain. Each installed row shows the package's name, version, author and its CurseForge thumbnail once the package records a provider identity, and one word about its update with the action that goes with it: **Update**, **Check**, **Retry**, **Open**, **Link** or **Manage**. **Not checked yet** means nothing has asked the provider about that package yet, and **Check** is what asks; **Update** asks anyway and either installs the newest file or reports that the package is current. **Update All** runs the same question for every eligible package and finishes when each one has been written, so rows settle together rather than returning to **Not checked yet**.

![Add-On Manager](screenshots/addon-manager.jpg)

## Back up or recover your interface

Use **UI Manager** before large interface changes. Create a backup, restore a selected backup if the interface becomes unusable, and use the graphics reset only for graphics and display settings. Recovery does not replace the game installation.

## Configure controls and voice

Use the touch toolbar, trackpad, keyboard, gamepad, physical keyboard, or controller that fits your device. For dictation, open voice configuration, grant permission, select a trigger and Hold or Toggle behavior, then use **Test Voice** before dictating into a text field. Enabling dictation establishes the game's duplex audio route before a controller hold; the hold and release themselves do not change the audio category or remove the game output route. Leaving the app stops an open dictation capture, but does not add a WolkaraForever frame cap to the running guest.

A DualSense or DualShock 4 touchpad can move the game's pointer. In **Settings**, choose **Use controller touchpad as mouse**; it is off until you turn it on. One finger moves the pointer and two fingers scroll. Pressing the touchpad is the left mouse button, or the right button with two fingers on the pad, and pressing while you slide drags. Tapping without pressing does nothing, so a thumb resting on the pad does not click. While this is on, the touchpad click is the mouse button only and cannot be chosen as a dictation trigger. **Controller touchpad speed** offers Slow, Normal and Fast. Choose **Stop using controller touchpad as mouse** to return the click to an ordinary controller button.

![Voice configuration](screenshots/voice-configuration.jpg)

## Get help safely

When something fails, send a log — it is three taps and needs no computer:
[Send us a log](SENDING_LOGS.md) shows where **Settings → Diagnostics and logs → Logs and
reports** is, which file to pick, and how to share it.

If a failure offers **Technical details** in the Settings sheet, copy that message too: it is
the exact reason, and it matches a line in the log. Do not share credentials, pairing data,
signing information, account information, or device identifiers, and do not delete the app
as a first troubleshooting step — the log you need goes with it.
