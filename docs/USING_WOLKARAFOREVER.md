# Using WolkaraForever

> **Current as of 2026-10-28 · source revision `fbd69f8`**

Use this guide after [installing the app](INSTALLATION.md). Labels may differ slightly as
the selected client, download state, and iPad permissions change.

## Home and game installation

![WolkaraForever home screen](screenshots/launcher-home.jpg)

On the home screen, choose **Forever**, then select a region and game language. Regions are
Europe, Americas, Korea, and Taiwan; game languages are English, Spanish, and German. The
launcher interface itself remains English.
Choose **Install** to download and verify the client, or let the app complete a required
update before playing. Keep WolkaraForever foregrounded while it downloads, verifies, or
prepares a launch.

For a ready Forever installation, changing the game language updates both `textLocale` and
`audioLocale` in the game's configuration. If its installed files belong to another language,
WolkaraForever marks the install as requiring a language update and downloads the selected-language
files before Play is available. It does not change the login region or other game settings.

Select **Play** when it becomes available. Startup preparation can take several minutes.
When the game is running, use **Leave game** in the in-game toolbar if the game has no useful
quit path. It closes WolkaraForever; reopen the app for a fresh session.

## Add-ons

![Add-on Manager installed list](screenshots/addon-manager.jpg)

Choose **Install Addons (Curse & Direct)** to manage add-ons for the selected edition.

- **Installed** lists packages on the device. Search narrows the list and refresh reloads it.
  Select a managed package to disable or restore it, pin or unpin its version, or remove it.
  WolkaraForever records the packages it manages and removes only those packages.
- **Browse CurseForge** searches CurseForge through its Core API. It needs an approved API
  key; the key is stored in this device's Keychain. The browser supports search, sorting,
  category and game-version filtering, configurable columns, project artwork and metadata,
  and compatible-file selection. A project or file can still be unavailable through the API;
  the app reports the provider's reason.
- The **plus** control imports one add-on archive from Files. **Open Add-on Directory** opens
  the relevant folder. Nothing changes until you select an archive or confirm an action.

Do not change add-ons while a download, update, or game startup is active.

## UI recovery and performance

The **Performance & UI Manager** operates on a ready Forever installation when no update,
launch preparation, or session is active.

- **Backup WoW UI Configuration** creates a verified ZIP of `WTF` (excluding its `Backups`
  folder) and `Interface` in `WTF/Backups`.
- **Reset to Default Graphical Settings** makes a backup, then removes only graphics and
  display settings from `WTF/Config.wtf`. Account data, locale, audio, input, gamepad
  configuration, bindings, SavedVariables, and unknown settings remain unchanged.
- **Restore WoW UI Configuration** restores a chosen `WoW-UI-…zip` from Files. It snapshots
  the current state first, so the restore itself can be reversed.
- **Gamepad UI** writes only `GamePadEnable` and takes effect when Forever next starts. It
  does not create or replace bindings.
- **Performance Overlay** shows frame rate, frame time, thermal state, battery, memory, and
  Low Power Mode in the game. It is off by default and applies immediately.

The app also uses background-aware frame pacing: when it loses the foreground it limits its
Metal frame loop to 5 fps and restores normal pacing when foregrounded. This reduces active
work while another app is in front; iPadOS still controls background execution.

## Controls and voice

![Key and button configuration](screenshots/voice-configuration.jpg)

The in-game toolbar exposes the cursor, keyboard, gamepad, settings, and leave-game controls.
The touch trackpad supports pointer movement, two-finger scrolling, and drag gestures. The
on-screen keyboard includes text, symbols, and dictation entry; the gamepad has layout,
size, opacity, grid, and haptic controls. Physical keyboard and controller input can also be
mapped in the app.

Open **Key / Button Configuration** for voice input:

1. Enable **Use a button to talk** and choose **Map a button**.
2. Press a supported keyboard key or controller control.
3. Choose **Hold to talk** or **Press to start and stop**.
4. Use **Test Voice** before opening the game, especially after changing a mapping.

Voice requires Microphone and Speech Recognition permission. The mapping can send text when
recognition completes or leave it for review; it can add a space after the text and accept
expected words. A mapped control can be withheld from the game while voice is active. Check
the controller-button collision warning before relying on a mapping—the safe choice depends
on the button bindings you use in the game.

## Help and safe recovery

Open **Settings → Technical details** for the app's current state and an exact failure
message. Include that message and a redacted log in a support report. Do not share account
credentials, API keys, signing data, pairing material, or device identifiers.

Do not delete the app as a first repair step: it removes downloaded game data and enrollment
state. If a download or startup fails, reopen the app, preserve its data, and use the
Technical details message to identify the next step.

For the boundary between feature availability and device-tested compatibility, see
[Compatibility](../COMPATIBILITY.md).
